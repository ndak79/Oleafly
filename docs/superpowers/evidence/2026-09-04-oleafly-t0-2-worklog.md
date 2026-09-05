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

## T0.2b bounded SQLite amalgamation contract evidence (2026-09-05)

This increment is an isolated, unshipped SQLite 3.53.4 contract. It adds a
narrow Zig-owned C ABI, an offline source snapshotter, and a static archive
symbol oracle; it does not integrate a ledger/search connection, set Task 6
limits, or admit SQLite into a worker image. The exact locked `sqlite3.c` and
`sqlite3.h` bytes are hashed before being copied into an immutable `payload`
directory. Compilation consumes only that published pair.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED (missing contract) | Initial focused suite failed `0/8`. | Source locks, ABI, runtime, FTS5, allocator, and symbol tests detect the absent contract. |
| Flag-compatibility repair | The exact plan flags exposed a 3.53.4 compile-time constraint: `SQLITE_MAX_SQL_LENGTH` must not exceed `SQLITE_MAX_LENGTH`. | The required `SQLITE_MAX_SQL_LENGTH=6291456` compatibility define is locked and independently asserted; it does not weaken the plan's 6-MiB SQL/length bound. |
| Symbol-oracle repair | Initial audit falsely classified `sqlite3_soft_heap_limit(int)` as omitted; the upstream build retains it, as well as three static auto-extension registry symbols. | Four retained upstream symbols are required in the archive but absent from the Zig surface; eleven genuinely prohibited symbols are required absent. |
| Review RED: nullable callback | Callback ABI regression failed `10/11` before the fix. | `empty_result_callbacks=ON` can pass `azVals=NULL`; the corrected nullable many-pointer ABI distinguishes that from a SQL NULL element. |
| Review RED: mutable snapshot race | A locked-reader regression reproduced `FileBusy` against the old truncating writer. | Concurrent builds could have read or held the shared source while another invocation rewrote it. |
| Review GREEN: immutable publication | Locked-reader, incomplete-payload refusal, and concurrent-publisher tests pass. A unique stage is populated, then published with atomic no-replace rename; an existing complete pair is rehashed and reused. | No compiler-held published member is opened for write, and readers see only a complete verified pair. |
| Windows Debug | `t0-2b-sqlite-test`: `14/14` tests; `9/9` steps. | ABI, runtime, FTS5, hard-heap, source-publication, and archive-symbol checks are green. |
| Windows ReleaseSafe | `t0-2b-sqlite-test`: `14/14` tests; `9/9` steps. | Safe optimized contract is green. |
| Windows ReleaseFast | `t0-2b-sqlite-test`: `14/14` tests; `9/9` steps. | Fast optimized contract is green. |
| Linux portability | `t0-2b-sqlite-check -Dtarget=x86_64-linux-gnu`: `8/8` compile/audit steps. | Cross-target compilation and archive audit are covered; Linux runtime execution is not claimed. |
| Concurrent build reality | Safe, Fast, and Linux checks ran concurrently against the shared snapshot and all completed cleanly. | The previously reproducible shared-output race is closed by immutable publication. |
| Fail-closed source override | Relative `-Dsqlite-source` rejected with `SqliteSourceMustBeAbsolute`; missing absolute source rejected with `FileNotFound`; no fallback/fetch occurred. | Source selection remains explicit and offline. |
| Independent gpt-6 reviewer, final pass | No actionable Medium+ findings; quality streak `1`. | Nullable callback, archive padding, source locks, flags, symbol distinctions, atomic publication, and build graph reviewed clean. |

The archive parser covers native GNU/MSVC first-linker-member tables and the
single NUL padding byte emitted by LLVM's even-sized archive writer. The
contract intentionally keeps SQLite's default allocator/page cache so the
hard-heap limiter accounts for both; connection-scoped limits, WAL policy,
ledger durability, and disposable FTS search semantics belong to Task 6.
No browser QA is applicable to this native/CLI-only slice; browser evidence is
required when the TExFlow UI/HTML evidence lane exists. Linux runtime and
product integration remain unverified and out of scope here.

## T0.2b bounded Scintilla static source/build contract evidence (2026-09-05)

This increment verifies the exact cached Scintilla 5.6.6 source and builds its
upstream Win32 static editor component as an isolated, uninstalled feasibility
artifact. The 39 C++ inputs are the upstream `SRC_OBJS + COMPONENT_OBJS`
inventory from `win32/scintilla.mak`: 33 `src/` units plus six Win32 units.
DLL-only `ScintillaDLL.cxx`/resources, Lexilla, its catalogue, and every worker
or product-install edge are excluded. The source snapshot is rehashed and
published atomically; an existing complete snapshot is reused and corruption
is refused.

