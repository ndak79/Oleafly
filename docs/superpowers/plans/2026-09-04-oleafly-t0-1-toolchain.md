# Plan: Oleafly T0.1 Toolchain

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a reproducible Zig 0.16.0 walking skeleton that builds a tiny Windows x64 executable, proves a fixed-width C ABI boundary, exercises a deterministic miscompile corpus in safe and fast modes, and runs in dedicated Windows and Linux CI lanes without changing the legacy application.

**Architecture:** T0.1 adds the future Zig build entry points at the repository root while keeping source files under native/zig/ so the existing React/Rust tree remains an explicit development oracle. The build graph has one minimal executable, one static ABI library, three independent test binaries, and named run, test, abi, miscompile-corpus, and simd-corpus steps. Toolchain acquisition is a checksum- and host-allowlisted CI bootstrap only; all product, build-graph, test, and ABI behavior is implemented in Zig, with a C header and compile-time C assertions as declarative boundary fixtures.

**Tech Stack:** Zig 0.16.0; build.zig/build.zig.zon; Windows x86_64 MSVC target; Ubuntu x86_64 verification lane; GitHub Actions with the actions/checkout v7 commit pin 3d3c42e5aac5ba805825da76410c181273ba90b1; fixed-width C ABI; FNV-1a 64-bit and portable `@Vector` known-answer corpora; PowerShell and Bash limited to archive download, hash verification, extraction, and command orchestration.

---

## Scope and non-goals

This plan is only slice T0.1 from the approved architecture. It must leave the existing Tauri/React/Rust production graph behavior unchanged. It does not add a window, editor, PDF engine, external tool pack, database, research feature, AI provider, packaging format, or native UI harness. Those belong to later slices and receive separate plans.

The native/zig/ prefix is a migration guard, not a second runtime. T5.2 moves the Zig modules to the final root src/ layout only after the legacy production graph is deleted and the cutover evidence is complete. No wrapper process or compatibility shell is introduced here.

ReleaseSafe is the default shipped mode. ReleaseFast is compiled only as a
diagnostic ABI/miscompile/SIMD lane; it is never the default or a shipped
artifact, and no process-wide safety removal is used for the product.

The approved design's exact low-tier/mainstream hardware freeze and all startup,
working-set, energy, and presentation budgets are a separate T0 performance
baseline gate. This toolchain slice records CI runner/target identity only and
must not claim those product measurements are complete.

## File map

| Path | Responsibility |
| --- | --- |
| build.zig | Root build graph, target/optimization options, executable, static ABI library, test runners, and named steps. |
| build.zig.zon | Package identity, Zig minimum, empty dependency graph, and explicit package paths. |
| native/zig/src/main.zig | Tiny runtime smoke executable with stable combined-stream output. |
| native/zig/src/abi.zig | Exported fixed-width C ABI functions and an extern struct; no ownership crosses the boundary. |
| native/zig/tests/abi_probe.zig | Independent extern declarations linked to the produced ABI library; layout, status, and calling-convention checks. |
| native/zig/tests/miscompile_corpus.zig | Deterministic FNV-1a and integer-overflow known answers checked at runtime and comptime. |
| native/zig/tests/simd_corpus.zig | Deterministic `@Vector` lane arithmetic known answers checked at runtime and comptime. |
| native/zig/include/oleafly_abi.h | C/C++ consumer declaration using stdint.h and extern C; declarative only. |
| native/zig/fixtures/abi_layout.c | C11 _Static_assert layout fixture; no main, I/O, or executable logic. |
| tools/zig/toolchain.json | Exact Zig release, source index, archive roots, sizes, SHA-256 hashes, and allowed targets. |
| .github/workflows/zig.yml | Pinned-Zig Windows and Linux lanes, archive verification, format/test/build/reproducibility checks. |
| .gitattributes | Keeps Zig source, manifest, and workflow inputs LF-normalized on Windows so formatter checks are deterministic. |
| .gitignore | Excludes Zig caches, install output, and any local archive. |
| docs/development.md | T0.1 local commands and migration-boundary explanation. |
| docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md | Post-verification evidence manifest containing actual commit, toolchain, commands, machine, results, unverified items, and streak. |

## Acceptance oracle

The slice is accepted only when every row has fresh evidence in both Pass A and Pass B. A failed command, unexplained flake, stale output, or missing environment is recorded as a finding or unverified; it is never silently treated as green.

| Requirement | Direct proof |
| --- | --- |
| Exact compiler and archive | tools/zig/toolchain.json, HTTPS host allowlist, byte-size check, SHA-256 check, and zig version == 0.16.0 in both CI jobs. |
| Reproducible dependency graph | build.zig.zon has the generated Oleafly fingerprint, .dependencies = .{}, explicit .paths, and zig build --fetch=all succeeds without a package download. |
| Zig-owned build and test behavior | zig fmt --check, Debug (`-Doptimize=Debug`), ReleaseSafe (`--release=safe`), `zig build run`, and the named ABI/miscompile/SIMD corpus steps execute the committed Zig graph. |
| Windows executable | Windows runner builds x86_64-windows-msvc ReleaseSafe, runs oleafly-t0.1.exe, and asserts exactly oleafly-t0.1 toolchain ok. |
| ABI safety | Static library build, independent Zig extern declarations, size/alignment/offset assertions, C11 layout assertions, zig translate-c of the public header, status/error cases, explicit wrapping arithmetic, and both ReleaseSafe and ReleaseFast builds. |
| Miscompile detection | FNV-1a 64 known answers for empty, a, abc, Oleafly, and bytes 00 FF (`590474061099445088`); explicit @addWithOverflow result; and a `@Vector(4, u32)` lane arithmetic corpus with comptime/runtime parity. |
| Reproducibility | Release executables are stripped of per-build PDB/CodeView metadata; two clean ReleaseSafe builds with distinct local and global cache directories have identical executable SHA-256 values. |
| Legacy safety | Existing ci.yml remains in the affected graph for non-document changes; the new Zig workflow has no path rule that can turn a Zig source change into a docs-only result. |
| Scope discipline | No new Rust/TypeScript/C++ runtime code, no dependency package, no external tool, no UI process, and no generated binary is committed. |
| Browser/UI QA boundary | T0.1 creates no window, renderer, native UI harness, or browser-visible surface; browser QA is explicitly not applicable to this slice and becomes mandatory when the first UI surface lands. |
| Performance-boundary honesty | Exact reference-machine freeze and product performance budgets are explicitly unverified in T0.1; no startup/working-set/energy/presentation pass is reported as complete here. |

