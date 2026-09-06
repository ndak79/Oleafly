# T0.2b Static Boundary Proof Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development or superpowers:executing-plans. Track every step with a checkbox.

Goal: add executable static contracts for the T0.2b Windows API facade, source-import boundary, and test-only Lexilla comparator while keeping the missing PDFium reconstruction and sealed-runner gates explicitly unverified.

Architecture: generated zigwin32 remains behind native/zig/src/platform/windows/api.zig. A pure-Zig scanner reads the non-generated repository tree and rejects direct root-package/everything.zig imports except the facade and the isolated cache-contract test. A Windows SDK C probe exports layout/GUID facts that the Zig test consumes, making the ABI check cross-language rather than self-referential. Lexilla is compiled only as a named, unshipped comparator over the locked LaTeX/BibTeX sources. No lane loads PDFium, launches a worker, mutates networking, or changes the shipping install graph.

Tech stack: Zig 0.16.0, pinned zigwin32/Scintilla/Lexilla archives, std.Io.Dir, std.Io.Reader, zig cc, and the existing build/test graph.

---

### Task 1: Pure-Zig source import boundary scanner

Files:

- Create tools/zig/source_boundary.zig
- Create native/zig/tests/source_boundary_test.zig
- Modify build.zig near the existing T0.2b argv module and steps
- Modify build.zig.zon to include both new Zig files
- Modify docs/development.md with the scanner scope and named commands

- [x] Step 1: Add a compilable RED stub and assertion-level tests.

Add a source_boundary module whose scanText function returns error.NotImplemented, add the test module and named test step, and run the x86_64-windows-msvc test. The test must compile and fail an assertion expecting DirectZigwin32Import for this exact fixture rather than fail with an unknown build step:

    test "direct generated import is rejected outside the facade" {
        try testing.expectError(error.DirectZigwin32Import, source_boundary.scanText("native/zig/src/app/main.zig", "const z = @import(\"zigwin32\");"));
    }

- [x] Step 2: Implement lexical scanning with a closed import grammar.

Implement scanText(path, source) !void. Validate UTF-8, skip // and /*...*/ comments, parse quoted Zig strings and escapes, and inspect @import calls only. Require exactly one quoted literal followed by optional whitespace and a closing parenthesis; reject a bare @import token, concatenation, interpolation, identifiers, or any other comptime expression with error.NonLiteralImport. Reject an import string equal to zigwin32, an import ending in everything.zig after slash normalization, and an import beginning zigwin32/ outside these two explicit test-only paths. On Windows, generated package names use filesystem case-folding; the two exception paths remain exact and intentionally narrow:

    native/zig/src/platform/windows/api.zig
    native/zig/tests/zigwin32_cache_test.zig

Do not reject ordinary strings containing import-like text, legal std imports, CRLF, escaped quotes, or multiline source. Return InvalidUtf8 and MalformedSource for invalid input.

- [x] Step 3: Implement deterministic non-generated tree scanning.

Implement scanTree(allocator, absolute_root) !Report using a component-wise no-follow walk for ordinary drive/UNC roots and recursive openDir/openFile calls with follow_symlinks=false. Re-check absolute-root ancestors after root acquisition, open each candidate source file from its already-validated directory handle, and retain that handle through the sorted scan so no later multi-component path reopen can cross a replaced junction. This scanner intentionally covers every filesystem file whose suffix is `.zig` (case-insensitive so Windows cannot bypass the boundary with `.ZIG`) under the root except generated trees (.git, .zig-cache, zig-cache, zig-out, tools/zig/.cache) and repository metadata trees (.superpowers, .codegraph, .gitnexus, .agents); it does not claim Git-tracked-file detection. Normalize slash styles and compare the facade exception case-sensitively on Windows and byte-sensitively on Linux. Validate every absolute-root ancestor and reject symlink/reparse entries and reparse-backed ancestors. Enforce a 64-level depth limit, a 16 MiB per-file limit, and a 256 MiB aggregate read limit; return explicit limit errors. Collect violation records as well as files, sort all relative paths by byte order, and report the first violation path/class through the host diagnostic while preserving typed error classes for callers.