The portable contract test and the Windows C++ build are intentionally separate
named steps: `t0-2b-scintilla-test` checks the source/graph contract, while
`t0-2b-scintilla-build` compiles the Win32 static archive. The acceptance
evidence below reports them together where both are required; Linux
`t0-2b-scintilla-check` remains compile-only and never attempts Win32 C++.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED (inventory/flags/path contract) | Three expected missing-contract failures, followed by four archive/snapshot/build-contract failures before implementation. | The tests detect absent source identity, platform inventory, snapshot, and build-graph boundaries. |
| Boundary falsification | Injecting a transitive product edge caused the install/product reachability test to fail (`8/9`); removing it restored `9/9`. | The static library remains uninstalled and unreachable from the baseline product executable. |
| Windows Debug | Combined `t0-2b-scintilla-test` + `t0-2b-scintilla-build`: `9/9` tests and `8/8` steps; actual static archive built. | Exact source snapshot, inventory, flags, and Win32 C++ compilation are green. |
| Windows ReleaseSafe | Same combined lane: `9/9` tests; static archive built. | Safe optimized static contract is green. |
| Windows ReleaseFast | Same combined lane: `9/9` tests; static archive built. | Fast optimized static contract is green. |
| Archive-member audit | Each produced `.lib` contains exactly 39 objects and no `ScintillaDLL`, `ScintRes`, Lexilla, or catalogue member. | The DLL/resource and test-only lexer surfaces are absent from the product-static artifact. |
| Linux portability | `t0-2b-scintilla-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe`: `5/5` compile steps; a Win32 static-build request fails with an explicit target diagnostic. | Contract compilation is portable; Linux runtime and Win32 library execution are not claimed. |
| Source/input negatives | Missing archive is rejected with `FileNotFound`; relative archive/output paths are rejected before touching files; altered archive, extra member, missing source, corruption, duplicate, DLL-only, and wrong-platform paths fail closed. | No fallback, fetch, or silent source substitution exists in this lane. |
| Local compiler/SDK evidence | Actual build used MSVC headers 14.51.36231 and Windows SDK 10.0.26100.0; WRL include is discovered or supplied through an absolute `-Dscintilla-winrt-include` path. | This proves local static feasibility only; the approved SDK/toolchain identity and executable/import closure remain later admission work. |
| Independent gpt-6 reviewer, final pass | No actionable Medium+ findings; quality streak `1`. | Inventory, archive identity, atomic publication, SDK include use, C++ flags, member set, target split, and reachability were reviewed clean. |

All upstream warning flags (`-Wall -Wextra -Wpedantic`) and C++17 are retained;
no TExFlow C++ shim or source/header patch was introduced. The static archive
is not linked into `TExFlow.exe` yet, and the window-class/direct-function,
document lifecycle, null/container lexer, notification, and batched-style
runtime probe remain a later UI/editor slice. No browser QA applies to this
native/CLI-only source/build contract; browser evidence is required once the
real TExFlow UI or HTML evidence lane is implemented.

## T0.2b bounded deterministic notices/source-license contract evidence (2026-09-05)

This increment adds the tracked `native/zig/THIRD_PARTY_NOTICES.txt` generated
from the locked manifest and a Zig renderer/validator for its canonical bytes.
The inventory covers all twelve locked source identities with explicit roles:
product-static (Scintilla, SQLite, zigwin32), build-only generated data
(Unicode), test-only comparator (Lexilla), reference-only PDFium inputs, QA
tools, and the disposable reconstruction tool. Lexilla is present only in the
complete source inventory; no Lexilla component record enters the shipping
notice. The PDFium reference/transitive runtime status is explicitly
`UNVERIFIED` until source reconstruction and runtime closure are admitted.