## Task 1: Write the ABI and miscompile contracts first

**Files:**

- Create: native/zig/tests/abi_probe.zig
- Create: native/zig/tests/miscompile_corpus.zig
- Create: native/zig/include/oleafly_abi.h
- Create: native/zig/fixtures/abi_layout.c

- [ ] **Step 1: Add the independent ABI probe**

Create native/zig/tests/abi_probe.zig with a local extern struct and extern function declarations. The test must not import the implementation module; the build graph links the implementation library later.

~~~zig
const std = @import("std");

const HeaderAbiVersion = extern struct {
    major: u32,
    minor: u32,
    patch: u32,
};

extern fn oleafly_abi_get_version(out: ?*HeaderAbiVersion) callconv(.c) i32;
extern fn oleafly_abi_add(a: i64, b: i64) callconv(.c) i64;

test "fixed-width C ABI layout and calls" {
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(HeaderAbiVersion));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(HeaderAbiVersion));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(HeaderAbiVersion, "major"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(HeaderAbiVersion, "minor"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(HeaderAbiVersion, "patch"));
    try std.testing.expectEqual(@as(i64, 42), oleafly_abi_add(40, 2));
    try std.testing.expectEqual(@as(i64, -4), oleafly_abi_add(-7, 3));
    try std.testing.expectEqual(std.math.maxInt(i64), oleafly_abi_add(std.math.maxInt(i64) - 1, 1));
    try std.testing.expectEqual(std.math.minInt(i64), oleafly_abi_add(std.math.maxInt(i64), 1));

    var version: HeaderAbiVersion = undefined;
    try std.testing.expectEqual(@as(i32, 0), oleafly_abi_get_version(&version));
    try std.testing.expectEqual(@as(u32, 0), version.major);
    try std.testing.expectEqual(@as(u32, 1), version.minor);
    try std.testing.expectEqual(@as(u32, 0), version.patch);
    try std.testing.expectEqual(@as(i32, -1), oleafly_abi_get_version(null));
}
~~~

- [ ] **Step 2: Add the deterministic known-answer corpus**

Create native/zig/tests/miscompile_corpus.zig. Wrapping multiplication is explicit so the corpus remains defined in every optimization mode.

~~~zig
const std = @import("std");

const Case = struct {
    input: []const u8,
    expected: u64,
};

const cases = [_]Case{
    .{ .input = "", .expected = 14695981039346656037 },
    .{ .input = "a", .expected = 12638187200555641996 },
    .{ .input = "abc", .expected = 16654208175385433931 },
    .{ .input = "Oleafly", .expected = 2268825733032138785 },
    .{ .input = &[_]u8{ 0x00, 0xff }, .expected = 590474061099445088 },
};

fn fnv1a64(bytes: []const u8) u64 {
    var hash: u64 = 14695981039346656037;
    for (bytes) |byte| {
        hash ^= @as(u64, byte);
        hash *%= 1099511628211;
    }
    return hash;
}

test "FNV-1a 64 known answers" {
    for (cases) |case| {
        try std.testing.expectEqual(case.expected, fnv1a64(case.input));
    }
}

test "comptime and runtime answers agree" {
    inline for (cases) |case| {
        const compile_value = comptime fnv1a64(case.input);
        try std.testing.expectEqual(compile_value, fnv1a64(case.input));
    }
}

test "integer overflow is represented explicitly" {
    const result = @addWithOverflow(@as(u8, 255), @as(u8, 1));
    try std.testing.expectEqual(@as(u8, 0), result[0]);
    try std.testing.expectEqual(@as(u1, 1), result[1]);
}
~~~

- [ ] **Step 3: Add the deterministic SIMD corpus**

Create native/zig/tests/simd_corpus.zig. The test uses Zig's portable `@Vector` type and exact lane reductions, so it checks compiler vector semantics without requiring a particular CPU instruction set.

~~~zig
const std = @import("std");

const Lane = @Vector(4, u32);

test "SIMD lane arithmetic known answers" {
    const values: Lane = .{ 1, 2, 3, 4 };
    const factors: Lane = .{ 5, 6, 7, 8 };
    const actual = values * factors + @as(Lane, @splat(9));
    const expected: Lane = .{ 14, 21, 30, 41 };
    try std.testing.expect(@reduce(.And, actual == expected));
    try std.testing.expectEqual(@as(u32, 106), @reduce(.Add, actual));
}

test "SIMD comptime and runtime answers agree" {
    const values: Lane = .{ 10, 20, 30, 40 };
    const actual = values + @as(Lane, @splat(2));
    const expected: Lane = .{ 12, 22, 32, 42 };
    const comptime_actual = comptime values + @as(Lane, @splat(2));
    try std.testing.expect(@reduce(.And, actual == expected));
    try std.testing.expect(@reduce(.And, comptime_actual == expected));
}
~~~

- [ ] **Step 4: Add the public C declaration**

Create native/zig/include/oleafly_abi.h exactly as follows. The typedef name is deliberately distinct from the getter function name so both C namespaces remain unambiguous.