- [x] Step 4: Add adversarial and tree tests.

As-built clarification (2026-09-07): the repository-root `node_modules` and the
direct `packages/<workspace>/node_modules` trees materialized by pnpm are
treated as generated dependency checkouts (case-insensitively on Windows).
Arbitrary nested `node_modules` paths remain scanned, including the adversarial
`project/node_modules` fixture, so this exception is not a basename-wide bypass.
The scanner still does not claim Git-tracked-file detection.

Cover ordinary strings, escaped and multiline-looking literals, comments at CRLF boundaries, invalid UTF-8, unterminated constructs, legal relative imports, @import(\"zig\" ++ \"win32\") and @import(name), ignored generated directories, deterministic first-violation ordering, depth/file/aggregate limits, and temporary symlink/reparse fixtures. If the host cannot create a symlink, test scanText and the scanner's explicit SymlinkEvidenceUnavailable result instead of silently skipping the security case. Assert that both test-only exceptions are outside the product graph.

- [x] Step 5: Wire and run all modes.

Add a host-target t0-2b-source-boundary step that passes the absolute repository root as the typed -Dsource-boundary-root option. Make t0-2b-argv-test depend on the scanner test, not the host tree scan. Run Debug, ReleaseSafe, and diagnostic ReleaseFast for x86_64-windows-msvc and compile-only Debug, ReleaseSafe, and ReleaseFast for x86_64-linux-gnu. Run the host scan with --summary all -j1; the native-deps-root option remains reserved for dependency lanes.

- [x] Step 6: Commit.

    git add tools/zig/source_boundary.zig native/zig/tests/source_boundary_test.zig build.zig build.zig.zon docs/development.md
    git commit -m "test(zig): enforce generated API import boundary"

### Task 2: Independent DXGI, DWM, and WIC facade contract

Files:

- Create native/zig/tests/windows_sdk_abi_probe.c
- Create native/zig/tests/windows_api_contract_test.zig
- Modify native/zig/src/platform/windows/api.zig for explicit dxgi_common, imaging, dwm, and dwmapi aliases
- Modify build.zig near the windows_api module
- Modify build.zig.zon to include both new test files and the C probe

- [x] Step 1: Add assertion-level RED tests and the cross-language probe.

The Zig test requires IDXGIOutput5, IID_IDXGIOutput5, IDXGIOutputDuplication, DXGI_FORMAT_B8G8R8A8_UNORM from api.dxgi_common, DWMWA_EXTENDED_FRAME_BOUNDS from api.dwm, DwmGetWindowAttribute from api.dwmapi, IWICImagingFactory, IID_IWICImagingFactory, GUID_ContainerFormatPng, GUID_WICPixelFormat32bppBGRA, and the WIC encoder interface/methods from api.imaging. It also asserts the api.d3d11 facade, D3D11_SDK_VERSION, D3D11_CREATE_DEVICE_BGRA_SUPPORT, ID3D11Device layout/CreateBuffer slot, and IID_ID3D11Device. It asserts exact pointer-sized extern-union layouts, complete 16-byte GUIDs, and exact callconv(.winapi) function types including every parameter and return type. The C probe includes d3d11.h, dxgi1_5.h, dwmapi.h, and wincodec.h; it uses _Static_assert for x64 sizeof/offsetof/constants and exports C functions returning the SDK's GUID fields and vtable offsets. The Zig test compares those returned values with the generated declarations. Add the test/build step before aliases so the first run fails an assertion, not step discovery.

- [x] Step 2: Implement the narrow aliases.

Expose dxgi_common as zigwin32.graphics.dxgi.common, imaging as zigwin32.graphics.imaging, dwm as zigwin32.graphics.dwm, and dwmapi as a one-function struct containing zigwin32.dwmapi.DwmGetWindowAttribute. Keep existing ole32.CoCreateInstance for the WIC factory; do not invent an imaging DLL export. Keep the C probe conditional on target.result.os.tag == .windows; Linux compiles only the Zig declaration-only test.

- [x] Step 3: Run Windows and Linux evidence.

    & $zig build t0-2b-api-contract-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug
    & $zig build t0-2b-api-contract-test -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe
    & $zig build t0-2b-api-contract-test -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseFast
    & $zig build t0-2b-api-contract-check -Dtarget=x86_64-linux-gnu -Doptimize=Debug
    & $zig build t0-2b-api-contract-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
    & $zig build t0-2b-api-contract-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseFast

The Linux commands are compile-only and must not claim Windows SDK runtime evidence.

- [x] Step 4: Commit.

    git add native/zig/src/platform/windows/api.zig native/zig/tests/windows_sdk_abi_probe.c native/zig/tests/windows_api_contract_test.zig build.zig build.zig.zon docs/development.md docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md docs/superpowers/plans/2026-09-06-texflow-t0-2b-static-boundary.md
    git commit -m "test(native): lock DXGI DWM WIC facade ABI"

### Task 3: Build and fence the Lexilla comparator

Files:

- Create tools/zig/lexilla_probe.zig
- Create tools/zig/lexilla_size_probe.zig
- Create native/zig/tests/lexilla_comparator_test.zig
- Modify build.zig near the existing Scintilla snapshot/build steps
- Modify build.zig.zon to include all new files
- Append direct evidence to docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md

- [x] Step 1: Add a compilable RED comparator contract.

Add a test step that initially fails with error.MissingLexillaComparator. The contract names the target lexilla-comparator-t0-2b-unshipped, requires the locked Lexilla 5.5.3 archive digest and LicenseRef-Lexilla, and requires exactly the 12 lexlib .cxx files plus LexBibTeX.cxx, LexLaTeX.cxx, and LexTeX.cxx. It requires reviewed LaTeX and BibTeX fixture names and rejects any product/install/worker dependency on the comparator.

- [x] Step 2: Implement the isolated source snapshot and static build.

Use the existing deps lock to materialize Lexilla into a generated output directory and emit a manifest-bound lock receipt. Compile the exact 15 sources as a C++17 static library with the existing Scintilla include tree. Do not add installFile, linkLibrary, runtime loading, or worker edges. Pass the actual source list, archive digest, license hash, archive member list, artifact name, and generated typed `u64` emitted-size receipt to the Zig test.

- [x] Step 3: Add static closure checks.

The test rejects DLL/shared linkage, Lexilla catalogue/loader sources, missing or duplicate source members, changed source/license digest, a size-less artifact, a product graph edge, and a shipping manifest member. Parse the produced COFF archive exactly (including canonical long-name paths and special-member cardinality), inspect binary strings/symbol names for catalogue/loader exports, verify the manifest-bound lock receipt, and measure any listed shipping payload from the real artifact. On Linux, compile the comparator contract only and emit not-in-scope for the Win32 C++ archive.

- [x] Step 4: Run focused modes and append evidence.

    & $zig build t0-2b-lexilla-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug --summary all -j1
    & $zig build t0-2b-lexilla-test -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe --summary all -j1
    & $zig build t0-2b-lexilla-test -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseFast --summary all -j1
    & $zig build t0-2b-lexilla-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe --summary all -j1

Append exact outputs and state that worker recursive closure and runtime Scintilla/UI probing remain later gates.

- [x] Step 5: Commit.

    git add tools/zig/lexilla_probe.zig native/zig/tests/lexilla_comparator_test.zig build.zig build.zig.zon docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md
    git commit -m "test(zig): fence Lexilla comparator from product"

### Task 4: Package and CI wiring

Files:

- Modify build.zig.zon paths
- Modify .github/workflows/zig.yml
- Modify docs/development.md
- Append evidence to docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md

- [x] Step 1: Include every new source/probe in the source package and keep generated outputs ignored.
- [x] Step 2: After deps-fetch succeeds, invoke the named Windows steps with TEXFLOW_NATIVE_DEPS_ROOT, --summary all, and -j1; invoke Linux compile-only checks with the same explicit target. Add an aggregate t0-2b-static step that always includes the host tree scan.
- [x] Step 3: Set standard job timeout to 45 minutes; keep qualified PDFium reconstruction separate and emit not-in-scope on hosted runners with only 14 GiB storage.
- [x] Step 4: Keep workflow shell logic to bootstrap, dependency ordering, and exit status. Zig owns source, ABI, comparator, and verdict calculations.
- [x] Step 5: Run YAML/static workflow checks and record that CI still cannot prove detached-NIC, independent PDFium reconstruction, worker runtime, or recursive product PE closure.
- [x] Step 6: Commit the CI/package wiring.

### Task 5: Review and admission boundary

- [x] Step 1: Run the five-pass loop: oracle, optimization portfolio, adversarial mutations, falsification of load/fetch/worker edges, and runtime reality.
- [x] Step 2: Run independent spec review and quality review against Task 2 lines 1255-1455. Any Medium+ finding resets the streak to 0/1; repair and rerun all affected modes until one clean pass is recorded.
- [x] Step 3: Push the committed branch to the configured remote branch after verifying its name; do not silently push an unrelated branch.

Review outcome (2026-09-06): the bounded static implementation is clean at
`1/1` after repairing the COFF canonical-path and special-member findings, and
the package/CI implementation is clean at `1/1` after correcting the Linux
compile-only aggregate. This does **not** admit full T0.2b. The original
roadmap still requires the sealed-runner receipt and actual reconstruction
execution, independent PDFium source reconstruction and equivalence, recursive
product/worker PE closure, complete ReleaseSafe payload/reproducibility proof,
Scintilla native runtime probing, dependency advisory review, and final
A01/A03/A11/A17 evidence. The committed CI matrix still covers only this
bounded static slice; hosted CI and detached-NIC/network-none evidence remain
unverified. T0.2a is therefore deliberately paused; T0.2c must not start.

This plan intentionally does not close T0.2b. The new `repro_check.zig` slice
provides only a Zig-owned preflight/receipt/payload oracle; it does not launch a
sealed runner or prove PDFium reconstruction. Independent PDFium
reconstruction/equivalence, sealed network evidence, recursive product/worker
PE closure, and final A01/A03/A11/A17 admission remain explicit follow-up
tasks.

### Task 6: Add the bounded reproducibility preflight and payload oracle

Files:

- Create `tools/zig/repro_check.zig`
- Create `native/zig/tests/repro_check_test.zig`
- Modify `build.zig`, `build.zig.zon`, and `.github/workflows/zig.yml`

- [x] Step 1: Add RED tests for target/root/preflight, exact network receipts,
  Windows role inventory, and equal/mutated payload roots.
- [x] Step 2: Implement fail-closed Zig-owned validation. The tool validates
  only the two allowlisted targets, rejects unsafe reconstruction roots,
  requires explicit runner authorization and resource thresholds, requires an
  offline receipt for reproduction, rejects unexpected Linux product roles,
  and compares complete canonical directory digests through the existing
  no-follow materialized-directory hasher. It never invokes a shell, network,
  compiler, or external runner.
- [x] Step 3: Wire a host `t0-2b-repro-test` runtime step and a target-aware
  `t0-2b-repro-check` compile-only step. Include the correct one in the
  Windows/Linux `t0-2b-static` aggregate and CI matrix. Linux remains
  compile-only; no Linux target test is executed.
- [x] Step 4: Verify Windows Debug/ReleaseSafe/ReleaseFast compile-only,
  Windows ReleaseSafe runtime (`4/4` tests), Linux Debug/ReleaseSafe/
  ReleaseFast compile-only, aggregate wiring, formatting, YAML parsing, and
  diff whitespace.
- [ ] Step 5: Do not treat this oracle as full T0.2b admission. A future
  authorized runner slice must add the independently reproducible PDFium
  rebuild, detached-NIC/network-none evidence, complete ReleaseSafe payload
  manifest/two-root proof, recursive worker PE closure, and toolchain receipt.

### Task 7: Parallel PDFium reconstruction receipt contract

Files:

- Create `tools/zig/pdfium_reproduce.zig`
- Create `native/zig/tests/pdfium_repro_toolchain_test.zig`
- Modify `build.zig`, `build.zig.zon`, and `.github/workflows/zig.yml`

- [x] Step 1: Define a strict JSON receipt schema for the future qualified
  Windows reconstruction runner: fixed PDFium/recipe/depot pins, explicit
  SHA-1 versus SHA-256 naming, GN feature locks, wrapper/process identities,
  disposable root/resource thresholds, and a canonical network-none receipt.
- [x] Step 2: Implement fail-closed parsing, duplicate/unknown-field rejection,
  exact target/phase/status checks, canonical argument ordering, safe path
  tokens, and approval revalidation. The module is pure Zig and never spawns,
  fetches, compiles, or mutates a cache.
- [x] Step 3: Add host runtime tests and target compile-only tests for Windows
  Debug/ReleaseSafe/ReleaseFast and Linux Debug/ReleaseSafe/ReleaseFast.
- [ ] Step 4: Do not claim reconstruction: a future authorized slice must
  supply the actual sealed runner, independent PDFium rebuild/equivalence,
  detached-NIC/network-none evidence, and a signed/retained receipt.

### Task 8: Parallel recursive PE role-closure oracle

Files:

- Create `tools/zig/pe_closure.zig`
- Create `native/zig/tests/pe_closure_test.zig`
- Modify `build.zig`, `build.zig.zon`, and `.github/workflows/zig.yml`

- [x] Step 1: Define a fixture-driven recursive role manifest for UI,
  PdfWorker, and ScienceWorker, with exact image paths, module/import/resource
  lists, depth bounds, and reuse of the offline PE parser.
- [x] Step 2: Reject missing/extra/duplicate roles, path traversal, malformed
  PE input, unexpected metadata, case-insensitive Scintilla/PDFium/Lexilla
  cross-role edges, and excessive traversal depth.
- [x] Step 3: Run the host runtime oracle on Windows and compile-only target
  checks on Linux across Debug/ReleaseSafe/ReleaseFast.
- [ ] Step 4: Do not treat fixture manifests as shipped-image evidence: a
  future product lane must inventory every emitted UI/worker PE recursively,
  authenticate the inventory, and prove the release payload closure.

### Task 9: Parallel Scintilla lifecycle contract oracle

Files:

- Create `tools/zig/scintilla_runtime_contract.zig`
- Create `native/zig/tests/scintilla_runtime_contract_test.zig`
- Modify `build.zig`, `build.zig.zon`, and `.github/workflows/zig.yml`

- [x] Step 1: Define the Windows lifecycle facts required by the future native
  probe: class registration, direct API resolution, document creation, null
  lexer selection, style notification, and batched style application.
- [x] Step 2: Return an explicit missing-event result and an explicit Linux
  not-in-scope result; do not claim that an HWND/document/notification was
  observed from this pure contract module.
- [x] Step 3: Run host runtime tests on Windows and compile-only checks on
  Linux across all three optimization modes.
- [x] Step 4: Add the real Windows native probe in an authorized parallel
  slice, including HWND/document/style lifetime evidence. The bounded probe
  intentionally does not claim UI Automation behavior.
- [ ] Step 5: Add UIA-visible behavior evidence and connect the probe to the
  product's actual editor surface; the current native probe remains a
  test-only Scintilla lifecycle gate.

### Task 10: Parallel-slice integration and review gate

- [x] Step 1: Keep runtime artifacts host-targeted and target checks
  compile-only; select aggregate runtime only when both host and target are
  Windows; wire all three new gates into `t0-2b-static` and both CI matrices.
- [x] Step 2: Run the combined Windows ReleaseSafe and Linux ReleaseSafe
  aggregates, formatting, workflow parsing, and whitespace checks.
- [x] Step 3: Obtain one independent clean review pass for this parallel
  scope. The first review found 3 High and 2 Medium findings; all were
  repaired, affected modes rerun, and the fresh independent review is CLEAN
  (`1/1`) with no Critical/High/Medium finding remaining.
- [x] Step 4: Commit/push this bounded slice separately as
  `b78f5783` (`test(zig): parallelize T0.2b admission oracles`) to
  `origin/main`. Full T0.2b remains **NOT ADMITTED** until Tasks 6–9's
  deferred external evidence exists; T0.2a stays paused and T0.2c stays
  unopened.

### Task 11: Parallel shipped-image inventory and native Scintilla probe

Files:

- Create `tools/zig/shipped_pe_inventory.zig`
- Create `native/zig/tests/shipped_pe_inventory_test.zig`
- Create `tools/zig/scintilla_native_probe.zig`
- Create `native/zig/tests/scintilla_native_probe_test.zig`
- Modify `native/zig/tests/source_inventory_test.zig`, `tools/zig/scintilla_probe.zig`,
  `build.zig`, `build.zig.zon`, `.github/workflows/zig.yml`, and the T0.2b
  evidence log

- [x] Step 1: Add an authenticated, caller-supplied Windows payload oracle.
  Bind exactly the UI, PdfWorker, and ScienceWorker roles to canonical image
  paths; reject unauthenticated or digest-mismatched manifests, traversal,
  duplicate/extra/missing images, malformed/cross-role PE imports, reparse
  entries, and depth/file/byte-limit violations. Return a deterministic
  sorted inventory digest. Linux is compile-only and explicitly returns
  `WindowsRuntimeOnly`.
- [x] Step 2: Add a real x86_64 Windows-MSVC Scintilla probe. Register the
  parent and Scintilla classes, create/destroy HWNDs, resolve direct API and
  document lifetime, select `SCI_SETILEXER(NULL)`/`SCLEX_CONTAINER`, observe
  `SCN_STYLENEEDED`, and verify batched style application. The probe is
  target-aware: on a Windows host it runs the selected MSVC target; elsewhere
  it is compile-only. It does not claim UI Automation evidence.
- [x] Step 3: Wire named runtime/check steps and all Debug/ReleaseSafe/
  ReleaseFast Windows/Linux matrix entries; keep the inventory and native
  Scintilla archive outside install/product/worker edges. Use SDK discovery
  for the MSVC/Windows library paths; do not hardcode developer-machine
  paths.
- [x] Step 4: Verify focused modes, final Windows/Linux aggregates, formatting,
  YAML parsing, and diff whitespace. The local Windows host produced
  `6/8 + 2 skips` for the PE inventory and `7/8 + 1 skip` for the native
  Scintilla probe in each runtime optimization mode; Linux checks remained
  compile-only.
- [x] Step 5: Obtain one fresh independent read-only review after integration;
  no Critical/High/Medium finding remains. Commit/push this slice as its own
  commit (`2dd0bdf9`, `test(zig): add shipped PE and native Scintilla gates`).
  Full T0.2b remains **NOT ADMITTED**: the authenticated
  inventory is not yet connected to the product's emitted payload, UIA proof
  is absent, and the independent PDFium/sealed-runner/reproducibility,
  worker-runtime, and advisory gates remain open.