The fresh-checkout EOL test is deliberately a separate QA-only step because it
uses an external Git executable. The ordinary notices test/check path is
portable and Git-free; checkout QA requires an explicit absolute
`-Dnotices-git-executable` and typed argv.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | Focused notice suite initially failed `0/7`. | Missing renderer, role inventory, legal validator, source-package paths, and canonical notice were detected before implementation. |
| Validator falsification | Temporarily bypassing source-role, canonical-notice, and exact-LICENSE checks produced four expected failures; code was restored. | Representative provenance, byte, and legal-boundary oracles are active. |
| Canonical notice | Native check passes; tracked notice is exactly 9,355 bytes, SHA-256 `7cd60c886c1af4c4a4e6608b9adf1586989aaf15038f73e11422bd378c88f241`. | Renderer output and tracked LF bytes are identical. |
| Inventory/role contract | Windows native notices suite passes `10/10`; all twelve manifest/git-source identities, versions, roles, URLs, license IDs, and digests are checked, including duplicate/missing/unknown/role-confusion mutations. | Source/license provenance is deterministic and cannot silently promote QA/reference/test inputs to shipping runtime. |
| Legal subset | Exact `LICENSE` plus `THIRD_PARTY_NOTICES.txt` accepted; missing, duplicate, extra, altered, and noncanonical files rejected. | The legal pair is bounded and ready for the later complete-payload oracle; it is not itself an installer/package result. |
| EOL regression RED→GREEN | Git fixture initially reported `text/eol unspecified`; after adding the exact `.gitattributes` rule `native/zig/THIRD_PARTY_NOTICES.txt text eol=lf`, checkout with `core.autocrlf=true` reproduces identical bytes and passes canonical validation. | Windows checkout cannot silently convert the byte-exact notice to CRLF. No broad repository renormalization was introduced. |
| Portable build graph | `t0-2b-notices-check` has no checkout-QA dependency and passes without a Git option; Linux `x86_64-linux-gnu` compile-check passes `3/3`. | Default/native compile paths remain offline and independent of ambient Git/PATH. |
| Explicit checkout QA | `t0-2b-notices-checkout-test -Dnotices-git-executable=<absolute git.exe>` passes `1/1` with `core.autocrlf=true`; canonical check and inventory/render CLI runs pass. | Fresh-checkout behavior is directly evidenced only in this separately authorized QA lane. |
| Independent gpt-6 reviewer, final pass | No actionable Medium+ findings; quality streak `1`. | EOL attributes, default graph separation, source package inclusion, license hashes, Lexilla/PDFium roles, and no invented owner were reviewed clean. |

The shipping notice retains the existing Oleafly AGPL source-lineage
attribution and complete Unicode License v3 text. Scintilla and zigwin32
license sections are hash-checked against the pinned cache; SQLite uses the
upstream public-domain blessing. The notice records reference provenance and
license URLs but does not claim a complete installed-payload inventory or
resolved PDFium transitive runtime closure. No browser QA applies to this
native/CLI/license slice; browser evidence remains a UI/HTML-lane requirement.

## T0.2b bounded static PE32+ auditor/fixture slice evidence (2026-09-05)

This increment adds a pure-Zig, offline PE32+ admission oracle and a generated
Windows x64 fixture. The auditor reads bytes only; it never maps, loads,
launches, fetches, signs, or installs an image. The narrow fixture profile
requires an executable AMD64 PE32+ image, canonical adjacent sections, bounded
headers/sections, NX/ASLR/high-entropy mitigations, real DIR64 relocations,
exact `kernel32.dll!ExitProcess` imports, an optional canonical CFG layout, and
the single empty reproducibility marker. Import lookup/IAT/name/descriptor
envelopes and all other audited metadata are protected from relocation writes;
recognized source-path forms are scanned deterministically.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | The initial focused suite failed against the missing auditor/fixture contract; the generated PE artifact was also refused until the source contract existed. | Tests detect missing implementation and missing native fixture evidence before green. |
| Review repair 1 | Independent review found that a DIR64 relocation could target import metadata; conservative per-section metadata envelopes and full eight-byte target checks were added. | The loader-written relocation surface cannot rewrite audited import bytes in this profile. |
| Review repair 2 | Independent review found PE32+ named-thunk reserved-bit handling, IAT/ILT aliasing, section RVA ordering/2-GiB image bound, and IAT overlap with a later DLL name; each finding received a regression oracle and was fixed. | The profile now rejects those malformed/ambiguous layouts instead of admitting them. |
| Windows Debug | `t0-2b-pe-test t0-2b-pe-audit -Doptimize=Debug -j1`: 8/8 steps, 31/31 tests; generated fixture accepted. | Parser, fixture, and CLI are green in debug mode. |
| Windows ReleaseSafe | Same commands with `-Doptimize=ReleaseSafe`: 8/8 steps, 31/31 tests; fixture SHA-256 `95e2740392b70031a54ed6ff314bcae68b850c0e718de67043547071716d2d0d`. | Safe optimized admission and deterministic artifact identity are green. |
| Windows ReleaseFast | `t0-2b-pe-test -Doptimize=ReleaseFast -j1`: 5/5 steps, 31/31 tests. | Fast optimized parser remains green. |
| Linux portability | `t0-2b-pe-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe -j1`: 3/3 compile steps. | Cross-target compilation is covered; Linux execution and Windows runtime are not claimed. |
| Baseline regression | `zig build test -Doptimize=ReleaseSafe -j1`: 9/9 steps, 6/6 tests. | Existing ABI/corpus/SIMD tests remain green. |
| Formatting/diff | `zig fmt --check` and `git diff --check` passed. | Source formatting and patch whitespace are clean. |
| Independent GPT-6 static review, final pass | No Medium+ findings; quality streak `1`. The reviewer inspected bounds, section/directory mapping, imports/IAT, relocations, unwind/CFG handling, reporting, tests, and build integration. | Final read-only review is clean; runtime/product-closure exclusions remain explicit. |

