# Oleafly Zig Scientific AI IDE Spec Review Evidence

| Field | Value |
| --- | --- |
| Review window | 2026-09-03 to 2026-09-04 |
| Reviewed baseline | `3a499fb292c4e63bd90fbec33c7e2585494ace77` |
| Reviewed artifact | [Oleafly Zig Scientific AI IDE Design](2026-09-03-oleafly-zig-scientific-ai-ide-design.md) |
| Review mode | Seven challenger rounds, cross-contract repair, then two fresh closed-coverage passes |
| Completion bar | Zero open Critical, High, or Medium findings in each of two consecutive passes |
| Implementation state | No Zig production scaffold or dependency installation has started |

This report is a durable audit trail for the written specification. It is not
runtime evidence for an application that does not yet exist. Runtime claims
remain provisional until the T0 kill-switch probes in the design pass.

## 1. Acceptance oracle

| Requirement | Required observable evidence | Prohibited result |
| --- | --- | --- |
| Match the approved product | Every retained and removed capability maps to an explicit section and delivery slice | Scope quietly expands back into a generic publishing suite |
| Entire owned runtime in Zig | Executable ownership rule, dependency boundary, cutover inventory, and future Zig CI are explicit | A browser, Tauri, Rust, TypeScript, C#, or owned C/C++ runtime survives cutover |
| Fast, light, smooth, efficient | Reproducible startup, memory, GPU, input, display, idle, RDP, and distribution gates | A mean, splash frame, trimmed working set, missing trace, or worker process hides failure |
| Correct live render | Immutable source closure, cancellation, acceptance fence, exact artifact/SyncTeX mapping, and last-good behavior | Stale, partial, or wrong-source output appears current |
| Scientific honesty | Exact quantities, versioned identity, anchors, status freshness, denominators, and reproducible searches | A confidence score, binary float, absent provider result, or model answer becomes verified truth |
| Safe AI and tools | Typed least-authority tools, prompt-injection boundary, patch transaction, egress consent, and adapter provenance | Untrusted text grants authority, fetches a URL, or writes accepted source |
| Durable local-first data | Crash-consistent edits, migrations, conflicts, ACLs, retention, and exportable checkpoints | Silent overwrite, last-writer-wins science, hidden Git commit, or unrecoverable migration |
| Accessible, attractive native UX | Stable Evidence Instrument frame, UIA, WCAG-derived numeric floors, keyboard/reflow/locale contracts | Color-only state, inaccessible primary journey, or browser QA substituted for native QA |
| Valid publishing | One snapshot binds PDF, source, EPUB, RO-Crate, validators, and receipt | Mixed revisions, unsafe archive members, false accessibility claim, or EPUB-driven scope expansion |
| Enforceable delivery | Objective severity rubric, closed coverage, independent Pass A/B, evidence manifest, atomic commit and push | A retry, skip, downgrade, or partial retest preserves the streak |

## 2. Decision plateau record

The review compared the current C+ native design with keeping the legacy stack,
mainstream managed/native frameworks, specialist native components, and narrower
custom alternatives. A challenger changed the design only when it removed a
missed must-have or a material failure mode. The seven-round ceiling was chosen
because this is a high-impact architecture; empirical uncertainty is handed to
the reversible T0 probes rather than hidden behind more paper scoring.

