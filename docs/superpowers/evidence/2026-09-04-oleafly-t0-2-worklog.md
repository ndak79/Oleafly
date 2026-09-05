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
| Fresh independent reviewer pass | No actionable Medium+ findings; quality streak `1`. | Candidate-path overlap, timestamp portability, Windows pinning, ACL/recovery/publication, transport, CI, and TExFlow naming reviewed clean. |

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
| Independent reviewer, final pass | No Medium+ findings; quality streak `1` | The ordering finding was fixed and re-reviewed clean. |

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
| Independent reviewer, final pass | No Medium+ findings; quality streak `1`. | Header comparison, LLP64 widths, config v6 layout, C pause callback, and build wiring reviewed clean. |

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
| Independent reviewer, final pass | No Medium+ findings; quality streak `1`. | Tar/gzip/hash/ownership/OOM and Windows collision review clean. |

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
| Independent reviewer, final pass | No actionable Medium+ findings; quality streak `1`. | Nullable callback, archive padding, source locks, flags, symbol distinctions, atomic publication, and build graph reviewed clean. |

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
| Independent reviewer, final pass | No actionable Medium+ findings; quality streak `1`. | Inventory, archive identity, atomic publication, SDK include use, C++ flags, member set, target split, and reachability were reviewed clean. |

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
| Independent reviewer, final pass | No actionable Medium+ findings; quality streak `1`. | EOL attributes, default graph separation, source package inclusion, license hashes, Lexilla/PDFium roles, and no invented owner were reviewed clean. |

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
| Independent static review, final pass | No Medium+ findings; quality streak `1`. The reviewer inspected bounds, section/directory mapping, imports/IAT, relocations, unwind/CFG handling, reporting, tests, and build integration. | Final read-only review is clean; runtime/product-closure exclusions remain explicit. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |

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
| Review repairs | Initial review found seven Medium issues; follow-up review found two additional semantic issues and one cancellation hand-off path. Tests and implementation were repaired, then re-reviewed. | Grace deadlines are bounded/preserved, cancellation wait events are actionable, stale completion retires active state, current vs last-good artifacts are explicit, queued work survives cancellation, empty close can finish, and semantic palette/contrast pairs match the lock. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |
| Final review | No Medium+ findings; quality streak `1`. | Final read-only review is clean for this bounded slice. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |
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
| Final review | Max read-only review: no Medium+ findings; quality streak `1`. | Final source/test/build review is clean for this bounded slice. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |
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

## T0.2c bounded smoke/ABI namespace cutover evidence (2026-09-05)

This increment moves the T0.1 toolchain smoke intent into a cache-only
`t0-1-smoke` Zig test, retires the legacy `run` step, and renames the internal
static C ABI namespace from `oleafly_abi` to `texflow_abi`. The public header is
now `native/zig/include/texflow_abi.h`; the old header, symbols, and library
name are not compatibility aliases. The placeholder `texflow` executable
remains installed only until the later native GUI cutover; this slice does not
claim product-shell completion.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | New smoke/header contracts initially failed when their implementation/artifact paths were absent; the install-reachability guard also failed before the ABI library was removed from the default install graph. | The tests exercised missing behavior and the accidental-install regression rather than passing vacuously. |
| Windows Debug | `zig build test -Doptimize=Debug --summary all`: `13/13` steps, `10/10` tests passed; `t0-1-smoke` contributed `2/2`. | Smoke, renamed ABI, FNV, and SIMD contracts are green in Debug. |
| Windows ReleaseSafe | `zig build test -Doptimize=ReleaseSafe --summary all`: `13/13` steps, `10/10` tests passed; `t0-1-smoke` contributed `2/2`. | Safe optimized behavior remains deterministic. |
| Windows ReleaseFast | `zig build test -Doptimize=ReleaseFast --summary all`: `13/13` steps, `10/10` tests passed; `t0-1-smoke` contributed `2/2`. | Fast comparison mode preserves the same ABI/smoke answers. |
| Linux compile-only | `zig build t0-1-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe --summary all`: `9/9` compile steps passed. | The cache-only smoke and renamed ABI paths compile without Windows-only dependencies. Linux runtime is not claimed. |
| Default install reachability | Fresh Windows ReleaseSafe prefix contained exactly `bin\texflow.exe`; no ABI or smoke artifact was installed. | The renamed ABI and test-only smoke remain outside the default product install graph. |
| C boundary | `zig translate-c` found `texflow_abi_get_version`/`texflow_abi_version_t`; `zig cc -target x86_64-windows-msvc` compiled `abi_layout.c`. | The renamed fixed-width C declaration and layout fixture remain valid. |
| Adversarial falsification | Mutants using the lowercase smoke answer and a legacy ABI alias failed their dedicated tests before restoration. | Known-answer and no-compatibility-prefix guards detect the intended regressions. |
| Formatting/diff | Full-path Zig `fmt --check` and `git diff --check` passed. | Source formatting and patch whitespace are clean. |
| Final review | Max read-only review: `CLEAN`, no Medium+ findings; quality streak `1`. | Build reachability, cross-target assumptions, C ABI/linkage, stale names, and CI/docs alignment were independently reviewed. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |

No browser QA applies to this cache-only native test increment. Browser/native
black-box evidence is required when the real TExFlow HWND/UIA/D3D surface and
HTML/live-render evidence lane exist. The GUI-subsystem entry point, Win32
window/resources, `t0-2-repro`, actual D3D/DWM presentation, and full Task 3
acceptance remain open.

## T0.2c bounded GUI-entry admission evidence (2026-09-05)