~~~c
#ifndef OLEAFLY_ABI_H
#define OLEAFLY_ABI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct oleafly_abi_version_t {
    uint32_t major;
    uint32_t minor;
    uint32_t patch;
} oleafly_abi_version_t;

int32_t oleafly_abi_get_version(oleafly_abi_version_t *out);
/* Returns the two's-complement i64 sum modulo 2^64. */
int64_t oleafly_abi_add(int64_t a, int64_t b);

#ifdef __cplusplus
}
#endif

#endif
~~~

- [ ] **Step 5: Add a compile-time C layout fixture**

Create native/zig/fixtures/abi_layout.c. It contains no executable entry point; zig cc -c only has to compile its static assertions.

~~~c
#include <stddef.h>

#include "oleafly_abi.h"

_Static_assert(sizeof(oleafly_abi_version_t) == 12, "ABI version size changed");
_Static_assert(_Alignof(oleafly_abi_version_t) == 4, "ABI version alignment changed");
_Static_assert(offsetof(oleafly_abi_version_t, major) == 0, "major offset changed");
_Static_assert(offsetof(oleafly_abi_version_t, minor) == 4, "minor offset changed");
_Static_assert(offsetof(oleafly_abi_version_t, patch) == 8, "patch offset changed");
~~~

- [ ] **Step 6: Run the contract compilation before implementation**

After the pinned compiler is available, run:

~~~text
zig test native/zig/tests/abi_probe.zig
~~~

Expected: compilation fails because the implementation symbols and library do not exist yet. Run the corpus directly as a sanity check:

~~~text
zig test native/zig/tests/miscompile_corpus.zig
~~~

Expected: all three corpus tests pass. The ABI failure is intentional TDD evidence and is not a release result; the next task supplies the missing library.

Run the SIMD corpus directly as a second compiler sanity check:

~~~text
zig test native/zig/tests/simd_corpus.zig
~~~

Expected: both SIMD tests pass in the compiler's default Debug mode; the build graph later repeats them in ReleaseSafe and ReleaseFast.

## Task 2: Add the pinned package manifest and Zig build graph

**Files:**

- Create: build.zig.zon
- Create: build.zig
- Create: tools/zig/toolchain.json

- [ ] **Step 1: Declare package identity and empty dependency graph**

Create build.zig.zon with the fingerprint generated by Zig 0.16.0 for the oleafly package name. Keep the dependency table empty until a later slice has a reviewed dependency decision.

~~~zig
.{
    .name = .oleafly,
    .fingerprint = 0xe1271ea97f497f3f,
    .version = "0.0.0",
    .minimum_zig_version = "0.16.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "native/zig",
        "tools/zig/toolchain.json",
        "LICENSE",
        "NOTICE",
    },
}
~~~

- [ ] **Step 2: Record the exact upstream toolchain artifacts**

Create tools/zig/toolchain.json:

~~~json
{
  "schema_version": 1,
  "zig_version": "0.16.0",
  "release_date": "2026-04-13",
  "source_index": "https://ziglang.org/download/index.json",
  "allowed_targets": [
    "x86_64-windows-msvc",
    "x86_64-linux-gnu"
  ],
  "artifacts": {
    "windows_x86_64": {
      "archive_format": "zip",
      "root_directory": "zig-x86_64-windows-0.16.0",
      "url": "https://ziglang.org/download/0.16.0/zig-x86_64-windows-0.16.0.zip",
      "sha256": "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e",
      "archive_size_bytes": 97217739
    },
    "linux_x86_64": {
      "archive_format": "tar.xz",
      "root_directory": "zig-x86_64-linux-0.16.0",
      "url": "https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz",
      "sha256": "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00",
      "archive_size_bytes": 55478392
    }
  }
}
~~~

- [ ] **Step 3: Add the root build graph**

Create build.zig:

~~~zig
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
~~~

- [ ] **Step 4: Verify the graph exposes only the intended steps**

Run:

~~~text
zig build --list-steps
~~~

Expected: the list contains install, run, test, abi, miscompile-corpus, and simd-corpus; no package fetch step or legacy application target is introduced by this graph.

## Task 3: Implement the minimal Zig executable and ABI

**Files:**

- Create: native/zig/src/main.zig
- Create: native/zig/src/abi.zig

- [ ] **Step 1: Add the stable runtime smoke output**

Create native/zig/src/main.zig:

~~~zig
const std = @import("std");

pub fn main() void {
    std.debug.print("oleafly-t0.1 toolchain ok\n", .{});
}
~~~

std.debug.print intentionally uses the standard diagnostic stream, and the CI runtime assertion captures stdout and stderr together. This avoids depending on an unstable 0.16 output-writer convenience API for a smoke string.

- [ ] **Step 2: Add the narrow fixed-width ABI implementation**

Create native/zig/src/abi.zig:

~~~zig
pub const AbiVersion = extern struct {
    major: u32,
    minor: u32,
    patch: u32,
};

pub const abi_ok: i32 = 0;
pub const abi_invalid_argument: i32 = -1;

pub export fn oleafly_abi_get_version(out: ?*AbiVersion) callconv(.c) i32 {
    const destination = out orelse return abi_invalid_argument;
    destination.* = .{
        .major = 0,
        .minor = 1,
        .patch = 0,
    };
    return abi_ok;
}

pub export fn oleafly_abi_add(a: i64, b: i64) callconv(.c) i64 {
    return a +% b;
}
~~~

The pointer is optional so a null caller receives a deterministic status rather than dereferencing invalid memory. The integer addition is explicitly wrapping (`+%`) so edge inputs have the same result in ReleaseSafe and ReleaseFast. No allocator, slice, error union, exception, C++ object, or standard-library object crosses this boundary.

- [ ] **Step 3: Run the focused ABI and corpus tests**

Run:

~~~text
zig build -Doptimize=Debug abi --summary all
zig build -Doptimize=Debug miscompile-corpus --summary all
zig build -Doptimize=Debug test --summary all
~~~

