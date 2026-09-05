const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const host_target = b.graph.host;
    // Keep the dependency cache outside a CI checkout when requested. This
    // matters on hosted Windows runners whose checkout owner can be
    // BUILTIN\\Administrators rather than the runner token; the cache itself
    // still enforces the owner-only ACL boundary in deps_fetch.zig.
    const native_deps_root = if (b.option(
        []const u8,
        "native-deps-root",
        "Absolute owner-only root for the locked native dependency cache (CI may place it under the runner profile)",
    )) |path| blk: {
        if (!std.fs.path.isAbsolute(path)) @panic("native-deps-root must be absolute");
        break :blk path;
    } else b.pathFromRoot("tools/zig/.cache/native-deps");
    // Zig 0.16's preferred_optimize_mode intentionally maps every release
    // request to the preferred mode, so it cannot expose a real ReleaseFast
    // comparison lane. Resolve the explicit enum option first, then map the
    // system --release selector while keeping a safe default for plain builds.
    const optimize: std.builtin.OptimizeMode = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size",
    ) orelse switch (b.release_mode) {
        .off, .any, .safe => .ReleaseSafe,
        .fast => .ReleaseFast,
        .small => .ReleaseSmall,
    };

    // FLIP_SEQUENTIAL is the admitted T0.2c baseline because it preserves
    // tracked back-buffer history for Present1 dirty metadata.  The discard
    // path remains an explicit challenger only; it can never be selected
    // implicitly per machine.
    const swap_effect_name = b.option(
        []const u8,
        "swap-effect",
        "Presenter effect: flip_sequential (admitted baseline) or flip_discard (challenger)",
    ) orelse "flip_sequential";
    const use_discard_swap_effect = if (std.mem.eql(u8, swap_effect_name, "flip_sequential"))
        false
    else if (std.mem.eql(u8, swap_effect_name, "flip_discard"))
        true
    else
        @panic("swap-effect must be flip_sequential or flip_discard");
    const presenter_options = b.addOptions();
    presenter_options.addOption(bool, "use_discard", use_discard_swap_effect);

    // Product admission is deliberately narrower than the portable test graph.
    const product_target = target.result.os.tag == .windows and target.result.cpu.arch == .x86_64;
    var executable: ?*std.Build.Step.Compile = null;

    const abi_library = b.addLibrary(.{
        .name = "texflow_abi",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/src/abi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // The portable ABI corpus belongs only to explicit cache/test paths.

    const abi_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/abi_probe.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    abi_tests.root_module.linkLibrary(abi_library);
    abi_tests.root_module.addIncludePath(b.path("native/zig/include"));
    abi_tests.root_module.addCSourceFile(.{ .file = b.path("native/zig/fixtures/abi_layout.c"), .flags = &.{"-std=c11"} });
    const abi_contract = b.addOptions();
    abi_contract.addOption([]const u8, "library_name", abi_library.name);
    abi_contract.addOptionPath("library_path", abi_library.getEmittedBin());
    abi_contract.addOptionPath("header_root", b.path("native/zig/include"));
    abi_tests.root_module.addOptions("abi_contract", abi_contract);
    const run_abi_tests = b.addRunArtifact(abi_tests);

    const smoke_tests = b.addTest(.{
        .name = "texflow-t0-1-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/t0_1_smoke.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const smoke_contract = b.addOptions();
    smoke_tests.root_module.addOptions("smoke_contract", smoke_contract);
    const run_smoke_tests = b.addRunArtifact(smoke_tests);
    const smoke_step = b.step("t0-1-smoke", "Run the cache-only TExFlow toolchain smoke test");
    smoke_step.dependOn(&run_smoke_tests.step);
    const t0_1_check = b.step("t0-1-check", "Compile portable smoke, ABI, miscompile, and SIMD tests without running");
    t0_1_check.dependOn(&smoke_tests.step);
    t0_1_check.dependOn(&abi_tests.step);

    const corpus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/miscompile_corpus.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_corpus_tests = b.addRunArtifact(corpus_tests);
    t0_1_check.dependOn(&corpus_tests.step);

    const simd_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/simd_corpus.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_simd_tests = b.addRunArtifact(simd_tests);
    t0_1_check.dependOn(&simd_tests.step);

    const test_step = b.step("test", "Run smoke, ABI, miscompile, and SIMD tests");
    test_step.dependOn(&run_smoke_tests.step);
    test_step.dependOn(&run_abi_tests.step);
    test_step.dependOn(&run_corpus_tests.step);
    test_step.dependOn(&run_simd_tests.step);

    const abi_step = b.step("abi", "Build and exercise the C ABI library");
    abi_step.dependOn(&abi_library.step);
    abi_step.dependOn(&run_abi_tests.step);

    const corpus_step = b.step("miscompile-corpus", "Run deterministic compiler answers");
    corpus_step.dependOn(&run_corpus_tests.step);

    const simd_step = b.step("simd-corpus", "Run deterministic SIMD answers");
    simd_step.dependOn(&run_simd_tests.step);

    const windows_argv_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/argv.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_argv_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/windows_argv_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    windows_argv_tests.root_module.addImport("windows_argv", windows_argv_module);
    const windows_api_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/api.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_argv_tests.root_module.addImport("windows_api", windows_api_module);
    const argv_child_options = b.addOptions();
    if (target.result.os.tag == .windows) {
        const argv_child = b.addExecutable(.{
            .name = "texflow-argv-child",
            .root_module = b.createModule(.{
                .root_source_file = b.path("native/zig/tests/windows_argv_child.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        argv_child.root_module.linkSystemLibrary("shell32", .{});
        argv_child_options.addOptionPath("path", argv_child.getEmittedBin());
    } else {
        argv_child_options.addOption([]const u8, "path", "");
    }
    windows_argv_tests.root_module.addOptions("argv_child_options", argv_child_options);
    const run_windows_argv_tests = b.addRunArtifact(windows_argv_tests);
    const windows_argv_step = b.step("t0-2b-argv-test", "Test Windows typed argv and narrow platform contracts");
    windows_argv_step.dependOn(&run_windows_argv_tests.step);
    const windows_argv_check = b.step("t0-2b-argv-check", "Compile Windows argv contracts for the selected target");
    windows_argv_check.dependOn(&windows_argv_tests.step);

    // T0.2c pure app-model contracts. These modules are deliberately kept
    // separate from the product/UI graph so Linux can compile and exercise
    // the deterministic state machines without any Windows dependencies.
    const app_role_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/role.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_build_identity_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/build_identity.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_version_resource_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/version_resource.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_build_identity_module.addImport("app_version_resource", app_version_resource_module);
    const resource_assets = b.addOptions();
    resource_assets.addOption([]const u8, "rc_source", @embedFile("native/zig/manifests/TExFlow.rc"));
    resource_assets.addOption([]const u8, "manifest_source", @embedFile("native/zig/manifests/TExFlow.exe.manifest"));
    const app_live_render_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/live_render.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_lifecycle_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/lifecycle.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_theme_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/theme.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_layout_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/layout.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_strings_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/strings.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_uia_shell_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/uia_shell.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_uia_shell_module.addImport("app_layout", app_layout_module);
    app_uia_shell_module.addImport("app_strings", app_strings_module);
    app_uia_shell_module.addImport("app_theme", app_theme_module);
    const windows_telemetry_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/telemetry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_workspace_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/workspace.zig"),
        .target = target,
        .optimize = optimize,
    });
    const app_editor_buffer_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/editor_buffer.zig"),
        .target = target,
        .optimize = optimize,
    });
    const texflow_icon_module = b.createModule(.{
        .root_source_file = b.path("native/zig/assets/texflow_icon.zig"),
        .target = target,
        .optimize = optimize,
    });
    const texflow_icon_host_module = b.createModule(.{
        .root_source_file = b.path("native/zig/assets/texflow_icon.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    const icon_assets = b.addOptions();
    icon_assets.addOption([]const u8, "tracked_svg", @embedFile("docs/assets/texflow-app-mark.svg"));
    const t0_2c_models_test = b.step("t0-2c-models-test", "Run deterministic T0.2c app-model tests");
    const t0_2c_models_check = b.step("t0-2c-models-check", "Compile deterministic T0.2c app-model tests");
    const workspace_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/workspace_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    workspace_tests.root_module.addImport("workspace", app_workspace_module);
    const run_workspace_tests = b.addRunArtifact(workspace_tests);
    const workspace_test_step = b.step("t1-1a-workspace-test", "Run T1.1a read-only source workspace inventory tests");
    workspace_test_step.dependOn(&run_workspace_tests.step);
    const workspace_check_step = b.step("t1-1a-workspace-check", "Compile T1.1a read-only source workspace inventory tests");
    workspace_check_step.dependOn(&workspace_tests.step);
    t0_2c_models_test.dependOn(&run_workspace_tests.step);
    t0_2c_models_check.dependOn(&workspace_tests.step);
    const editor_buffer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/editor_buffer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    editor_buffer_tests.root_module.addImport("editor_buffer", app_editor_buffer_module);
    const run_editor_buffer_tests = b.addRunArtifact(editor_buffer_tests);
    const editor_buffer_test_step = b.step("t1-1b-editor-buffer-test", "Run T1.1b revisioned editor-buffer tests");
    editor_buffer_test_step.dependOn(&run_editor_buffer_tests.step);
    const editor_buffer_check_step = b.step("t1-1b-editor-buffer-check", "Compile T1.1b revisioned editor-buffer tests");
    editor_buffer_check_step.dependOn(&editor_buffer_tests.step);
    t0_2c_models_test.dependOn(&run_editor_buffer_tests.step);
    t0_2c_models_check.dependOn(&editor_buffer_tests.step);
    const uia_shell_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/uia_shell_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    uia_shell_tests.root_module.addImport("app_uia_shell", app_uia_shell_module);
    uia_shell_tests.root_module.addImport("app_strings", app_strings_module);
    uia_shell_tests.root_module.addImport("app_theme", app_theme_module);
    const run_uia_shell_tests = b.addRunArtifact(uia_shell_tests);
    const uia_shell_test_step = b.step("t0-2c-shell-uia-test", "Run deterministic shell accessibility-tree contract tests");
    uia_shell_test_step.dependOn(&run_uia_shell_tests.step);
    const uia_shell_check_step = b.step("t0-2c-shell-uia-check", "Compile shell accessibility-tree contract tests");
    uia_shell_check_step.dependOn(&uia_shell_tests.step);
    t0_2c_models_test.dependOn(&run_uia_shell_tests.step);
    t0_2c_models_check.dependOn(&uia_shell_tests.step);
    const telemetry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/telemetry_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    telemetry_tests.root_module.addImport("windows_telemetry", windows_telemetry_module);
    const run_telemetry_tests = b.addRunArtifact(telemetry_tests);
    const telemetry_test_step = b.step("t0-2c-telemetry-test", "Run fixed-schema native render telemetry tests");
    telemetry_test_step.dependOn(&run_telemetry_tests.step);
    const telemetry_check_step = b.step("t0-2c-telemetry-check", "Compile fixed-schema native render telemetry tests");
    telemetry_check_step.dependOn(&telemetry_tests.step);
    t0_2c_models_test.dependOn(&run_telemetry_tests.step);
    t0_2c_models_check.dependOn(&telemetry_tests.step);
    const icon_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/icon_gen_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    icon_tests.root_module.addImport("texflow_icon", texflow_icon_module);
    icon_tests.root_module.addOptions("icon_assets", icon_assets);
    const run_icon_tests = b.addRunArtifact(icon_tests);
    const icon_test_step = b.step("t0-2c-icon-test", "Run deterministic TExFlow source-mark and ICO tests");
    icon_test_step.dependOn(&run_icon_tests.step);
    const icon_check_step = b.step("t0-2c-icon-check", "Compile deterministic TExFlow source-mark and ICO tests");
    icon_check_step.dependOn(&icon_tests.step);
    const icon_generator_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/icon_gen.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    icon_generator_tests.root_module.addImport("texflow_icon", texflow_icon_host_module);
    const run_icon_generator_tests = b.addRunArtifact(icon_generator_tests);
    icon_test_step.dependOn(&run_icon_generator_tests.step);
    icon_check_step.dependOn(&icon_generator_tests.step);
    t0_2c_models_test.dependOn(&run_icon_tests.step);
    t0_2c_models_check.dependOn(&icon_tests.step);
    t0_2c_models_test.dependOn(&run_icon_generator_tests.step);
    t0_2c_models_check.dependOn(&icon_generator_tests.step);
    const presenter_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/presenter.zig"),
        .target = target,
        .optimize = optimize,
    });
    const presenter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/presenter_state_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    presenter_tests.root_module.addImport("presenter", presenter_module);
    const run_presenter_tests = b.addRunArtifact(presenter_tests);
    const presenter_test_step = b.step("t0-2c-presenter-test", "Run the portable presenter state model tests");
    presenter_test_step.dependOn(&run_presenter_tests.step);
    const presenter_check_step = b.step("t0-2c-presenter-check", "Compile the portable presenter state model tests");
    presenter_check_step.dependOn(&presenter_tests.step);
    t0_2c_models_test.dependOn(&run_presenter_tests.step);
    t0_2c_models_check.dependOn(&presenter_tests.step);
    const graphics_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/graphics.zig"),
        .target = target,
        .optimize = optimize,
    });
    graphics_module.addImport("windows_api", windows_api_module);
    const graphics_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/graphics_device_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    graphics_tests.root_module.addImport("graphics", graphics_module);
    const run_graphics_tests = b.addRunArtifact(graphics_tests);
    const graphics_test_step = b.step("t0-2c-graphics-test", "Run the native D3D11 device and swap-chain contract tests");
    graphics_test_step.dependOn(&run_graphics_tests.step);
    const graphics_check_step = b.step("t0-2c-graphics-check", "Compile the native D3D11 device and swap-chain contracts");
    graphics_check_step.dependOn(&graphics_tests.step);
    t0_2c_models_test.dependOn(&run_graphics_tests.step);
    t0_2c_models_check.dependOn(&graphics_tests.step);
    const presenter_native_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/presenter_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    presenter_native_module.addImport("windows_api", windows_api_module);
    presenter_native_module.addImport("graphics", graphics_module);
    const presenter_native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/presenter_native_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    presenter_native_tests.root_module.addImport("presenter_native", presenter_native_module);
    presenter_native_tests.root_module.addImport("windows_api", windows_api_module);
    presenter_native_tests.root_module.addImport("graphics", graphics_module);
    if (target.result.os.tag == .windows) {
        inline for (.{ "d3d11", "dxgi", "user32", "kernel32" }) |library| presenter_native_module.linkSystemLibrary(library, .{});
        inline for (.{ "user32", "kernel32" }) |library| presenter_native_tests.root_module.linkSystemLibrary(library, .{});
    }
    const run_presenter_native_tests = b.addRunArtifact(presenter_native_tests);
    const presenter_native_test_step = b.step("t0-2c-presenter-native-test", "Run the native waitable swap-chain binding tests");
    presenter_native_test_step.dependOn(&run_presenter_native_tests.step);
    const presenter_native_check_step = b.step("t0-2c-presenter-native-check", "Compile the native waitable swap-chain binding");
    presenter_native_check_step.dependOn(&presenter_native_tests.step);
    t0_2c_models_test.dependOn(&run_presenter_native_tests.step);
    t0_2c_models_check.dependOn(&presenter_native_tests.step);
    const ui_entry_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/ui_entry.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ui_entry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/ui_entry_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ui_entry_tests.root_module.addImport("ui_entry", ui_entry_module);
    const run_ui_entry_tests = b.addRunArtifact(ui_entry_tests);
    const ui_entry_test_step = b.step("t0-2c-entry-test", "Run portable GUI argument admission tests");
    ui_entry_test_step.dependOn(&run_ui_entry_tests.step);
    const ui_entry_check_step = b.step("t0-2c-entry-check", "Compile portable GUI argument admission tests");
    ui_entry_check_step.dependOn(&ui_entry_tests.step);
    t0_2c_models_test.dependOn(&run_ui_entry_tests.step);
    t0_2c_models_check.dependOn(&ui_entry_tests.step);
    const windows_shell_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/shell.zig"),
        .target = target,
        .optimize = optimize,
    });
    windows_shell_module.addImport("ui_entry", ui_entry_module);
    const windows_com_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/com.zig"),
        .target = target,
        .optimize = optimize,
    });
    const windows_shell_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/windows_shell_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    windows_shell_tests.root_module.addImport("windows_shell", windows_shell_module);
    windows_shell_tests.root_module.addImport("ui_entry", ui_entry_module);
    windows_shell_tests.root_module.addImport("windows_com", windows_com_module);
    const run_windows_shell_tests = b.addRunArtifact(windows_shell_tests);
    b.step("t0-2c-shell-test", "Run portable native-shell sequencing and cleanup tests").dependOn(&run_windows_shell_tests.step);
    b.step("t0-2c-shell-check", "Compile native-shell model tests").dependOn(&windows_shell_tests.step);
    t0_2c_models_test.dependOn(&run_windows_shell_tests.step);
    t0_2c_models_check.dependOn(&windows_shell_tests.step);
    const shell_native_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/shell_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    shell_native_module.addOptions("presenter_config", presenter_options);
    shell_native_module.addImport("windows_shell", windows_shell_module);
    shell_native_module.addImport("windows_com", windows_com_module);
    shell_native_module.addImport("ui_entry", ui_entry_module);
    shell_native_module.addImport("app_role", app_role_module);
    shell_native_module.addImport("graphics", graphics_module);
    shell_native_module.addImport("presenter_native", presenter_native_module);
    if (target.result.os.tag == .windows) {
        inline for (.{ "kernel32", "user32", "shell32", "ole32", "bcrypt", "d3d11", "dxgi" }) |library| shell_native_module.linkSystemLibrary(library, .{});
    }
    const product_build_step = b.step("t0-2c-product-build", "Build the x64 Windows GUI product without installing");
    if (product_target) {
        const icon_generator = b.addExecutable(.{
            .name = "texflow-icon-gen",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/zig/icon_gen.zig"),
                .target = host_target,
                .optimize = .ReleaseSafe,
            }),
        });
        icon_generator.root_module.addImport("texflow_icon", texflow_icon_host_module);
        const run_icon_generator = b.addRunArtifact(icon_generator);
        run_icon_generator.addArg("emit");
        const icon_outputs = run_icon_generator.addOutputDirectoryArg("TExFlow-resources");
        const icon_rc = icon_outputs.path(b, "TExFlow-icon.rc");
        const product = b.addExecutable(.{
            .name = "TExFlow",
            .root_module = b.createModule(.{
                .root_source_file = b.path("native/zig/src/main.zig"),
                .target = target,
                .optimize = optimize,
                .strip = optimize != .Debug,
            }),
        });
        product.root_module.addImport("shell_native", shell_native_module);
        product.root_module.addWin32ResourceFile(.{
            .file = b.path("native/zig/manifests/TExFlow.rc"),
            .flags = &.{"/x"},
            .include_paths = &.{},
        });
        product.root_module.addWin32ResourceFile(.{
            .file = icon_rc,
            .flags = &.{"/x"},
            .include_paths = &.{},
        });
        product.subsystem = .Windows;
        b.installArtifact(product);
        product.step.dependOn(&run_icon_generator.step);
        product_build_step.dependOn(&product.step);
        executable = product;
    }
    const shell_native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/windows_shell_native_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    shell_native_tests.root_module.addImport("shell_native", shell_native_module);
    shell_native_tests.root_module.addImport("windows_shell", windows_shell_module);
    shell_native_tests.root_module.addImport("windows_com", windows_com_module);
    shell_native_tests.root_module.addImport("graphics", graphics_module);
    b.step("t0-2c-shell-native-test", "Test narrow Win32 ABI command line and COM contracts").dependOn(&b.addRunArtifact(shell_native_tests).step);
    b.step("t0-2c-shell-native-check", "Compile narrow Win32 ABI contracts").dependOn(&shell_native_tests.step);
    const product_contract = b.addOptions();
    const product_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/windows_product_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    product_tests.root_module.addOptions("product_contract", product_contract);
    product_tests.root_module.addOptions("resource_assets", resource_assets);
    product_tests.root_module.addImport("windows_argv", windows_argv_module);
    product_tests.root_module.addImport("app_version_resource", app_version_resource_module);
    product_tests.root_module.addImport("texflow_icon", texflow_icon_module);
    if (target.result.os.tag == .windows) product_tests.root_module.linkSystemLibrary("user32", .{});
    b.step("t0-2c-product-test", "Test native product PE and owned Windows shell runtime").dependOn(&b.addRunArtifact(product_tests).step);
    b.step("t0-2c-product-check", "Compile product contract tests without execution").dependOn(&product_tests.step);
    const version_resource_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/version_resource_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    version_resource_tests.root_module.addImport("app_version_resource", app_version_resource_module);
    version_resource_tests.root_module.addOptions("resource_assets", resource_assets);
    const run_version_resource_tests = b.addRunArtifact(version_resource_tests);
    const version_resource_test_step = b.step("t0-2c-resource-test", "Run portable TExFlow version and resource contract tests");
    version_resource_test_step.dependOn(&run_version_resource_tests.step);
    const version_resource_check_step = b.step("t0-2c-resource-check", "Compile TExFlow version and resource contract tests");
    version_resource_check_step.dependOn(&version_resource_tests.step);
    t0_2c_models_test.dependOn(&run_version_resource_tests.step);
    t0_2c_models_check.dependOn(&version_resource_tests.step);
    inline for (.{
        "role_test.zig",
        "build_identity_test.zig",
        "live_render_scheduler_test.zig",
        "lifecycle_test.zig",
        "theme_layout_test.zig",
        "strings_test.zig",
    }) |test_file| {
        const model_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("native/zig/tests/" ++ test_file),
                .target = target,
                .optimize = optimize,
            }),
        });
        model_tests.root_module.addImport("app_role", app_role_module);
        model_tests.root_module.addImport("app_build_identity", app_build_identity_module);
        model_tests.root_module.addImport("app_live_render", app_live_render_module);
        model_tests.root_module.addImport("app_lifecycle", app_lifecycle_module);
        model_tests.root_module.addImport("app_theme", app_theme_module);
        model_tests.root_module.addImport("app_layout", app_layout_module);
        model_tests.root_module.addImport("app_strings", app_strings_module);
        const run_model_tests = b.addRunArtifact(model_tests);
        t0_2c_models_test.dependOn(&run_model_tests.step);
        t0_2c_models_check.dependOn(&model_tests.step);
    }

    // T0.2b declares the Windows public-C contract only. These artifacts do
    // not link or load an engine and have no dependency-cache/fetch edge.
    const pdfium_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf/pdfium.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pdfium_contract = b.addOptions();
    pdfium_contract.addOption([]const u8, "source", @embedFile("native/zig/src/pdf/pdfium.zig"));
    const pdfium_abi_step = b.step("t0-2b-pdfium-abi", "Run static PDFium public ABI and boundary tests without an engine");
    const pdfium_static_step = b.step("t0-2b-pdfium-static", "Compile the static PDFium ABI tests for the selected target without running them");
    inline for (.{ "native_abi_test.zig", "pdf_engine_boundary_test.zig" }) |test_file| {
        const pdfium_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("native/zig/tests/" ++ test_file),
                .target = target,
                .optimize = optimize,
            }),
        });
        pdfium_tests.root_module.addImport("pdfium", pdfium_module);
        pdfium_tests.root_module.addOptions("pdfium_contract", pdfium_contract);
        const run_pdfium_tests = b.addRunArtifact(pdfium_tests);
        pdfium_abi_step.dependOn(&run_pdfium_tests.step);
        pdfium_static_step.dependOn(&pdfium_tests.step);
    }

    // Static PE parser only: no image loading, launch, fetch or product edge.
    const pe_audit_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/pe_audit.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pe_audit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pe_audit_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pe_audit_tests.root_module.addImport("pe_audit", pe_audit_module);
    const pe_artifact = b.addOptions();
    const pe_fixture = b.addExecutable(.{
        .name = "texflow-pe-fixture-unshipped",
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pe_fixture.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .msvc }),
            .optimize = .ReleaseSafe,
            .strip = true,
            .unwind_tables = .none,
        }),
    });
    pe_fixture.entry = .{ .symbol_name = "WinMainCRTStartup" };
    pe_fixture.subsystem = .Console;
    pe_fixture.root_module.linkSystemLibrary("kernel32", .{});
    if (target.result.os.tag == .windows) {
        pe_artifact.addOptionPath("path", pe_fixture.getEmittedBin());
    } else {
        pe_artifact.addOption([]const u8, "path", "");
    }
    pe_audit_tests.root_module.addOptions("pe_artifact", pe_artifact);
    b.step("t0-2b-pe-test", "Test the offline static PE32+ auditor").dependOn(&b.addRunArtifact(pe_audit_tests).step);
    b.step("t0-2b-pe-check", "Compile the static PE auditor tests without executing the target").dependOn(&pe_audit_tests.step);
    const pe_audit_tool = b.addExecutable(.{
        .name = "texflow-pe-audit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/pe_audit.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    const pe_audit_run = b.addRunArtifact(pe_audit_tool);
    if (b.option([]const u8, "pe-audit-path", "Explicit PE file to read under the narrow fixture import profile; no image is executed")) |path| {
        pe_audit_run.addFileArg(.{ .cwd_relative = path });
    } else {
        pe_audit_run.addFileArg(pe_fixture.getEmittedBin());
    }
    pe_audit_run.has_side_effects = true;
    b.step("t0-2b-pe-audit", "Statically audit a Windows fixture PE; this is not product closure").dependOn(&pe_audit_run.step);

    // Offline fixture compression oracle: no fetch, installer, or product edge.
    const package_probe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/package_probe_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    package_probe_tests.root_module.addImport("package_probe", b.createModule(.{
        .root_source_file = b.path("tools/zig/package_probe.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const package_probe_contract = b.addOptions();
    package_probe_contract.addOption([]const u8, "zon", @embedFile("build.zig.zon"));
    package_probe_tests.root_module.addOptions("package_probe_contract", package_probe_contract);
    const run_package_probe_tests = b.addRunArtifact(package_probe_tests);
    const package_probe_test = b.step("t0-2b-package-test", "Run the offline fixture package/compression oracle");
    package_probe_test.dependOn(&run_package_probe_tests.step);
    const package_probe_check = b.step("t0-2b-package-check", "Compile the package oracle tests for the selected target");
    package_probe_check.dependOn(&package_probe_tests.step);

    // Isolated T0.2b SQLite contract; no install or product/runtime edge.
    const sqlite_source = b.option([]const u8, "sqlite-source", "Absolute directory containing the exact locked SQLite 3.53.4 sqlite3.c and sqlite3.h (offline only)") orelse
        b.pathJoin(&.{ native_deps_root, ".v2", "sqlite", "generations", "g-14ea30ba6b8a3c158e833613", "payload", "sqlite-autoconf-3530400" });
    const sqlite_probe = b.addExecutable(.{
        .name = "texflow-sqlite-contract-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/sqlite_probe.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    const sqlite_snapshot = b.addRunArtifact(sqlite_probe);
    sqlite_snapshot.addArg("snapshot");
    sqlite_snapshot.addArg(sqlite_source);
    // Rehash even on warm builds. The generation pointer and completion
    // receipt are not trusted, and there is no network/fetch dependency.
    sqlite_snapshot.has_side_effects = true;
    const sqlite_snapshot_output = sqlite_snapshot.addOutputDirectoryArg("sqlite-3.53.4-verified");
    const sqlite_snapshot_root = sqlite_snapshot_output.path(b, "payload");
    const sqlite_c_flags = @import("native/zig/src/db/sqlite.zig").Contract.c_flags;
    const sqlite_library = b.addLibrary(.{
        .name = "sqlite-t0-2b-unshipped",
        .linkage = .static,
        .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
    });
    sqlite_library.root_module.addCSourceFile(.{ .file = sqlite_snapshot_root.path(b, "sqlite3.c"), .flags = sqlite_c_flags });
    const sqlite_symbols = b.addRunArtifact(sqlite_probe);
    sqlite_symbols.addArg("symbols");
    sqlite_symbols.addFileArg(sqlite_library.getEmittedBin());
    const sqlite_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/sqlite_abi_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sqlite_tests.root_module.addImport("sqlite", b.createModule(.{
        .root_source_file = b.path("native/zig/src/db/sqlite.zig"),
        .target = target,
        .optimize = optimize,
    }));
    sqlite_tests.root_module.addImport("sqlite_probe", b.createModule(.{
        .root_source_file = b.path("tools/zig/sqlite_probe.zig"),
        .target = target,
        .optimize = optimize,
    }));
    const sqlite_contract = b.addOptions();
    sqlite_contract.addOption([]const []const u8, "c_flags", sqlite_c_flags);
    sqlite_contract.addOption([]const u8, "wrapper_source", @embedFile("native/zig/src/db/sqlite.zig"));
    sqlite_contract.addOptionPath("source_root", sqlite_snapshot_root);
    sqlite_tests.root_module.addOptions("sqlite_contract", sqlite_contract);
    sqlite_tests.root_module.addIncludePath(sqlite_snapshot_root);
    sqlite_tests.root_module.linkLibrary(sqlite_library);
    const sqlite_test_step = b.step("t0-2b-sqlite-test", "Run the unshipped SQLite amalgamation contract; no product integration");
    sqlite_test_step.dependOn(&b.addRunArtifact(sqlite_tests).step);
    sqlite_test_step.dependOn(&sqlite_symbols.step);
    const sqlite_check_step = b.step("t0-2b-sqlite-check", "Compile the unshipped SQLite contract for the selected target");
    sqlite_check_step.dependOn(&sqlite_tests.step);
    sqlite_check_step.dependOn(&sqlite_symbols.step);

    const deps_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/deps.zig"),
        .target = target,
        .optimize = optimize,
    });
    const deps_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/deps.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    const notices_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/notices.zig"),
        .target = target,
        .optimize = optimize,
    });
    notices_module.addImport("deps", deps_module);
    const notices_contract = b.addOptions();
    notices_contract.addOption([]const u8, "root_notice", @embedFile("NOTICE"));
    notices_contract.addOption([]const u8, "license", @embedFile("LICENSE"));
    notices_contract.addOption([]const u8, "shipping_notice", @embedFile("native/zig/THIRD_PARTY_NOTICES.txt"));
    notices_contract.addOption([]const u8, "zon", @embedFile("build.zig.zon"));
    notices_contract.addOption([]const u8, "git_attributes", @embedFile(".gitattributes"));
    const notices_inputs = notices_contract.createModule();
    notices_module.addImport("notices_contract", notices_inputs);
    const notices_tool = b.addExecutable(.{ .name = "texflow-notices", .root_module = notices_module });
    const run_notices = b.addRunArtifact(notices_tool);
    run_notices.addArgs(b.args orelse &.{"check"});
    b.step("t0-2b-notices", "Check canonical notices; -- render or -- inventory writes deterministic text").dependOn(&run_notices.step);
    const notices_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/notices_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    notices_tests.root_module.addImport("notices", notices_module);
    notices_tests.root_module.addImport("notices_contract", notices_inputs);
    b.step("t0-2b-notices-test", "Run the offline native notice and source/license contracts").dependOn(&b.addRunArtifact(notices_tests).step);
    const notices_checkout_contract = b.addOptions();
    notices_checkout_contract.addOption([]const u8, "git_executable", b.option([]const u8, "notices-git-executable", "Absolute Git executable for the external QA-only notice checkout test; no PATH discovery") orelse "");
    const notices_checkout_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/notices_checkout_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    notices_checkout_tests.root_module.addImport("notices", notices_module);
    notices_checkout_tests.root_module.addImport("notices_contract", notices_inputs);
    notices_checkout_tests.root_module.addOptions("notices_checkout_contract", notices_checkout_contract);
    b.step("t0-2b-notices-checkout-test", "QA-only fresh checkout with autocrlf=true; requires -Dnotices-git-executable").dependOn(&b.addRunArtifact(notices_checkout_tests).step);
    const notices_check = b.step("t0-2b-notices-check", "Compile the offline native notice contracts for the selected target");
    notices_check.dependOn(&notices_tests.step);
    notices_contract.addOption(bool, "portable_check_has_checkout_edge", std.mem.indexOfScalar(*std.Build.Step, notices_check.dependencies.items, &notices_checkout_tests.step) != null);
    const scintilla_probe_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/scintilla_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    scintilla_probe_module.addImport("deps", deps_module);
    const scintilla_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/source_inventory_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scintilla_tests.root_module.addImport("scintilla_probe", scintilla_probe_module);
    const scintilla_contract = b.addOptions();
    const scintilla_archive = b.option([]const u8, "scintilla-archive", "Absolute path to the exact Scintilla 5.6.6 archive (offline only)") orelse
        b.pathJoin(&.{ native_deps_root, ".v2", "scintilla", "generations", "g-0c7dc920040326b993b39ff6", "archive.bin" });
    scintilla_contract.addOption([]const u8, "archive_path", scintilla_archive);
    const scintilla_probe = b.addExecutable(.{
        .name = "texflow-scintilla-source-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/scintilla_probe.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    scintilla_probe.root_module.addImport("deps", deps_host_module);
    const scintilla_snapshot = b.addRunArtifact(scintilla_probe);
    scintilla_snapshot.addArgs(&.{ "snapshot", scintilla_archive });
    scintilla_snapshot.has_side_effects = true;
    const scintilla_root = scintilla_snapshot.addOutputDirectoryArg("scintilla-5.6.6-verified").path(b, "payload/scintilla");
    scintilla_contract.addOptionPath("source_root", scintilla_root);
    const scintilla_inventory = @import("tools/zig/scintilla_probe.zig");
    const scintilla_flags = switch (optimize) {
        inline else => |mode| scintilla_inventory.cxxFlags(mode),
    };
    const scintilla_winrt_include = b.option([]const u8, "scintilla-winrt-include", "Absolute Windows SDK WinRT include directory containing wrl.h; default: installed SDK discovery");
    // This local artifact belongs solely to the unshipped UI feasibility lane.
    // No install, product, worker, Lexilla, download, or dependency-fetch edge.
    const scintilla_library: ?*std.Build.Step.Compile = if (target.result.os.tag == .windows) library: {
        const library = b.addLibrary(.{
            .name = "scintilla-ui-t0-2b-unshipped",
            .linkage = .static,
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        library.root_module.addIncludePath(scintilla_root.path(b, "include"));
        library.root_module.addIncludePath(scintilla_root.path(b, "src"));
        // Zig discovers MSVC/SDK C headers, but not the WRL headers used by
        // upstream Scintilla. Use the installed SDK's matching WinRT tree.
        if (scintilla_winrt_include) |path| {
            if (!std.fs.path.isAbsolute(path)) @panic("scintilla-winrt-include must be absolute");
            library.root_module.addSystemIncludePath(.{ .cwd_relative = path });
        } else if (host_target.result.os.tag == .windows) {
            if (std.zig.WindowsSdk.find(b.allocator, b.graph.io, target.result.cpu.arch, &b.graph.environ_map)) |sdk| {
                if (sdk.windows10sdk) |windows_sdk| library.root_module.addSystemIncludePath(.{
                    .cwd_relative = b.pathJoin(&.{ windows_sdk.path, "Include", windows_sdk.version, "winrt" }),
                });
            } else |_| {}
        }
        library.root_module.addCSourceFiles(.{ .root = scintilla_root, .files = &scintilla_inventory.sources, .flags = scintilla_flags });
        _ = library.getEmittedBin();
        break :library library;
    } else null;
    const scintilla_build = b.step("t0-2b-scintilla-build", "Compile the unshipped Win32 Scintilla static library; no runtime probe");
    if (scintilla_library) |library| {
        scintilla_build.dependOn(&library.step);
        // Read the actual compiler input, not a second self-reported list.
        const inputs = library.root_module.link_objects.items[0].c_source_files;
        scintilla_contract.addOption([]const []const u8, "source_files", inputs.files);
        scintilla_contract.addOption([]const []const u8, "cxx_flags", inputs.flags);
        scintilla_contract.addOption([]const u8, "artifact_kind", @tagName(library.kind));
        scintilla_contract.addOption([]const u8, "artifact_linkage", @tagName(library.linkage.?));
    } else {
        scintilla_build.dependOn(&b.addFail("Scintilla's Win32 static library requires a Windows target; t0-2b-scintilla-check compiles only the contract tests on Linux.").step);
        scintilla_contract.addOption([]const []const u8, "source_files", &scintilla_inventory.sources);
        scintilla_contract.addOption([]const []const u8, "cxx_flags", scintilla_flags);
        scintilla_contract.addOption([]const u8, "artifact_kind", "absent");
        scintilla_contract.addOption([]const u8, "artifact_linkage", "absent");
    }
    scintilla_contract.addOption(bool, "library_created", scintilla_library != null);
    scintilla_tests.root_module.addOptions("scintilla_contract", scintilla_contract);
    b.step("t0-2b-scintilla-test", "Run the unshipped Scintilla source and build contract tests").dependOn(&b.addRunArtifact(scintilla_tests).step);
    b.step("t0-2b-scintilla-check", "Compile Scintilla contract tests only; no Win32 C++ compilation on Linux").dependOn(&scintilla_tests.step);
    const deps_tool = b.addExecutable(.{
        .name = "texflow-deps",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/deps.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    const audit_ucd = b.addRunArtifact(deps_tool);
    audit_ucd.addArg("audit-ucd");
    const audit_pdfium_evidence = b.addRunArtifact(deps_tool);
    audit_pdfium_evidence.addArg("audit-evidence");
    const deps_manifest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/deps_manifest_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    deps_manifest_tests.root_module.addImport("deps", deps_module);
    const package_contract = b.addOptions();
    package_contract.addOption([]const u8, "notice", @embedFile("NOTICE"));
    package_contract.addOption([]const u8, "zon", @embedFile("build.zig.zon"));
    package_contract.addOption(
        []const u8,
        "development_guide",
        @embedFile("docs/development.md"),
    );
    deps_manifest_tests.root_module.addOptions("package_contract", package_contract);
    const run_deps_manifest_tests = b.addRunArtifact(deps_manifest_tests);
    const deps_manifest_test_step = b.step(
        "deps-manifest-test",
        "Run the source-package allowlist and notice contract tests",
    );
    deps_manifest_test_step.dependOn(&run_deps_manifest_tests.step);

    const archive_security_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/archive_security_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    archive_security_tests.root_module.addImport("deps", deps_module);
    const portable_collision_module = b.createModule(.{
        .root_source_file = b.path("native/zig/tests/portable_collision.zig"),
        .target = target,
        .optimize = optimize,
    });
    archive_security_tests.root_module.addImport("unicode", portable_collision_module);
    const run_archive_security_tests = b.addRunArtifact(archive_security_tests);

    const attestation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/attestation_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    attestation_tests.root_module.addImport("deps", deps_module);
    const run_attestation_tests = b.addRunArtifact(attestation_tests);

    const unicode_generator_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/unicode_gen.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    const run_unicode_generator_tests = b.addRunArtifact(unicode_generator_tests);

    const unicode_generator = b.addExecutable(.{
        .name = "texflow-unicode-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/unicode_gen.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    const ascii_collision_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/ascii_collision.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    ascii_collision_module.addImport("deps", deps_host_module);
    const deps_fetch_bootstrap = b.addExecutable(.{
        .name = "texflow-deps-bootstrap",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/deps_fetch.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    deps_fetch_bootstrap.root_module.addImport("deps", deps_host_module);
    deps_fetch_bootstrap.root_module.addImport("collision", ascii_collision_module);
    if (host_target.result.os.tag == .windows) {
        deps_fetch_bootstrap.root_module.linkSystemLibrary("advapi32", .{});
    }
    const run_deps_fetch_bootstrap = b.addRunArtifact(deps_fetch_bootstrap);
    run_deps_fetch_bootstrap.addArgs(&.{
        "bootstrap",
        native_deps_root,
    });

    // Fetch may create the UCD generation, but every consumer receives an
    // independently materialized, rehashed build-cache snapshot. A distinct
    // read-only export is used by audit so `zig build deps-audit` never gains a
    // dependency on the mutating bootstrap step.
    const export_ucd_for_fetch = b.addRunArtifact(deps_fetch_bootstrap);
    export_ucd_for_fetch.addArgs(&.{ "export-ucd", native_deps_root });
    const ucd_export_for_fetch = export_ucd_for_fetch.addOutputDirectoryArg(
        "unicode-ucd-fetch-snapshot",
    );
    export_ucd_for_fetch.step.dependOn(&run_deps_fetch_bootstrap.step);
    const ucd_root_for_fetch = ucd_export_for_fetch.path(b, "payload");

    const export_ucd_for_audit = b.addRunArtifact(deps_fetch_bootstrap);
    export_ucd_for_audit.addArgs(&.{ "export-ucd", native_deps_root });
    const ucd_export_for_audit = export_ucd_for_audit.addOutputDirectoryArg(
        "unicode-ucd-audit-snapshot",
    );
    const ucd_root_for_audit = ucd_export_for_audit.path(b, "payload");
    audit_ucd.addFileArg(ucd_export_for_audit.path(b, "archive.bin"));

    const generate_unicode_for_fetch = b.addRunArtifact(unicode_generator);
    generate_unicode_for_fetch.addArg("generate");
    generate_unicode_for_fetch.addDirectoryArg(ucd_root_for_fetch);
    const generated_unicode_for_fetch = generate_unicode_for_fetch.addOutputFileArg(
        "unicode-data-fetch.zig",
    );

    const generate_unicode_a = b.addRunArtifact(unicode_generator);
    generate_unicode_a.addArg("generate");
    generate_unicode_a.addDirectoryArg(ucd_root_for_audit);
    const generated_unicode_a = generate_unicode_a.addOutputFileArg("unicode-data-a.zig");
    const generate_unicode_b = b.addRunArtifact(unicode_generator);
    generate_unicode_b.addArg("generate");
    generate_unicode_b.addDirectoryArg(ucd_root_for_audit);
    const generated_unicode_b = generate_unicode_b.addOutputFileArg("unicode-data-b.zig");
    const compare_unicode = b.addRunArtifact(unicode_generator);
    compare_unicode.addArg("compare");
    compare_unicode.addFileArg(generated_unicode_a);
    compare_unicode.addFileArg(generated_unicode_b);
    _ = compare_unicode.addOutputFileArg("unicode-receipt.txt");

    const unicode_data_module = b.createModule(.{
        .root_source_file = generated_unicode_a,
        .target = target,
        .optimize = optimize,
    });
    const unicode_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/text/unicode.zig"),
        .target = target,
        .optimize = optimize,
    });
    unicode_module.addImport("unicode_data", unicode_data_module);
    const source_set_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/source_set.zig"),
        .target = target,
        .optimize = optimize,
    });
    source_set_module.addImport("unicode", unicode_module);
    const source_set_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/source_set_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    source_set_tests.root_module.addImport("source_set", source_set_module);
    source_set_tests.root_module.addImport("app_build_identity", app_build_identity_module);
    const run_source_set_tests = b.addRunArtifact(source_set_tests);
    const source_set_test_step = b.step("t0-2c-source-set-test", "Run canonical source-set digest model tests");
    source_set_test_step.dependOn(&run_source_set_tests.step);
    const source_set_check_step = b.step("t0-2c-source-set-check", "Compile canonical source-set digest model tests");
    source_set_check_step.dependOn(&source_set_tests.step);
    t0_2c_models_test.dependOn(&run_source_set_tests.step);
    t0_2c_models_check.dependOn(&source_set_tests.step);
    const unicode_archive_security_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/archive_security_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unicode_archive_security_tests.root_module.addImport("deps", deps_module);
    unicode_archive_security_tests.root_module.addImport("unicode", unicode_module);
    const run_unicode_archive_security_tests = b.addRunArtifact(
        unicode_archive_security_tests,
    );

    const unicode_fetch_data_module = b.createModule(.{
        .root_source_file = generated_unicode_for_fetch,
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    const unicode_fetch_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/text/unicode.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    unicode_fetch_module.addImport("unicode_data", unicode_fetch_data_module);
    const ucd_contract_for_fetch = b.addOptions();
    ucd_contract_for_fetch.addOptionPath("root", ucd_root_for_fetch);
    const unicode_fetch_conformance_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/unicode_data_test.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    unicode_fetch_conformance_tests.root_module.addImport("deps", deps_host_module);
    unicode_fetch_conformance_tests.root_module.addImport("unicode", unicode_fetch_module);
    unicode_fetch_conformance_tests.root_module.addImport(
        "unicode_data",
        unicode_fetch_data_module,
    );
    unicode_fetch_conformance_tests.root_module.addOptions(
        "ucd_contract",
        ucd_contract_for_fetch,
    );
    const run_unicode_fetch_conformance_tests = b.addRunArtifact(
        unicode_fetch_conformance_tests,
    );
    const deps_fetch_tool = b.addExecutable(.{
        .name = "texflow-deps-fetch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/deps_fetch.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    deps_fetch_tool.root_module.addImport("deps", deps_host_module);
    deps_fetch_tool.root_module.addImport("collision", unicode_fetch_module);
    if (host_target.result.os.tag == .windows) {
        deps_fetch_tool.root_module.linkSystemLibrary("advapi32", .{});
    }
    const run_deps_fetch = b.addRunArtifact(deps_fetch_tool);
    run_deps_fetch.addArgs(&.{ "all", native_deps_root });
    // The Unicode collision implementation is trusted for artifact two and
    // later only after all pinned official conformance vectors pass.
    run_deps_fetch.step.dependOn(&run_unicode_fetch_conformance_tests.step);

    const unicode_audit_host_data_module = b.createModule(.{
        .root_source_file = generated_unicode_a,
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    const unicode_audit_host_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/text/unicode.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    unicode_audit_host_module.addImport("unicode_data", unicode_audit_host_data_module);
    const deps_cache_audit_tool = b.addExecutable(.{
        .name = "texflow-deps-cache-audit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/deps_fetch.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    deps_cache_audit_tool.root_module.addImport("deps", deps_host_module);
    deps_cache_audit_tool.root_module.addImport("collision", unicode_audit_host_module);
    if (host_target.result.os.tag == .windows) {
        deps_cache_audit_tool.root_module.linkSystemLibrary("advapi32", .{});
    }
    const run_deps_cache_audit = b.addRunArtifact(deps_cache_audit_tool);
    run_deps_cache_audit.addArgs(&.{ "audit", native_deps_root });

    const export_zigwin32 = b.addRunArtifact(deps_cache_audit_tool);
    export_zigwin32.addArgs(&.{ "export-zigwin32", native_deps_root });
    const zigwin32_export = export_zigwin32.addOutputDirectoryArg("zigwin32-snapshot");
    const zigwin32_cache_module = b.createModule(.{
        .root_source_file = zigwin32_export.path(
            b,
            "zigwin32-9f15c276b4e9d05afd34a10d8662a7dfc34647ea/win32.zig",
        ),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    if (target.result.os.tag == .windows) {
        const zigwin32_target_module = b.createModule(.{
            .root_source_file = zigwin32_export.path(
                b,
                "zigwin32-9f15c276b4e9d05afd34a10d8662a7dfc34647ea/win32.zig",
            ),
            .target = target,
            .optimize = optimize,
        });
        windows_api_module.addImport("zigwin32", zigwin32_target_module);
    }

    const export_attestation_inputs = b.addRunArtifact(deps_cache_audit_tool);
    export_attestation_inputs.addArgs(&.{
        "export-attestation-inputs",
        native_deps_root,
    });
    const attestation_inputs = AbsoluteAuditInputs.create(
        b,
        export_attestation_inputs.addOutputDirectoryArg("attestation-inputs"),
    );

    const attestation_audit_tool = b.addExecutable(.{
        .name = "texflow-attestation-audit",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/attestation_verify.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    attestation_audit_tool.root_module.addImport("deps", deps_host_module);
    const run_attestation_audit = b.addRunArtifact(attestation_audit_tool);
    run_attestation_audit.addArg("verify");
    run_attestation_audit.addDirectoryArg(attestation_inputs);
    run_attestation_audit.addFileArg(attestation_inputs.path(b, "github-cli/payload/bin/gh.exe"));
    run_attestation_audit.addFileArg(attestation_inputs.path(b, "pdfium-reference/archive.bin"));
    run_attestation_audit.addFileArg(
        b.path("tools/zig/attestations/pdfium-chromium-8035-win-x64.jsonl"),
    );
    run_attestation_audit.addFileArg(
        b.path("tools/zig/attestations/github-attestation-trusted-root-2026-09-04.jsonl"),
    );
    run_attestation_audit.step.dependOn(&run_deps_cache_audit.step);

    const deps_fetch_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/deps_fetch.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    deps_fetch_tests.root_module.addImport("deps", deps_host_module);
    deps_fetch_tests.root_module.addImport("collision", ascii_collision_module);
    if (host_target.result.os.tag == .windows) {
        deps_fetch_tests.root_module.linkSystemLibrary("advapi32", .{});
    }
    const run_deps_fetch_tests = b.addRunArtifact(deps_fetch_tests);
    const deps_fetch_fixture_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/deps_fetch.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    deps_fetch_fixture_module.addImport("deps", deps_host_module);
    deps_fetch_fixture_module.addImport("collision", ascii_collision_module);
    const deps_fetch_fixture_worker = b.addExecutable(.{
        .name = "texflow-deps-fetch-fixture-worker",
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/deps_fetch_fixture_worker.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    deps_fetch_fixture_worker.root_module.addImport("deps", deps_host_module);
    deps_fetch_fixture_worker.root_module.addImport("deps_fetch", deps_fetch_fixture_module);
    if (host_target.result.os.tag == .windows) {
        deps_fetch_fixture_worker.root_module.linkSystemLibrary("advapi32", .{});
    }
    const fixture_options = b.addOptions();
    fixture_options.addOptionPath("worker_path", deps_fetch_fixture_worker.getEmittedBin());
    const deps_fetch_integration_tests = b.addTest(.{
        .filters = if (b.option([]const u8, "deps-fetch-test-filter", "Run only dependency cache integration tests matching this text")) |filter| &.{filter} else &.{},
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/deps_fetch_integration_test.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    deps_fetch_integration_tests.root_module.addImport("deps", deps_host_module);
    deps_fetch_integration_tests.root_module.addImport("deps_fetch", deps_fetch_fixture_module);
    deps_fetch_integration_tests.root_module.addOptions("fixture_options", fixture_options);
    if (host_target.result.os.tag == .windows) {
        deps_fetch_integration_tests.root_module.linkSystemLibrary("advapi32", .{});
    }
    const run_deps_fetch_integration_tests = b.addRunArtifact(deps_fetch_integration_tests);
    const deps_fetch_integration_test_step = b.step(
        "deps-fetch-integration-test",
        "Run deterministic dependency cache process integration tests",
    );
    deps_fetch_integration_test_step.dependOn(&run_deps_fetch_integration_tests.step);
    const attestation_audit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/attestation_verify.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    attestation_audit_tests.root_module.addImport("deps", deps_host_module);
    const run_attestation_audit_tests = b.addRunArtifact(attestation_audit_tests);
    const zigwin32_cache_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/zigwin32_cache_test.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    zigwin32_cache_tests.root_module.addImport("zigwin32", zigwin32_cache_module);
    // The generated LazyPath makes export and its locked verification a hard
    // prerequisite; the compiler never imports from the dependency cache.
    const run_zigwin32_cache_tests = b.addRunArtifact(zigwin32_cache_tests);
    const unicode_data_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/unicode_data_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unicode_data_tests.root_module.addImport("unicode", unicode_module);
    unicode_data_tests.root_module.addImport("unicode_data", unicode_data_module);
    unicode_data_tests.root_module.addImport("deps", deps_module);
    const ucd_contract_for_audit = b.addOptions();
    ucd_contract_for_audit.addOptionPath("root", ucd_root_for_audit);
    unicode_data_tests.root_module.addOptions("ucd_contract", ucd_contract_for_audit);
    const run_unicode_data_tests = b.addRunArtifact(unicode_data_tests);

    const deps_test_step = b.step("deps-test", "Run native dependency manifest and acquisition tests");
    deps_test_step.dependOn(&run_deps_manifest_tests.step);
    deps_test_step.dependOn(&run_archive_security_tests.step);
    deps_test_step.dependOn(&run_attestation_tests.step);
    deps_test_step.dependOn(&run_unicode_generator_tests.step);
    deps_test_step.dependOn(&run_deps_fetch_tests.step);
    deps_test_step.dependOn(&run_deps_fetch_integration_tests.step);
    deps_test_step.dependOn(&run_attestation_audit_tests.step);

    const deps_fetch_step = b.step(
        "deps-fetch",
        "Acquire locked native dependencies into the verified local cache",
    );
    deps_fetch_step.dependOn(&run_deps_fetch.step);

    const unicode_audit_step = b.step(
        "unicode-audit",
        "Regenerate and verify deterministic Unicode 17 tables and conformance",
    );
    unicode_audit_step.dependOn(&compare_unicode.step);
    unicode_audit_step.dependOn(&run_unicode_data_tests.step);
    unicode_audit_step.dependOn(&run_unicode_archive_security_tests.step);

    const deps_audit_step = b.step(
        "deps-audit",
        "Audit locked archives, Unicode tables, and offline attestation evidence",
    );
    deps_audit_step.dependOn(&audit_ucd.step);
    deps_audit_step.dependOn(&audit_pdfium_evidence.step);
    deps_audit_step.dependOn(&run_deps_cache_audit.step);
    deps_audit_step.dependOn(&run_attestation_audit.step);
    deps_audit_step.dependOn(&run_zigwin32_cache_tests.step);
    deps_audit_step.dependOn(unicode_audit_step);
    scintilla_contract.addOption(bool, "install_reaches_library", if (scintilla_library) |library| buildReachesLibrary(b, b.getInstallStep(), library) else false);
    scintilla_contract.addOption(bool, "product_reaches_library", if (executable) |product| if (scintilla_library) |library| buildReachesLibrary(b, &product.step, library) else false else false);
    abi_contract.addOption(bool, "install_reaches_library", buildReachesLibrary(b, b.getInstallStep(), abi_library));
    abi_contract.addOption(bool, "product_reaches_library", if (executable) |product| buildReachesLibrary(b, &product.step, abi_library) else false);
    smoke_contract.addOption(bool, "install_reaches_smoke", buildReachesLibrary(b, b.getInstallStep(), smoke_tests));
    smoke_contract.addOption(bool, "product_reaches_smoke", if (executable) |product| buildReachesLibrary(b, &product.step, smoke_tests) else false);
    product_contract.addOption(bool, "has_product", executable != null);
    product_contract.addOption([]const u8, "product_name", if (executable) |product| product.name else "");
    if (executable) |product| product_contract.addOptionPath("path", product.getEmittedBin()) else product_contract.addOption([]const u8, "path", "");
    product_contract.addOption(bool, "install_empty", b.getInstallStep().dependencies.items.len == 0);
    product_contract.addOption(bool, "install_reaches_product", if (executable) |product| buildReachesLibrary(b, b.getInstallStep(), product) else false);
}

// Inspect actual build steps and transitive module/library edges. Checking only
// direct Step.dependencies during build() misses linkLibrary dependencies that
// Zig expands later. The visited sets also handle shared modules and cycles.
fn buildReachesLibrary(b: *std.Build, root: *std.Build.Step, library: *std.Build.Step.Compile) bool {
    var steps: std.AutoArrayHashMapUnmanaged(*std.Build.Step, void) = .empty;
    var modules: std.AutoArrayHashMapUnmanaged(*std.Build.Module, void) = .empty;
    steps.put(b.allocator, root, {}) catch @panic("OOM");
    var step_index: usize = 0;
    var module_index: usize = 0;
    while (step_index < steps.count() or module_index < modules.count()) {
        while (step_index < steps.count()) : (step_index += 1) {
            const step = steps.keys()[step_index];
            if (step == &library.step) return true;
            for (step.dependencies.items) |dependency| steps.put(b.allocator, dependency, {}) catch @panic("OOM");
            if (step.id == .compile) {
                const compile: *std.Build.Step.Compile = @fieldParentPtr("step", step);
                modules.put(b.allocator, compile.root_module, {}) catch @panic("OOM");
            }
        }
        while (module_index < modules.count()) : (module_index += 1) {
            const module = modules.keys()[module_index];
            for (module.import_table.values()) |dependency| modules.put(b.allocator, dependency, {}) catch @panic("OOM");
            for (module.link_objects.items) |object| switch (object) {
                .other_step => |dependency| steps.put(b.allocator, &dependency.step, {}) catch @panic("OOM"),
                else => {},
            };
        }
    }
    return false;
}

// Generated Run outputs may be relative to the build runner's CWD. Resolve the
// audit snapshot only after its export finishes, retaining the LazyPath edge
// while satisfying the verifier's strict absolute-input contract.
const AbsoluteAuditInputs = struct {
    step: std.Build.Step,
    input: std.Build.LazyPath,
    output: std.Build.GeneratedFile,

    fn create(b: *std.Build, input: std.Build.LazyPath) std.Build.LazyPath {
        const adapter = b.allocator.create(AbsoluteAuditInputs) catch @panic("OOM");
        adapter.* = .{
            .step = .init(.{
                .id = .custom,
                .name = "resolve absolute attestation inputs",
                .owner = b,
                .makeFn = make,
            }),
            .input = input.dupe(b),
            .output = .{ .step = &adapter.step },
        };
        input.addStepDependencies(&adapter.step);
        return .{ .generated = .{ .file = &adapter.output } };
    }

    fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
        const adapter: *AbsoluteAuditInputs = @fieldParentPtr("step", step);
        const b = step.owner;
        const input_path = try adapter.input.getPath4(b, step);
        const path = try input_path.toString(b.allocator);
        adapter.output.path = b.pathResolve(&.{ b.graph.cache.cwd, path });
    }
};
