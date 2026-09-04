# Oleafly T0.1 Toolchain Evidence

## Identity

- Source snapshot commit: `e5d71a398edbf0a853d15f6c06a35e70b985b9ba`.
- Source snapshot tree: `4a003826e5ecdf729e0be8122d09332e181a4042`.
- Pre-implementation parent commit: `d45e26ef7b2279ff211c9daa087bc9f6ca5cdcd1`.
- T0.1 was delivered as focused commits for contracts, build graph, runtime/ABI,
  developer hygiene, CI, and the Windows line-ending correction; the source
  snapshot above is the reviewed aggregate tree.
- Toolchain manifest: `tools/zig/toolchain.json`.
- Zig version: `0.16.0`.
- Local verification host: `DESKTOP-52Q391S`, Microsoft Windows 11 Pro
  10.0.26200, 64-bit; native target `x86_64-windows-msvc`.
- Windows archive SHA-256:
  `68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e`;
  local byte-size and SHA-256 verification passed, and both accepted remote
  runs repeated the manifest bootstrap check.
- Linux archive SHA-256:
  `70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00`;
  both accepted Ubuntu runners passed strict size and `sha256sum` verification.
- Remote Run A: `33825541019`,
  <https://github.com/ndak79/Oleafly/actions/runs/33825541019>, source
  `e5d71a398edbf0a853d15f6c06a35e70b985b9ba`; `Zig T0.1 (Windows x64)`
  and `Zig T0.1 (Linux x64)` both concluded `success`.
- Remote Run B: `33825809417`,
  <https://github.com/ndak79/Oleafly/actions/runs/33825809417>, source
  `e5d71a398edbf0a853d15f6c06a35e70b985b9ba`; `Zig T0.1 (Windows x64)`
  and `Zig T0.1 (Linux x64)` both concluded `success`.
- Rejected pre-streak run: `33825017735` failed on Windows CRLF formatting and
  was not counted. Finding `T0.1-F01` below records its closure.
- Provenance correction: the first evidence commit
  `00965f7adb1f795ab98ac9183ed40b10b00acc9b` incorrectly labelled its own tree
  `b4a80b042ff5df0d4a7e707fccc0036ed1ac8d1c` as `Reviewed-Tree`. The source
  tree is the value above, independently resolved with
  `git rev-parse e5d71a398edbf0a853d15f6c06a35e70b985b9ba^{tree}`. Finding `T0.1-F02`
  records the correction and streak reset.

## Matrix

| Pass | Host/target | Process/cache state | Result |
| --- | --- | --- | --- |
| A | Local Windows 11 / `x86_64-windows-msvc`, local Linux cross-target, remote Windows Server 2022 and Ubuntu 24.04 native runners | Fresh processes plus distinct install/local/global cache roots for reproducibility | Local format/fetch/C11/header checks, Debug/Safe/Fast tests, smoke run, and both cross-builds passed; accepted remote Run A had exactly two successful jobs. |
| B | Local Linux cross-target first, then Windows Fast before Safe/Debug; remote Windows Server 2022 and Ubuntu 24.04 native runners | New processes and new disposable install/local/global cache roots; failed attempts excluded from the streak | Changed-order local checks and three subsequent exact-order stress sequences passed; accepted remote Run B had exactly two successful jobs. |

## Direct outputs

- `zig build -Doptimize=Debug test`: `9/9 steps succeeded; 6/6 tests passed`
  on both accepted native runners and the local Windows lane.
- `zig build --release=safe test`: `9/9 steps succeeded; 6/6 tests passed`
  on both accepted native runners and the local Windows lane.
- `zig build abi` in `--release=safe` and `--release=fast`: each invocation
  reported `5/5 steps succeeded; 1/1 tests passed` on Windows and Linux.
- `zig build miscompile-corpus` in `--release=safe` and `--release=fast`: each
  invocation reported `3/3 steps succeeded; 3/3 tests passed` on Windows and
  Linux.
- `zig build simd-corpus` in `--release=safe` and `--release=fast`: each
  invocation reported `3/3 steps succeeded; 2/2 tests passed` on Windows and
  Linux.
- Header and C ABI: `zig translate-c` contained
  `oleafly_abi_get_version` and `oleafly_abi_version_t`; the C11 layout fixture
  compiled for both `x86_64-windows-msvc` and `x86_64-linux-gnu`.
- Native executable output on Windows and Linux:
  `oleafly-t0.1 toolchain ok` (exact combined-stream assertion).