This is intentionally a bounded static slice, not final product PE closure:
it does not enumerate or recursively audit transitive DLLs, verify the shipped
TExFlow executable identity/resources/manifest/certificate/signature, simulate
runtime CFG, admit extended unwind/load-config/debug formats, or prove module
and worker dependency closure. The CLI accepts an explicit path but applies
only the fixture allowlist; broader policies must use the Zig API. Browser QA
is not applicable to this native/CLI-only increment; it remains required for
the future TExFlow UI/HTML/live-render evidence lane.

## T0.2c bounded pure-Zig app-model foundation evidence (2026-09-05)

This increment adds the deterministic, platform-independent model layer for
the eventual TExFlow shell: authenticated UI/PDF/science role identities,
versioned build identity, event/deadline-driven live-render scheduling,
monotonic lifecycle ownership, locked semantic theme/layout tokens, and a
versioned English resource table with pseudo-locale helpers. It is deliberately
kept outside the product/UI graph so the models can be compiled on Windows and
Linux without admitting HWND, COM, graphics, worker binaries, or native
dependency loading.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | Focused model tests initially failed to compile against the absent scheduler, lifecycle, theme, layout, and resource APIs. | The new tests were written before the corresponding implementation and detect missing contracts. |
| Windows Debug | `t0-2c-models-test -Doptimize=Debug -j1`: `22/22` tests passed. | All role, identity, scheduler, lifecycle, palette/layout, and string-resource paths are green. |
| Windows ReleaseSafe | `t0-2c-models-test -Doptimize=ReleaseSafe -j1`: `22/22` tests passed. | Safe optimized model behavior remains deterministic. |
| Windows ReleaseFast | `t0-2c-models-test -Doptimize=ReleaseFast -j1`: `22/22` tests passed. | Fast optimized model behavior remains deterministic. |
| Linux portability | `t0-2c-models-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe -j1`: `7/7` compile steps passed. | The pure models have no Windows-only compile dependency; Linux execution is not claimed. |
| Baseline regression | `zig build test -Doptimize=ReleaseSafe -j1`: `9/9` steps, `6/6` tests passed. | Existing ABI, corpus, and SIMD gates remain green. |
| Allocation-failure coverage | Pseudo-localization is exercised through `std.testing.checkAllAllocationFailures`; all focused tests pass. | Partial UTF-8 output and owned-buffer failures are released correctly. |
| GPT-6 review repairs | Initial review found seven Medium issues; follow-up review found two additional semantic issues and one cancellation hand-off path. Tests and implementation were repaired, then re-reviewed. | Grace deadlines are bounded/preserved, cancellation wait events are actionable, stale completion retires active state, current vs last-good artifacts are explicit, queued work survives cancellation, empty close can finish, and semantic palette/contrast pairs match the lock. |
| Final GPT-6 review | No Medium+ findings; quality streak `1`. | Final read-only review is clean for this bounded slice. |
| Formatting/diff | Explicit `zig fmt --check` and `git diff --check` passed. | Source formatting and patch whitespace are clean. |

The scheduler adapts Auto delays within 220–750 ms, keeps supersession grace
at or below 75 ms without cancellation storms, waits on the earliest render or
cancellation deadline, preserves a due latest request while an older worker is
being retired, and accepts a completion only after explicit worker admission.
Lifecycle teardown is monotonic and reverse-ordered, with a direct empty-startup
close path and a typed `not_ready` clean-exit result. Theme tokens separate
shell/pane chrome from the always-light PDF paper/ink pair and check body,
semantic, syntax, divider, focus, shell, pane, and PDF contrast in linear sRGB.
Layout data encodes the 1180/880/760 breakpoints, pane minima, 58/42 Source/PDF
allocation, and compact/touch targets. Strings fail closed for unsupported
locales/missing keys and support deterministic expanded/combining/BiDi QA.