| Round | Distinct angle and fresh primary evidence | Challenger or failure mode | Decision impact |
| --- | --- | --- | --- |
| 1 | Windows lifecycle, release health, ETW/PresentMon measurement semantics | Keep build 22621 and vague cold/warm/working-set gates | C+ retained; replaced obsolete support floor and made startup, memory, RDP, and presentation evidence non-gameable |
| 2 | Tectonic dependency reporting plus Win32 process, handle, Job, and AppContainer boundaries | Dependency-cache-only snapshot or ambient compiler tree | C+ retained; added full seed closure, bounded host fallback, acceptance fence, I/O quotas, and exact SyncTeX path map |
| 3 | SQLite numeric behavior, WAL, RFC 8785 JCS, and RO-Crate provenance | Canonical `REAL` values or a hash chain described as authorship proof | C+ retained; exact decimal/unit/uncertainty representation, monotonic order, honest hash semantics, and migration rollback added |
| 4 | Final MCP 2026-07-28 release, authorization changes, and tool security guidance | Generic shell/filesystem MCP plus model-mediated permission | C+ retained; added prompt-injection, egress, inbound-server, issuer/PKCE, patch, and multi-file crash-consistency boundaries |
| 5 | EPUB 3.3, EPUB Accessibility 1.1/1.2 status, WCAG 2.2, and EPUBCheck | Treat EPUBCheck or metadata presence as accessibility proof | C+ retained; added semantic/MathML conversion, discoverability report, human-check unknowns, and numeric native accessibility floors |
| 6 | Windows DACL, DPAPI, process creation, filesystem alias, and recovery failure modes | Inherited AppData permissions, ambiguous argv, or ordinary delete marketed as secure erase | C+ retained; added owner-only state, redacted diagnostics, exact process serialization, hard-link handling, and honest deletion/threat limits |
| 7 | Zig 0.16, Scintilla direct-access/threading, and MuPDF context/thread rules | Fully custom GPU editor or unsafe cross-thread/native ABI calls | No replacement satisfied maturity, size, accessibility, and schedule together; added C ABI exception fence, HWND-owner rule, per-surface latency proof, and kept T0 editor/PDF switch conditions |

Primary choice remains the C+ event-driven Win32/D3D11/Direct2D design. The
fallback is not a hidden hybrid: T0 switches Scintilla, PDF, composition, or the
Zig pin independently when a measured kill switch fails. Evidence strength is
strong for standards and failure boundaries, moderate for projected resource
budgets, and intentionally absent for runtime performance until T0.

## 3. Finding and repair ledger

Every item below met the design's Medium-or-higher threshold and reset the
streak to zero when found. “Closed” means the written contract was repaired;
runtime feasibility is still governed by its named T0 or slice proof.