This increment adds the allocation-free `ui_entry` admission contract used
before the future UI initializes a window, database, network, or worker. The
argv vector admits only an optional `--trace-trial=<32 lowercase hexadecimal
digits>` value. It decodes to exactly sixteen bytes, or obtains exactly sixteen
bytes once through the existing secure `std.Io.randomSecure` backend when the
option is absent. Worker selectors, internal/probe switches, bootstrap-handle
spelling, separated values, duplicates, and every other argument fail closed.
This module has no Win32, allocator, fixture, test-mode, or policy side effect;
native command-line decoding and inherited-handle inspection remain later
entry-binding responsibilities.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `ui_entry_test.zig` first failed because `ui_entry.zig` was absent. | The admission oracle was proven to fail before implementation. |
| Windows Debug | `zig build t0-2c-entry-test -Doptimize=Debug --summary all`: `3/3` steps, `12/12` tests passed. | Exact grammar, rejection classes, entropy ordering, and secure adapter are green. |
| Windows ReleaseSafe | `zig build t0-2c-entry-test -Doptimize=ReleaseSafe --summary all`: `3/3` steps, `12/12` tests passed. | Safe optimized admission remains deterministic. |
| Windows ReleaseFast | `zig build t0-2c-entry-test -Doptimize=ReleaseFast --summary all`: `3/3` steps, `12/12` tests passed. | Fast comparison mode preserves the same contract. |
| Linux compile-only | `zig build t0-2c-entry-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe --summary all`: `2/2` steps passed. | The parser is portable and has no Windows-only compile dependency. Linux runtime is not claimed. |
| Combined model regression | `zig build t0-2c-models-test -Doptimize=ReleaseSafe --summary all`: `17/17` steps, `58/58` tests passed. | Entry admission integrates without regressing the existing T0.2c models. |
| Adversarial falsification | Swapped-nibble/uppercase mutations failed `4` checks, premature entropy mutations failed `11`, and a nonsecure random adapter mutation failed `1`; all were restored. Exhaustive rejection covers all `240` noncanonical byte values at every hex position. | Decode correctness, full-vector validation before entropy, and no weak-random fallback are actively detected. |
| Formatting/diff | Full-path Zig `fmt --check` and `git diff --check` passed. | Source formatting and patch whitespace are clean. |
| Final review | Max read-only review: `CLEAN`, no Medium+ findings; quality streak `1`. | Grammar, error ordering, secure entropy, prohibited switches, and build wiring were independently reviewed. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |

No browser QA applies to this native parser-only increment. The real UI entry
binding must later connect this contract before Win32 initialization and add
native inherited-handle/command-line decoding evidence; this slice does not
claim GUI shell, worker isolation, or full Task 3 acceptance.

## T0.2c bounded canonical source-set v2 evidence (2026-09-05)

This increment adds a pure-Zig canonical source-set v2 digest model. Callers
provide already byte-sorted raw Git-style paths, exact `100644`/`100755` modes,
u64 content lengths, and 32-byte blob SHA-256 values. The wire identity is
`SHA-256("texflow:source-set:v2\0" || count_u64_le || entries)` with raw UTF-8
path bytes preserved. Unicode-17 NFD/full case folding is used only to reject
portable collisions, including file-vs-directory prefix conflicts; it never
changes the bytes hashed. Git enumeration, content hashing/verification,
controller wiring, and runtime build identity collection remain later work.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `t0-2c-source-set-test` initially failed with `FileNotFound` for the absent module; prefix regressions then failed `3` cases before the P2 repair. | The implementation and the security regression were both proven non-vacuous. |
| Windows Debug | `zig build t0-2c-source-set-test -Doptimize=Debug -j1 --summary all`: `7/7` steps, `14/14` tests passed. | Canonical vectors, path/mode validation, Unicode collisions, prefix checks, and OOM cleanup are green. |
| Windows ReleaseSafe | `zig build t0-2c-source-set-test -Doptimize=ReleaseSafe -j1 --summary all`: `7/7` steps, `14/14` tests passed. | Safe optimized behavior remains deterministic. |
| Windows ReleaseFast | `zig build t0-2c-source-set-test -Doptimize=ReleaseFast -j1 --summary all`: `7/7` steps, `14/14` tests passed. | Fast optimized behavior preserves the same contract. |
| Linux portability | `zig build t0-2c-source-set-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe -j1 --summary all`: `6/6` compile steps passed; full-model Linux compile was `14/14`. | The model and Unicode-17 dependency compile without Windows-only APIs; Linux runtime is not claimed. |
| Combined model regression | `zig build t0-2c-models-test -Doptimize=ReleaseSafe -j1 --summary all`: `23/23` steps, `72/72` tests passed. | Source-set wiring does not regress role, identity, scheduler, lifecycle, theme/layout, strings, presenter, or entry models. |
| Baseline/product regression | `zig build test -Doptimize=ReleaseSafe -j1 --summary all`: `13/13` steps, `10/10` tests; product `zig build -Doptimize=ReleaseSafe -j1`: `3/3` steps. | Existing baseline checks and the installed placeholder executable remain green. |
| Install reachability | Fresh ReleaseSafe prefix contained exactly `bin\texflow.exe`; no source-set test or Unicode fixture artifact was installed. | The new model stays outside the default product install graph. |
| Independent digest vectors | Six fixed answers (empty, single, multi-entry, Unicode raw-byte, u64-max length, and build-identity composition) match independently generated values. | The encoder is not merely self-consistent. |
| Adversarial falsification | One-bit count mutations killed `4` checks; Unicode-fold bypass killed `4`; prefix-check bypass killed `3`; OOM sweep covers success, canonical collision, and prefix collision paths. | The tests detect plausible wire-format, portability, and cleanup regressions. |
| Review | First review found P2 file-vs-directory prefix collision; after repair, the max read-only review returned `CLEAN` with no Medium+ findings. | Quality streak reset on the P2 and is now `1/1` clean for this slice. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |
| Formatting/diff | Full-path `zig fmt --check` and `git diff --check` passed. | Formatting and patch whitespace are clean. |