Expected: all ABI, FNV, and SIMD corpus tests pass; the build summary reports successful run test steps and no missing symbol errors.

- [ ] **Step 4: Prove both release modes**

Run:

~~~text
zig build --release=safe abi --summary all
zig build --release=fast abi --summary all
zig build --release=safe miscompile-corpus --summary all
zig build --release=fast miscompile-corpus --summary all
~~~

Expected: every command passes. ReleaseFast is a comparison lane only; the default plain `zig build` mode remains ReleaseSafe because of the explicit resolver above.

## Task 4: Add local hygiene and developer documentation

**Files:**

- Modify: .gitignore
- Modify: .gitattributes
- Modify: docs/development.md

- [ ] **Step 1: Ignore generated Zig state without hiding source**

Append to .gitignore:

~~~gitignore
# Zig build output and local tool archives
.zig-cache/
zig-out/
tools/zig/.cache/
tools/zig/zig-*.zip
tools/zig/zig-*.tar.xz
~~~

- [ ] **Step 2: Keep Zig inputs LF-normalized on Windows**

Append to .gitattributes:

~~~gitattributes
# Zig formatting and workflow verification require stable LF bytes on Windows.
*.zig text eol=lf
*.zon text eol=lf
tools/zig/toolchain.json text eol=lf
~~~

Run `git check-attr eol -- build.zig build.zig.zon native/zig/src/main.zig
tools/zig/toolchain.json .github/workflows/zig.yml` and require `eol: lf` for
every path. This closes the Windows checkout normalization gap where
`zig fmt --check` rejects CRLF input.

- [ ] **Step 3: Document the migration-safe local loop**

Insert the following section after the existing prerequisites in docs/development.md, before the legacy Tauri first-run instructions:

~~~~markdown
## Zig walking skeleton (T0.1)

The rewrite starts in native/zig/ while the existing Tauri/React/Rust tree
remains a development oracle. The root build.zig and build.zig.zon are the
future build entry points; no legacy runtime is wrapped or packaged by this
slice.

Download the exact archive listed in tools/zig/toolchain.json from
ziglang.org, verify its byte size and SHA-256 before extraction, and put the
matching directory on PATH. CI performs the same checks on fresh Windows and
Linux runners.

~~~
zig version
zig fmt --check build.zig build.zig.zon native/zig
zig build --fetch=all
zig build -Doptimize=Debug test --summary all
zig build --release=safe test --summary all
zig build --release=safe abi --summary all
zig build --release=fast abi --summary all
zig build --release=safe miscompile-corpus --summary all
zig build --release=safe simd-corpus --summary all
zig build --release=fast simd-corpus --summary all
zig build --release=safe run --summary all
~~~

The final command prints oleafly-t0.1 toolchain ok. ReleaseSafe is the
shipping default; ReleaseFast is used only to expose optimizer-dependent ABI,
FNV, or SIMD known-answer regressions. The full application, native Windows UI, editor,
compiler workers, research ledger, and publishing pipeline remain future
bounded slices.
~~~~

- [ ] **Step 4: Check the docs, attributes, and ignore rules**

Run:

~~~text
git diff --check
git check-attr eol -- build.zig build.zig.zon native/zig/src/main.zig tools/zig/toolchain.json .github/workflows/zig.yml
rg -n "native/zig|ReleaseSafe|miscompile-corpus|simd-corpus|toolchain.json" docs/development.md .gitignore .gitattributes
~~~

Expected: no whitespace errors; every named local command and generated path is present; every Zig/manifest/workflow path reports `eol: lf`; no generated directory is accidentally ignored under native/zig/.

## Task 5: Add the dedicated reproducible CI lanes

**Files:**

- Create: .github/workflows/zig.yml

- [ ] **Step 1: Add workflow triggers, permissions, and action pin**

Create .github/workflows/zig.yml with this complete workflow. The only third-party action is the official checkout action pinned to its v7 commit; archive download and all verification remain explicit shell commands.

~~~yaml
name: Zig T0.1

on:
  push:
    branches: [main]
    paths:
      - "build.zig"
      - "build.zig.zon"
      - "native/zig/**"
      - "tools/zig/**"
      - ".gitattributes"
      - ".github/workflows/zig.yml"
  pull_request:
    branches: [main]
    paths:
      - "build.zig"
      - "build.zig.zon"
      - "native/zig/**"
      - "tools/zig/**"
      - ".gitattributes"
      - ".github/workflows/zig.yml"
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: zig-t0.1-${{ github.ref }}
  cancel-in-progress: true