| ID | Severity | Finding | Repair in design | State |
| --- | --- | --- | --- | --- |
| SR-01 | High | Precise decision scores had no reproducible matrix or seed in the repository | Removed false precision; durable challenger record and T0 evidence are authoritative | Closed |
| SR-02 | High | Windows 10/11 support floors included unserviced releases | Split compatibility/ESU and current serviced Windows 11 lanes; refresh before signing | Closed |
| SR-03 | High | Cold/warm, interactive, memory, and installer metrics were gameable | Defined process/frame/input points, 30-trial conditions, process-tree private memory, installed footprint, and anti-trimming rules | Closed |
| SR-04 | High | DXGI shell data could hide stale Scintilla child-HWND rendering; RDP used an impossible local photon promise | Added separate HWND/swap-chain correlation, missing-evidence rule, optical fallback, and controlled RDP comparator | Closed |
| SR-05 | Medium | GPU allocations and viewport matrix were not bounded | Added three resolutions and a formula over viewport, intermediate, tile, and other committed graphics bytes | Closed |
| SR-06 | High | Dynamic TeX dependency closure was underspecified | Added bounded full-root seed snapshot, external-root consent, `.fls`/makefile optimization, and unproven-closure state | Closed |
| SR-07 | High | Delayed watcher events could allow a stale compile to pass | Added off-thread acceptance barrier with current buffer sequences, file identities, and hashes | Closed |
| SR-08 | Medium | Edit cancellation could kill explicit publish; snapshot GC lifetime was absent | Separated interactive and pinned publish jobs; added reference-counted artifact roots and crash mark/sweep | Closed |
| SR-09 | High | IPC lacked peer authentication, queue limits, and flood behavior | Added DACL, one-launch secret, peer identity, credit backpressure, bounded rings, deadlines, and circuit breaker | Closed |
| SR-10 | Medium | Scintilla C++ exception/allocator and cross-thread boundaries were implicit | Added C-compatible status bridge, exception fence, ABI probes, and HWND-owner-only direct calls | Closed |
| SR-11 | High | Editor text could have two mutable truths and non-UTF-8 save could corrupt source | Defined one edit endpoint, ordered derived snapshots, hash resync, lossless encoding and newline policy | Closed |
| SR-12 | Medium | Hard links, case aliases, cloud placeholders, and non-atomic filesystems could fork buffers or weaken save invisibly | Added file identity ownership and explicit weaker-filesystem recovery decision | Closed |
| SR-13 | High | Host tool discovery and Windows command-line encoding could execute the wrong binary or wrong argv | Added canonical selection/fingerprint expiry, non-null application path, per-tool serializer corpus, and no shell | Closed |
| SR-14 | High | External-job disk output was unbounded | Added active-job I/O/output/log/free-space watchdog and regular-file output-handle validation | Closed |
| SR-15 | High | Canonical measurements could be stored as approximate binary floats | Added original decimal token, unit, uncertainty, significant figures, missingness, and calculation receipt | Closed |
| SR-16 | Medium | Event clock and hash chain could be mistaken for order, authorship, or tamper protection | Added monotonic sequence authority and explicit non-signature/same-user limitation | Closed |
| SR-17 | High | Ledger schema failure lacked a verified rollback protocol | Added backup, source hash/schema, transactional migration, integrity/chain/projection checks, and read-only forward handling | Closed |
| SR-18 | Medium | Source anchors and vector indexes lacked sufficient version namespace | Added file/syntax/macro context and model/tokenizer/quantization/dimension namespaces | Closed |
| SR-19 | Medium | Literature searches and scholarly status were not reproducible or retraction-aware enough | Added query/provider/cursor/result receipts and correction/retraction/unknown semantics | Closed |
| SR-20 | Medium | Model-assisted audits lacked drift and false-citation evaluation | Added versioned per-family precision/recall/abstention/variance/cost corpus and invalidation on model change | Closed |
| SR-21 | High | Prompt injection, model-supplied URLs, redirects, and provider output could become authority or egress | Added inert-data rule, broker-only authority, destination/data-class validation, TLS and response bounds | Closed |
| SR-22 | High | Patch paths, binary changes, and multi-file partial accept were incomplete | Added path/reparse/encoding/base checks plus staged crash-consistent transaction journal | Closed |
| SR-23 | High | Host-access external agents could bypass visible diff | Made Brokered default, used disposable worktree, quarantined live-project changes, and disallowed enforced receipts | Closed |
| SR-24 | High | MCP inbound exposure/auth and protocol status were ambiguous | Targeted final 2026-07-28, made inbound local server off by default, pipe/loopback/token only, and added issuer/resource/PKCE rules | Closed |
| SR-25 | High | Recovery manuscripts, logs, and dumps lacked concrete privacy boundaries | Added owner-only DACL, retention/delete UI, redacted opt-in bundle, and OS-managed WER disclosure | Closed |
| SR-26 | Medium | Recovery durability and recovery-time claims were unmeasured | Added one-second/256-KiB RPO bound and low-tier 100-MiB enumeration target | Closed |
| SR-27 | Medium | EPUB accessibility, MathML, and false-conformance handling were incomplete | Added EPUB Accessibility 1.1, semantic mapping, discoverability report, human unknowns, and 1.2-CR watch | Closed |
| SR-28 | Medium | Native UI lacked numeric contrast/focus/target and locale-resource gates | Added WCAG-derived values, UIA PDF/graph alternatives, resource-only UI prose, BiDi and locale completeness | Closed |
| SR-29 | Medium | Zotero/provider account and mutation authority were too implicit | Added off-by-default loopback connector, read-only default, mutation previews, and paid/key provider opt-in | Closed |
| SR-30 | High | Pack hashes could be fetched beside a compromised payload | Required an Oleafly-signed manifest trust root plus exact payload hash and upstream signature where available | Closed |
| SR-31 | Medium | Git could invoke repository helpers, hooks, prompts, or leak credentials | Added inert default environment and separately previewed host/network operations | Closed |
| SR-32 | High | Severity, closed coverage, independent second pass, legacy-state rollback, and dual CI were not enforceable | Added objective rubric, Pass A/B isolation, no-skip rule, migration protocol, and Zig-plus-legacy CI condition | Closed |
| SR-33 | High | The performance contract named a global `ReleaseFast` artifact even though Oleafly parses hostile input | Made `ReleaseSafe` the shipped and measured default; prohibited global safety removal and constrained any scoped exception to benchmarked, fuzzed non-trust code | Closed |
| SR-34 | High | A writable link from an external tool's build tree could corrupt the authoritative content-addressed store | Prohibited child-visible writable aliases; required independent read-only inputs, separate disposable outputs, re-hash, and immutable artifact ingestion | Closed |
| SR-35 | Medium | Qualitative low-tier/mainstream machines allowed silent hardware upgrades to hide regressions | Required exact hardware, firmware, thermal, display, power, and equivalence-calibration records | Closed |
| SR-36 | Medium | “Normalized unit” had no interoperable identity or dimensional-conversion rule | Preserved original spelling and added versioned UCUM identity, dimensional checks, exact factors, rounding provenance, and unresolved state | Closed |
| SR-37 | High | A raw copy of a live SQLite database could omit WAL state and invalidate migration rollback | Required a transactionally consistent Online Backup API or proved equivalent snapshot and independent open/integrity verification | Closed |
| SR-38 | High | Recovery-journal append or flush failure had no close-time safety behavior | Separated editor echo from durability acknowledgement and added persistent unprotected state plus save/export/repair/discard close gate | Closed |
| SR-39 | High | Portable distribution, stale signed metadata, binary mitigations, and release-CI trust were incomplete | Added Authenticode and signed archive metadata, anti-replay fields and key rotation, exploit-mitigation audit, immutable CI pins, least privilege, and protected signing | Closed |
| SR-40 | Medium | An evidence file cannot contain its own future commit or tree ID, and two pre-push passes cannot prove a not-yet-pushed GitHub render | Gave the manifest a non-self-referential path/hash inventory, bound tree and manifest hashes in the commit message, and moved commit/remote confirmation post-push with failure reopening the candidate | Closed |
| SR-41 | Medium | Local possession or indexing of a paper could be mistaken for redistribution permission in source or RO-Crate export | Added access-policy compliance, rights provenance and unknown state, default third-party payload exclusion, and explicit redistribution-basis review | Closed |
| SR-42 | Medium | EPUB conversion simultaneously said active content was sanitized and rejected, leaving artifact mutation semantics ambiguous | Made rejection the sole rule so unsafe content cannot be silently rewritten into a misleading successful export | Closed |
| SR-43 | Medium | Passing Pandoc `title` metadata duplicated the document H1 in the rendered QA artifact | Changed the deterministic preview recipe to `pagetitle`, preserving one semantic H1 while retaining a non-empty HTML title | Closed |
| SR-44 | Medium | The standalone preview left all article content outside a landmark, producing a full-page axe `region` failure | Wrapped the rendered document in one named `main` landmark and made the full axe audit, not a zero-rule filtered run, authoritative | Closed |
| SR-45 | Medium | Cross-document Markdown links resolved to missing `.md` files inside the standalone preview directory | Added a preview-only link rewrite to the corresponding generated HTML companion and made activation plus HTTP success part of browser QA | Closed |
| SR-46 | Medium | A wide findings table became a scrollable region with no keyboard focus target | Made every generated preview table focusable while preserving native table semantics and added keyboard-scroll reachability to the oracle | Closed |
| SR-47 | Medium | Chromium's implicit favicon request returned 404, violating the zero-failed-request browser oracle | Embedded a deterministic data-URI favicon in the standalone preview so the document performs no missing auxiliary fetch | Closed |