No browser QA applies to this native model-only increment; browser evidence is
required when the real TExFlow UI/HTML/live-render lane exists. This slice does
not create the Win32 entry point, HWND/COM/DPI shell, D3D presenter, UIA,
manifest/resources/icon, worker executables, TexLab/TeX compiler, real timer or
thread integration, research/evidence graph, publishing pipeline, or full
product/reproducibility closure. Those remain subsequent T0.2c/T0.2d–T5
tasks and are not implied by the green model gates.

## T0.2c bounded portable presenter state-model evidence (2026-09-05)

This increment adds an allocation-free, single-owner presenter policy model in
`native/zig/src/platform/windows/presenter.zig`. It is intentionally free of
Win32/D3D imports: the model specifies the contract that a later native adapter
must satisfy for a two-buffer `FLIP_SEQUENTIAL` baseline and a full-redraw
`FLIP_DISCARD` challenger. It covers frame-latency grants, coherent damage
history, occlusion/minimize behavior, resize/DPI transactions, reference
release gates, stale-token rejection, device recovery, and bounded hardware to
WARP fallback.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `t0-2c-presenter-test` initially failed because `presenter.zig` was absent; later fault probes also failed on resize-buffer rotation, reference lifetime, and frame-grant semantics before repair. | Tests expose missing implementation and representative state-machine regressions. |
| Windows Debug | `t0-2c-presenter-test -Doptimize=Debug -j1`: `24/24` tests passed. | State transitions, dirty/history policy, waits, and recovery are green. |
| Windows ReleaseSafe | `t0-2c-presenter-test -Doptimize=ReleaseSafe -j1`: `24/24` tests passed. | Safe optimized presenter policy remains deterministic. |
| Windows ReleaseFast | `t0-2c-presenter-test -Doptimize=ReleaseFast -j1`: `24/24` tests passed. | Fast optimized presenter policy remains deterministic. |
| Linux portability | `t0-2c-presenter-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe -j1`: `2/2` compile steps passed. | The model has no Windows-only compile dependency; Linux runtime is not claimed. |
| Combined model regression | `t0-2c-models-test -Doptimize=ReleaseSafe -j1`: `15/15` steps, `46/46` tests passed. | Presenter changes do not regress the role, identity, scheduler, lifecycle, theme/layout, or strings models. |
| Baseline regression | `zig build test -Doptimize=ReleaseSafe -j1`: `9/9` steps, `6/6` tests passed. | Existing ABI, compiler-corpus, and SIMD gates remain green. |
| Adversarial repair | Review caught preservation of a due latest request during cancellation, held back-buffer references after Present, reuse of unsubmitted frame grants, stale old-chain grants after rebuild, and submitted-occluded grant replay. Each received a regression test and fix. | The model does not spin, overwrite an active worker-equivalent frame, resize/rebuild with retained references, or bypass a required fresh wait. |
| Final GPT-6 review | `gpt-6-astra` max read-only review: no Medium+ findings; quality streak `1`. | Final source/test/build review is clean for this bounded slice. |
| Formatting/diff | Explicit `zig fmt --check` and `git diff --check` passed. | Formatting and patch whitespace are clean. |

`max_frame_latency = 1` is an explicit model invariant. A frame-latency grant
is consumed only when `begin_frame` admits a frame; pre-Present invalidation
returns it, submitted Present outcomes consume it, and a rebuilt swap chain
requires a fresh grant. Sequential buffers use conservative bounding-box scene
damage and never emit scroll metadata; uncertain history, resize, DPI, adapter,
theme, coverage, resume, or recovery paths force a full redraw. Occluded and
minimized states never admit a Present, while last-valid frame identity remains
available until a replacement succeeds.

No browser QA applies to this native model-only increment; browser evidence is
required for the future real TExFlow UI/HTML/live-render lane. The slice does
not create the Win32 HWND/COM/DPI shell, D3D11/DXGI swap chain or waitable
handle, Direct2D/DirectWrite drawing, actual COM reference release, WARP device,
ETW/QoS runtime, DWM-visible pixel preservation, or authoritative capture.
Those native/runtime/capture obligations remain open in Task 3 and later QA
tasks; this commit must not be represented as product presentation closure.
