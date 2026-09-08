const std = @import("std");

comptime {
    // The source-set identity hashes embedded product inputs while compiling
    // this build script. Keep the quota local to this compile-time operation;
    // it does not affect runtime binaries.
    @setEvalBranchQuota(1_000_000);
}

const SourceIdentity = struct {
    source_set_sha256: [32]u8,
    dependency_lock_sha256: [32]u8,
    build_identity: [32]u8,
    git_executable_sha256: [32]u8,
    authoritative: bool,
};

const cache_selector_prefix = "texflow-native-cache-v2\n";
const cache_generation_name_len = 26;
const empty_cache_generation = "g-000000000000000000000000";

fn cacheGenerationName(b: *std.Build, native_deps_root: []const u8, artifact_id: []const u8) []const u8 {
    const selector_path = b.pathJoin(&.{
        native_deps_root,
        ".v2",
        artifact_id,
        "current",
    });
    const selector = std.Io.Dir.cwd().readFileAlloc(
        b.graph.io,
        selector_path,
        b.allocator,
        .limited(cache_selector_prefix.len + cache_generation_name_len + 2),
    ) catch |err| switch (err) {
        error.FileNotFound => return empty_cache_generation,
        else => @panic("unable to read the native dependency cache selector"),
    };
    defer b.allocator.free(selector);
    if (selector.len != cache_selector_prefix.len + cache_generation_name_len + 1 or
        !std.mem.startsWith(u8, selector, cache_selector_prefix) or
        selector[selector.len - 1] != '\n')
    {
        @panic("invalid native dependency cache selector");
    }
    const generation = selector[cache_selector_prefix.len .. selector.len - 1];
    if (!std.mem.startsWith(u8, generation, "g-") or generation.len != cache_generation_name_len) {
        @panic("invalid native dependency cache generation");
    }
    for (generation[2..]) |byte| {
        if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) {
            @panic("invalid native dependency cache generation");
        }
    }
    return b.dupe(generation);
}

fn cacheArchivePath(b: *std.Build, native_deps_root: []const u8, artifact_id: []const u8) []const u8 {
    return b.pathJoin(&.{
        native_deps_root,
        ".v2",
        artifact_id,
        "generations",
        cacheGenerationName(b, native_deps_root, artifact_id),
        "archive.bin",
    });
}

fn cachePayloadPath(
    b: *std.Build,
    native_deps_root: []const u8,
    artifact_id: []const u8,
    payload_root: []const u8,
) []const u8 {
    return b.pathJoin(&.{
        native_deps_root,
        ".v2",
        artifact_id,
        "generations",
        cacheGenerationName(b, native_deps_root, artifact_id),
        "payload",
        payload_root,
    });
}

fn collectSourceIdentity(b: *std.Build, source_commit: ?[]const u8) SourceIdentity {
    const git = if (b.graph.environ_map.get("TEXFLOW_GIT_PATH")) |configured| blk: {
        if (configured.len == 0 or !std.fs.path.isAbsolute(configured)) {
            @panic("T0.2 source identity requires an absolute TEXFLOW_GIT_PATH");
        }
        break :blk configured;
    } else b.findProgram(&.{ "git.exe", "git" }, &.{}) catch @panic("T0.2 source identity requires an absolute Git executable");
    if (!std.fs.path.isAbsolute(git)) @panic("T0.2 source identity requires an absolute Git executable");
    var identity_args: [12][]const u8 = undefined;
    var identity_arg_count: usize = 0;
    for ([_][]const u8{
        b.graph.zig_exe,
        "run",
        b.pathFromRoot("tools/zig/source_identity.zig"),
        "--",
        "--repo",
        b.pathFromRoot("."),
        "--git",
        git,
    }) |arg| {
        identity_args[identity_arg_count] = arg;
        identity_arg_count += 1;
    }
    if (source_commit) |commit| {
        identity_args[identity_arg_count] = "--commit";
        identity_arg_count += 1;
        identity_args[identity_arg_count] = commit;
        identity_arg_count += 1;
    }
    const output = b.run(identity_args[0..identity_arg_count]);
    var result: SourceIdentity = undefined;
    var found = [_]bool{ false, false, false, false, false, false };
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const separator = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..separator];
        const value = line[separator + 1 ..];
        if (std.mem.eql(u8, key, "source_set_sha256")) {
            _ = std.fmt.hexToBytes(&result.source_set_sha256, value) catch @panic("invalid source-set digest from Zig identity collector");
            found[0] = true;
        } else if (std.mem.eql(u8, key, "dependency_lock_sha256")) {
            _ = std.fmt.hexToBytes(&result.dependency_lock_sha256, value) catch @panic("invalid dependency-lock digest from Zig identity collector");
            found[1] = true;
        } else if (std.mem.eql(u8, key, "build_identity")) {
            _ = std.fmt.hexToBytes(&result.build_identity, value) catch @panic("invalid build identity from Zig identity collector");
            found[2] = true;
        } else if (std.mem.eql(u8, key, "git_executable_sha256")) {
            _ = std.fmt.hexToBytes(&result.git_executable_sha256, value) catch @panic("invalid Git executable digest from Zig identity collector");
            found[4] = true;
        } else if (std.mem.eql(u8, key, "git_version")) {
            if (!std.mem.startsWith(u8, value, "git version ") or value.len <= "git version ".len) @panic("invalid Git version from Zig identity collector");
            found[5] = true;
        } else if (std.mem.eql(u8, key, "authoritative")) {
            result.authoritative = if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else @panic("invalid source identity authority");
            found[3] = true;
        }
    }
    for (found) |present| if (!present) @panic("incomplete source identity output");
    return result;
}