No browser QA applies to this pure native model-only increment; browser/native
black-box evidence is required once the real TExFlow UI/HTML/live-render lane
exists. This slice does not enumerate Git, hash files, validate a checkout,
connect `build_identity.compute` to runtime artifacts, or claim full
reproducibility/Task 3 closure.

## T0.2c bounded shell orchestration evidence (2026-09-05)

This increment adds the portable startup/teardown contract that the future
native UI adapter must satisfy. UTF-16 arguments are converted and fully
admitted before any DLL, DPI, COM, class, or HWND operation. Successful setup
is released in reverse ownership order; `GetMessageW`-style `-1` is an error,
`0` is a clean quit, and the first operational error is preserved over cleanup
failures. The narrow COM binding accepts only successful `S_OK`/`S_FALSE`
HRESULTs and never claims activation or interface ownership. Native entry,
Win32 adapter, product install cutover, resources, D3D, workers, and the full
UI surface remain later slices.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `t0-2c-shell-test` initially failed because `shell.zig` was absent. | The portable orchestration oracle was proven non-vacuous. |
| Windows Debug | `zig build t0-2c-shell-test -Doptimize=Debug -j1 --summary all`: `3/3` steps, `8/8` tests passed. | Admission ordering, cleanup, message statuses, COM HRESULT semantics, and UTF-16 allocation handling are green. |
| Windows ReleaseSafe | `zig build t0-2c-shell-test -Doptimize=ReleaseSafe -j1 --summary all`: `3/3` steps, `8/8` tests passed. | Safe optimized orchestration remains deterministic. |
| Windows ReleaseFast | `zig build t0-2c-shell-test -Doptimize=ReleaseFast -j1 --summary all`: `3/3` steps, `8/8` tests passed. | Fast optimized orchestration preserves the contract. |
| Linux portability | `zig build t0-2c-shell-check -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe -j1 --summary all`: `2/2` compile steps passed; full-model Linux compile was `15/15`. | The model compiles without Windows-only link execution; Linux runtime is not claimed. |
| Combined model regression | `zig build t0-2c-models-test -Doptimize=ReleaseSafe -j1 --summary all`: `25/25` steps, `80/80` tests passed. | Shell orchestration integrates without regressing source-set, presenter, entry, lifecycle, rendering, theme/layout, strings, role, or identity models. |
| Adversarial falsification | A skipped-COM-cleanup mutant killed `4` tests; a `GetMessage(-1)` mutant killed `2`; an `S_FALSE`-handling mutant killed `1`; scratch mutations were restored. | Resource ownership, message error handling, and COM success semantics are actively detected. |
| Review | Max read-only review: `CLEAN`, no Medium+ or P3 evidence findings. | Quality streak for this bounded slice is `1/1` clean. Model identity is intentionally not recorded because the runtime does not expose a verified model ID in this worklog. |
| Formatting/diff | Full-path `zig fmt --check` and `git diff --check` passed. | Formatting and patch whitespace are clean. |

No browser QA applies to this native orchestration-only increment; browser
evidence becomes relevant only if a later slice emits an HTML artifact or
browser-visible surface. This commit must not be represented as a real
Win32/DPI/COM/UIA/D3D shell or as Task 3 completion.

## T0.2c bounded native Windows shell/product cutover evidence (2026-09-05)

This increment replaces the temporary installed console artifact with the
first real x64-Windows GUI product, `TExFlow.exe`. The narrow Zig adapter owns
UTF-16 command-line tokenization through `CommandLineToArgvW`, exact admission
before native setup, system32-only DLL search, per-monitor-v2 DPI context,
COM STA initialization, the `texflow.main.v1`/`TExFlow` window, a blocking
`GetMessageW` loop, and reverse cleanup. The product is installed only for
x64 Windows; unsupported targets, including Linux, have an empty install
graph. This slice deliberately does not add resources/manifest/icon, D3D or
DirectWrite presentation, workers, UIA, telemetry, or the remaining Task 3
runtime/capture obligations.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | Product contract initially failed four expected checks: lowercase product name, console PE subsystem, absent HWND, and malformed-argument exit `0` instead of `2`. | The product/runtime oracle was non-vacuous before the adapter and build cutover. |
| Windows Debug | `zig build t0-2c-shell-native-test -Doptimize=Debug -j1 --summary all`: `3/3` steps, `6/6` tests; `zig build t0-2c-product-test -Doptimize=Debug -j1 --summary all`: `5/5` steps, `4/4` tests. | Native ABI/argv/COM contracts and the real GUI product are green in Debug. |
| Windows ReleaseSafe | Native `6/6` and product `4/4` tests passed (`3/3` and `5/5` steps respectively). | Safe optimized shell and product behavior remains green. |
| Windows ReleaseFast | Native `6/6` and product `4/4` tests passed (`3/3` and `5/5` steps respectively). | Fast optimized shell and product behavior remains green. |
| Existing regression | `zig build test -Doptimize=ReleaseSafe -j1 --summary all`: `13/13` steps, `10/10` tests; `t0-2c-models-test`: `25/25` steps, `80/80` tests. | T0.1 smoke/ABI/corpus and all prior T0.2 models remain green. |
| Linux compile-only | `t0-2c-shell-native-check`: `2/2`; `t0-2c-product-check`: `3/3`; `t0-2c-models-check`: `15/15` compile steps for x86_64-linux-gnu ReleaseSafe. | Portable contracts compile without emitting a Linux product; Linux runtime is not claimed. |
| Install graph | Fresh x64-Windows ReleaseSafe prefix contained exactly `bin\TExFlow.exe`; a fresh x86_64-linux-gnu prefix contained no files. | Product naming/install reachability is target-gated and legacy `bin\texflow` is retired. |
| Runtime/PE oracle | Product tests verify AMD64 PE, GUI subsystem `2`, narrow Unicode shell imports, exact `TExFlow` title and `texflow.main.v1` class, standard caption style, PMv2 context, visible HWND, WM_CLOSE exit `0`, and rejected worker/unknown arguments exit `2`. | The first real Windows shell is directly exercised, not inferred from a compile-only stub. |
| Adversarial falsification | An argv0-inclusion mutant was detected by `2` native tests; a PMv2-to-PMv1 mutant was detected by the actual-window DPI assertion. | Command-line indexing and DPI policy are regression-protected. |
| CI alignment repair | The Linux reproducibility step now creates two clean prefixes and asserts both are empty instead of hashing the retired `bin/texflow`. | CI no longer contradicts the target-gated product install graph. |
| Final review | The available reviewer runtime returned `CLEAN`, with no Medium+ or P3 findings after the CI repair; quality streak for this slice is `1/1`. | Exact current code/build/test/workflow diff was independently reviewed. Model identity is intentionally not recorded because the runtime does not expose a verified provider/model ID. |
| Formatting/diff | Full-path `zig fmt --check` and `git diff --check` passed. | Formatting and patch whitespace are clean. |