jobs:
  zig-windows:
    name: Zig T0.1 (Windows x64)
    runs-on: windows-2022
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          persist-credentials: false

      - name: Bootstrap verified Zig 0.16.0
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $PSNativeCommandUseErrorActionPreference = $true
          $manifest = Get-Content -LiteralPath "tools/zig/toolchain.json" -Raw | ConvertFrom-Json
          if ($manifest.schema_version -ne 1 -or $manifest.zig_version -ne "0.16.0") { throw "unsupported Zig manifest" }
          if (@($manifest.allowed_targets) -notcontains "x86_64-windows-msvc") { throw "Windows target is not allowlisted" }
          $artifact = $manifest.artifacts.windows_x86_64
          $uri = [Uri]$artifact.url
          if ($uri.Scheme -ne "https" -or $uri.Host -ne "ziglang.org") { throw "untrusted Zig archive host" }
          if ($artifact.archive_format -ne "zip") { throw "unexpected Windows archive format" }
          if ($artifact.root_directory -ne "zig-x86_64-windows-0.16.0") { throw "unexpected Windows archive root" }
          if ($uri.AbsolutePath -ne "/download/0.16.0/zig-x86_64-windows-0.16.0.zip") { throw "unexpected Windows archive path" }
          $archive = Join-Path $env:RUNNER_TEMP "zig-x86_64-windows-0.16.0.zip"
          Invoke-WebRequest -Uri $artifact.url -OutFile $archive
          $item = Get-Item -LiteralPath $archive
          if ([int64]$item.Length -ne [int64]$artifact.archive_size_bytes) { throw "Zig archive size mismatch" }
          $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
          if ($actual -ne $artifact.sha256.ToLowerInvariant()) { throw "Zig archive SHA-256 mismatch" }
          Expand-Archive -LiteralPath $archive -DestinationPath $env:RUNNER_TEMP -Force
          $zigRoot = Join-Path $env:RUNNER_TEMP $artifact.root_directory
          $zigExe = Join-Path $zigRoot "zig.exe"
          if (-not (Test-Path -LiteralPath $zigExe -PathType Leaf)) { throw "verified Zig executable missing" }
          $version = (& $zigExe version).Trim()
          if ($version -ne $manifest.zig_version) { throw "Zig version mismatch: $version" }
          (Split-Path -Parent $zigExe) | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
          "ZIG_VERSION=$version" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

      - name: Verify dependency graph, formatting, and C layout
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $PSNativeCommandUseErrorActionPreference = $true
          zig build --fetch=all
          zig fmt --check build.zig build.zig.zon native/zig
          $translated = Join-Path $env:RUNNER_TEMP "oleafly-abi-translated.zig"
          zig translate-c -I native/zig/include native/zig/include/oleafly_abi.h | Out-File -FilePath $translated -Encoding utf8
          if (-not (Select-String -LiteralPath $translated -Pattern "oleafly_abi_get_version" -Quiet)) { throw "translated header omitted oleafly_abi_get_version" }
          if (-not (Select-String -LiteralPath $translated -Pattern "oleafly_abi_version_t" -Quiet)) { throw "translated header omitted oleafly_abi_version_t" }
          zig cc -target x86_64-windows-msvc -std=c11 -I native/zig/include -c native/zig/fixtures/abi_layout.c -o (Join-Path $env:RUNNER_TEMP "oleafly-abi-layout.obj")

      - name: Run Debug and ReleaseSafe tests
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $PSNativeCommandUseErrorActionPreference = $true
          zig build -Doptimize=Debug test --summary all
          zig build --release=safe test --summary all

      - name: Build ABI, miscompile, and SIMD comparison modes
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $PSNativeCommandUseErrorActionPreference = $true
          zig build -Dtarget=x86_64-windows-msvc --release=safe abi --summary all
          zig build -Dtarget=x86_64-windows-msvc --release=fast abi --summary all
          zig build -Dtarget=x86_64-windows-msvc --release=safe miscompile-corpus --summary all
          zig build -Dtarget=x86_64-windows-msvc --release=fast miscompile-corpus --summary all
          zig build -Dtarget=x86_64-windows-msvc --release=safe simd-corpus --summary all
          zig build -Dtarget=x86_64-windows-msvc --release=fast simd-corpus --summary all

      - name: Build and run the Windows executable
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $PSNativeCommandUseErrorActionPreference = $true
          zig build -Dtarget=x86_64-windows-msvc --release=safe --summary all
          $output = (& .\zig-out\bin\oleafly-t0.1.exe 2>&1 | Out-String).Trim()
          if ($output -ne "oleafly-t0.1 toolchain ok") { throw "unexpected smoke output: $output" }

      - name: Prove two clean ReleaseSafe hashes
        shell: pwsh
        run: |
          $ErrorActionPreference = "Stop"
          $PSNativeCommandUseErrorActionPreference = $true
          $outA = Join-Path $env:RUNNER_TEMP "oleafly-t0.1-out-a"
          $outB = Join-Path $env:RUNNER_TEMP "oleafly-t0.1-out-b"
          $cacheA = Join-Path $env:RUNNER_TEMP "oleafly-t0.1-cache-a"
          $cacheB = Join-Path $env:RUNNER_TEMP "oleafly-t0.1-cache-b"
          $globalA = Join-Path $env:RUNNER_TEMP "oleafly-t0.1-global-a"
          $globalB = Join-Path $env:RUNNER_TEMP "oleafly-t0.1-global-b"
          zig build -Dtarget=x86_64-windows-msvc --release=safe --prefix $outA --cache-dir $cacheA --global-cache-dir $globalA --summary all
          zig build -Dtarget=x86_64-windows-msvc --release=safe --prefix $outB --cache-dir $cacheB --global-cache-dir $globalB --summary all
          $hashA = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $outA "bin\oleafly-t0.1.exe")).Hash.ToLowerInvariant()
          $hashB = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $outB "bin\oleafly-t0.1.exe")).Hash.ToLowerInvariant()
          if ($hashA -ne $hashB) { throw "ReleaseSafe build is not reproducible: $hashA != $hashB" }
          Write-Output "ReleaseSafe SHA-256: $hashA"

  zig-linux:
    name: Zig T0.1 (Linux x64)
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          persist-credentials: false

      - name: Bootstrap verified Zig 0.16.0
        shell: bash
        run: |
          set -euo pipefail
          version="$(jq -r '.zig_version' tools/zig/toolchain.json)"
          format="$(jq -r '.artifacts.linux_x86_64.archive_format' tools/zig/toolchain.json)"
          root="$(jq -r '.artifacts.linux_x86_64.root_directory' tools/zig/toolchain.json)"
          target="$(jq -r '.allowed_targets[]' tools/zig/toolchain.json | grep -Fx 'x86_64-linux-gnu')"
          url="$(jq -r '.artifacts.linux_x86_64.url' tools/zig/toolchain.json)"
          sha="$(jq -r '.artifacts.linux_x86_64.sha256' tools/zig/toolchain.json)"
          size="$(jq -r '.artifacts.linux_x86_64.archive_size_bytes' tools/zig/toolchain.json)"
          test "$version" = "0.16.0"
          test "$target" = "x86_64-linux-gnu"
          test "$format" = "tar.xz"
          test "$root" = "zig-x86_64-linux-0.16.0"
          test "$url" = "https://ziglang.org/download/0.16.0/zig-x86_64-linux-0.16.0.tar.xz"
          case "$url" in https://ziglang.org/*) ;; *) echo "untrusted Zig archive host" >&2; exit 1 ;; esac
          archive="$RUNNER_TEMP/zig-x86_64-linux-0.16.0.tar.xz"
          curl --fail --location --retry 3 --output "$archive" "$url"
          test "$(stat -c '%s' "$archive")" = "$size"
          printf '%s  %s\n' "$sha" "$archive" | sha256sum --check --strict
          tar -xJf "$archive" -C "$RUNNER_TEMP"
          test -x "$RUNNER_TEMP/$root/zig"
          test "$($RUNNER_TEMP/$root/zig version)" = "$version"
          echo "$RUNNER_TEMP/$root" >> "$GITHUB_PATH"
          echo "ZIG_VERSION=$version" >> "$GITHUB_ENV"

      - name: Verify dependency graph, formatting, and C layout
        shell: bash
        run: |
          set -euo pipefail
          zig build --fetch=all
          zig fmt --check build.zig build.zig.zon native/zig
          translated="$RUNNER_TEMP/oleafly-abi-translated.zig"
          zig translate-c -I native/zig/include native/zig/include/oleafly_abi.h > "$translated"
          grep -q "oleafly_abi_get_version" "$translated"
          grep -q "oleafly_abi_version_t" "$translated"
          zig cc -target x86_64-linux-gnu -std=c11 -I native/zig/include -c native/zig/fixtures/abi_layout.c -o "$RUNNER_TEMP/oleafly-abi-layout.o"

      - name: Run Debug and ReleaseSafe tests
        shell: bash
        run: |
          set -euo pipefail
          zig build -Dtarget=x86_64-linux-gnu -Doptimize=Debug test --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=safe test --summary all

      - name: Build ABI, miscompile, and SIMD comparison modes
        shell: bash
        run: |
          set -euo pipefail
          zig build -Dtarget=x86_64-linux-gnu --release=safe abi --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=fast abi --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=safe miscompile-corpus --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=fast miscompile-corpus --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=safe simd-corpus --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=fast simd-corpus --summary all

      - name: Build and run the Linux executable
        shell: bash
        run: |
          set -euo pipefail
          zig build -Dtarget=x86_64-linux-gnu --release=safe --summary all
          test "$(./zig-out/bin/oleafly-t0.1 2>&1)" = "oleafly-t0.1 toolchain ok"

      - name: Prove two clean ReleaseSafe hashes
        shell: bash
        run: |
          set -euo pipefail
          out_a="$RUNNER_TEMP/oleafly-t0.1-out-a"
          out_b="$RUNNER_TEMP/oleafly-t0.1-out-b"
          cache_a="$RUNNER_TEMP/oleafly-t0.1-cache-a"
          cache_b="$RUNNER_TEMP/oleafly-t0.1-cache-b"
          global_a="$RUNNER_TEMP/oleafly-t0.1-global-a"
          global_b="$RUNNER_TEMP/oleafly-t0.1-global-b"
          zig build -Dtarget=x86_64-linux-gnu --release=safe --prefix "$out_a" --cache-dir "$cache_a" --global-cache-dir "$global_a" --summary all
          zig build -Dtarget=x86_64-linux-gnu --release=safe --prefix "$out_b" --cache-dir "$cache_b" --global-cache-dir "$global_b" --summary all
          hash_a="$(sha256sum "$out_a/bin/oleafly-t0.1" | cut -d' ' -f1)"
          hash_b="$(sha256sum "$out_b/bin/oleafly-t0.1" | cut -d' ' -f1)"
          test "$hash_a" = "$hash_b"
          echo "ReleaseSafe SHA-256: $hash_a"
