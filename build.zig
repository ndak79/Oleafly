const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
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

    const executable = b.addExecutable(.{
        .name = "oleafly-t0.1",
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // Release artifacts are stripped so PE/PDB metadata cannot inject
    // per-build timestamps or identifiers into the reproducibility hash.
    // Debug keeps symbols for local diagnostics.
    executable.root_module.strip = optimize != .Debug;
    b.installArtifact(executable);

    const abi_library = b.addLibrary(.{
        .name = "oleafly_abi",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/src/abi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(abi_library);

    const run_executable = b.addRunArtifact(executable);
    const run_step = b.step("run", "Run the T0.1 executable");
    run_step.dependOn(&run_executable.step);

    const abi_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/abi_probe.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    abi_tests.root_module.linkLibrary(abi_library);
    const run_abi_tests = b.addRunArtifact(abi_tests);

    const corpus_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/miscompile_corpus.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_corpus_tests = b.addRunArtifact(corpus_tests);

    const simd_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("native/zig/tests/simd_corpus.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_simd_tests = b.addRunArtifact(simd_tests);

    const test_step = b.step("test", "Run ABI, miscompile, and SIMD tests");
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
}