No browser QA applies to this native-only cutover: there is no HTML/browser
surface or live-render canvas in this slice. Browser QA remains conditional on
a future HTML/browser surface; native pixel/capture evidence is a separate
requirement for the D3D/UI/live-render lane. The product is not yet
Task 3 complete: resources/manifest, renderer, waitable presenter, workers,
security hardening beyond entry-time policy, and full reproducibility/capture
closure remain open.

## T0.2c resources, VERSIONINFO, and PMv2 compatibility evidence (2026-09-05)

This bounded increment adds the tracked TExFlow manifest and VERSIONINFO
resource, embeds both only in the x64-Windows GUI product, and keeps the
portable version contract shared with build identity. The manifest requests
`asInvoker`, Common Controls v6, and `PerMonitorV2`; the resource metadata is a
pre-release/private feasibility build (`0.0.2.0`) with the exact TExFlow
identity and US-English Unicode translation. The native shell accepts an
already-established PMv2 context from the manifest or verifies the explicit
runtime setter path; it never silently accepts another DPI context.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| Resource contract | `t0-2c-resource-test` passed `3/3` tests in Debug, ReleaseSafe, and ReleaseFast. | Version tuple, flags, identity, legal-field exclusions, tracked RC literals, and manifest policy are deterministic on every target. |
| Product/resource oracle | `t0-2c-product-test` passed `8/8` tests in Debug, ReleaseSafe, and ReleaseFast. | The actual AMD64 GUI PE round-trips the embedded manifest byte-for-byte and the exact VERSIONINFO structure, flags, strings, translation, and resource tree. |
| Native shell regression | `t0-2c-shell-native-test` passed `7/7` tests in Debug, ReleaseSafe, and ReleaseFast. | PMv2 acceptance, Unicode argv, secure entropy, COM, DLL search, cleanup, and ABI contracts remain green. |
| Full portable regression | `t0-2c-models-test -Doptimize=ReleaseSafe -j1 --summary all`: `28/28` steps, `83/83` tests; `zig build test`: `13/13` steps, `10/10` tests. | Prior T0.1/T0.2 models and smoke/ABI corpus remain green after resource/build wiring. |
| Linux reachability | `t0-2c-resource-check`: `3/3`; `t0-2c-shell-native-check`: `2/2`; `t0-2c-product-check`: `4/4`; `t0-2c-models-check`: `17/17` compile steps for x86_64-linux-gnu ReleaseSafe. | Non-Windows graph compiles without a product install edge; Linux runtime was not claimed from this Windows host. |
| Fresh install reproducibility | Two fresh x86_64-windows-msvc ReleaseSafe prefixes each contained exactly `bin\TExFlow.exe`; SHA-256 for both was `613c4453e0a2f6a82cd70c02584fd4bd518b0442b7897bf8a5b594bbbb3231f5`. | Resources are embedded in the named product and do not introduce nondeterministic output or extra installed artifacts. |
| Adversarial resource falsification | Wrong US locale, non-zero sibling padding, hidden leaf data, malformed flags/string/length, and a valid synthetic resource tree outside the declared resource span were all rejected by the product parser. | The parser guards are exercised with mutants that keep unrelated PE/resource limits valid. |
| CI closure | Windows workflow now runs resource, native-shell, and product gates in Debug/ReleaseSafe/ReleaseFast; Linux runs portable resource gates in all three modes plus ReleaseSafe models. YAML parse and `git diff --check` passed. | CI executes the product/resource acceptance oracle instead of only compiling the graph. |
| Final review | Review cycles found and repaired seven P2 findings (root-tree cardinality, locale, sibling padding, resource-span bounds, leaf completeness, and synthetic-tree fixture correctness); final independent read-only review returned `CLEAN`. Quality streak: `1/1`. | The bounded slice is closed for Medium+ findings under the user-selected one-pass streak policy. Model identity is intentionally not recorded because this runtime does not expose a verified provider/model ID. |

No browser QA applies to this native-only resource/manifest slice: there is no
HTML/browser surface or live-render canvas. Icon artwork, D3D/DirectWrite
presentation, waitable presenter, workers, UIA, telemetry, and full native
pixel/capture evidence remain later Task 3 work; this section does not claim
those features.

## T0.2c bounded deterministic TExFlow app-mark/ICO resource evidence (2026-09-05)