~~~

- [ ] **Step 2: Check workflow syntax and path coverage locally**

Run:

~~~text
git diff --check
rg -n "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1|native/zig/\\*\\*|build\\.zig\\.zon|\\.gitattributes|ReleaseSafe SHA-256" .github/workflows/zig.yml
~~~

Expected: one pinned checkout per job, both Zig source/path triggers plus `.gitattributes`, both release-safe reproducibility assertions, and no paths-ignore clause in the Zig workflow.

- [ ] **Step 3: Execute both jobs locally where the host permits**

On Windows, execute the commands from zig-windows in a clean PowerShell session. On a Linux host, execute the commands from zig-linux. If the opposite OS lane cannot run locally, record it as environment-unverified and rely on the corresponding GitHub runner; do not skip the native lane that is available.

## Task 6: Run the T0.1 evidence and quality-streak protocol

**Files:**

- Create after verification: docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md

- [ ] **Step 1: Run the five-pass test-effectiveness review**

Use this order and record the result in the evidence file:

1. Oracle: compare every acceptance row above with a command or fixture that can fail when the contract is wrong.
2. Portfolio: confirm Debug, ReleaseSafe, ReleaseFast, Windows, Linux, static library, independent extern declarations, header translation, C static assertions, and SIMD `@Vector` tests are all represented.
3. Adversarial: run null ABI output, negative/in-range signed adds, the `maxInt(i64) + 1 -> minInt(i64)` wrapping edge, empty input, embedded zero/0xFF, SIMD lane reduction, and all optimizer modes.
4. Falsification: temporarily mutate one FNV expected constant, one SIMD expected lane, and one ABI field offset in a disposable copy; confirm the corpus, SIMD test, and C compilation fail, then restore the committed files and rerun the full matrix.
5. Reality: run the actual ReleaseSafe executable on the native Windows runner and native Linux runner and capture the exact output plus SHA-256.
6. UI boundary: record browser/UI QA as not applicable because the slice intentionally has no window, renderer, browser surface, or native UI harness; do not use that exemption for later UI slices.