## 4. Source record

Primary sources used for changed decisions:

- [Windows 10 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-10-home-and-pro)
- [Windows 11 release health](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [PresentMon console metrics](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)
- [CreateProcess and handle inheritance](https://learn.microsoft.com/en-us/windows/win32/procthread/creating-processes)
- [Launch an AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [Tectonic compile and dependency options](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html)
- [Scintilla direct access](https://scintilla.org/ScintillaDoc.html)
- [MuPDF C threading model](https://mupdf.readthedocs.io/en/latest/reference/c/overview.html)
- [SQLite floating-point behavior](https://sqlite.org/floatingpoint.html)
- [SQLite Online Backup API](https://sqlite.org/backup.html)
- [UCUM unit specification](https://ucum.org/ucum)
- [RFC 8785 JCS](https://www.rfc-editor.org/rfc/rfc8785)
- [RO-Crate 1.3](https://www.researchobject.org/ro-crate/specification/1.3/index.html)
- [MCP 2026-07-28 release](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [MCP tool security considerations](https://modelcontextprotocol.io/specification/draft/server/tools)
- [EPUB 3.3](https://www.w3.org/TR/epub-33/)
- [EPUB Accessibility 1.1](https://www.w3.org/TR/epub-a11y-11/)
- [EPUBCheck](https://www.w3.org/publishing/epubcheck/)
- [WCAG 2.2](https://www.w3.org/TR/WCAG22/)
- [Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html)
- [MSIX package signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)

## 5. Final verification contract

The pre-push candidate is accepted only when both passes independently prove
every pre-push row below. A failed row resets the streak to zero and is added to
the finding ledger before repair. Commit identity and hosted rendering are then
confirmed from a fresh post-push session; failure there reopens the candidate,
requires a repair and new commit, and restarts the two-pass pre-push streak.

| Surface | Evidence and timing |
| --- | --- |
| Source integrity | Pre-push A/B: clean Pandoc parse with warnings fatal; standalone preview uses `pagetitle` rather than a duplicate title block and wraps content in one named `main`; balanced fences/tables; one H1; ordered numbered sections; no placeholder or unresolved internal file link |
| Requirement coverage | Pre-push A/B: deterministic phrase/section checks for Zig ownership, live render, retained EPUB, scientific model, AI diff, security/privacy, accessibility, migration, severity, and quality streak |
| Primary references | Pre-push A/B: every distinct HTTP(S) source returns a non-error response or a documented publisher-specific equivalent; redirects resolve |
| Browser structure | Pre-push A/B: separate fresh browser contexts, one H1, complete heading hierarchy, image loaded at natural size, internal companion links activate successfully, tables/code readable, no horizontal document overflow |
| Responsive and accessible preview | Pre-push A/B: 1264, 900, and 680 CSS-px viewports; keyboard traversal and focusable scroll regions; 200% zoom/narrow reflow; full axe audit including WCAG A/AA; no console or failed network request |
| Visual inspection | Pre-push A/B: title, status table, architecture image, performance table, security, EPUB, review protocol, references, and approval gate are readable and visually distinct |
| Git hygiene | Pre-push A/B: only the spec and this review evidence are staged; `.superpowers/` and unrelated user files are excluded; staged diff check is clean |
| Commit binding and remote proof | Post-push: `origin/main` resolves to the new commit; external evidence binds that commit to the reviewed tree; a fresh GitHub session renders both Markdown documents and the image |

The live catalog was checked on 2026-09-03 and confirmed the exact completion
scaffold [The quality streak loop](https://signals.forwardfuture.com/loop-library/loops/quality-streak-loop/): a failure is repaired and protected, then the consecutive-success count restarts.

## 6. Residual empirical decisions

No open Medium-or-higher design finding is intentionally accepted. The
following are not paper-approved facts and therefore remain explicit T0 gates:

- the exact Zig patch pin and compiler/ABI corpus;
- Scintilla accessibility, IME/BiDi, memory, and per-HWND latency on the matrix;
- MuPDF minimal-build size, hostile-corpus isolation, and cache behavior;
- signed MSIX/portable startup, memory, GPU, RDP, and idle budgets;
- SQLite power-loss recovery and ledger/search split behavior;
- dependency licenses, hashes, source offers, and packaged binary inventory.

Failure of one of these gates stops the next train or activates the documented
fallback. It does not get reclassified as a Low issue merely because the written
spec passed review.