This increment adds one canonical fixed-point geometry source for the reviewed
TExFlow source-to-evidence mark. Pure Zig emits the tracked SVG-equivalent bytes
and a cache-only five-size 32-bit alpha ICO (`16/24/32/48/256`), plus a
self-contained generated RC fragment. The generator validates its own output
before writing and never mutates tracked source. The Windows product embeds the
generated `RT_GROUP_ICON`/`RT_ICON` tree while the Linux graph remains
product-empty.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `t0-2c-icon-test` first failed because `native/zig/assets/texflow_icon.zig` was absent; a later corner-coverage failure caught a renderer bounds mismatch before repair. | The source-mark and raster output tests were non-vacuous and detected a real geometry bug. |
| Windows icon/tool tests | `t0-2c-icon-test` passed `10/10` tests in Debug, ReleaseSafe, and ReleaseFast (9 target icon tests plus 1 host generator test). | Fixed-point geometry, tracked-SVG equality, ICO directory/DIB/alpha/AND-mask invariants, mutation rejection, and allocator-failure cleanup are green. |
| Linux portability | `t0-2c-icon-check -Dtarget=x86_64-linux-gnu` passed `4/4` compile steps in Debug, ReleaseSafe, and ReleaseFast. | The source/validator and host generator compile without Windows-only APIs; Linux runtime is not claimed. |
| Product/resource oracle | `t0-2c-product-test` passed `11/11` in Windows Debug, ReleaseSafe, and ReleaseFast. The PE parser found one US-English group resource with five ordered entries and matching RT_ICON DIB sizes/IDs and canonical bytes. | The real AMD64 GUI PE embeds the generated mark and preserves the exact five-resolution contract. |
| Full regression | `t0-2c-models-test -Doptimize=ReleaseSafe -j1`: `33/33` steps, `93/93` tests; `zig build test -Doptimize=ReleaseSafe -j1`: `13/13`, `10/10`. | Existing T0.1/T0.2 models and baseline gates remain green. |
| Fresh reproducibility | Two fresh x86_64-Windows ReleaseSafe prefixes with disjoint local/global caches each contained exactly `bin\TExFlow.exe` (851,968 bytes); both SHA-256 were `82b2e1bb44c3268ec78e39c682e1fd74ea60f24e8d63a06f836348679543aaf5`. | Generated ICO/RC inputs do not introduce output drift or extra installed files. |
| Adversarial falsification | Count, offset, dimension, truncation, alpha/AND-mask mismatch, stale-alpha, named-resource cardinality, canonical-pixel mutation, and every injected allocation-failure path were rejected; the source SVG must byte-match the canonical generator output. | Plausible resource corruption and cleanup regressions are actively detected. |
| Formatting/CI | Full-path `zig fmt --check`, `git diff --check`, and YAML parsing passed; workflow runs icon gates in all three Windows and Linux optimization lanes. | Formatting and CI reachability are aligned with the target-gated install graph. |
| Review | Independent read-only review is required before commit; quality streak remains `0` until that review and the post-review rerun are clean. | This section does not pre-claim the streak or Task 3 completion. |

No browser QA applies: this is a native resource/build increment with no HTML
surface. Explorer/Alt-Tab/taskbar visual capture, D3D/DirectWrite presentation,
waitable swap-chain behavior, and full A05 pixel evidence remain open Task 3
obligations. The icon generator is build-time/test-time only and is not a
shipping executable or installed payload.

## T0.2c corrective review round: icon/resource oracle gaps (2026-09-05)

The independent read-only reviewer returned `NOT CLEAN` with four P2 findings
and one P3. This is recorded before any quality-streak transition. The issues
were verified against the current source and corrected in this working tree:

| Finding | Correction | Direct oracle |
| --- | --- | --- |
| SVG path coordinates could drift from raster geometry | `canonical_svg` is now comptime-formatted from the fixed-point segment/style constants used by the rasterizer; the tracked SVG remains a byte-checked generated artifact. | Tracked-SVG equality plus compile-time geometry references. |
| All-zero legacy AND mask erased transparency for older consumers | ICO generation now emits bottom-up 1-bpp AND bits for `alpha == 0`, clears row padding, and validates every bit against the pixel alpha. | Per-size alpha/mask/padding test and mutation rejection. |
| PE parser accepted extra or duplicate icon/group resources | Resource-name validation now requires exactly group ID `1` and icon IDs `1..5`, with no names, extras, missing IDs, or duplicates; every leaf is validated. | Always-run resource-ID mutation tests and Windows PE test. |
| PE oracle checked only DIB headers and lengths | Windows product tests compare every embedded `RT_ICON` byte-for-byte with the canonical ICO image; a preserved-header pixel mutation is rejected by the oracle helper. | Canonical image equality and mutation test. |
| Allocation-overflow test name overstated its cases | The unsupported-size test was renamed; the separate allocation-failure sweep remains the cleanup oracle. | `checkAllAllocationFailures` test. |

| Package-path TDD RED | The new `deps-manifest-test` first failed because `build.zig.zon` omitted the tracked SVG and host icon generator required by `build.zig`. | The source-package allowlist oracle detected a clean-archive build gap before it could ship. |
| Package-path GREEN | After adding both exact paths to `build.zig.zon`, `zig build deps-manifest-test -Doptimize=Debug -j1 --summary all` passed `17/17` tests. | The build-script inputs are now represented in the package source contract. |
| Corrective matrix | Fresh Windows Debug icon/tool `10/10`, product `11/11`; ReleaseSafe/ReleaseFast icon `10/10`, product `11/11`; Linux Debug/ReleaseSafe/ReleaseFast icon-check `4/4` compile steps; full `t0-2c-models-test` `33/33` steps, `93/93` tests. | The five reviewer fixes and package allowlist correction survive the target/optimization matrix. |

The independent post-review verdict is still required before commit. Quality
streak remains `0/1` until that verdict and one final clean rerun are recorded.

## T0.2c final review and post-review clean pass (2026-09-05)