- [ ] **Step 2: Execute Pass A from a clean process and disposable output roots**

On the available Windows host, run the complete Windows matrix in workflow order and cross-compile the Linux x64 ReleaseSafe executable. On a Linux host, run the native Linux matrix as well. Use disposable output/cache roots and collect:

~~~text
git rev-parse HEAD
git ls-files build.zig build.zig.zon native/zig tools/zig .github/workflows/zig.yml
zig version
git diff --check
~~~

The evidence file must record the actual pre-implementation parent commit, toolchain version, archive hashes from the manifest, commands, runner/OS/target, test summaries, runtime output, reproducible hash pair, and any explicitly unverified native lane. A cross-compiled binary is compile evidence, not native runtime evidence.

- [ ] **Step 3: Execute Pass B with fresh state and changed order**

Start a fresh terminal/process and fresh disposable output/cache roots. On Windows, run the Linux cross-target commands first, then the Windows commands; run ReleaseFast before ReleaseSafe in this pass. On Linux, run the native Linux commands first. Rebuild the outputs and generate a new hash line. Do not reuse a mutable cache, test process, or verdict from Pass A.

- [ ] **Step 4: Review and push the source commit before recording remote verdicts**

Stage only the T0.1 source, build, workflow, documentation, and hygiene files. Keep the evidence file out of this commit because the native Linux and fresh-run verdicts are produced by GitHub Actions after the push:

~~~text
git add .gitignore docs/development.md build.zig build.zig.zon native/zig tools/zig/toolchain.json .github/workflows/zig.yml
git diff --cached --check
git diff --cached --stat
git diff --cached -- .github/workflows/zig.yml build.zig build.zig.zon native/zig tools/zig/toolchain.json docs/development.md .gitignore
git status --short
~~~

Expected: the staged diff contains only the files listed above; the cached whitespace check is clean; no downloaded archive, cache, zig-out, .zig-cache, legacy source file, generated translation output, or evidence file is staged.

Compute the staged tree, commit, verify that the commit tree is unchanged, and push it:

~~~text
$tree = (git write-tree).Trim()
git commit -m "feat: establish reproducible Zig T0.1 toolchain" `
  -m "Quality-Streak: pending remote CI 2/2" `
  -m "Toolchain: Zig 0.16.0" `
  -m "Reviewed-Tree: $tree" `
  -m "Runtime-Status: T0.1 walking skeleton only; remote streak gate remains"
if ((git rev-parse 'HEAD^{tree}').Trim() -ne $tree) { throw "commit tree differs from staged tree" }
git push origin HEAD:main
if ((git rev-parse HEAD).Trim() -ne (git ls-remote origin refs/heads/main).Split()[0]) { throw "origin/main moved during push" }
~~~

If the push or remote runner is unavailable, record that state and do not claim the T0.1 quality streak or completion.

- [ ] **Step 5: Obtain two consecutive clean remote workflow runs**

Wait for the push-triggered run for the source commit and require both `zig-windows` and `zig-linux` jobs to finish with conclusion `success`:

~~~text
$commit = (git rev-parse HEAD).Trim()
$runA = gh run list --workflow zig.yml --commit $commit --limit 1 --json databaseId,status,conclusion,url | ConvertFrom-Json | Select-Object -First 1
if ($null -eq $runA) { throw "no push-triggered Zig workflow run found" }
gh run watch $runA.databaseId --exit-status
$jobsA = gh run view $runA.databaseId --json jobs | ConvertFrom-Json
if (@($jobsA.jobs).Count -ne 2 -or @($jobsA.jobs | Where-Object { $_.name -notin @("Zig T0.1 (Windows x64)", "Zig T0.1 (Linux x64)") -or $_.conclusion -ne "success" }).Count -ne 0) { throw "Run A did not finish with two successful native jobs" }
~~~

After Run A is complete, verify that `origin/main` still points to the same source commit and dispatch a second fresh run. Wait for every job to finish successfully; a cancelled, flaky, or unavailable job resets the streak and requires a fix/new source commit before restarting at Run A:

~~~text
if ((git ls-remote origin refs/heads/main).Split()[0] -ne $commit) { throw "source commit is no longer origin/main" }
gh workflow run zig.yml --ref main
$runB = $null
for ($attempt = 0; $attempt -lt 30 -and $null -eq $runB; $attempt++) {
  Start-Sleep -Seconds 2
  $runB = gh run list --workflow zig.yml --commit $commit --limit 10 --json databaseId,status,conclusion,url | ConvertFrom-Json | Where-Object { $_.databaseId -ne $runA.databaseId } | Select-Object -First 1
}
if ($null -eq $runB) { throw "no second Zig workflow run found" }
gh run watch $runB.databaseId --exit-status
$jobsB = gh run view $runB.databaseId --json jobs | ConvertFrom-Json
if (@($jobsB.jobs).Count -ne 2 -or @($jobsB.jobs | Where-Object { $_.name -notin @("Zig T0.1 (Windows x64)", "Zig T0.1 (Linux x64)") -or $_.conclusion -ne "success" }).Count -ne 0) { throw "Run B did not finish with two successful native jobs" }
~~~

Pass B's changed local command order supplies the state-order challenge; the two remote runs supply fresh native Windows/Linux execution and clean runner/cache evidence. Do not count a local-only pass as a remote streak substitute.

- [ ] **Step 6: Write the evidence manifest with no invented results**

Create docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md with this exact section structure, filling each field from the just-completed commands:

~~~markdown
# Oleafly T0.1 Toolchain Evidence

## Identity