- Windows ReleaseSafe hash A:
  `38aae9904324c0f1fbdda57a4ac1c2b52721a5ef1ca52a80dd12ed54273e0cad`.
- Windows ReleaseSafe hash B:
  `38aae9904324c0f1fbdda57a4ac1c2b52721a5ef1ca52a80dd12ed54273e0cad`;
  equality passed with different local and global cache roots.
- Linux ReleaseSafe hash A:
  `e85a6328a802bf05743edc8047ad68500e5c7efe6146cd1f8c66ace229b731ca`.
- Linux ReleaseSafe hash B:
  `e85a6328a802bf05743edc8047ad68500e5c7efe6146cd1f8c66ace229b731ca`;
  equality passed with different local and global cache roots.

## Five-pass review

- Oracle: every T0.1 acceptance row has a direct failing oracle. Compiler and
  archive identity, empty dependencies, format, ABI layout/calls, known
  answers, native execution, deterministic hashes, legacy isolation, scope,
  browser boundary, and performance-boundary honesty were each checked.
- Portfolio: Debug, ReleaseSafe, ReleaseFast, Windows, Linux, the static
  library, independent extern declarations, header translation, C static
  assertions, FNV, overflow, and portable SIMD lanes are represented. Local
  Linux execution was unavailable on the Windows workstation, but two Ubuntu
  runners supplied native Linux evidence.
- Adversarial: null ABI output returned `-1`; `-7 + 3` returned `-4`;
  `maxInt(i64) + 1` wrapped to `minInt(i64)`; empty and `00 FF` byte inputs
  matched independent FNV answers; SIMD lanes were `{14, 21, 30, 41}` with
  reduction `106`; every optimizer lane passed.
- Falsification: changing the `abc` FNV answer made one of three tests fail;
  changing the first SIMD expected lane made one of two tests fail; changing
  the C `minor` offset from 4 to 5 produced a static-assert diagnostic showing
  `4 == 5`. All mutations were confined to a disposable clone; the source
  repository remained clean.
- Reality: both native runners executed the actual ReleaseSafe binary and
  asserted the exact smoke line. Two distinct-cache builds per OS produced
  identical OS-specific SHA-256 hashes in each accepted run.
- UI/browser: not applicable to this no-UI slice. T0.1 creates no window,
  renderer, browser surface, or native UI harness; the first UI slice must add
  black-box browser/native interaction evidence.

## Findings and closure

- Medium-or-higher findings: `T0.1-F01` (Medium) exposed CRLF-normalized Zig
  files on a Windows checkout, making `zig fmt --check` fail in rejected run
  `33825017735`. Commit `e5d71a398edbf0a853d15f6c06a35e70b985b9ba`
  added LF attributes for `*.zig`, `*.zon`, and the toolchain manifest and made
  `.gitattributes` a workflow trigger. A fresh `core.autocrlf=true` clone, local
  formatter replay, and accepted Runs A/B all passed. The finding is closed;
  no product-code Medium-or-higher finding remains open.
- `T0.1-F02` (Medium) exposed incorrect provenance in the first evidence
  commit: `Reviewed-Tree` named that evidence commit's tree rather than the
  reviewed source tree, and blank lines separated its message fields so Git
  parsed only the last field as a canonical trailer. This revision records the
  actual source tree, uses one contiguous trailer block, and resets the quality
  streak. The original Runs A/B remain valid source-build evidence but do not
  count toward the renewed post-finding streak. Two new remote runs are required
  before T0.1 can close.
- Flakes or unexplained skips: one local changed-order attempt reported a
  transient Zig standard-library read error,
  `crypto/aes_ocb.zig: unable to load: Unexpected`, during Debug compilation.
  That process was excluded from the streak. The file and all 552 standard
  library files matched a second verified extraction byte-for-byte; three
  fresh exact-order stress sequences and both accepted native CI runs passed.
  No accepted CI run contained a flake or unexplained skip. The single local
  process remains an explicitly unverified environmental observation, not a
  product-pass claim.
- Explicitly unverified items: native Linux execution on the local Windows
  workstation; T0.2 native-window feasibility; startup, working-set, energy,
  presentation, and application performance budgets; all later editor,
  research, AI, quality, versioning, publishing, and UI behavior.
- Browser/UI QA: not applicable to T0.1 by explicit scope; no browser-visible
  surface exists.
- Quality streak: reset to 0/2 after `T0.1-F02`; post-correction remote reruns
  are intentionally pending.