The independent reviewer returned `CLEAN` after the corrective round. One
fresh post-review verification pass then reproduced the relevant matrix without
new Medium-or-higher findings:

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| Package contract | `zig build deps-manifest-test -Doptimize=Debug -j1 --summary all`: `17/17` tests. | The source-package allowlist includes every icon build input. |
| Windows icon/tool matrix | `t0-2c-icon-test`: `10/10` in Debug, ReleaseSafe, and ReleaseFast (9 target + 1 host). | Canonical geometry/style, SVG bytes, ICO alpha/mask, mutations, and allocation cleanup remain green. |
| Windows product matrix | `t0-2c-product-test`: `11/11` in Debug, ReleaseSafe, and ReleaseFast. | Strict resource cardinality, canonical RT_ICON bytes, PE metadata, and owned shell tests remain green. |
| Linux portability | `t0-2c-icon-check`: `4/4` compile steps in Debug, ReleaseSafe, and ReleaseFast. | The portable source and host generator remain cross-target compilable; no Linux runtime is claimed. |
| Full regression | `t0-2c-models-test`: `33/33` steps, `93/93` tests; `zig build test`: `13/13` steps, `10/10` tests. | Existing T0.1/T0.2 behavior and baseline gates remain green. |
| Clean-build reproducibility | Two explicitly contained fresh ReleaseSafe prefixes each contained exactly `bin\TExFlow.exe` (851,968 bytes); both SHA-256 were `D326FAA5D5EFCE6CDBE070F14BFB870A54E0258D001AD295958BC7D904005AA4`. | Generated resources do not add output drift or extra install files. |
| Formatting and stale-label scan | `zig fmt --check`, `git diff --cached --check`, YAML parse, and GPT-6/Astra scan all passed/clean. | The staged source is formatted, workflow syntax-valid, and contains no unsupported model claim. |
| Quality streak | Reviewer `CLEAN` + this fresh post-review pass: `1/1`. | This bounded T0.2c increment is ready for its own commit; it does not close full Task 3. |

Browser QA is not applicable to this native resource/build increment. Explorer,
Alt-Tab/taskbar captures, D3D/DirectWrite presentation, waitable swap-chain
behavior, and the remaining Task 3 visual/runtime obligations stay explicitly
open for their owning slices.

## T0.2c presenter decision research (2026-09-05)

The presenter choice was re-opened before adding any D3D code. The decision gate
used six distinct challenger rounds (five required deep-research rounds plus
one additional confirmation) and two final no-improvement rounds. Evidence was
restricted to the Microsoft SDK/architecture documentation and the pinned
zigwin32/Zig documentation; no benchmark claim is inferred from the API docs.

