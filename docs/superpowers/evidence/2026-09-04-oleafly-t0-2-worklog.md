# TExFlow T0.2 Worklog

This tracked file is an append-only operational log for the sequential T0.2
slices. The `oleafly` segment in its filename is a historical repository
locator; the product and new native graph are named TExFlow. Entries distinguish
observed evidence from claims that remain unverified. Raw and generated evidence
stays in ignored local output directories or approved durable stores; this log
records digests and locations rather than embedding binary output.

## T0.2a: lock and acquire native sources safely

### Interim observed command evidence

The active T0.2a implementation lane reported the first three build results
from the current working tree on 2026-09-04; this documentation slice did not
retain a separate raw transcript for them. The remaining manifest and ignore
checks were run directly in this slice. All rows are observed command summaries,
not final acceptance or a clean-streak pass.

| Command | Observed result | Interpretation |
| --- | --- | --- |
| `zig build deps-fetch --summary all` | Exit 0; `7/7` summary; every ordinary locked artifact reported acquired. | The explicit ordinary acquisition path completed and activated verified local cache entries. It does not prove later replay was network-isolated. |
| `zig build deps-test --summary all` | Exit 0; `54/54` tests passed. | The current portable lock, fetcher, archive-security, Unicode-generator, and attestation test portfolio passed this run. |
| `zig build deps-audit --summary all` | Exit 0; `15/15` summary. The PDFium bundle contained 45 subjects and exactly 1 matched the locked archive. The external verifier reported GitHub CLI 2.100.0. | The current cache, Unicode inputs, committed bundle/root, and locked external verifier passed the aggregate audit. The verifier's fail-fast proxy configuration is not detached-NIC evidence. |
| `tools/zig/.cache/toolchain-0.16.0/zig.exe build --help` after renaming the package to `.texflow` | Initial exit 1 rejected the legacy fingerprint and supplied `0x675417cd87a146a4` as the required fingerprint for the renamed package. | The manifest fingerprint is part of package identity. The tool-derived replacement was applied; this failed probe is not a product-test failure and does not count toward a streak. |
| Fresh pinned-Zig `build --help` rerun with `.texflow` and fingerprint `0x675417cd87a146a4` | Exit 0; the build graph listed `deps-fetch`, `deps-test`, `unicode-audit`, and `deps-audit`. | The renamed package manifest and its source-path allowlist parse successfully under Zig 0.16.0. |
| Pinned-Zig `build --fetch=all` and a manifest path scan | Exit 0; all 17 declared paths existed and zero declared paths named a dependency cache, Zig cache, install output, or raw/generated evidence directory. | The source package includes the current T0.2a tools, tests, lock, attestations, and developer/ADR inputs without admitting generated caches. |
| `git check-ignore -v` plus `git ls-files` for local T0.2a outputs | Exit 0; `/.superpowers/`, `tools/zig/.cache/`, and the generated/raw evidence directories matched ignore rules; no file below those probes was tracked. | Local agent state, dependency/cache payloads, and raw/generated evidence stay outside the tracked source set. |

`deps-audit` includes the Unicode audit dependency in this aggregate run. A
separate standalone `zig build unicode-audit --summary all` transcript has not
yet been recorded here.

### Claims and limitations

- `deps-fetch` is the sole ordinary dependency-download step. Normal build,
  test, `deps-test`, `unicode-audit`, and `deps-audit` paths are required to use
  only locked tracked inputs and owner-only local caches. The separately gated
  PDFium reconstruction lane is exceptional and outside T0.2a's ordinary path.
- The cached `gh.exe` 2.100.0, committed PDFium bundle, and committed dated
  trusted root are verified as exact locked inputs before and after the
  external `gh attestation verify` process. The audit uses explicit paths and a
  scrubbed empty profile rather than `PATH`, user configuration, credentials,
  or an ambient trust cache.
- The PDFium attestation proves that the locked archive digest was emitted by
  the named community GitHub workflow and builder commit. It does not prove an
  independent source reconstruction from the official PDFium commit. The
  contained community DLL is unsigned reference evidence, not an admitted or
  shipping TExFlow runtime. Other unsigned upstream archives likewise have
  integrity/inventory locks, not blanket publisher authentication.
- Build-generated Unicode tables and receipts, downloaded archives, extracted
  dependency payloads, test/audit executables, and raw evidence are cache-only.
  They are ignored and must not be committed or included in a product package.

### Explicitly unverified and incomplete evidence