pub fn build(b: *std.Build) void {
    const source_commit = b.graph.environ_map.get("TEXFLOW_SOURCE_COMMIT");
    const remote_run_id = b.graph.environ_map.get("TEXFLOW_REMOTE_RUN_ID");
    const remote_run_attempt = b.graph.environ_map.get("TEXFLOW_REMOTE_RUN_ATTEMPT");
    const source_identity = collectSourceIdentity(b, source_commit);
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
    const source_boundary_root = if (b.option(
        []const u8,
        "source-boundary-root",
        "Absolute repository root for the T0.2b source import boundary scan",
    )) |path| blk: {
        if (!std.fs.path.isAbsolute(path)) @panic("source-boundary-root must be absolute");
        break :blk path;
    } else b.pathFromRoot(".");
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
    // GNU Windows remains a declaration/compile-only lane; it must not be
    // mistaken for the MSVC product image or a runnable Windows evidence lane.
    const product_target = target.result.os.tag == .windows and
        target.result.cpu.arch == .x86_64 and
        target.result.abi == .msvc;
    const can_run_windows_runtime = target.result.os.tag == .windows and
        host_target.result.os.tag == .windows and
        target.result.abi == .msvc and
        target.result.cpu.arch == .x86_64 and
        host_target.result.cpu.arch == .x86_64;
    // The Windows loader can execute either x64 Windows ABI from an x64
    // Windows host; Zig's own host ABI is the compiler default, not a process
    // execution restriction. Keep the stricter ABI match for portable POSIX
    // lanes, where the selected libc/ABI is part of the runnable contract.
    const can_run_selected_target = target.result.os.tag == host_target.result.os.tag and
        target.result.cpu.arch == host_target.result.cpu.arch and
        (target.result.os.tag == .windows or target.result.abi == host_target.result.abi);
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
    if (can_run_selected_target) {
        windows_argv_step.dependOn(&run_windows_argv_tests.step);
    } else {
        windows_argv_step.dependOn(&windows_argv_tests.step);
    }
    const windows_argv_check = b.step("t0-2b-argv-check", "Compile Windows argv contracts for the selected target");
    windows_argv_check.dependOn(&windows_argv_tests.step);

    const source_boundary_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/source_boundary.zig"),
        .target = target,
        .optimize = optimize,
    });
    const source_boundary_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/source_boundary_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    source_boundary_tests.root_module.addImport("source_boundary", source_boundary_module);
    const run_source_boundary_tests = b.addRunArtifact(source_boundary_tests);
    const source_boundary_step = b.step("t0-2b-source-boundary-test", "Run the Zig source import boundary contract");
    if (can_run_selected_target) {
        source_boundary_step.dependOn(&run_source_boundary_tests.step);
    } else {
        source_boundary_step.dependOn(&source_boundary_tests.step);
    }
    const source_boundary_check = b.step("t0-2b-source-boundary-check", "Compile the source import boundary contract");
    source_boundary_check.dependOn(&source_boundary_tests.step);
    const source_boundary_tool = b.addExecutable(.{
        .name = "texflow-source-boundary",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/source_boundary.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    const run_source_boundary_tool = b.addRunArtifact(source_boundary_tool);
    run_source_boundary_tool.addArgs(&.{ "tree", source_boundary_root });
    const source_boundary_tree = b.step("t0-2b-source-boundary", "Scan the repository Zig import boundary");
    source_boundary_tree.dependOn(&run_source_boundary_tool.step);
    windows_argv_step.dependOn(source_boundary_step);

    const windows_api_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/windows_api_contract_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = target.result.os.tag == .windows,
        }),
    });
    windows_api_contract_tests.root_module.addImport("windows_api", windows_api_module);
    if (target.result.os.tag == .windows) {
        windows_api_contract_tests.root_module.addCSourceFile(.{
            .file = b.path("native/zig/tests/windows_sdk_abi_probe.c"),
            .flags = &.{"-std=c11"},
        });
    }
    const run_windows_api_contract_tests = b.addRunArtifact(windows_api_contract_tests);
    const windows_api_contract_test = b.step("t0-2b-api-contract-test", "Run the Windows SDK DXGI/DWM/WIC facade contract");
    if (can_run_selected_target) {
        windows_api_contract_test.dependOn(&run_windows_api_contract_tests.step);
    } else {
        windows_api_contract_test.dependOn(&windows_api_contract_tests.step);
    }
    const windows_api_contract_check = b.step("t0-2b-api-contract-check", "Compile the Windows SDK facade contract for the selected target");
    windows_api_contract_check.dependOn(&windows_api_contract_tests.step);

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
    const build_identity_options = b.addOptions();
    build_identity_options.addOption([32]u8, "source_set_sha256", source_identity.source_set_sha256);
    build_identity_options.addOption([32]u8, "dependency_lock_sha256", source_identity.dependency_lock_sha256);
    build_identity_options.addOption([32]u8, "build_identity", source_identity.build_identity);
    // The source/index digest is useful for every developer build, but it is
    // evidence-grade only for the locked product profile.  In particular,
    // Debug, ReleaseFast, FLIP_DISCARD, non-MSVC, and non-baseline CPU builds
    // must never inherit the admitted identity merely because the checkout is
    // clean.
    var baseline_query = target.query;
    baseline_query.cpu_model = .baseline;
    baseline_query.cpu_features_add = .empty;
    baseline_query.cpu_features_sub = .empty;
    const baseline_target = b.resolveTargetQuery(baseline_query);
    const exact_baseline_cpu = target.result.cpu.arch == baseline_target.result.cpu.arch and
        std.meta.eql(target.result.cpu.features, baseline_target.result.cpu.features);
    const authoritative_product_identity = source_identity.authoritative and
        product_target and
        optimize == .ReleaseSafe and
        !use_discard_swap_effect and
        std.mem.eql(u8, target.result.cpu.model.name, "baseline") and
        exact_baseline_cpu;
    build_identity_options.addOption(bool, "authoritative", authoritative_product_identity);
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
    const app_atomic_save_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/app/atomic_save.zig"),
        .target = target,
        .optimize = optimize,
    });
    const atomic_save_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/atomic_save_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    atomic_save_tests.root_module.addImport("atomic_save", app_atomic_save_module);
    const run_atomic_save_tests = b.addRunArtifact(atomic_save_tests);
    const atomic_save_test_step = b.step("t1-1c-atomic-save-test", "Run T1.1c atomic-save and external-change precondition tests");
    atomic_save_test_step.dependOn(&run_atomic_save_tests.step);
    const atomic_save_check_step = b.step("t1-1c-atomic-save-check", "Compile T1.1c atomic-save tests for the selected target");
    atomic_save_check_step.dependOn(&atomic_save_tests.step);
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
    const telemetry_native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/telemetry_native_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    telemetry_native_tests.root_module.addImport("windows_telemetry", windows_telemetry_module);
    if (target.result.os.tag == .windows) telemetry_native_tests.root_module.linkSystemLibrary("advapi32", .{});
    const telemetry_native_run = b.addRunArtifact(telemetry_native_tests);
    const telemetry_native_test_step = b.step("t0-2c-telemetry-native-test", "Exercise the native ETW provider ABI");
    telemetry_native_test_step.dependOn(&telemetry_native_run.step);
    const telemetry_native_check_step = b.step("t0-2c-telemetry-native-check", "Compile the native ETW provider ABI");
    telemetry_native_check_step.dependOn(&telemetry_native_tests.step);
    t0_2c_models_test.dependOn(&telemetry_native_run.step);
    t0_2c_models_check.dependOn(&telemetry_native_tests.step);
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
    const composition_native_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/composition_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    composition_native_module.addImport("windows_api", windows_api_module);
    composition_native_module.addImport("graphics", graphics_module);
    composition_native_module.addImport("app_role", app_role_module);
    composition_native_module.addImport("app_layout", app_layout_module);
    composition_native_module.addImport("app_strings", app_strings_module);
    const composition_native_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/composition_native_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    composition_native_tests.root_module.addImport("composition_native", composition_native_module);
    composition_native_tests.root_module.addImport("graphics", graphics_module);
    composition_native_tests.root_module.addImport("app_layout", app_layout_module);
    const run_composition_native_tests = b.addRunArtifact(composition_native_tests);
    const composition_native_test_step = b.step("t0-2c-composition-test", "Run the native Direct2D/DirectWrite composition contracts");
    composition_native_test_step.dependOn(&run_composition_native_tests.step);
    const composition_native_check_step = b.step("t0-2c-composition-check", "Compile the native Direct2D/DirectWrite composition contracts");
    composition_native_check_step.dependOn(&composition_native_tests.step);
    t0_2c_models_test.dependOn(&run_composition_native_tests.step);
    t0_2c_models_check.dependOn(&composition_native_tests.step);
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
    shell_native_module.addOptions("build_identity_config", build_identity_options);
    shell_native_module.addImport("windows_shell", windows_shell_module);
    shell_native_module.addImport("windows_com", windows_com_module);
    shell_native_module.addImport("ui_entry", ui_entry_module);
    shell_native_module.addImport("app_role", app_role_module);
    shell_native_module.addImport("app_build_identity", app_build_identity_module);
    shell_native_module.addImport("app_layout", app_layout_module);
    shell_native_module.addImport("app_uia_shell", app_uia_shell_module);
    shell_native_module.addImport("app_strings", app_strings_module);
    shell_native_module.addImport("windows_telemetry", windows_telemetry_module);
    shell_native_module.addImport("graphics", graphics_module);
    shell_native_module.addImport("composition_native", composition_native_module);
    shell_native_module.addImport("presenter_native", presenter_native_module);
    shell_native_module.addImport("windows_qos", b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/qos.zig"),
        .target = target,
        .optimize = optimize,
    }));
    if (target.result.os.tag == .windows) {
        inline for (.{ "kernel32", "user32", "shell32", "ole32", "bcrypt", "advapi32", "d3d11", "dxgi", "d2d1", "dwrite" }) |library| shell_native_module.linkSystemLibrary(library, .{});
    }
    // Generate the exact ICO once per build graph.  Both the product and the
    // native runtime test consume this same resource, so the test exercises
    // the real class-icon lookup instead of silently relying on a default.
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
    const product_build_step = b.step("t0-2c-product-build", "Build the x64 Windows GUI product without installing");
    if (product_target) {
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
    shell_native_tests.root_module.addImport("composition_native", composition_native_module);
    shell_native_tests.root_module.addImport("presenter_native", presenter_native_module);
    if (target.result.os.tag == .windows) {
        shell_native_tests.root_module.addWin32ResourceFile(.{
            .file = icon_rc,
            .flags = &.{"/x"},
            .include_paths = &.{},
        });
    }
    const run_shell_native_tests = b.addRunArtifact(shell_native_tests);
    const shell_native_test_step = b.step("t0-2c-shell-native-test", "Test narrow Win32 ABI command line and COM contracts");
    shell_native_test_step.dependOn(&run_shell_native_tests.step);
    const shell_native_check_step = b.step("t0-2c-shell-native-check", "Compile narrow Win32 ABI contracts");
    shell_native_check_step.dependOn(&shell_native_tests.step);
    t0_2c_models_test.dependOn(&run_shell_native_tests.step);
    t0_2c_models_check.dependOn(&shell_native_tests.step);
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
    product_tests.root_module.addImport("windows_api", windows_api_module);
    product_tests.root_module.addImport("windows_com", windows_com_module);
    product_tests.root_module.addImport("app_layout", app_layout_module);
    product_tests.root_module.addImport("app_version_resource", app_version_resource_module);
    product_tests.root_module.addImport("texflow_icon", texflow_icon_module);
    if (target.result.os.tag == .windows) {
        inline for (.{ "user32", "ole32", "oleaut32" }) |library| product_tests.root_module.linkSystemLibrary(library, .{});
    }
    const run_product_tests = b.addRunArtifact(product_tests);
    const product_test_step = b.step("t0-2c-product-test", "Run native product PE/runtime checks on matching Windows MSVC hosts; otherwise compile the contract");
    if (can_run_windows_runtime) {
        product_test_step.dependOn(&run_product_tests.step);
    } else {
        product_test_step.dependOn(&product_tests.step);
    }
    if (product_target) product_test_step.dependOn(product_build_step);
    const product_check_step = b.step("t0-2c-product-check", "Compile product contract tests without execution");
    product_check_step.dependOn(&product_tests.step);
    // Keep the aggregate honest: T0.2c models include the product contract
    // compile on every target, and execute the product only in the matching
    // x64 Windows MSVC runtime lane. T1.1 suites have their own gates above.
    t0_2c_models_check.dependOn(&product_tests.step);
    if (product_target) t0_2c_models_test.dependOn(product_build_step);
    if (can_run_windows_runtime) t0_2c_models_test.dependOn(product_test_step);
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
    const pe_audit_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/pe_audit.zig"),
        .target = host_target,
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
    const pe_closure_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/pe_closure.zig"),
        .target = target,
        .optimize = optimize,
    });
    pe_closure_module.addImport("pe_audit", pe_audit_module);
    const pe_closure_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pe_closure_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pe_closure_tests.root_module.addImport("pe_closure", pe_closure_module);
    pe_closure_tests.root_module.addImport("pe_audit", pe_audit_module);
    const pe_closure_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/pe_closure.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    pe_closure_host_module.addImport("pe_audit", pe_audit_host_module);
    const pe_closure_host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pe_closure_test.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    pe_closure_host_tests.root_module.addImport("pe_closure", pe_closure_host_module);
    pe_closure_host_tests.root_module.addImport("pe_audit", pe_audit_host_module);
    const pe_closure_run = b.addRunArtifact(pe_closure_host_tests);
    const pe_closure_test_step = b.step("t0-2b-pe-closure-test", "Run the fixture-driven recursive PE role closure oracle");
    pe_closure_test_step.dependOn(&pe_closure_run.step);
    const pe_closure_check_step = b.step("t0-2b-pe-closure-check", "Compile the PE role closure oracle for the selected target");
    pe_closure_check_step.dependOn(&pe_closure_tests.step);

    // Real release-payload PE inventory oracle. This lane is host-runtime
    // only on Windows; Linux and cross-target invocations compile the same
    // authenticated manifest surface without claiming Windows evidence.
    const shipped_pe_inventory_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/shipped_pe_inventory.zig"),
        .target = target,
        .optimize = optimize,
    });
    shipped_pe_inventory_module.addImport("pe_audit", pe_audit_module);
    const shipped_pe_inventory_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/shipped_pe_inventory_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    shipped_pe_inventory_tests.root_module.addImport("shipped_pe_inventory", shipped_pe_inventory_module);
    shipped_pe_inventory_tests.root_module.addImport("pe_audit", pe_audit_module);
    const shipped_pe_inventory_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/shipped_pe_inventory.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    shipped_pe_inventory_host_module.addImport("pe_audit", pe_audit_host_module);
    const shipped_pe_inventory_host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/shipped_pe_inventory_test.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    shipped_pe_inventory_host_tests.root_module.addImport("shipped_pe_inventory", shipped_pe_inventory_host_module);
    shipped_pe_inventory_host_tests.root_module.addImport("pe_audit", pe_audit_host_module);
    const shipped_pe_inventory_run = b.addRunArtifact(shipped_pe_inventory_host_tests);
    const shipped_pe_inventory_test_step = b.step("t0-2b-shipped-pe-inventory-test", "Run the authenticated Windows payload PE inventory oracle");
    if (host_target.result.os.tag == .windows and target.result.os.tag == .windows) {
        shipped_pe_inventory_test_step.dependOn(&shipped_pe_inventory_run.step);
    } else {
        shipped_pe_inventory_test_step.dependOn(&shipped_pe_inventory_tests.step);
    }
    const shipped_pe_inventory_check_step = b.step("t0-2b-shipped-pe-inventory-check", "Compile the authenticated payload PE inventory for the selected target");
    shipped_pe_inventory_check_step.dependOn(&shipped_pe_inventory_tests.step);
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
    const pe_audit_test_run = b.addRunArtifact(pe_audit_tests);
    const pe_audit_test_step = b.step("t0-2b-pe-test", "Test the offline static PE32+ auditor");
    if (can_run_selected_target) {
        pe_audit_test_step.dependOn(&pe_audit_test_run.step);
    } else {
        pe_audit_test_step.dependOn(&pe_audit_tests.step);
    }
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
    if (can_run_selected_target) {
        package_probe_test.dependOn(&run_package_probe_tests.step);
    } else {
        package_probe_test.dependOn(&package_probe_tests.step);
    }
    const package_probe_check = b.step("t0-2b-package-check", "Compile the package oracle tests for the selected target");
    package_probe_check.dependOn(&package_probe_tests.step);

    // Isolated T0.2b SQLite contract; no install or product/runtime edge.
    const sqlite_source = b.option([]const u8, "sqlite-source", "Absolute directory containing the exact locked SQLite 3.53.4 sqlite3.c and sqlite3.h (offline only)") orelse
        cachePayloadPath(b, native_deps_root, "sqlite", "sqlite-autoconf-3530400");
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
    const repro_check_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/repro_check.zig"),
        .target = host_target,
        .optimize = .ReleaseSafe,
    });
    repro_check_host_module.addImport("deps", deps_host_module);
    const repro_check_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/repro_check_test.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    repro_check_tests.root_module.addImport("repro_check", repro_check_host_module);
    const run_repro_check_tests = b.addRunArtifact(repro_check_tests);
    const repro_check_test_step = b.step("t0-2b-repro-test", "Run the offline reproducibility and sealed-runner preflight oracle");
    repro_check_test_step.dependOn(&run_repro_check_tests.step);
    const repro_check_target_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/repro_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    repro_check_target_module.addImport("deps", deps_module);
    const repro_check_target = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/repro_check_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    repro_check_target.root_module.addImport("repro_check", repro_check_target_module);
    const repro_check_target_step = b.step("t0-2b-repro-check", "Compile the reproducibility oracle for the selected target");
    repro_check_target_step.dependOn(&repro_check_target.step);
    const pdfium_repro_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/pdfium_reproduce.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const pdfium_repro_host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdfium_repro_toolchain_test.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    pdfium_repro_host_tests.root_module.addImport("pdfium_reproduce", pdfium_repro_host_module);
    const pdfium_repro_run = b.addRunArtifact(pdfium_repro_host_tests);
    const pdfium_repro_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/pdfium_reproduce.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pdfium_repro_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdfium_repro_toolchain_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pdfium_repro_tests.root_module.addImport("pdfium_reproduce", pdfium_repro_module);
    const pdfium_repro_test_step = b.step("t0-2b-pdfium-repro-test", "Run the offline PDFium reconstruction receipt schema oracle");
    pdfium_repro_test_step.dependOn(&pdfium_repro_run.step);
    const pdfium_repro_check_step = b.step("t0-2b-pdfium-repro-check", "Compile the PDFium reconstruction receipt oracle for the selected target");
    pdfium_repro_check_step.dependOn(&pdfium_repro_tests.step);
    const scintilla_runtime_contract_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/scintilla_runtime_contract.zig"),
        .target = host_target,
        .optimize = optimize,
    });
    const scintilla_runtime_contract_host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/scintilla_runtime_contract_test.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    scintilla_runtime_contract_host_tests.root_module.addImport("scintilla_runtime_contract", scintilla_runtime_contract_host_module);
    const scintilla_runtime_contract_run = b.addRunArtifact(scintilla_runtime_contract_host_tests);
    const scintilla_runtime_contract_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/scintilla_runtime_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const scintilla_runtime_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/scintilla_runtime_contract_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scintilla_runtime_contract_tests.root_module.addImport("scintilla_runtime_contract", scintilla_runtime_contract_module);
    const scintilla_runtime_contract_test_step = b.step("t0-2b-scintilla-runtime-contract-test", "Run the Windows-only Scintilla lifecycle contract oracle");
    scintilla_runtime_contract_test_step.dependOn(&scintilla_runtime_contract_run.step);
    const scintilla_runtime_contract_check_step = b.step("t0-2b-scintilla-runtime-contract-check", "Compile the Scintilla lifecycle contract for the selected target");
    scintilla_runtime_contract_check_step.dependOn(&scintilla_runtime_contract_tests.step);
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
        cacheArchivePath(b, native_deps_root, "scintilla");
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
    const scintilla_library: ?*std.Build.Step.Compile = if (target.result.os.tag == .windows and target.result.abi == .msvc) library: {
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
    const run_scintilla_tests = b.addRunArtifact(scintilla_tests);
    const scintilla_test_step = b.step("t0-2b-scintilla-test", "Run the unshipped Scintilla source and build contract tests");
    if (can_run_selected_target) {
        scintilla_test_step.dependOn(&run_scintilla_tests.step);
    } else {
        scintilla_test_step.dependOn(&scintilla_tests.step);
    }
    b.step("t0-2b-scintilla-check", "Compile Scintilla contract tests only; no Win32 C++ compilation on Linux").dependOn(&scintilla_tests.step);

    // Native HWND/document/style probe. The target-facing artifact is always
    // compile-only; it is linked and executed only when both the selected
    // target and the host are x86_64 Windows, against the unshipped static
    // Scintilla snapshot above.
    const can_run_native_scintilla = host_target.result.os.tag == .windows and
        target.result.os.tag == .windows and
        target.result.abi == .msvc and
        host_target.result.cpu.arch == .x86_64 and
        target.result.cpu.arch == .x86_64;
    // On a Windows host whose Zig default ABI is GNU, the selected MSVC
    // target is still runnable and is the only honest native-runtime lane.
    // On Linux/macOS, retain host-target declarations for compile-only checks.
    const scintilla_native_probe_run_target = if (can_run_native_scintilla) target else host_target;
    const scintilla_native_probe_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/scintilla_native_probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = false,
    });
    const scintilla_native_probe_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/scintilla_native_probe_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = false,
        }),
    });
    scintilla_native_probe_tests.root_module.addImport("scintilla_native_probe", scintilla_native_probe_module);
    const scintilla_native_probe_host_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/scintilla_native_probe.zig"),
        .target = scintilla_native_probe_run_target,
        .optimize = optimize,
        .link_libc = false,
    });
    const scintilla_native_probe_host_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/scintilla_native_probe_test.zig"),
            .target = scintilla_native_probe_run_target,
            .optimize = optimize,
            .link_libc = can_run_native_scintilla,
        }),
    });
    scintilla_native_probe_host_tests.root_module.addImport("scintilla_native_probe", scintilla_native_probe_host_module);
    if (scintilla_library) |library| {
        if (can_run_native_scintilla) {
            // Link the emitted archive as a raw static path rather than as a
            // Build compile dependency. The Scintilla archive is compiled
            // with its own MSVC `/MT` runtime; keeping it out of the Build
            // dependency graph prevents its compile-time libc flag from
            // leaking into other targets. The probe executable itself uses
            // the selected MSVC target's Zig-managed CRT below.
            scintilla_native_probe_host_tests.root_module.addObjectFile(library.getEmittedBin());
            // Scintilla's MSVC-mode C++ objects carry /DEFAULTLIB records for
            // the MSVC runtime and uuid.lib. Resolve those through the same
            // installed SDK discovery used by the source build; never bake a
            // developer-machine path into the project.
            if (std.zig.WindowsSdk.find(b.allocator, b.graph.io, scintilla_native_probe_run_target.result.cpu.arch, &b.graph.environ_map)) |sdk| {
                if (sdk.msvc_lib_dir) |msvc_lib_dir| {
                    scintilla_native_probe_host_tests.root_module.addLibraryPath(.{ .cwd_relative = msvc_lib_dir });
                }
                if (sdk.windows10sdk) |windows_sdk| {
                    const sdk_arch = switch (scintilla_native_probe_run_target.result.cpu.arch) {
                        .x86_64 => "x64",
                        .x86 => "x86",
                        .aarch64 => "arm64",
                        else => "x64",
                    };
                    const sdk_um = b.pathJoin(&.{ windows_sdk.path, "Lib", windows_sdk.version, "um", sdk_arch });
                    const sdk_ucrt = b.pathJoin(&.{ windows_sdk.path, "Lib", windows_sdk.version, "ucrt", sdk_arch });
                    scintilla_native_probe_host_tests.root_module.addLibraryPath(.{ .cwd_relative = sdk_um });
                    scintilla_native_probe_host_tests.root_module.addLibraryPath(.{ .cwd_relative = sdk_ucrt });
                    scintilla_native_probe_host_tests.root_module.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ sdk_um, "uuid.lib" }) });
                }
            } else |_| {}
            inline for (.{ "advapi32", "comctl32", "d2d1", "d3d11", "dwrite", "gdi32", "imm32", "kernel32", "msimg32", "ole32", "oleaut32", "oldnames", "shell32", "shlwapi", "uxtheme", "user32", "usp10", "version", "dxgi" }) |library_name| {
                scintilla_native_probe_host_tests.root_module.linkSystemLibrary(library_name, .{});
            }
        }
    }
    const scintilla_native_probe_run = b.addRunArtifact(scintilla_native_probe_host_tests);
    const scintilla_native_probe_test_step = b.step("t0-2b-scintilla-native-test", "Run the real Windows Scintilla HWND/document/style probe");
    if (can_run_native_scintilla and scintilla_library != null) {
        scintilla_native_probe_test_step.dependOn(&scintilla_native_probe_run.step);
    } else {
        scintilla_native_probe_test_step.dependOn(&scintilla_native_probe_tests.step);
    }
    const scintilla_native_probe_check_step = b.step("t0-2b-scintilla-native-check", "Compile the Scintilla native probe for the selected target");
    scintilla_native_probe_check_step.dependOn(&scintilla_native_probe_tests.step);
    const lexilla_probe_module = b.createModule(.{
        .root_source_file = b.path("tools/zig/lexilla_probe.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexilla_probe_module.addImport("deps", deps_module);
    const lexilla_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/lexilla_comparator_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lexilla_tests.root_module.addImport("lexilla_probe", lexilla_probe_module);
    lexilla_tests.root_module.addImport("deps", deps_module);
    const lexilla_contract = b.addOptions();
    const lexilla_archive = b.option([]const u8, "lexilla-archive", "Absolute path to the exact Lexilla 5.5.3 archive (offline only)") orelse
        cacheArchivePath(b, native_deps_root, "lexilla");
    lexilla_contract.addOption([]const u8, "archive_path", lexilla_archive);
    const lexilla_probe = b.addExecutable(.{
        .name = "texflow-lexilla-source-probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/zig/lexilla_probe.zig"),
            .target = host_target,
            .optimize = .ReleaseSafe,
        }),
    });
    lexilla_probe.root_module.addImport("deps", deps_host_module);
    const lexilla_snapshot = b.addRunArtifact(lexilla_probe);
    lexilla_snapshot.addArgs(&.{ "snapshot", lexilla_archive });
    lexilla_snapshot.has_side_effects = true;
    const lexilla_snapshot_output = lexilla_snapshot.addOutputDirectoryArg("lexilla-5.5.3-verified");
    const lexilla_root = lexilla_snapshot_output.path(b, "payload/lexilla");
    if (target.result.os.tag == .windows and target.result.abi == .msvc) {
        lexilla_contract.addOptionPath("source_root", lexilla_root);
        lexilla_contract.addOptionPath("snapshot_receipt_path", lexilla_snapshot_output.path(b, "payload.lock.json"));
    } else {
        lexilla_contract.addOption([]const u8, "source_root", "not-in-scope-on-linux");
        lexilla_contract.addOption([]const u8, "snapshot_receipt_path", "not-in-scope-on-linux");
    }
    const lexilla_inventory = @import("tools/zig/lexilla_probe.zig");
    const lexilla_flags = switch (optimize) {
        inline else => |mode| lexilla_inventory.cxxFlags(mode),
    };
    const lexilla_library: ?*std.Build.Step.Compile = if (target.result.os.tag == .windows and target.result.abi == .msvc) library: {
        const library = b.addLibrary(.{
            .name = lexilla_inventory.artifact_name,
            .linkage = .static,
            .root_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true }),
        });
        library.step.dependOn(&lexilla_snapshot.step);
        lexilla_root.addStepDependencies(&library.step);
        library.root_module.addIncludePath(lexilla_root.path(b, "include"));
        library.root_module.addIncludePath(lexilla_root.path(b, "lexlib"));
        library.root_module.addIncludePath(scintilla_root.path(b, "include"));
        library.root_module.addIncludePath(scintilla_root.path(b, "src"));
        library.root_module.addCSourceFiles(.{ .root = lexilla_root, .files = &lexilla_inventory.sources, .flags = lexilla_flags });
        _ = library.getEmittedBin();
        break :library library;
    } else null;
    var lexilla_size_receipt: ?std.Build.LazyPath = null;
    const lexilla_size_run: ?*std.Build.Step.Run = if (lexilla_library) |library| size_run: {
        const lexilla_size_probe = b.addExecutable(.{
            .name = "texflow-lexilla-size-probe",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tools/zig/lexilla_size_probe.zig"),
                .target = host_target,
                .optimize = .ReleaseSafe,
            }),
        });
        const lexilla_size_run = b.addRunArtifact(lexilla_size_probe);
        lexilla_size_run.addFileArg(library.getEmittedBin());
        const lexilla_size_source = lexilla_size_run.addOutputFileArg("lexilla-artifact-size.zig");
        lexilla_size_receipt = lexilla_size_source;
        lexilla_tests.root_module.addImport("lexilla_size", b.createModule(.{
            .root_source_file = lexilla_size_source,
            .target = target,
            .optimize = optimize,
        }));
        lexilla_size_run.step.dependOn(&library.step);
        break :size_run lexilla_size_run;
    } else null;
    if (lexilla_library) |library| {
        const inputs = library.root_module.link_objects.items[0].c_source_files;
        lexilla_contract.addOption([]const []const u8, "source_files", inputs.files);
        lexilla_contract.addOption([]const []const u8, "cxx_flags", inputs.flags);
        lexilla_contract.addOption([]const u8, "artifact_kind", @tagName(library.kind));
        lexilla_contract.addOption([]const u8, "artifact_linkage", @tagName(library.linkage.?));
        lexilla_contract.addOptionPath("artifact_path", library.getEmittedBin());
    } else {
        lexilla_contract.addOption([]const []const u8, "source_files", &lexilla_inventory.sources);
        lexilla_contract.addOption([]const []const u8, "cxx_flags", lexilla_flags);
        lexilla_contract.addOption([]const u8, "artifact_kind", "absent");
        lexilla_contract.addOption([]const u8, "artifact_linkage", "absent");
        lexilla_contract.addOption([]const u8, "artifact_path", "");
    }
    lexilla_contract.addOption(bool, "library_created", lexilla_library != null);
    lexilla_contract.addOption([]const []const u8, "fixtures", &lexilla_inventory.reviewed_fixtures);
    lexilla_contract.addOption([]const []const u8, "archive_member_names", &lexilla_inventory.archive_member_names);
    lexilla_contract.addOption([]const u8, "artifact_name", lexilla_inventory.artifact_name);
    lexilla_contract.addOption([]const u8, "archive_sha256", lexilla_inventory.archive_sha256);
    lexilla_contract.addOption([]const u8, "license_spdx", lexilla_inventory.license_spdx);
    lexilla_contract.addOption([]const u8, "license_sha256", lexilla_inventory.license_sha256);
    if (lexilla_size_receipt) |receipt| {
        lexilla_contract.addOptionPath("artifact_size_receipt", receipt);
    } else {
        lexilla_contract.addOption([]const u8, "artifact_size_receipt", "");
    }
    lexilla_tests.root_module.addOptions("lexilla_contract", lexilla_contract);
    const lexilla_run = b.addRunArtifact(lexilla_tests);
    lexilla_run.step.dependOn(&lexilla_snapshot.step);
    if (lexilla_library) |library| lexilla_run.step.dependOn(&library.step);
    if (lexilla_size_run) |size_run| lexilla_run.step.dependOn(&size_run.step);
    const lexilla_test_step = b.step("t0-2b-lexilla-test", "Run the unshipped Lexilla comparator contract");
    if (can_run_selected_target) {
        lexilla_test_step.dependOn(&lexilla_run.step);
    } else {
        lexilla_test_step.dependOn(&lexilla_tests.step);
    }
    const lexilla_check_step = b.step("t0-2b-lexilla-check", "Compile the Lexilla comparator contract only; no Win32 C++ compilation on Linux");
    lexilla_check_step.dependOn(&lexilla_tests.step);
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

    // T0.2d Editor text units, lexer, and large-book fixture
    const text_units_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/text_units.zig"),
        .target = target,
        .optimize = optimize,
    });
    text_units_module.addImport("unicode", unicode_module);

    const editor_lexer_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });

    const large_book_fixture_module = b.createModule(.{
        .root_source_file = b.path("native/zig/fixtures/t0_2/large_book.zig"),
        .target = target,
        .optimize = optimize,
    });

    const editor_model_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/model.zig"),
        .target = target,
        .optimize = optimize,
    });
    editor_model_module.addImport("editor_buffer", app_editor_buffer_module);
    editor_model_module.addImport("text_units", text_units_module);

    const editor_model_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/editor_model_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    editor_model_tests.root_module.addImport("editor_model", editor_model_module);
    editor_model_tests.root_module.addImport("editor_buffer", app_editor_buffer_module);
    editor_model_tests.root_module.addImport("text_units", text_units_module);
    const run_editor_model_tests = b.addRunArtifact(editor_model_tests);
    const editor_model_test_step = b.step("t0-2d-model-test", "Run T0.2d editor model and line indexing tests");
    editor_model_test_step.dependOn(&run_editor_model_tests.step);
    const editor_model_check_step = b.step("t0-2d-model-check", "Compile T0.2d editor model contracts");
    editor_model_check_step.dependOn(&editor_model_tests.step);

    const text_units_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/text_units_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    text_units_tests.root_module.addImport("text_units", text_units_module);
    const run_text_units_tests = b.addRunArtifact(text_units_tests);
    const text_units_test_step = b.step("t0-2d-text-units-test", "Run T0.2d UAX-29 text unit and UTF boundary tests");
    text_units_test_step.dependOn(&run_text_units_tests.step);
    const text_units_check_step = b.step("t0-2d-text-units-check", "Compile T0.2d UAX-29 text unit contracts");
    text_units_check_step.dependOn(&text_units_tests.step);

    const lexer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/lexer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lexer_tests.root_module.addImport("lexer", editor_lexer_module);
    const run_lexer_tests = b.addRunArtifact(lexer_tests);
    const lexer_test_step = b.step("t0-2d-lexer-test", "Run T0.2d LaTeX/BibTeX container lexer tests");
    lexer_test_step.dependOn(&run_lexer_tests.step);
    const lexer_check_step = b.step("t0-2d-lexer-check", "Compile T0.2d LaTeX/BibTeX container lexer contracts");
    lexer_check_step.dependOn(&lexer_tests.step);

    const large_book_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/large_book_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    large_book_tests.root_module.addImport("large_book", large_book_fixture_module);
    const run_large_book_tests = b.addRunArtifact(large_book_tests);
    const large_book_test_step = b.step("t0-2d-large-book-test", "Run T0.2d deterministic 10 MiB large-book fixture tests");
    large_book_test_step.dependOn(&run_large_book_tests.step);
    const large_book_check_step = b.step("t0-2d-large-book-check", "Compile T0.2d 10 MiB large-book fixture tests");
    large_book_check_step.dependOn(&large_book_tests.step);

    // T0.2d UIA modules and Scintilla editor wrapper
    const uia_snapshot_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/uia/snapshot.zig"),
        .target = target,
        .optimize = optimize,
    });
    uia_snapshot_module.addImport("text_units", text_units_module);

    const uia_range_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/uia/range.zig"),
        .target = target,
        .optimize = optimize,
    });
    uia_range_module.addImport("text_units", text_units_module);
    uia_range_module.addImport("uia_snapshot", uia_snapshot_module);

    const uia_thread_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/uia/thread.zig"),
        .target = target,
        .optimize = optimize,
    });
    uia_thread_module.addImport("text_units", text_units_module);
    uia_thread_module.addImport("uia_snapshot", uia_snapshot_module);
    uia_thread_module.addImport("uia_range", uia_range_module);

    const uia_provider_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/editor/uia/provider.zig"),
        .target = target,
        .optimize = optimize,
    });
    uia_provider_module.addImport("text_units", text_units_module);
    uia_provider_module.addImport("uia_snapshot", uia_snapshot_module);
    uia_provider_module.addImport("uia_range", uia_range_module);
    uia_provider_module.addImport("uia_thread", uia_thread_module);

    // T0.2d UIA provider tests
    const uia_provider_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/uia_provider_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    uia_provider_tests.root_module.addImport("uia_snapshot", uia_snapshot_module);
    uia_provider_tests.root_module.addImport("uia_range", uia_range_module);
    uia_provider_tests.root_module.addImport("uia_thread", uia_thread_module);
    uia_provider_tests.root_module.addImport("uia_provider", uia_provider_module);
    const run_uia_provider_tests = b.addRunArtifact(uia_provider_tests);
    const uia_provider_test_step = b.step("t0-2d-uia-provider-test", "Run T0.2d UIA text provider contract and range tests");
    uia_provider_test_step.dependOn(&run_uia_provider_tests.step);
    const uia_provider_check_step = b.step("t0-2d-uia-provider-check", "Compile T0.2d UIA provider contracts");
    uia_provider_check_step.dependOn(&uia_provider_tests.step);

    // T0.2d Scintilla editor compile check (no tests yet, compile-only)
    const scintilla_editor_check = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/src/editor/scintilla.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const scintilla_editor_check_step = b.step("t0-2d-scintilla-editor-check", "Compile T0.2d Scintilla editor wrapper");
    scintilla_editor_check_step.dependOn(&scintilla_editor_check.step);

    // T0.2d UIA QA client
    const uia_client_module = b.createModule(.{
        .root_source_file = b.path("native/zig/qa/uia_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        uia_client_module.addImport("windows_com", windows_com_module);
        uia_client_module.addImport("windows_api", windows_api_module);
        inline for (.{ "kernel32", "user32", "ole32", "oleaut32" }) |library| {
            uia_client_module.linkSystemLibrary(library, .{});
        }
    }
    const uia_client_tests = b.addTest(.{
        .root_module = uia_client_module,
    });
    const run_uia_client_tests = b.addRunArtifact(uia_client_tests);
    const uia_client_test_step = b.step("t0-2d-uia-client-test", "Run T0.2d UIA client MTA discovery and query tests");
    uia_client_test_step.dependOn(&run_uia_client_tests.step);
    const uia_client_check_step = b.step("t0-2d-uia-client-check", "Compile T0.2d UIA client contracts");
    uia_client_check_step.dependOn(&uia_client_tests.step);

    const uia_client_exe = b.addExecutable(.{
        .name = "texflow-t0-2d-uia-client",
        .root_module = uia_client_module,
    });
    const uia_client_exe_step = b.step("t0-2d-uia-client-exe", "Build the T0.2d out-of-process UIA QA client executable");
    uia_client_exe_step.dependOn(&uia_client_exe.step);

    // T0.2d aggregate steps
    const t0_2d_test_step = b.step("t0-2d-test", "Run all T0.2d editor, lexer, UIA, and fixture tests");
    t0_2d_test_step.dependOn(editor_model_test_step);
    t0_2d_test_step.dependOn(text_units_test_step);
    t0_2d_test_step.dependOn(lexer_test_step);
    t0_2d_test_step.dependOn(large_book_test_step);
    t0_2d_test_step.dependOn(uia_provider_test_step);
    t0_2d_test_step.dependOn(uia_client_test_step);

    const t0_2d_check_step = b.step("t0-2d-check", "Compile all T0.2d contracts and QA targets");
    t0_2d_check_step.dependOn(editor_model_check_step);
    t0_2d_check_step.dependOn(text_units_check_step);
    t0_2d_check_step.dependOn(lexer_check_step);
    t0_2d_check_step.dependOn(large_book_check_step);
    t0_2d_check_step.dependOn(scintilla_editor_check_step);
    t0_2d_check_step.dependOn(uia_provider_check_step);
    t0_2d_check_step.dependOn(uia_client_check_step);
    t0_2d_check_step.dependOn(uia_client_exe_step);

    // T0.2e IPC & PDF Worker modules
    const ipc_frame_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/ipc/frame.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ipc_peer_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/ipc/peer.zig"),
        .target = target,
        .optimize = optimize,
    });
    ipc_peer_module.addImport("frame.zig", ipc_frame_module);

    const ipc_pipe_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/ipc/pipe.zig"),
        .target = target,
        .optimize = optimize,
    });

    const platform_process_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/process.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pdf_protocol_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pdf_tile_handoff_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf/tile_handoff.zig"),
        .target = target,
        .optimize = optimize,
    });
    pdf_tile_handoff_module.addImport("protocol.zig", pdf_protocol_module);

    const pdf_tile_cache_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf/tile_cache.zig"),
        .target = target,
        .optimize = optimize,
    });
    pdf_tile_cache_module.addImport("protocol.zig", pdf_protocol_module);

    const pdf_uia_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf/uia.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pdf_worker_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf/worker.zig"),
        .target = target,
        .optimize = optimize,
    });
    pdf_worker_module.addImport("../ipc/frame.zig", ipc_frame_module);
    pdf_worker_module.addImport("../ipc/peer.zig", ipc_peer_module);
    pdf_worker_module.addImport("../ipc/pipe.zig", ipc_pipe_module);
    pdf_worker_module.addImport("protocol.zig", pdf_protocol_module);
    pdf_worker_module.addImport("pdfium.zig", pdfium_module);

    const pdf_corpus_module = b.createModule(.{
        .root_source_file = b.path("native/zig/fixtures/t0_2/pdf_corpus.zig"),
        .target = target,
        .optimize = optimize,
    });

    // T0.2e Tests
    const ipc_property_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/ipc_property_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    ipc_property_tests.root_module.addImport("ipc_frame", ipc_frame_module);
    ipc_property_tests.root_module.addImport("ipc_peer", ipc_peer_module);
    const run_ipc_property_tests = b.addRunArtifact(ipc_property_tests);
    const ipc_property_test_step = b.step("t0-2e-ipc-test", "Run T0.2e IPC property and HMAC tests");
    ipc_property_test_step.dependOn(&run_ipc_property_tests.step);
    const ipc_property_check_step = b.step("t0-2e-ipc-check", "Compile T0.2e IPC property contracts");
    ipc_property_check_step.dependOn(&ipc_property_tests.step);

    const lpac_boundary_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/lpac_boundary_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lpac_boundary_tests.root_module.addImport("platform_process", platform_process_module);
    const run_lpac_boundary_tests = b.addRunArtifact(lpac_boundary_tests);
    const lpac_boundary_test_step = b.step("t0-2e-lpac-test", "Run T0.2e LPAC process and token boundary tests");
    lpac_boundary_test_step.dependOn(&run_lpac_boundary_tests.step);
    const lpac_boundary_check_step = b.step("t0-2e-lpac-check", "Compile T0.2e LPAC process contracts");
    lpac_boundary_check_step.dependOn(&lpac_boundary_tests.step);

    const pdf_geometry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdf_geometry_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pdf_geometry_tests.root_module.addImport("pdf_protocol", pdf_protocol_module);
    const run_pdf_geometry_tests = b.addRunArtifact(pdf_geometry_tests);
    const pdf_geometry_test_step = b.step("t0-2e-geometry-test", "Run T0.2e PDF tile geometry and budget tests");
    pdf_geometry_test_step.dependOn(&run_pdf_geometry_tests.step);
    const pdf_geometry_check_step = b.step("t0-2e-geometry-check", "Compile T0.2e PDF geometry contracts");
    pdf_geometry_check_step.dependOn(&pdf_geometry_tests.step);

    const pdf_tile_handoff_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdf_tile_handoff_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pdf_tile_handoff_tests.root_module.addImport("pdf_tile_handoff", pdf_tile_handoff_module);
    pdf_tile_handoff_tests.root_module.addImport("pdf_protocol", pdf_protocol_module);
    const run_pdf_tile_handoff_tests = b.addRunArtifact(pdf_tile_handoff_tests);
    const pdf_tile_handoff_test_step = b.step("t0-2e-handoff-test", "Run T0.2e tile handoff state machine tests");
    pdf_tile_handoff_test_step.dependOn(&run_pdf_tile_handoff_tests.step);
    const pdf_tile_handoff_check_step = b.step("t0-2e-handoff-check", "Compile T0.2e tile handoff contracts");
    pdf_tile_handoff_check_step.dependOn(&pdf_tile_handoff_tests.step);

    const pdf_uia_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdf_uia_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pdf_uia_tests.root_module.addImport("pdf_uia", pdf_uia_module);
    const run_pdf_uia_tests = b.addRunArtifact(pdf_uia_tests);
    const pdf_uia_test_step = b.step("t0-2e-uia-test", "Run T0.2e accessible PDF tree tests");
    pdf_uia_test_step.dependOn(&run_pdf_uia_tests.step);
    const pdf_uia_check_step = b.step("t0-2e-uia-check", "Compile T0.2e accessible PDF contracts");
    pdf_uia_check_step.dependOn(&pdf_uia_tests.step);

    const pdf_isolation_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdf_isolation_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pdf_isolation_tests.root_module.addImport("platform_process", platform_process_module);
    pdf_isolation_tests.root_module.addImport("ipc_frame", ipc_frame_module);
    const run_pdf_isolation_tests = b.addRunArtifact(pdf_isolation_tests);
    const pdf_isolation_test_step = b.step("t0-2e-isolation-test", "Run T0.2e PDF worker isolation tests");
    pdf_isolation_test_step.dependOn(&run_pdf_isolation_tests.step);
    const pdf_isolation_check_step = b.step("t0-2e-isolation-check", "Compile T0.2e PDF isolation contracts");
    pdf_isolation_check_step.dependOn(&pdf_isolation_tests.step);

    const pdf_resilience_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/pdf_resilience_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pdf_resilience_tests.root_module.addImport("pdf_worker", pdf_worker_module);
    pdf_resilience_tests.root_module.addImport("pdf_protocol", pdf_protocol_module);
    pdf_resilience_tests.root_module.addImport("pdf_corpus", pdf_corpus_module);
    const run_pdf_resilience_tests = b.addRunArtifact(pdf_resilience_tests);
    const pdf_resilience_test_step = b.step("t0-2e-resilience-test", "Run T0.2e PDF open error and digest validation tests");
    pdf_resilience_test_step.dependOn(&run_pdf_resilience_tests.step);
    const pdf_resilience_check_step = b.step("t0-2e-resilience-check", "Compile T0.2e PDF resilience contracts");
    pdf_resilience_check_step.dependOn(&pdf_resilience_tests.step);

    // PDF Worker Executable
    const pdf_worker_exe_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/pdf_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    pdf_worker_exe_module.addImport("pdf/worker.zig", pdf_worker_module);
    const pdf_worker_exe = b.addExecutable(.{
        .name = "TExFlow.PdfWorker",
        .root_module = pdf_worker_exe_module,
    });
    if (target.result.os.tag == .windows) {
        pdf_worker_exe.root_module.addWin32ResourceFile(.{
            .file = b.path("native/zig/manifests/TExFlow.PdfWorker.rc"),
        });
    }
    const pdf_worker_exe_step = b.step("t0-2e-worker-exe", "Build the headless TExFlow.PdfWorker.exe");
    pdf_worker_exe_step.dependOn(&pdf_worker_exe.step);

    // T0.2e Aggregate steps
    const t0_2e_test_step = b.step("t0-2e-test", "Run all T0.2e IPC, LPAC, and PDF tests");
    t0_2e_test_step.dependOn(ipc_property_test_step);
    t0_2e_test_step.dependOn(lpac_boundary_test_step);
    t0_2e_test_step.dependOn(pdf_geometry_test_step);
    t0_2e_test_step.dependOn(pdf_tile_handoff_test_step);
    t0_2e_test_step.dependOn(pdf_uia_test_step);
    t0_2e_test_step.dependOn(pdf_isolation_test_step);
    t0_2e_test_step.dependOn(pdf_resilience_test_step);

    const t0_2e_check_step = b.step("t0-2e-check", "Compile all T0.2e contracts and worker executable");
    t0_2e_check_step.dependOn(ipc_property_check_step);
    t0_2e_check_step.dependOn(lpac_boundary_check_step);
    t0_2e_check_step.dependOn(pdf_geometry_check_step);
    t0_2e_check_step.dependOn(pdf_tile_handoff_check_step);
    t0_2e_check_step.dependOn(pdf_uia_check_step);
    t0_2e_check_step.dependOn(pdf_isolation_check_step);
    t0_2e_check_step.dependOn(pdf_resilience_check_step);
    t0_2e_check_step.dependOn(pdf_worker_exe_step);

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
    if (host_target.result.os.tag == .windows) {
        deps_audit_step.dependOn(&run_attestation_audit.step);
    }
    deps_audit_step.dependOn(&run_zigwin32_cache_tests.step);
    deps_audit_step.dependOn(unicode_audit_step);
    scintilla_contract.addOption(bool, "install_reaches_library", if (scintilla_library) |library| buildReachesLibrary(b, b.getInstallStep(), library) else false);
    scintilla_contract.addOption(bool, "product_reaches_library", if (executable) |product| if (scintilla_library) |library| buildReachesLibrary(b, &product.step, library) else false else false);
    const lexilla_install_reaches_library = if (lexilla_library) |library| buildReachesLibrary(b, b.getInstallStep(), library) else false;
    const lexilla_product_reaches_library = if (executable) |product| if (lexilla_library) |library| buildReachesLibrary(b, &product.step, library) else false else false;
    const lexilla_worker_reaches_library = if (lexilla_library) |library| buildReachesLibrary(b, &deps_fetch_fixture_worker.step, library) else false;
    lexilla_contract.addOption(bool, "install_reaches_library", lexilla_install_reaches_library);
    lexilla_contract.addOption(bool, "product_reaches_library", lexilla_product_reaches_library);
    lexilla_contract.addOption(bool, "worker_reaches_library", lexilla_worker_reaches_library);
    lexilla_contract.addOption(bool, "install_reaches_snapshot", buildReachesStep(b, b.getInstallStep(), &lexilla_snapshot.step));
    lexilla_contract.addOption(bool, "product_reaches_snapshot", if (executable) |product| buildReachesStep(b, &product.step, &lexilla_snapshot.step) else false);
    lexilla_contract.addOption(bool, "worker_reaches_snapshot", buildReachesStep(b, &deps_fetch_fixture_worker.step, &lexilla_snapshot.step));
    lexilla_contract.addOption(bool, "library_reaches_snapshot", if (lexilla_library) |library| buildReachesStep(b, &library.step, &lexilla_snapshot.step) else false);
    lexilla_contract.addOption(bool, "install_reaches_probe", buildReachesStep(b, b.getInstallStep(), &lexilla_probe.step));
    lexilla_contract.addOption(bool, "product_reaches_probe", if (executable) |product| buildReachesStep(b, &product.step, &lexilla_probe.step) else false);
    lexilla_contract.addOption(bool, "worker_reaches_probe", buildReachesStep(b, &deps_fetch_fixture_worker.step, &lexilla_probe.step));
    lexilla_contract.addOption(bool, "install_reaches_source_root", buildReachesLazyPath(b, b.getInstallStep(), lexilla_root));
    lexilla_contract.addOption(bool, "product_reaches_source_root", if (executable) |product| buildReachesLazyPath(b, &product.step, lexilla_root) else false);
    lexilla_contract.addOption(bool, "worker_reaches_source_root", buildReachesLazyPath(b, &deps_fetch_fixture_worker.step, lexilla_root));
    lexilla_contract.addOption(bool, "library_reaches_source_root", if (lexilla_library) |library| buildReachesLazyPath(b, &library.step, lexilla_root) else false);
    lexilla_contract.addOption(bool, "library_reaches_probe", if (lexilla_library) |library| buildReachesStep(b, &library.step, &lexilla_probe.step) else false);
    const lexilla_loader_step: ?*std.Build.Step = null;
    lexilla_contract.addOption(bool, "install_reaches_loader", if (lexilla_loader_step) |loader| buildReachesStep(b, b.getInstallStep(), loader) else false);
    lexilla_contract.addOption(bool, "product_reaches_loader", if (executable) |product| if (lexilla_loader_step) |loader| buildReachesStep(b, &product.step, loader) else false else false);
    lexilla_contract.addOption(bool, "worker_reaches_loader", if (lexilla_loader_step) |loader| buildReachesStep(b, &deps_fetch_fixture_worker.step, loader) else false);
    // Materialize an inspectable install-manifest oracle from the actual graph.
    // It remains empty while the comparator is test-only; if an install edge is
    // ever introduced, the runtime audit measures the emitted archive itself.
    const lexilla_shipping_manifest = b.addNamedWriteFiles("texflow-lexilla-shipping-manifest");
    const lexilla_shipping_manifest_contents = if (lexilla_install_reaches_library)
        lexilla_inventory.artifact_name ++ ".lib\n"
    else
        "";
    const lexilla_shipping_manifest_path = lexilla_shipping_manifest.add("members.txt", lexilla_shipping_manifest_contents);
    lexilla_contract.addOptionPath("shipping_manifest_path", lexilla_shipping_manifest_path);
    abi_contract.addOption(bool, "install_reaches_library", buildReachesLibrary(b, b.getInstallStep(), abi_library));
    abi_contract.addOption(bool, "product_reaches_library", if (executable) |product| buildReachesLibrary(b, &product.step, abi_library) else false);
    smoke_contract.addOption(bool, "install_reaches_smoke", buildReachesLibrary(b, b.getInstallStep(), smoke_tests));
    smoke_contract.addOption(bool, "product_reaches_smoke", if (executable) |product| buildReachesLibrary(b, &product.step, smoke_tests) else false);
    product_contract.addOption(bool, "has_product", executable != null);
    product_contract.addOption([]const u8, "product_name", if (executable) |product| product.name else "");
    if (executable) |product| product_contract.addOptionPath("path", product.getEmittedBin()) else product_contract.addOption([]const u8, "path", "");
    product_contract.addOption(bool, "install_empty", b.getInstallStep().dependencies.items.len == 0);
    product_contract.addOption(bool, "install_reaches_product", if (executable) |product| buildReachesLibrary(b, b.getInstallStep(), product) else false);

    // One named, target-aware static boundary gate keeps the host source scan
    // mandatory even when a platform-specific contract is compile-only. The
    // aggregate remains limited to the T0.2b static contracts; product/UI and
    // worker admission stay on their own later-phase gates.
    const t0_2b_static = b.step("t0-2b-static", "Run the T0.2b static boundary contracts and mandatory host tree scan");
    t0_2b_static.dependOn(source_boundary_tree);
    // Runtime tests are evidence only when the selected target is Windows
    // and the current host can execute that target. Cross-compiling a
    // Windows target from Linux must stay compile-only.
    if (can_run_windows_runtime) {
        t0_2b_static.dependOn(package_probe_test);
        t0_2b_static.dependOn(source_boundary_step);
        t0_2b_static.dependOn(windows_argv_step);
        t0_2b_static.dependOn(windows_api_contract_test);
        t0_2b_static.dependOn(lexilla_test_step);
        t0_2b_static.dependOn(repro_check_test_step);
        t0_2b_static.dependOn(pe_closure_test_step);
        t0_2b_static.dependOn(shipped_pe_inventory_test_step);
        t0_2b_static.dependOn(pdfium_repro_test_step);
        t0_2b_static.dependOn(scintilla_runtime_contract_test_step);
        t0_2b_static.dependOn(scintilla_native_probe_test_step);
    } else {
        t0_2b_static.dependOn(package_probe_check);
        t0_2b_static.dependOn(source_boundary_check);
        t0_2b_static.dependOn(windows_argv_check);
        t0_2b_static.dependOn(windows_api_contract_check);
        t0_2b_static.dependOn(lexilla_check_step);
        t0_2b_static.dependOn(repro_check_target_step);
        t0_2b_static.dependOn(pe_closure_check_step);
        t0_2b_static.dependOn(shipped_pe_inventory_check_step);
        t0_2b_static.dependOn(pdfium_repro_check_step);
        t0_2b_static.dependOn(scintilla_runtime_contract_check_step);
        t0_2b_static.dependOn(scintilla_native_probe_check_step);
    }

    // T0.2g fixture-only benchmark/evidence contracts. These modules are pure
    // Zig and deliberately have no WPR/WPA/PresentMon process or filesystem
    // campaign side effects. Windows executes the fixture tests; Linux and
    // other cross-target lanes compile the same contracts only.
    const bench_events_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/bench/events.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_events_module.addImport("windows_telemetry", windows_telemetry_module);
    const bench_presentmon_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/bench/presentmon_csv.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bench_wpa_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/bench/wpa_csv.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_wpa_module.addImport("bench_events", bench_events_module);
    const bench_matrix_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/bench/matrix.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bench_evidence_pack_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/bench/evidence_pack.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bench_runner_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/bench/runner.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_runner_module.addImport("bench_events", bench_events_module);
    bench_runner_module.addImport("bench_presentmon_csv", bench_presentmon_module);
    bench_runner_module.addImport("bench_wpa_csv", bench_wpa_module);
    const bench_parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/bench_parser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench_parser_tests.root_module.addImport("windows_telemetry", windows_telemetry_module);
    bench_parser_tests.root_module.addImport("bench_events", bench_events_module);
    bench_parser_tests.root_module.addImport("bench_presentmon_csv", bench_presentmon_module);
    bench_parser_tests.root_module.addImport("bench_wpa_csv", bench_wpa_module);
    bench_parser_tests.root_module.addImport("bench_runner", bench_runner_module);
    const run_bench_parser_tests = b.addRunArtifact(bench_parser_tests);
    const bench_matrix_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/bench_matrix_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench_matrix_tests.root_module.addImport("bench_matrix", bench_matrix_module);
    const run_bench_matrix_tests = b.addRunArtifact(bench_matrix_tests);
    const evidence_pack_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/evidence_pack_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    evidence_pack_tests.root_module.addImport("bench_evidence_pack", bench_evidence_pack_module);
    const run_evidence_pack_tests = b.addRunArtifact(evidence_pack_tests);
    const bench_test_step = b.step("t0-2g-bench-test", "Run fixture-only benchmark tests only for a matching native x86_64 Windows host; otherwise compile the same contracts");
    const bench_check_step = b.step("t0-2g-bench-check", "Compile fixture-only benchmark and evidence contracts for the selected target");
    bench_check_step.dependOn(&bench_parser_tests.step);
    bench_check_step.dependOn(&bench_matrix_tests.step);
    bench_check_step.dependOn(&evidence_pack_tests.step);
    // Match the existing Scintilla host-run rule: Windows PE test binaries
    // may execute when host and selected target are both native x86_64
    // Windows even when their Zig ABIs differ. This proves the selected
    // target binary ran on Windows; it does not claim that the host itself
    // uses the selected target's CRT/ABI.
    const bench_runs_on_host = target.result.os.tag == .windows and
        host_target.result.os.tag == .windows and
        target.result.cpu.arch == .x86_64 and
        host_target.result.cpu.arch == .x86_64;
    if (bench_runs_on_host) {
        bench_test_step.dependOn(&run_bench_parser_tests.step);
        bench_test_step.dependOn(&run_bench_matrix_tests.step);
        bench_test_step.dependOn(&run_evidence_pack_tests.step);
        t0_2c_models_test.dependOn(&run_bench_parser_tests.step);
        t0_2c_models_test.dependOn(&run_bench_matrix_tests.step);
        t0_2c_models_test.dependOn(&run_evidence_pack_tests.step);
    } else {
        bench_test_step.dependOn(bench_check_step);
    }
    t0_2c_models_check.dependOn(&bench_parser_tests.step);
    t0_2c_models_check.dependOn(&bench_matrix_tests.step);
    t0_2c_models_check.dependOn(&evidence_pack_tests.step);
    const bench_step = b.step("t0-2g-bench", "Validate fixture-only benchmark contracts without making external campaign claims");
    bench_step.dependOn(bench_check_step);
    if (bench_runs_on_host) bench_step.dependOn(bench_test_step);

    // T0.2c capture boundary contract. This is intentionally a pure fixture
    // module: it validates frame metadata, crop/DPI rules, bounded waits,
    // access-loss generations, and deterministic digests without claiming a
    // live DXGI Desktop Duplication/WIC/DWM adapter or physical capture run.
    const capture_contract_module = b.createModule(.{
        .root_source_file = b.path("native/zig/src/platform/windows/capture_contract.zig"),
        .target = target,
        .optimize = optimize,
    });
    const capture_contract_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/capture_contract_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    capture_contract_tests.root_module.addImport("capture_contract", capture_contract_module);
    const run_capture_contract_tests = b.addRunArtifact(capture_contract_tests);
    const capture_contract_test_step = b.step("t0-2c-capture-contract-test", "Run capture boundary tests only for a matching native x86_64 Windows host; otherwise compile the same contract");
    const capture_contract_check_step = b.step("t0-2c-capture-contract-check", "Compile deterministic capture boundary contracts for the selected target");
    capture_contract_check_step.dependOn(&capture_contract_tests.step);
    const capture_runs_on_host = target.result.os.tag == .windows and
        host_target.result.os.tag == .windows and
        target.result.cpu.arch == .x86_64 and
        host_target.result.cpu.arch == .x86_64;
    if (capture_runs_on_host) {
        capture_contract_test_step.dependOn(&run_capture_contract_tests.step);
        t0_2c_models_test.dependOn(&run_capture_contract_tests.step);
    } else {
        capture_contract_test_step.dependOn(capture_contract_check_step);
    }
    t0_2c_models_check.dependOn(&capture_contract_tests.step);
    const capture_contract_step = b.step("t0-2c-capture-contract", "Validate capture boundary contracts without making physical capture claims");
    capture_contract_step.dependOn(capture_contract_check_step);
    if (capture_runs_on_host) capture_contract_step.dependOn(capture_contract_test_step);

    // The physical QA adapters are a separate executable/test surface.  They
    // are compiled for every selected target, but only the explicit Windows
    // runtime step may make a display-capture claim.  Keeping this edge out of
    // the portable model aggregate prevents a fixture pass from masquerading
    // as DXGI/WIC evidence.
    const capture_qa_module = b.createModule(.{
        .root_source_file = b.path("native/zig/qa/capture.zig"),
        .target = target,
        .optimize = optimize,
    });
    capture_qa_module.addImport("capture_contract", capture_contract_module);
    capture_qa_module.addImport("windows_com", windows_com_module);
    capture_qa_module.addImport("windows_api", windows_api_module);
    if (target.result.os.tag == .windows) {
        inline for (.{ "kernel32", "ole32", "d3d11", "dxgi", "windowscodecs" }) |library| {
            capture_qa_module.linkSystemLibrary(library, .{});
        }
    }
    const capture_qa_tests = b.addTest(.{ .root_module = capture_qa_module });
    const capture_qa_check_step = b.step("t0-2c-capture-qa-check", "Compile independent DXGI/WIC capture QA");
    capture_qa_check_step.dependOn(&capture_qa_tests.step);
    const capture_qa_test_step = b.step("t0-2c-capture-qa-test", "Run independent capture adapter contract tests");
    if (capture_runs_on_host)
        capture_qa_test_step.dependOn(&b.addRunArtifact(capture_qa_tests).step)
    else
        capture_qa_test_step.dependOn(capture_qa_check_step);
    t0_2c_models_check.dependOn(capture_qa_check_step);

    const journey_module = b.createModule(.{
        .root_source_file = b.path("native/zig/qa/journey.zig"),
        .target = target,
        .optimize = optimize,
    });
    journey_module.addImport("capture_contract", capture_contract_module);
    journey_module.addImport("windows_com", windows_com_module);
    journey_module.addImport("windows_api", windows_api_module);
    if (target.result.os.tag == .windows) {
        inline for (.{ "kernel32", "user32", "ole32", "dwmapi" }) |library| {
            journey_module.linkSystemLibrary(library, .{});
        }
    }
    const journey_check = b.addTest(.{ .root_module = journey_module });
    const journey_check_step = b.step("t0-2c-journey-check", "Compile the independent UIA/input journey client");
    journey_check_step.dependOn(&journey_check.step);
    const journey_test_step = b.step("t0-2c-journey-test", "Run the independent UIA/input journey contract tests");
    if (can_run_selected_target)
        journey_test_step.dependOn(&b.addRunArtifact(journey_check).step)
    else
        journey_test_step.dependOn(journey_check_step);
    t0_2c_models_check.dependOn(journey_check_step);

    // The live lane is an independently launched QA process. It is never a
    // product dependency and stays out of the portable model aggregate because
    // hosted CI has no authoritative interactive desktop. On a native x64
    // Windows host it launches the product, walks its real UIA tree, injects a
    // key event, and writes only bounded DXGI/WIC PNG+JSON evidence.
    const live_journey_module = b.createModule(.{
        .root_source_file = if (target.result.os.tag == .windows)
            b.path("native/zig/qa/live_journey.zig")
        else
            b.path("native/zig/qa/live_journey_portable.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag == .windows) {
        live_journey_module.addImport("journey", journey_module);
        live_journey_module.addImport("capture_qa", capture_qa_module);
        live_journey_module.addImport("windows_argv", windows_argv_module);
        live_journey_module.linkSystemLibrary("user32", .{});
    }
    const live_journey_exe = b.addExecutable(.{
        .name = "texflow-t0-2c-live-qa",
        .root_module = live_journey_module,
    });
    const live_journey_check = b.step("t0-2c-live-qa-check", "Compile the independent T0.2c UIA/input/DXGI QA process");
    live_journey_check.dependOn(&live_journey_exe.step);
    const live_journey_step = b.step("t0-2c-live-qa", "Run the independent T0.2c UIA/input/DXGI QA process");
    if (can_run_windows_runtime and executable != null) {
        const live_run = b.addRunArtifact(live_journey_exe);
        live_run.addArgs(&.{ "run", "--product" });
        live_run.addFileArg(executable.?.getEmittedBin());
        live_run.addArgs(&.{ "--output", b.pathFromRoot("zig-out/t0-2c-live-qa") });
        live_run.step.dependOn(product_build_step);
        live_journey_step.dependOn(&live_run.step);
    } else {
        live_journey_step.dependOn(live_journey_check);
    }
    t0_2c_models_check.dependOn(live_journey_check);

    // Public T0.2 reproducibility cutover. The command is intentionally
    // fail-closed when the sealed runner has not supplied two independent
    // payload roots, a network-none receipt, an authenticated role manifest,
    // and a complete payload manifest. It never mutates host networking and
    // never substitutes the ordinary build cache for those inputs.
    const t0_2_repro = b.step(
        "t0-2-repro",
        "Run the Zig-owned two-root reproducibility gate from a sealed runner",
    );
    const repro_left = b.option(
        []const u8,
        "repro-left",
        "Absolute first clean-build payload root from the sealed runner",
    );
    const repro_right = b.option(
        []const u8,
        "repro-right",
        "Absolute second clean-build payload root from the sealed runner",
    );
    const repro_test_left = b.option(
        []const u8,
        "repro-test-left",
        "Absolute first cache-only texflow_abi artifact root from the sealed runner",
    );
    const repro_test_right = b.option(
        []const u8,
        "repro-test-right",
        "Absolute second cache-only texflow_abi artifact root from the sealed runner",
    );
    const repro_network_receipt = b.option(
        []const u8,
        "repro-network-receipt",
        "Absolute network-none receipt produced by the sealed runner",
    );
    const repro_role_manifest = b.option(
        []const u8,
        "repro-role-manifest",
        "Absolute authenticated installed-payload role manifest",
    );
    const repro_payload_manifest = b.option(
        []const u8,
        "repro-payload-manifest",
        "Absolute authenticated complete installed-payload manifest",
    );
    const repro_target_name: ?[]const u8 = if (product_target)
        "x86_64-windows-msvc"
    else if (target.result.os.tag == .linux and target.result.cpu.arch == .x86_64 and target.result.abi == .gnu)
        "x86_64-linux-gnu"
    else
        null;
    const repro_inputs_ready = repro_left != null and repro_left.?.len != 0 and
        repro_right != null and repro_right.?.len != 0 and
        repro_test_left != null and repro_test_left.?.len != 0 and
        repro_test_right != null and repro_test_right.?.len != 0 and
        repro_network_receipt != null and repro_network_receipt.?.len != 0 and
        repro_role_manifest != null and repro_role_manifest.?.len != 0 and
        repro_payload_manifest != null and repro_payload_manifest.?.len != 0;
    if (repro_target_name) |selected_target| {
        const repro_host_compatible =
            (std.mem.eql(u8, selected_target, "x86_64-windows-msvc") and host_target.result.os.tag == .windows) or
            (std.mem.eql(u8, selected_target, "x86_64-linux-gnu") and host_target.result.os.tag == .linux);
        if (!repro_host_compatible) {
            t0_2_repro.dependOn(&b.addFail(
                "UNVERIFIED-REPRO-HOST-TARGET: t0-2-repro must execute on the selected x86_64 Windows/Linux host; cross-target execution is not admission evidence",
            ).step);
        } else if (!source_identity.authoritative) {
            t0_2_repro.dependOn(&b.addFail(
                "UNVERIFIED-SOURCE-IDENTITY: t0-2-repro requires a clean authoritative Git source identity from the exact checked-out commit",
            ).step);
        } else if (source_commit == null or remote_run_id == null or remote_run_attempt == null or
            source_commit.?.len == 0 or remote_run_id.?.len == 0 or remote_run_attempt.?.len == 0)
        {
            t0_2_repro.dependOn(&b.addFail(
                "UNVERIFIED-REMOTE-CI-RUN-IDS: t0-2-repro requires TEXFLOW_SOURCE_COMMIT, TEXFLOW_REMOTE_RUN_ID, and TEXFLOW_REMOTE_RUN_ATTEMPT from the producing CI run",
            ).step);
        } else if (repro_inputs_ready) {
            const repro_cli_module = b.createModule(.{
                .root_source_file = b.path("tools/zig/repro_check.zig"),
                .target = host_target,
                .optimize = .ReleaseSafe,
            });
            repro_cli_module.addImport("deps", deps_host_module);
            const repro_cli = b.addExecutable(.{
                .name = "texflow-t0-2-repro",
                .root_module = repro_cli_module,
            });
            const run_repro_cli = b.addRunArtifact(repro_cli);
            var source_set_hex_array = std.fmt.bytesToHex(source_identity.source_set_sha256, .lower);
            var dependency_lock_hex_array = std.fmt.bytesToHex(source_identity.dependency_lock_sha256, .lower);
            var build_identity_hex_array = std.fmt.bytesToHex(source_identity.build_identity, .lower);
            const source_set_hex = b.dupe(&source_set_hex_array);
            const dependency_lock_hex = b.dupe(&dependency_lock_hex_array);
            const build_identity_hex = b.dupe(&build_identity_hex_array);
            run_repro_cli.addArgs(&.{
                "compare-both",
                selected_target,
                repro_left.?,
                repro_right.?,
                repro_test_left.?,
                repro_test_right.?,
                repro_network_receipt.?,
                repro_role_manifest.?,
                repro_payload_manifest.?,
                source_commit.?,
                source_set_hex,
                dependency_lock_hex,
                build_identity_hex,
                remote_run_id.?,
                remote_run_attempt.?,
            });
            t0_2_repro.dependOn(&run_repro_cli.step);
        } else {
            t0_2_repro.dependOn(&b.addFail(
                "UNVERIFIED-NETWORK-ISOLATION: t0-2-repro requires two product roots, two cache-only ABI roots, a network-none receipt, an authenticated role manifest, and a complete payload manifest from a sealed detached-NIC/network-none runner; it never changes host networking",
            ).step);
        }
    } else {
        t0_2_repro.dependOn(&b.addFail(
            "T0.2 reproducibility requires target x86_64-windows-msvc or x86_64-linux-gnu",
        ).step);
    }

    // Exceptional PDFium source-resolution/reconstruction lane.  The build
    // option is only a typed driver for the Zig controller; all source roots,
    // tool paths, and sealed-runner evidence remain explicit environment
    // inputs owned by the operator/CI job.
    const pdfium_phase = b.option(
        []const u8,
        "phase",
        "PDFium lane phase: resolve or reproduce",
    );
    const pdfium_allow_network = b.option(
        bool,
        "allow-network",
        "Explicitly authorize the exceptional PDFium lane (the controller still requires its own receipt)",
    ) orelse false;
    const pdfium_repro_root = b.option(
        []const u8,
        "repro-root",
        "Absolute disposable PDFium reconstruction root",
    );
    const pdfium_repro_output = b.option(
        []const u8,
        "repro-output",
        "Absolute candidate/verified PDFium receipt output path",
    );
    const pdfium_reproduce_step = b.step(
        "deps-reproduce-pdfium",
        "Run the explicitly authorized, fail-closed PDFium resolve/reproduce controller",
    );
    if (pdfium_phase == null or pdfium_repro_root == null or pdfium_repro_output == null) {
        pdfium_reproduce_step.dependOn(&b.addFail(
            "deps-reproduce-pdfium requires -Dphase=resolve|reproduce, -Dallow-network=true, -Drepro-root=<absolute>, and -Drepro-output=<absolute>",
        ).step);
    } else if (!pdfium_allow_network) {
        pdfium_reproduce_step.dependOn(&b.addFail(
            "UNVERIFIED-NETWORK-ISOLATION: deps-reproduce-pdfium requires explicit -Dallow-network=true; it never changes host networking",
        ).step);
    } else if (!std.mem.eql(u8, pdfium_phase.?, "resolve") and
        !std.mem.eql(u8, pdfium_phase.?, "reproduce"))
    {
        pdfium_reproduce_step.dependOn(&b.addFail(
            "deps-reproduce-pdfium phase must be exactly resolve or reproduce",
        ).step);
    } else if (!std.fs.path.isAbsolute(pdfium_repro_root.?) or
        !std.fs.path.isAbsolute(pdfium_repro_output.?))
    {
        pdfium_reproduce_step.dependOn(&b.addFail(
            "deps-reproduce-pdfium root and output must be absolute paths",
        ).step);
    } else {
        const pdfium_reproduce_exe = b.addExecutable(.{
            .name = "texflow-pdfium-reproduce",
            .root_module = pdfium_repro_host_module,
        });
        const run_pdfium_reproduce = b.addRunArtifact(pdfium_reproduce_exe);
        if (std.mem.eql(u8, pdfium_phase.?, "resolve")) {
            run_pdfium_reproduce.addArgs(&.{ "resolve", "--candidate", pdfium_repro_output.? });
        } else {
            run_pdfium_reproduce.addArgs(&.{ "reproduce", "--receipt", pdfium_repro_output.? });
        }
        run_pdfium_reproduce.setEnvironmentVariable("TEXFLOW_PDFIUM_REPRO_ROOT", pdfium_repro_root.?);
        pdfium_reproduce_step.dependOn(&run_pdfium_reproduce.step);
    }
}

// Inspect actual build steps and transitive module/library edges. Checking only
// direct Step.dependencies during build() misses linkLibrary dependencies that
// Zig expands later. The visited sets also handle shared modules and cycles.
fn buildReachesLibrary(b: *std.Build, root: *std.Build.Step, library: *std.Build.Step.Compile) bool {
    return buildReachesStep(b, root, &library.step);
}

fn buildReachesLazyPath(b: *std.Build, root: *std.Build.Step, lazy_path: std.Build.LazyPath) bool {
    return switch (lazy_path) {
        .generated => |generated| buildReachesStep(b, root, generated.file.step),
        else => false,
    };
}

fn buildReachesStep(b: *std.Build, root: *std.Build.Step, target_step: *std.Build.Step) bool {
    var steps: std.AutoArrayHashMapUnmanaged(*std.Build.Step, void) = .empty;
    var modules: std.AutoArrayHashMapUnmanaged(*std.Build.Module, void) = .empty;
    steps.put(b.allocator, root, {}) catch @panic("OOM");
    var step_index: usize = 0;
    var module_index: usize = 0;
    while (step_index < steps.count() or module_index < modules.count()) {
        while (step_index < steps.count()) : (step_index += 1) {
            const step = steps.keys()[step_index];
            if (step == target_step) return true;
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