| Round | Challenger angle | Decision impact |
| --- | --- | --- |
| 1 | D3D11 hardware creation versus WARP/legacy reference drivers. | Keep hardware first with an explicit feature-level list, `BGRA_SUPPORT`, and WARP fallback; never pair a non-null adapter with `HARDWARE`. [`D3D11CreateDevice`](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-d3d11createdevice), [`DirectX WARP`](https://learn.microsoft.com/en-us/windows/win32/direct3darticles/directx-warp) |
| 2 | Flip-model presentation, dirty rectangles, and frame-latency waitable objects. | Baseline is two-buffer `FLIP_SEQUENTIAL` + waitable flag + `Present1`; dirty metadata is allowed only for coherent coverage, otherwise redraw fully. [`DXGI 1.2 presentation improvements`](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-2-presentation-improvements) |
| 3 | Resize, occlusion, device removal, and reference lifetime. | Release every direct/indirect back-buffer reference before `ResizeBuffers`; recreate the complete device-dependent chain after removal; standby on `DXGI_STATUS_OCCLUDED`. [`ResizeBuffers`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgiswapchain-resizebuffers), [`DXGI overview`](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-overviews) |
| 4 | Direct2D/DirectWrite interop versus GDI or a separate renderer device. | Use the same DXGI device for D2D and a shared DirectWrite factory; do not target the flip HWND with GDI. [`Direct2D/D3D interop`](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-and-direct3d-interoperation-overview), [`DirectWrite`](https://learn.microsoft.com/en-us/windows/win32/directwrite/introducing-directwrite) |
| 5 | Composition swap chain, D3D12, and blt-model challengers. | Composition adds an unnecessary compositor/commit surface, D3D12 adds queue/fence overhead for no current benefit, and blt/GDI violates the ownership/performance contract. Keep composition as a reversible post-profile spike only. [`CreateSwapChainForComposition`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforcomposition), [`CreateSwapChainForHwnd`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgifactory2-createswapchainforhwnd) |
| 6 | Binding boundary: generated zigwin32 root versus a manually duplicated ABI. | Keep the pinned generated declarations behind `platform/windows/api.zig`; TExFlow code imports only that facade, avoiding a second hand-maintained ABI path. [`Zig @cImport/extern ABI`](https://ziglang.org/documentation/master/#cImport) |
| Final 1 | `IDXGISwapChain2` maximum latency and waitable-flag restrictions. | `max_frame_latency = 1` remains the lowest admitted queue depth; both flip-model challengers retain the frame-latency waitable object, while the challenger differs only in preservation/partial-present semantics. [`SetMaximumFrameLatency`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_3/nf-dxgi1_3-idxgiswapchain2-setmaximumframelatency), [`GetFrameLatencyWaitableObject`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_3/nf-dxgi1_3-idxgiswapchain2-getframelatencywaitableobject), [`DXGI swap-chain flags`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ne-dxgi-dxgi_swap_chain_flag) |
| Final 2 | HWND swap-chain descriptor restrictions and same-device D2D path. | Keep width/height zero (HWND-sized), BGRA8, sample count one, two buffers, and `CreateSwapChainForHwnd`; no material improvement over the selected D3D11/DXGI/D2D/DWrite path. |

**Selected baseline:** D3D11 hardware creation with explicit feature levels and
`D3D11_CREATE_DEVICE_BGRA_SUPPORT`, WARP fallback, `CreateSwapChainForHwnd`, a
two-buffer `FLIP_SEQUENTIAL` descriptor with a frame-latency waitable object
and maximum latency one, then Direct2D/DirectWrite on the same device. The
`FLIP_DISCARD` path remains a full-redraw/no-partial-metadata challenger with
the same waitable pacing gate.
DirectComposition, D3D12, blt/GDI, WebView/Qt/Tauri/.NET, and a duplicated
manual binding are rejected for this slice. Unknowns left for native runtime
measurement are present/capture latency, WARP/RDP power behavior, and device
loss recovery timing.

## T0.2c native D3D11 admission probe (2026-09-05)

This bounded implementation increment turns the selected device boundary into
real Zig code. `platform/windows/graphics.zig` exposes an allocation-free,
ABI-neutral swap-chain descriptor validator and calls the pinned zigwin32
`D3D11CreateDevice` declaration on Windows. It requests hardware first, releases
any partial COM outputs on failure, retries with WARP, and releases the immediate
context before the device during teardown. `shell_native.zig` now refuses to
leave a visible HWND alive unless this device exists; it never falls back to
GDI. The generated binding is linked only through the `api.zig` facade and the
product adds only `d3d11.dll` to its allowlisted imports.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | `t0-2c-graphics-test` initially failed because `graphics.zig` was absent. | The new acceptance gate was non-vacuous before implementation. |
| Windows Debug | `t0-2c-graphics-test`: 5 passed, 1 skipped; `t0-2c-shell-native-test`: 7/7; `t0-2c-product-test`: 11/11. | Descriptor invariants, x64 binding layouts/GUID/vtable presence, real hardware-or-WARP creation, COM cleanup, and the actual GUI product are green in Debug. |
| Linux portability | `t0-2c-graphics-check` and `t0-2c-shell-native-check`: compile-only ReleaseSafe gates passed for x86_64-linux-gnu; no Linux runtime is claimed. | Non-Windows builds retain a declaration-only graphics surface and install no product. |
| Import/resource oracle | Product PE now requires `D3D11CreateDevice` and allowlists `d3d11.dll`; no GDI or alternate renderer import was added. | The binary contract matches the selected native path. |
| Browser applicability | No HTML/browser surface exists in this native-only increment. | Native runtime/capture QA remains required for the later swap-chain, D2D/DWrite, and visual A05 slices. |

The final review and the ReleaseSafe/ReleaseFast matrix are intentionally still
open; this section does not pre-claim a quality-streak pass or full Task 3
completion.

## T0.2c presenter correction and final review (2026-09-05)

The first closed review found three P2 gaps and reset this increment's streak to
zero: the challenger incorrectly removed the frame-latency waitable flag,
device admission could accept FL9_3, and CI had no explicit cold-cache
acquisition edge. The fixes retain the waitable flag for both flip-model
effects, request only FL11_0/10_1/10_0 and route any below-floor success through
COM release and WARP retry, and run the locked `deps-fetch` step before cache
consumers on both CI operating systems (with a 30-minute job budget for the
network-capable bootstrap).

The native adapter now calls the same exported `admitsFeatureLevel` predicate
covered by the below-floor regression test; no duplicate threshold oracle
remains. The validator/test/worklog policy now describes `FLIP_DISCARD` as a
full-redraw challenger with the same waitable pacing gate.

| Fresh post-review evidence | Result |
| --- | --- |
| `zig build deps-fetch --summary all -j1` | 11/11 steps, 9/9 tests; every ordinary artifact cache entry verified/cached. |
| Windows `t0-2c-graphics-test` Debug/ReleaseSafe/ReleaseFast | 6 passed, 1 platform skip in each mode. |
| Windows `t0-2c-shell-native-test` Debug/ReleaseSafe/ReleaseFast | 7/7 in each mode. |
| Windows `t0-2c-product-test` Debug/ReleaseSafe/ReleaseFast | 11/11 in each mode; GUI PE imports `D3D11CreateDevice` and only the allowlisted system DLL set. |
| Windows `t0-2c-models-test --release=safe` | 99 passed, 1 platform skip. |
| Linux `t0-2c-graphics-check` and `t0-2c-shell-native-check` Debug/ReleaseSafe/ReleaseFast | 6/6 compile-only targets succeeded; no Linux runtime claim. |
| Linux `t0-2c-models-check --release=safe` | 21/21 compile steps succeeded. |
| `deps-manifest-test`, `deps-test`, `unicode-audit`, `deps-audit` | 17/17, 149/149, 44/44, and 45/45 respectively. |
| Formatting, `git diff --check`, YAML parse, CI acquisition-order assertion | Clean/pass. |

An attempted Linux `t0-2c-models-test` from this Windows host was rejected by
Zig's cross-target execution guard; it is an expected environment limitation,
not a product failure, and the matching Linux workflow runs that lane natively.
No browser QA applies to this native-only increment. Reviewer result after the
corrections is `CLEAN`; the required quality streak is now `1/1`. This closes
only the bounded D3D11 admission/policy increment, not full Task 3 or the
overall TExFlow roadmap.

## T0.2c native DXGI HWND binding boundary and ACL follow-up (2026-09-05)

This bounded slice keeps the shipping surface Windows x64 only. The new
`presenter_native.zig` adapter owns the `IDXGISwapChain1`/`IDXGISwapChain2`
interfaces and the DXGI frame-latency waitable `HANDLE`: it validates the
admitted two-buffer BGRA8 descriptor, creates an HWND flip-model chain, sets
and reads back maximum frame latency `1`, obtains the waitable handle, and
closes/releases each resource exactly once. It intentionally exposes no
`Present1` or `ResizeBuffers` method yet. Those entry points belong with the
render-target owner that can enforce wait-before-first/every-draw, release and
rebind barriers, typed HRESULT/device-loss handling, and occlusion recovery.
Linux is a compile-only portability guard; no Linux product, UI, or package is
produced.

| Evidence | Observed result | Interpretation |
| --- | --- | --- |
| TDD RED | The first targeted presenter build failed because `presenter_native.zig` was absent. | The new gate was non-vacuous before implementation. |
| Adversarial runtime falsification | A temporary `Present1(1, 0, null)` experiment crashed ReleaseSafe in `dxgi.dll`; the SDK marks `pPresentParameters` as required input. A zeroed parameters struct made that call safe, but the partial Present/Resize API was removed from this slice until its lifecycle owner exists. | An unsafe partial API was caught and is not shipped. |
| Windows native matrix | `t0-2c-presenter-native-test`: `4/5` tests passed with one non-Windows skip in Debug, ReleaseSafe, and ReleaseFast. The x64 runtime test creates both `FLIP_SEQUENTIAL` and `FLIP_DISCARD` HWND chains, verifies a non-null waitable handle and read-back latency `1`, then calls `deinit` twice. | Both admitted binding variants and idempotent teardown are exercised on the real Windows target. |
| Linux portability | `t0-2c-presenter-native-check`: `2/2` compile steps succeeded in Debug, ReleaseSafe, and ReleaseFast for x86_64-linux-gnu. | The portable declaration surface remains buildable; Linux runtime is not claimed. |
| Integrated Windows gates | `t0-2c-models-test -Dtarget=x86_64-windows-msvc --release=safe`: `39/39` steps, `103/105` tests with two documented skips; `zig build test`: `13/13` steps, `10/10` tests. | Existing model, shell, graphics, resource, and presenter behavior remain green. |
| Dependency/ACL regression | `deps-test --summary all -j1`: `18/18` steps, `152/152` tests. The ACL helper now has a positive exact `TokenOwner` path, a host-independent unrelated-group negative path, and the Windows workflow runs the dependency gate. | Effective-token-owner semantics are directly tested and continuously exercised. |
| Source-package allowlist | `deps-manifest-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug -j1`: `4/4` steps, `17/17` tests after adding both presenter source/test paths to `build.zig.zon`. | A clean source archive retains every build input for this increment. |
| Formatting/workflow | Full-path `zig fmt --check build.zig native/zig tools/zig`, `git diff --check`, and PyYAML parsing of `.github/workflows/zig.yml` passed. | Source and CI syntax are clean. |
| Review status | The first presenter review's unsafe Present/Resize findings were addressed by narrowing the public surface to binding/lifetime only; re-review is required before commit. Quality streak is `0/1` until that verdict and one fresh post-review rerun. | This increment does not pre-claim the streak or full Task 3 completion. |

Browser QA is not applicable: this increment has no HTML/browser surface.
Explorer/Alt-Tab/taskbar visual capture, D3D/DirectWrite render targets,
wait-before-draw, Present1 parameter/dirty metadata, ResizeBuffers barriers,
HRESULT/device-loss/occlusion recovery, SyncTeX, and the remaining Task 3
runtime obligations remain explicitly open for their owning slices.

## T0.2c presenter/ACL final review and post-review clean pass (2026-09-05)

Two independent read-only reviews returned `CLEAN` for this narrowed
increment. The presenter reviewer verified the generated DXGI signatures,
descriptor ABI offsets, balanced factory/COM/handle ownership, both runtime
flip effects, and idempotent teardown. The ACL reviewer verified the aligned
TokenUser/TokenOwner buffers, exact SID matching, positive/negative helper
paths, and CI wiring. The only reviewer note was a wording clarification in
the ACL comment; it was corrected without changing behavior.

| Fresh post-review evidence | Result |
| --- | --- |
| Windows presenter runtime | `t0-2c-presenter-native-test -Dtarget=x86_64-windows-msvc --release=safe`: `9/9` steps, `4/5` tests passed, one expected non-Windows skip. | Real x64 Windows creation/latency/handle ownership remains green after review. |
| Linux presenter guard | `t0-2c-presenter-native-check -Dtarget=x86_64-linux-gnu --release=safe`: `2/2` compile steps. | Only the portable declaration surface is checked; no Linux product/runtime claim. |
| Source-package contract | `deps-manifest-test --release=safe`: `4/4` steps, `17/17` tests. | The final `build.zig.zon` allowlist contains both new presenter inputs. |
| Integrated Windows gates | `t0-2c-models-test`: `39/39` steps, `103/105` tests with two documented skips; `zig build test`: `13/13`, `10/10`. | Existing T0.1/T0.2 contracts and this increment remain green. |
| Dependency/ACL gate | `deps-test --summary all -j1`: `18/18` steps, `152/152` tests. | The effective-owner policy passes the full adversarial dependency suite. |
| Formatting/workflow | `zig fmt --check`, staged `git diff --check`, and PyYAML workflow parse passed. | No formatting or workflow syntax gap remains. |
| Quality streak | Reviewer `CLEAN` + fresh post-review rerun: `1/1`. | This bounded increment is clean and ready for commit; full Task 3 remains open. |

Browser QA remains not applicable because this is a native Windows build/API
increment with no HTML surface. Linux remains a compile-only CI guard and is
not a supported product target.

## T0.2c remote CI closure (2026-09-05)

The first post-push workflow run (`33975936373`) completed the Linux lane but
the initial Windows cold-cache acquisition hit HTTP `403` for the upstream
Scintilla archive before any compile/test step. The failed job was rerun once;
the same workflow then completed cleanly. This was recorded as an upstream
transport transient, not suppressed as a test failure.

| Remote evidence | Result |
| --- | --- |
| Windows x64 rerun | Job `101334175547` passed in 17m08s: acquisition, dependency/ACL, formatting/C layout, Debug/Safe, ABI/miscompile/SIMD, toolchain smoke, resource/graphics/presenter/native-shell/product, and two clean ReleaseSafe hashes. | The shipping Windows lane is green on the pushed commit `ded15d0f`. |
| Linux compile guard | Job `101334176218` passed in 11m36s across the full portable lane, including presenter compile checks and empty install proofs. | Linux remains CI portability evidence only; no Linux product artifact is emitted. |
| Remote quality status | Rerun green after the one documented upstream 403; no code change was needed. | Quality streak remains `1/1` for this bounded increment. |