- No authorized sealed Windows VM with its virtual NIC detached, and no
  authorized Linux container/network namespace with network mode `none`, has a
  recorded isolation receipt for this run. Status:
  `UNVERIFIED-NETWORK-ISOLATION`.
- The `network=proxy-denied` verifier result demonstrates scrubbed environment
  and fail-fast proxy settings only. It does not prove the host lacked another
  usable route and is not an offline-pass claim.
- The standalone `unicode-audit` summary/exit-code transcript, fresh-profile
  and cache identities, a dedicated real-filesystem read-only-cache receipt,
  raw-log locations and digests, final source commit and tree, remote CI
  run/job IDs, and durable evidence-copy receipts are not yet recorded.
- No final closed-coverage review or post-repair quality streak has been
  completed. The three command results above are interim only and count as zero
  final streak passes.
- PDFium independent source reconstruction, admitted-runtime equivalence, and
  protected signed shipping qualification belong to later gates and remain
  unverified by T0.2a.

### Findings and streak state

- Package-identity transition: pinned Zig 0.16.0 correctly rejected the legacy
  `.oleafly` fingerprint after the `.texflow` rename. The manifest now uses the
  exact replacement fingerprint emitted by the pinned tool. A successful
  validation rerun is required before this entry is closed.
- Package-identity transition closure: the immediate pinned-Zig rerun exited 0;
  this manifest-only finding is closed and does not create a streak pass.
- Medium-or-higher findings: final review not yet performed; no closure claim.
- Retries/flakes: no raw transcript was provided to this documentation slice,
  so retry and flake status remains unverified rather than inferred from the
  passing summaries.
- Interim streak state: `0` final closed-coverage passes.

## T0.2a final closure evidence (2026-09-05)

The final QA pass deliberately exercised the two portability defects found
during review before closure. First, the GitHub CLI timestamp parser rejected
the same Sigstore instant on non-Bangkok hosts; the parser now accepts only a
strict whole-second RFC3339 value (`Z` or a known `+/-HH:MM` offset), converts it
to UTC, and compares it with the locked bundle `integratedTime`. Second, the
attestation preflight treated the entire `%TEMP%` parent as overlapping a
generated cache descendant; it now canonicalizes the random profile candidate
(`parent + validated basename`) and checks that candidate against each locked
input, preserving true overlap and collision rejection while allowing a sibling
cache under `%TEMP%`.

| Command / review | Observed result | Interpretation |
| --- | --- | --- |
| `zig build -j1 deps-test --summary all` | Exit 0; `18/18` steps; `149/149` tests passed. | Final dependency lock, parser, archive, Unicode, ACL, cache, and process-integration portfolio is green. |
| `zig build -j1 deps-fetch-integration-test --summary all` | Exit 0; `5/5` steps; `19/19` tests passed. | Crash/recovery, cache publication, ACL, transport, bounded-resource, and fixture process scenarios passed. |
| `zig build -j1 test --summary all` | Exit 0; `9/9` steps; `6/6` tests passed. | Existing portable ABI/native smoke tests remain green. |
| `zig build -j1 unicode-audit --summary all` | Exit 0; `12/12` steps; `44/44` tests passed. | Deterministic Unicode generation and audit remain green after the final changes. |
| `zig build -j1 deps-audit --summary all` | Exit 0; `25/25` steps; `45/45` tests passed; `subjects=45 matching=1 cli=2.100.0 negative=10`; `network-isolation=unverified`. | Default-cache audit passed with locked bundle/root, real `gh.exe`, strict metadata, and all negative cases. |
| `zig build -j1 --cache-dir <absolute path under %TEMP%> deps-audit --summary all` | Two consecutive exit-0 runs; each `25/25` steps and `45/45` tests with the same real positive/10-negative attestation result. | Explicit absolute-cache and TEMP-ancestor path contract is now verified. |
| `zig build -j1 --release=safe run --summary all` | Exit 0; `texflow toolchain ok`; `3/3` steps. | TExFlow executable naming and release smoke path are green. |
| `zig fmt --check build.zig build.zig.zon native/zig tools/zig` and `git diff --check` | Exit 0; only Git LF/CRLF normalization notices. | Formatting and whitespace gate is clean. |
| Fresh gpt-6 reviewer pass | No actionable Medium+ findings; quality streak `1`. | Candidate-path overlap, timestamp portability, Windows pinning, ACL/recovery/publication, transport, CI, and TExFlow naming reviewed clean. |