- Parent/source commit: record the source commit SHA and the pre-implementation parent SHA.
- Toolchain manifest: `tools/zig/toolchain.json`.
- Zig version: record the output of `zig version`.
- Windows archive SHA-256: record the `windows_x86_64.sha256` manifest value and verified download hash.
- Linux archive SHA-256: record the `linux_x86_64.sha256` manifest value and verified download hash.
- Remote Run A: record the `gh run` database ID, URL, commit, and both successful job conclusions.
- Remote Run B: record the `gh run` database ID, URL, commit, and both successful job conclusions.

## Matrix

| Pass | Host/target | Process/cache state | Result |
| --- | --- | --- | --- |
| A | record local Windows x64 plus remote Windows/Linux x64 runner targets | clean process and cache roots | record each lane result and Run A |
| B | record changed-order local pass plus remote Windows/Linux x64 runner targets | fresh process and cache roots | record each lane result and Run B |

## Direct outputs

- `zig build -Doptimize=Debug test`: record each lane summary.
- `zig build --release=safe test`: record each lane summary.
- `zig build abi` in both `--release=safe` and `--release=fast` modes: record summaries.
- `zig build miscompile-corpus` in both `--release=safe` and `--release=fast` modes: record summaries.
- `zig build simd-corpus` in both `--release=safe` and `--release=fast` modes: record summaries.
- native executable output: record the exact combined-stream line.
- ReleaseSafe hash A: record the first clean-build SHA-256.
- ReleaseSafe hash B: record the second clean-build SHA-256 and equality result.

## Five-pass review

- Oracle: record pass/fail for every acceptance row.
- Portfolio: record the completed host, target, mode, fixture, and boundary matrix.
- Adversarial: record null, binary-byte, and in-range signed-add outcomes.
- Falsification: record the mutated-constant failures and restored rerun.
- Reality: record native executable output and reproducible hash evidence.
- UI/browser: record not applicable for this no-UI slice; the first UI slice must add browser evidence.

## Findings and closure

- Medium-or-higher findings: list every finding ID and closure evidence, or record none.
- Flakes or unexplained skips: list each diagnostic, or record none.
- Explicitly unverified items: name unavailable hosts or later-slice budgets.
- Browser/UI QA: not applicable to T0.1 by explicit scope; no browser-visible surface exists.
- Quality streak: 2/2 clean closed-coverage passes
~~~

Do not state a lane is clean when it was unavailable. The T0.2 native feasibility measurements and all application performance budgets remain explicitly unverified here because they are outside this slice. The evidence file is written only after both remote runs are green, and it is immutable once the evidence commit is pushed.

- [ ] **Step 7: Review and push the evidence-only commit**

Run:

~~~text
git add docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md
git diff --cached --check
git diff --cached --stat
git diff --cached -- docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md
git status --short
~~~

Expected: only the evidence file is staged; the cached whitespace check is clean; no downloaded archive, cache, zig-out, .zig-cache, legacy source file, or generated translation output is present.

Compute the evidence hash from the reviewed file, commit it separately, and push. This commit must not trigger the Zig workflow because the workflow path filter intentionally excludes docs/superpowers/evidence/; the two remote runs already prove the source tree.

~~~text
$commit = (git rev-parse HEAD).Trim()
$tree = (git write-tree).Trim()
$evidence = (Get-FileHash -Algorithm SHA256 -LiteralPath docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md).Hash.ToLowerInvariant()
git commit -m "docs: record T0.1 verification evidence" `
  -m "Quality-Streak: 2/2 clean closed-coverage passes" `
  -m "Source-Commit: $commit" `
  -m "Reviewed-Tree: $tree" `
  -m "Evidence-SHA256: $evidence" `
  -m "Runtime-Status: T0.1 walking skeleton only; T0.2 gate remains"
if ((git rev-parse 'HEAD^{tree}').Trim() -ne $tree) { throw "commit tree differs from staged tree" }
git push origin HEAD:main
~~~

The evidence commit message body must include these trailers with the actual values from the source/evidence files:

~~~text
Quality-Streak: 2/2 clean closed-coverage passes
Source-Commit: value printed by git rev-parse HEAD before the evidence commit
Reviewed-Tree: value printed by git write-tree before the evidence commit
Evidence-SHA256: value printed by Get-FileHash -Algorithm SHA256 docs/superpowers/evidence/2026-09-04-oleafly-t0-1-toolchain.md
Runtime-Status: T0.1 walking skeleton only; T0.2 gate remains
~~~

After pushing, verify `git rev-parse HEAD` equals `origin/main`, confirm the evidence hash from the pushed file, and report the source/evidence commits and Run A/Run B URLs outside the committed tree. If an evidence edit is needed, it is a new evidence change and requires the full two-pass protocol again.

## T0.1 review checklist before implementation starts

- [ ] Every file path in the file map appears in an implementation task.
- [ ] The root build graph has no dependency package and no legacy runtime edge.
- [ ] The default optimization is ReleaseSafe; ReleaseFast is comparison-only, and release artifacts are stripped for deterministic hashes.
- [ ] The ABI test links the produced static library through independent extern declarations.
- [ ] The public header is translated and its layout is compiled by Zig's C frontend without a C executable.
- [ ] Known-answer constants are independently computed and include empty, ASCII, project-name, and binary-byte cases.
- [ ] The SIMD `@Vector` corpus has exact lane and reduction answers in Debug, ReleaseSafe, and ReleaseFast.
- [ ] CI verifies archive host, format, size, hash, extraction root, and compiler version.
- [ ] Both CI jobs use the same source manifest and pinned checkout commit.
- [ ] Reproducibility uses different local and global cache roots and compares final executable hashes.
- [ ] Evidence records actual results, explicit unverified items, and the two-pass streak.
- [ ] No step depends on a future type, function, external tool, package, or unspecified test harness.
- [ ] T0.2 and later product work is explicitly out of scope.
