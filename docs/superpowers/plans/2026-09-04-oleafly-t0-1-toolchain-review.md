# Oleafly T0.1 Plan Review

## Review identity

| Field | Value |
| --- | --- |
| Reviewed plan | `docs/superpowers/plans/2026-09-04-oleafly-t0-1-toolchain.md` |
| Plan SHA-256 at review close | `5fc851a4d97df518f94b95c04f7446841da8b47f7468861cb977e7da0e833cb3` |
| Parent repository commit | `d45e26ef7b2279ff211c9daa087bc9f6ca5cdcd1` |
| Implementation state | No T0.1 source, build graph, workflow, or dependency has been added to the repository |
| Gate result | Ready to commit/push the plan, then execute T0.1; no open Medium+ plan finding |

## Adversarial review rounds

| Round | Focus and fresh evidence | Finding | Closure and result |
| --- | --- | --- | --- |
| 1 | Zig 0.16 build-system/API compile probe; `zig build -h`, `--list-steps`, Debug/Safe/Fast verbose invocations | Initial `-Doptimize=...` commands were invalid with `preferred_optimize_mode`, and the apparent Fast lane compiled Safe | Replaced the preferred helper with an explicit `OptimizeMode` resolver; `-Doptimize=Debug`, `--release=safe`, and `--release=fast` now produce the named modes. Closed. |
| 2 | Independent FNV calculation and ABI edge inspection; direct test compilation | The `00 FF` expected value was wrong; signed `i64` addition lacked overflow semantics; Zig layout offsets were not asserted | Corrected the constant to `590474061099445088`, changed the ABI operation to `+%`, added `maxInt + 1 -> minInt`, and added three `@offsetOf` assertions. Closed. |
| 3 | Two clean Windows ReleaseSafe builds with different prefixes/caches and byte-level PE diff | Executable hashes differed in PE/PDB metadata (timestamp and identifiers) despite identical source | Release executables are stripped while Debug retains symbols; fresh builds now produce identical `38aae9904324c0f1fbdda57a4ac1c2b52721a5ef1ca52a80dd12ed54273e0cad` hashes. Closed. |
| 4 | Traceability against the approved spec's T0 kill-switch table | Plan omitted the required SIMD corpus | Added portable `@Vector(4, u32)` lane arithmetic, comptime/runtime parity, `simd-corpus` build step, Debug/Safe/Fast CI coverage, and falsification. Closed. |
| 5 | CI YAML parse, shell/error semantics, archive bootstrap threat model, and target pin review | PowerShell native non-zero exits were not guaranteed to stop a step; archive root/path and translated-header content were under-asserted; checkout credentials were unnecessary | Added `$PSNativeCommandUseErrorActionPreference = $true`, exact URL/root/allowlisted-target checks, translation symbol assertions, explicit C targets, and `persist-credentials: false`. YAML parses with symmetric path triggers and two pinned checkout uses. Closed. |
| 6 | Evidence/commit ordering and remote-run state machine review | Requiring remote Linux proof before a commit that contains its evidence was circular; a one-shot second-run lookup could race | Split source and evidence commits; source pushes first, two fresh successful native workflow runs are mandatory, Run B is polled and both job conclusions are checked, then evidence is committed/pushed. Closed. |
| 7 | Scope, browser, performance, and migration-boundary review | A no-UI toolchain slice could be mistaken for completed browser/performance proof | Added explicit Browser/UI-N/A and performance-boundary acceptance rows, with T0.2/native UI/performance budgets explicitly unverified and never counted as complete. Closed. |

## Final closed-coverage passes

| Pass | Fresh state/order | Direct result |
| --- | --- | --- |
| A | New process, new Windows caches/prefixes; format/fetch/translation/C11 checks; Debug → Safe → ABI/FNV/SIMD Fast; Windows native run; Linux x64 cross-build | All commands passed; Windows runtime `oleafly-t0.1 toolchain ok`; Windows hash `38aae9904324c0f1fbdda57a4ac1c2b52721a5ef1ca52a80dd12ed54273e0cad`; Linux cross hash `e85a6328a802bf05743edc8047ad68500e5c7efe6146cd1f8c66ace229b731ca`. |
| B | Fresh process, fresh caches/prefixes; Linux cross-build first; Fast ABI/FNV/SIMD before Safe/Debug tests; translation/C11 recheck; Windows native run | All commands passed; the same Windows and Linux cross hashes were reproduced; runtime line was exact. |

## Falsification results

- Mutating the `abc` FNV expected constant made `zig build -Doptimize=Debug miscompile-corpus` exit 1 with an explicit expected/actual mismatch; the committed value was restored.
- Mutating the C `minor` field offset from 4 to 5 made `zig cc -target x86_64-windows-msvc -std=c11 -c ...` exit 1 with a static-assertion diagnostic; the committed value was restored.
- The SIMD corpus was independently run in direct Debug, ReleaseSafe, and ReleaseFast modes; all two tests passed in each mode.

## Open items intentionally outside this plan

- Native GitHub Actions Windows/Linux execution and the required two-run quality streak occur only after the source commit is pushed; the plan refuses to claim completion before both runs are green.
- Browser/UI QA is not applicable because T0.1 creates no UI surface; it is a hard requirement for the first UI slice.
- Reference-machine freeze, startup/working-set/energy/presentation budgets, and all T0.2+ application behavior remain explicitly unverified.

## Decision

The plan has no unresolved Medium-or-higher bugs or gaps after the seven adversarial rounds and two clean closed-coverage passes. Commit/push this plan and begin implementation with the executing-plans workflow; do not claim T0.1 complete until the source commit, two remote green runs, and evidence-only commit all exist.