The observed red-to-green regressions were: (1) equivalent UTC timestamp
before the RFC3339 instant fix, and (2) absolute `%TEMP%` cache before the
candidate-path preflight fix. No temporary audit profiles or falsification
files remain. The browser lane is not applicable to this native-only T0.2a
slice; native Windows command evidence is the acceptance oracle here.

### Final limitations

- No authorized detached-NIC Windows VM or network-namespace `none` run was
  available, so network isolation remains `UNVERIFIED-NETWORK-ISOLATION`.
- Remote GitHub Actions job IDs and a fresh-clone receipt are not yet recorded
  in this worklog; those are post-commit/repository-delivery checks.
- PDFium source reconstruction, admitted runtime equivalence, and signed
  shipping qualification remain later T0.2/T1 gates.

### Final streak state

- Medium-or-higher findings in the final review: none.
- Retries/flakes: no failed retry was promoted to evidence; all final commands
  listed above completed successfully.
- Closed-coverage quality streak: `1` (the user-selected streak policy).

## Post-commit delivery evidence (2026-09-05)

The pushed commit was checked from a new local clone at
`C:\\Users\\Ba Gau\\AppData\\Local\\Temp\\TExFlow-fresh-clone-20260905-115216-final2`.
The clone resolved to commit `11d2205d`; with the host's `core.autocrlf=true`,
the exact trusted-root evidence remained binary/CRLF and the development guide
remained LF as required by their contracts.

| Fresh-clone command | Observed result |
| --- | --- |
| `zig build -j1 deps-test --summary all` | Exit 0; `18/18` steps; `149/149` tests passed. |
| `zig build -j1 test --summary all` | Exit 0; `9/9` steps; `6/6` tests passed. |
| `zig build -j1 --release=safe run --summary all` | Exit 0; `texflow toolchain ok`; `3/3` steps. |
| `git ls-remote origin refs/heads/main` | Remote resolves `refs/heads/main` to `11d2205d8c41d7004df9eaf2c1defab86634aeed`. |

The fresh clone intentionally did not run cache-only `unicode-audit` or
`deps-audit`: the native dependency cache is ignored and must first be seeded
through the authorized `deps-fetch` lane. Those audits were run successfully in
the verified workspace, including the absolute `%TEMP%` cache case above.

## T0.2b bounded argv/API slice evidence (2026-09-05)

This is an incremental, separately reviewable slice of T0.2b; it does not close
the Task 2 acceptance rows. It adds one Zig-owned `CreateProcessW` launch-buffer
serializer, a declarative 16-namespace Windows API inventory, and a native child
oracle that checks Windows' `CommandLineToArgvW`, explicit environment, and
current-directory behavior. No zigwin32 bindings, SDK layout admission, PDFium
loading, package probe, or reconstruction controller is claimed here.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED (initial serializer stub) | `t0-2b-argv-test`: `0/7` passed | Contract tests detect the missing implementation. |
| TDD GREEN (before review repair) | `t0-2b-argv-test`: `13/13` passed | Serializer, path rejection, native-child seam, and allocation cleanup were green. |
| Review repair RED | `t0-2b-argv-test`: `14/16` passed; `Z`/`_` and punctuation-order regressions failed | The reviewer exposed a real Windows environment-block ordering defect. |
| Review repair GREEN | `t0-2b-argv-test`: `16/16` passed | ASCII-uppercase ordinal comparator, prefixes, punctuation, and duplicate names are covered. |
| Debug regression | `t0-2b-argv-test test -Doptimize=Debug`: `22/22` passed | Existing ABI, corpus, and SIMD tests remain green. |
| ReleaseFast regression | `t0-2b-argv-test -Doptimize=ReleaseFast`: `16/16` passed | Optimized launch contract remains green. |
| Cross-target portability | `t0-2b-argv-check -Dtarget=x86_64-linux-gnu`: compiled successfully | Linux compilation is covered; Linux execution is intentionally not claimed. |
| Formatting | `zig fmt --check` and `git diff --check` | Clean. |
| Independent gpt-6 reviewer, final pass | No Medium+ findings; quality streak `1` | The ordering finding was fixed and re-reviewed clean. |

The serializer rejects missing/non-absolute or unsafe application paths,
embedded NUL/invalid UTF-8, UTF-16/command-line overflow, shell/device names,
ambiguous environment names, and inherited environment state. Canonical file
identity and existence remain the caller's responsibility. The native child
test is Windows-only; the Linux lane is compile-only.

## T0.2b bounded PDFium ABI/static slice evidence (2026-09-05)

This increment adds a declarative, Zig-owned public-C table for the locked
PDFium root commit. It is deliberately static-only: no DLL is linked, loaded,
executed, or compared here. The table admits 35 stable exports for lifecycle,
memory-backed loading, page geometry, external bitmap/progressive rendering,
text/search, and inert link rectangles. Active form-fill/JavaScript/XFA/file
callbacks and unreviewed experimental APIs remain absent.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | With the table absent, six of seven focused tests failed; the static guard test passed. | Tests detect missing declarations before implementation. |
| ReleaseSafe | `t0-2b-pdfium-abi`: `7/7` passed. | Layout, widths, signatures, symbol bijection, and active-content exclusions are green. |
| Debug | `t0-2b-pdfium-abi -Doptimize=Debug`: `7/7` passed. | Debug ABI/static regression is green. |
| ReleaseFast | `t0-2b-pdfium-abi -Doptimize=ReleaseFast`: `7/7` passed. | Optimized static contract remains green. |
| Linux portability | `t0-2b-pdfium-static -Dtarget=x86_64-linux-gnu`: `4/4` compile-only steps passed. | Cross-target declaration portability is covered; Linux execution is not claimed. |
| Falsification | Mutating `FPDFBitmap_FillRect` to `void` and duplicating an allowlist entry both failed tests. | Signature and exact-symbol oracles detect representative drift. |
| Static source guard | Import, `@cImport`, `@extern`, `extern fn`, function-body, mutable-state, and call-expression fixtures were rejected. | No executable/loader path is admitted by the module contract. |
| Combined regression | `t0-2b-argv-test test -Doptimize=ReleaseSafe`: `22/22` passed. | Earlier Windows launch-boundary slice and legacy tests remain green. |
| Independent gpt-6 reviewer, final pass | No Medium+ findings; quality streak `1`. | Header comparison, LLP64 widths, config v6 layout, C pause callback, and build wiring reviewed clean. |

The ABI source was manually matched against the cached public headers for
PDFium commit `6f2272e1f3aaa141305475b83ef4eac2c1f527b8` (generation
`g-9ad8e1bb88ea1c84316a43a9`). An independent C compiler layout probe was not
available in this environment and is intentionally not implied by the green
Zig tests. The slice does not close full T0.2b acceptance, PDFium source
reconstruction, binary equivalence, authenticated worker loading, or Task 5
runtime qualification.

## T0.2b bounded deterministic package-oracle slice evidence (2026-09-05)

This increment adds a pure-Zig, in-memory fixture oracle for the eventual
release payload archive. It is not an installer, MSIX, runtime inventory, or
product-size result. The oracle writes a canonical POSIX-ustar stream and
deterministic gzip level 9 bytes, and binds the exact sorted path/byte manifest
to SHA-256 receipts.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `t0-2b-package-test`: `14/14` failed against the empty module/missing source allowlist. | Tests detect absent implementation and package inclusion. |
| ReleaseSafe GREEN | `t0-2b-package-test`: `20/20` passed. | Canonical tar/gzip, path safety, receipts, round-trip and ownership contracts are green. |
| Debug | `t0-2b-package-test -Doptimize=Debug`: `20/20` passed. | Debug regression is green. |
| ReleaseFast | `t0-2b-package-test -Doptimize=ReleaseFast`: `20/20` passed. | Optimized oracle remains deterministic. |
| Linux portability | `t0-2b-package-check -Dtarget=x86_64-linux-gnu`: `3/3` compile-only steps passed. | Cross-target compilation is covered; Linux execution is not claimed. |
| Falsification | Tar header/metadata/padding/end-marker mutations, gzip header/body/footer/truncation/concatenation, changed payload, unsafe path, duplicate/conflict, nonregular file, and allocation-failure cases were rejected. | Representative negative paths fail closed. |
| Windows path hardening | COM/PRN/AUX/NUL/CONIN$/CONOUT$, COM/LPT ASCII and superscript aliases, extensions/nested components, ASCII/Unicode case aliases, and folded file-directory ancestors are rejected. | No known Windows path collision remains in this fixture scope. |
| Independent gpt-6 reviewer, final pass | No Medium+ findings; quality streak `1`. | Tar/gzip/hash/ownership/OOM and Windows collision review clean. |

The oracle deliberately does not claim the real release-payload inventory,
90/30 MiB gates, filesystem-root isolation, installer packaging, or signed
shipping evidence. Those remain later T0.2b/T0.2h gates.
