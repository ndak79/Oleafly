# TExFlow Zig Scientific AI IDE Spec Review Evidence

| Field | Value |
| --- | --- |
| Review window | 2026-09-03 to 2026-09-04 |
| Original reviewed baseline | `3a499fb292c4e63bd90fbec33c7e2585494ace77` |
| PDF ADR review baseline | T0.1 evidence commit `4898f33c88ca93e95295d2da5c4ffa367b90a8d6` |
| Reviewed artifact | [TExFlow Zig Scientific AI IDE Design](2026-09-03-oleafly-zig-scientific-ai-ide-design.md) |
| Review mode | Original seven challenger rounds; PDF decision reset with eight rounds; presenter reset with six rounds; lexer-boundary reset with five rounds; worker-isolation reset with seven rounds; worker-image/mitigation reset with seven rounds; exact TExFlow Windows-identity repair; cross-contract repair; Unicode/search/storage reset with thirty-four rounds; final full closed-coverage pass completed after SR-132 and the one-pass amendment |
| Completion bar | One full closed-coverage pass after the last repair, with zero open or newly discovered Critical, High, or Medium findings |
| Implementation state | T0.1 toolchain/evidence is complete; T0.2 implementation and native dependency acquisition have not started |
| Current written-spec streak | `1/1`; the final post-repair pass found no open or newly discovered Medium-or-higher finding |

This report is a durable audit trail for the written specification. It is not
runtime evidence for an application that does not yet exist. Runtime claims
remain provisional until the T0 kill-switch probes in the design pass.

**Quality-streak amendment, 2026-09-04.** The user explicitly replaced the
former dual-pass completion streak with one final clean pass. Multi-round
adversarial review, finding repair, closed coverage, and fresh evidence remain
mandatory. After any Medium-or-higher finding, the state resets to `0/1`; once
repaired, one new full closed-coverage pass must run from the beginning. Ledger
wording that names the legacy dual-pass gate records the superseded contract
that existed when those findings were discovered; it is historical evidence
and cannot override the amended admission rule.

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
| Enforceable delivery | Objective severity rubric, multi-round adversarial review, one fresh full admission pass after the last repair, evidence manifest, atomic commit and push | A retry, skip, downgrade, pre-repair verdict, or partial retest preserves the streak |

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
| 7 | Zig 0.16, Scintilla direct-access/threading, and the original MuPDF context/thread proposal | Fully custom GPU editor or unsafe cross-thread/native ABI calls | Retained the mature editor and native renderer; kept an empirical PDF switch condition. The later source-level error-ABI finding below invalidated MuPDF and reset only the PDF decision. |

Primary choice remains the C+ event-driven Win32/D3D11/Direct2D design. The
fallback is not a hidden hybrid: T0 switches Scintilla, PDF, composition, or the
Zig pin independently when a measured kill switch fails. Evidence strength is
strong for standards and failure boundaries, moderate for projected resource
budgets, and intentionally absent for runtime performance until T0.

### 2.1 PDF decision reset

The original broad review did not inspect MuPDF's macro-level error control
deeply enough. Once that High finding appeared, no earlier PDF pass counted.
The replacement search used a strict upstream-C-ABI gate plus the complete
render/text/search/geometry/link surface, then ran eight distinct rounds. The
final two rounds found no improvement and closed the paper decision only; T0.2
source reconstruction and runtime evidence remain mandatory.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | MuPDF `fz_try`/`fz_catch` definitions and documented error discipline | Required `setjmp`/`longjmp` cannot safely cross Zig frames without a forbidden owned C bridge; process isolation does not repair the ABI. MuPDF rejected. |
| 2 | PDFium, Windows.Data.Pdf, Poppler, and PoDoFo public feature surfaces | PDFium alone combined a direct upstream C ABI with render, text, search, character geometry, links, and progressive rendering. |
| 3 | Windows payload/dependency closure and deployment shape | Exact PDFium x64 artifact remained compatible with the footprint probe; framework and GLib/Cairo alternatives added broader runtime weight. |
| 4 | Thread ownership, cancellation, and latency failure modes | PDFium is admitted only with one engine-owning thread, progressive pause/cancel, bounded priority queues, and an outer worker watchdog. |
| 5 | Active-content, sandbox, servicing, and hostile-document surface | V8/XFA/form-fill initialization and action execution are forbidden; AppContainer isolation and a malformed/hang corpus became hard gates. |
| 6 | Release provenance, source identity, license inventory, and reproducibility | The community attestation proves a build event, not official source equivalence; independent exact-commit reconstruction is required before architecture admission. |
| 7 | Specialist alternatives and a doubled performance-weight sensitivity run | No candidate cleared both mandatory gates or removed a material failure mode: first final no-improvement round. |
| 8 | Direct PE import/export inventory, disabled-feature stubs, and doubled provenance-weight sensitivity | PDFium remained conditional on reconstruction and later protected shipping build; second consecutive no-improvement round. |

### 2.2 Presentation decision reset

Deeper API review invalidated the original combination of flip-discard and
partial presentation. Six distinct rounds compared the current choice, the
mainstream flip-sequential path, and the Windows 11 composition specialist.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | `DXGI_SWAP_EFFECT` and `DXGI_PRESENT_PARAMETERS` contracts | `FLIP_DISCARD` explicitly forbids partial presentation; the former combination was impossible and the streak reset. |
| 2 | Dirty/scroll bandwidth, power, and Remote Desktop guidance | Sparse scientific-document updates favor `FLIP_SEQUENTIAL` with valid dirty/scroll metadata. |
| 3 | DirectFlip, independent-flip, reverse-composition, and waitable-latency behavior | Full-redraw `FLIP_DISCARD` may still win on some modern hardware, so it remains a measured challenger rather than being mislabeled partial. |
| 4 | Separate Scintilla child HWND and mixed-API constraints | A flip chain is safe on its own HWND; GDI or another presenter may not target that same HWND. |
| 5 | Windows 10, WARP/RDP, and composition-swapchain requirements | Flip-sequential is the compatible baseline; the composition API remains a Windows 11/WDDM specialist and cannot replace the matrix. First final no-improvement round. |
| 6 | Two-buffer dirty-history intersections, first frame, resize, DPI/adapter change, occlusion, and device loss | Required coherent-history tracking and full redraw on uncertainty. Weighted sensitivity over correctness, latency, power/bandwidth, compatibility, and complexity retained flip-sequential; second no-improvement round. |

### 2.3 Lexer trust-boundary reset

The editor decision was narrowed without reopening the already rejected custom
editor. Five rounds compared shipped Lexilla, isolated Lexilla, and Scintilla's
documented container-styling path.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | Scintilla 5.6.6 `SCI_SETILEXER(NULL)`/`SCN_STYLENEEDED` contract | A Zig-owned container lexer can apply byte styles without an `ILexer5` C++ shim. |
| 2 | Exact Scintilla/Lexilla source archives and LaTeX/BibTeX lexer/test inventory | The mature lexers are useful comparison evidence, but shipping their catalogue/helpers is unnecessary for two bounded markup modes. |
| 3 | Lexilla release history and lexer memory-safety failure class | Even a minimal native lexer expands the privileged C++ input surface; no LaTeX-specific vulnerability is asserted, but the boundary must not promise all parsers are sandboxed. |
| 4 | `ILexer5`/`IDocument`, hidden-worker, asynchronous-style, and full-custom-editor alternatives | Isolating Lexilla adds a C++ document adapter or hidden editor/IPC latency; replacing Scintilla loses mature IME/UIA behavior. The bounded Zig container scanner is the smaller seam: first final no-improvement round. |
| 5 | Long-line, invalid UTF-8, random-edit convergence, line-state checkpoints, corpus differential, latency, and binary-size sensitivity | Retained Scintilla as the named UI TCB, made the Zig scanner non-semantic/non-authoritative, and kept Lexilla test-only; second no-improvement round. |

### 2.4 PDF tile-handoff trust reset

The former reusable worker-write/UI-read section pool had no enforceable
write-revocation point. Six distinct rounds compared that design, bounded pipe
copy, and generation-unique one-shot sections with a UI-private upload buffer.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | File-mapping access rights and coherent cross-process views | `FILE_MAP_READ` protects the UI view from UI writes but does not make the underlying object immutable while another view can write; direct GPU upload was rejected. |
| 2 | Mapping-object, handle, and view lifetime | Closing the worker's declared handle does not unmap an existing view or destroy an object retained by another handle; close acknowledgement is not revocation. |
| 3 | Shared-memory synchronization and crash/cancel states | Added an authenticated broker-owned one-way state machine, exact generation/digest validation, bounded in-flight credits, and fail-closed retirement. |
| 4 | Overlapped named-pipe copy alternative | Pipe copy naturally lands in UI-owned memory and remains the safe fallback, but adds framing/copy/queue pressure that must be measured on the same tile trace. |
| 5 | D3D11 system-memory upload and resident-cache accounting | A two-slot private staging pool is sufficient for bounded upload; transport sections are capped separately from the GPU LRU. Security/correctness-first and doubled-performance sensitivities both retained one-shot sections as baseline: first final no-improvement round. |
| 6 | `DuplicateHandle`, process-local unmapping, retained writer, malicious-pixel, and stale-generation attacks | A worker can retain or duplicate write authority, so the section object is never reused and pixels remain untrusted derived data; only a private verified copy reaches D3D. No challenger removed this limit with less authority or cost: second final no-improvement round. |

### 2.5 Native campaign and capture decision reset

The prior wording neither froze a reproducible configuration design nor proved
that a screenshot represented the desktop the user saw. Seven distinct rounds
compared a naive/full Cartesian matrix, a constrained covering array, DXGI
Desktop Duplication, Windows Graphics Capture, `PrintWindow`, screen-DC capture,
and instrumented/camera evidence. Correct visible output, support-floor coverage,
fail-closed timing, and reproducibility were weighted above implementation
convenience.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | T0.1's explicit hardware-baseline deferral plus NIST combinatorial-testing guidance | Moved exact machine ownership to T0.2; selected a predeclared constrained mixed-strength array and named repeated benchmark cells instead of either an infeasible Cartesian product or an undocumented sample. |
| 2 | DWM-composed desktop fidelity, visible popup/overlay behavior, and window-only capture | `IDXGIOutput5::DuplicateOutput1` became the authoritative visual source; WGC remains diagnostic because a window surface is not always the visible desktop and secondary-window inclusion is unavailable on the Windows 10 floor. |
| 3 | Windows 10 22H2 API floor, direct HWND/monitor targeting, WinRT ABI surface, and Zig maintenance cost | DXGI 1.5 satisfies the supported floor through the existing narrow graphics ABI; WGC's WinRT interop adds a larger QA-only binding without closing popup/overlay coverage. |
| 4 | QPC frame metadata, protected-content indication, rotation, multi-output timing, access loss, desktop switch, and RDP disconnect | Required per-output identity, finite waits, explicit re-creation, no cross-output timestamp fiction, and fail-closed metadata; WGC did not remove these campaign failure modes. |
| 5 | HDR/WCG capture and SDR review artifacts | `DuplicateOutput1` can request high-color scan-out formats; the harness must preserve raw high-color evidence and produce an explicitly tone-mapped review copy. Plain `DuplicateOutput` is an SDR-only fallback and cannot close an HDR row. |
| 6 | `PrintWindow`, BitBlt/screen-DC, app framebuffer, and browser screenshot challengers | `PrintWindow` is synchronous and asks the target app to render; the other paths lack the required compositor/frame contract. None can replace DXGI: first final no-improvement round. |
| 7 | Measurement perturbation, known-pixel calibration, capture/tool disagreement, fixed matrix rows, and privacy-safe machine identity | Isolated visual trials from timed trials, added calibration and immutable row manifests, and made disagreement/unavailable hardware unverified. Doubling complexity or HDR weight did not change the leader; second final no-improvement round. |

Sensitivity checks doubled implementation-complexity weight and then doubled
HDR/color weight. DXGI remained the only candidate that covered the visible
desktop, support floor, and timestamped fail-closed evidence together; WGC is a
reversible diagnostic rather than a silent fallback.

### 2.6 Worker-isolation decision reset

The earlier phrase “zero-capability AppContainer” conflated an empty named
capability list with an explicit-only authority set. Microsoft documents that a
regular AppContainer can still use resources granted to `ALL APPLICATION
PACKAGES`; the isolation decision and all former clean verdicts were therefore
invalidated. Seven distinct rounds compared regular AppContainer, LPAC,
restricted-token/Job containment, and the newer composable sandbox API.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | `TokenIsLessPrivilegedAppContainer` semantics and Windows-wide `ALL APPLICATION PACKAGES` ACLs | A regular AppContainer has a larger ambient system-read surface even with no named capability; the former “only brokered resources” claim was false and the streak reset. |
| 2 | Official AppContainer/LPAC launch sequence | Imperative LPAC creation has a stable Win32 mechanism: add `PROC_THREAD_ATTRIBUTE_ALL_APPLICATION_PACKAGES_POLICY=PROCESS_CREATION_ALL_APPLICATION_PACKAGES_OPT_OUT` beside security capabilities. |
| 3 | Package-SID DACL sharing plus profile/TEMP behavior | Exact role-SID ACLs can expose the pipe/runtime resources while the writable profile remains explicit untrusted scratch; LPAC does not require a broad named capability for those grants. |
| 4 | Registry, COM, fonts, PDFium, and SQLite compatibility failure surfaces | LPAC intentionally loses ordinary AppContainer registry/COM/system-resource access. The complete PDF/font/search corpus must run with sealed explicit resources and no `registryRead`/`lpacCom`; incompatibility is a T0 rejection, not a reason to weaken the label. |
| 5 | 2026 experimental Create Process in Sandbox API | It is Windows 11-only, explicitly experimental, has no public header, and rejects inherited handles; it cannot preserve the Windows 10 floor or the authenticated two-handle bootstrap, so it remains a future challenger rather than the baseline. |
| 6 | Regular AppContainer, restricted token, Job-only, and LPAC fault oracles | LPAC removes AAP while retaining the smaller ARAP/package-SID baseline. Token queries plus AAP, ARAP, and exact-role canaries make all three authorities observable: first final no-improvement round. |
| 7 | Doubled compatibility/implementation-cost sensitivity | Compatibility cannot justify hiding ambient authority. Manual LPAC remains the smallest supported baseline, with its ARAP surface inventoried rather than called zero; failure reopens the worker architecture instead of silently falling back: second final no-improvement round. |

### 2.7 Worker-image and mitigation decision reset

The isolation repair exposed a second pre-entry boundary. Windows performs
load-time dependency mapping and DLL initialization before application argument
dispatch, so one UI/worker image could not honestly promise Win32k lockdown
while statically linking Scintilla and importing UI/graphics DLLs. Seven rounds
compared the former single image, delayed/runtime linking, one shared headless
worker, dedicated role images, and framework/service alternatives while also
freezing the mitigation policy.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | Windows load-time linking, DLL initialization, and pre-start mitigation order | UI imports can enter the address space before Zig role dispatch; the former `TExFlow.exe --worker=*` baseline and its Win32k claim were incompatible, so the streak remained reset. |
| 2 | Runtime-loading every UI dependency from one executable | It can avoid load-time UI DLLs but still maps the broad UI code image, complicates a large Win32 ABI surface, and weakens static import oracles. It is not the smallest trusted boundary. |
| 3 | One separate headless executable shared by PDF and science | It removes Scintilla/UI imports, but maps both roles' owned code and complicates exact per-role executable ACLs. It remains a packaging challenger. |
| 4 | Dedicated Zig UI, PDF-worker, and science-worker PE images | Role images give the smallest import/module/code and ACL closure, allow static Scintilla only in the UI, and improve worker startup/working-set falsifiability. Shared Zig modules remain source-shared. |
| 5 | Windows App Service/out-of-process COM and the experimental sandbox API | Framework/service variants add packaging or COM/runtime authority, and the experimental API still breaks the Windows 10/two-handle contract. They do not improve the boundary. |
| 6 | Exact pre-start mitigation flags, recursive PE/load-config evidence, and full PDF/font/search compatibility | Froze a non-negotiable DEP/SEHOP/ASLR/heap/handle/Win32k/extension/dynamic-code/font/image/child baseline; separated normal versus strict CFG and capability-conditioned CET so a header bit cannot masquerade as coverage: first final no-improvement round. |
| 7 | Doubled package-size and servicing-complexity sensitivity | The small role PEs remain inside the existing payload/compression gates and let MSIX/release manifests update them atomically. No size saving justified remapping UI code or silently dropping a mitigation: second final no-improvement round. |

### 2.8 Unicode, search, and trusted-presentation decision reset

Removing worker-authored snippets exposed the larger question: whether one
shared, versioned Zig text pipeline and descriptor-free search boundary still
beat OS services, specialist Unicode libraries, stored-content FTS, richer FTS
metadata, a trusted offset cache, duplicate wide canonical rows, or unused
identity copies in the worker. Thirty-four distinct rounds used current primary API/source
contracts. Mandatory scientific soundness and deterministic all-Zig ownership
precede the sensitivity weights: trust/correctness 30%, versioned all-Zig
determinism 20%, interactive latency 20%, resident/on-disk footprint 15%, and
maintenance 15%.

| Round | Fresh angle/evidence | Result and decision impact |
| --- | --- | --- |
| 1 | SQLite's `unicode61` version and diacritic behavior against Unicode 17/UAX #29/#15 | Unicode-6.1 segmentation and accent removal contradicted modern multilingual/Vietnamese identity; the streak reset and a generated Zig `texflow17` tokenizer became mandatory. |
| 2 | UIA TextUnit semantics, original UTF-8 source identity, normalization stability, controls, and BiDi | Froze half-open source-byte anchors, exact Character/Word/Format/Line/Paragraph/Page semantics, never-normalized source, and visible escaping instead of inheriting OS-version behavior. |
| 3 | FTS5 v2 tokenizer ABI, callback modes, query grammar, and adversarial resource expansion | Added the `fts5_api.iVersion >= 3`/tokenizer-v2 gates, one literal-AND query string, shared profile/table hash, and field/token/scratch/transaction caps. |
| 4 | Worker-authored snippet, markup, and byte-range trust | UTF-8 validity alone could not establish canonical provenance; all presentation bytes moved into the trusted broker. |
| 5 | Valid-occurrence cherry-picking, field/ordinal ambiguity, and snippet determinism | The broker now tokenizes every frozen canonical field, proves returned-row soundness, and alone chooses the bounded deterministic window. |
| 6 | FTS5 `xInst` offsets versus the broker work already required | Worker hit descriptors removed no trusted work and enlarged wire/ABI/fuzz surfaces, so the worker reply became exactly `(entity_uuid, rank_f64_le)`. |
| 7 | Floating rank representation, tie order, and false quantitative meaning | Froze canonical finite binary64 little-endian encoding, signed-zero handling, binary UUID tie-break, and lexical-feasibility labeling. |
| 8 | Worker false negatives/rank manipulation plus missing search-specific latency, memory, database-size, rebuild, and cancellation gates | Sound returned rows do not prove completeness. Added exact no-negative-evidence copy, canonical-ledger completeness rules, the 10,000-entity/128-MiB `W6-search` oracle, and a preregistered `detail=full`/`column`/`none` reversible spike. |
| 9 | Current ICU data slicing, Windows `NormalizeString`, utf8proc 2.11.3, and libgrapheme 3.0.0 APIs | ICU/Windows add runtime/version/footprint drift; utf8proc lacks UAX #29 word segmentation in its public surface; libgrapheme lacks the required normalization/full-case-fold pipeline. Combining either specialist with custom code is larger and less coherent than one generated Zig pipeline. |
| 10 | Persistent trusted token-offset mirror/cache versus bounded off-UI re-tokenization; doubled latency and then footprint weight | A trusted offset mirror duplicates derived state, expands invalidation and memory, and still cannot prove worker completeness. The current-query UI may retain its already bounded final snippets, but no persistent occurrence cache enters T0.2. Descriptor-free lazy validation remained the then-current leader. |
| 11 | FTS5 default stored-content behavior versus current contentless-delete support | The default table copies all four canonical text fields although the broker, not FTS, renders them. SQLite 3.53.4 supports contentless-delete update/delete, so the design moved to `content=''`, `contentless_delete=1`, `columnsize=1`, a small UUID/rowid map, and no duplicate source corpus. |
| 12 | Contentless full-column update semantics versus the 2-MiB logical-message cap | One authenticated 4-MiB blob would violate IPC. A begin/four bounded field-message/commit protocol assembles at most one entity and applies all columns atomically without increasing the common message limit. |
| 13 | Database-thread saturation, SQLite progress semantics, tokenizer callbacks, and cancel arrival | A single pipe/database loop could not receive cancellation while inside SQLite. Split one authenticated control-I/O thread from the sole SQLite thread; progress and tokenizer checks observe generation/deadline atomics without cross-thread connection use. |
| 14 | Positive-row publication, hostile empty replies, title controls, cold search, and storage-sidecar accounting | Canonical identity alone did not prove a query match, and `search.db` length alone was gameable. Rows now publish only after broker literal-AND proof; exact epistemic states, bounded safe titles, `H`-based endpoints, first-use latency, and recursive logical/allocated root gates replaced the ambiguous contract. |
| 15 | External-content/default-content FTS and `columnsize=0` against the repaired contentless-delete design | External/default content reintroduces duplicate bytes or synchronization risk; contentless `columnsize=0` removes BM25 document-length data. None improves the mandatory trust/rank/footprint combination. |
| 16 | Per-field FTS rows, a bespoke Zig inverted index, and a persistent trusted occurrence mirror under doubled maintenance and latency weights | Per-field rows complicate cross-field literal-AND/BM25 identity, a bespoke index recreates mature transactional/search machinery, and a trusted mirror still duplicates invalidation state. Bounded contentless-delete FTS plus broker proof remained the leader. |
| 17 | Canonical presentation re-tokenization on the ledger writer, WAL read-mark lifetime, and concurrent scientific commits | Even two-millisecond CPU yields cannot bound one SQLite fetch or prevent a long read snapshot from delaying checkpoints. Added one trusted query-only lane that copies one entity, finalizes before tokenization, and rechecks watermark/revision before publication. |
| 18 | Same-writer interleaving, a persistent canonical presentation cache, and a short-lived query-only connection | Same-writer fetches retain head-of-line risk; a persistent cache duplicates invalidation-sensitive canonical text. The one-entity read-only lane has the smaller authority/state surface and no WAL reader across yields: first final no-improvement round. |
| 19 | Doubled memory/maintenance weights plus append/checkpoint/search race ordering | One <=4-MiB owned snapshot and one query-only connection remain inside the existing caps; removing them moves unbounded work back to the writer or UI. No challenger improves latency without duplicating canonical state: second final no-improvement round. |
| 20 | SQLite complete-row encoding against the two-MiB trusted-ledger limit and four-MiB canonical entity | A wide entity projection cannot satisfy both limits; the storage design was not implementable at its required boundary, so the streak reset. |
| 21 | Raise ledger row/heap limits, chunk duplicate event/projection text, or store immutable content once and reference it | Raising limits weakens fault bounds and still duplicates at least 256 MiB for the 128-MiB corpus; chunking both copies preserves that footprint. Project-scoped content chunks plus typed event/projection references keep small rows, atomicity, and canonical bytes with less storage. |
| 22 | SQLite chunk table versus external blob files and a second content database | External or second-database content cannot join the event/projection commit atomically and adds path, backup, and crash states. Ordered <=256-KiB rows inside `ledger.db` retain one SQLite transaction and the existing backup boundary. |
| 23 | Doubled latency/complexity weights, read amplification, dedup collision handling, and four-MiB presentation | Four bounded fields require at most sixteen chunk rows; one short snapshot plus streaming hash/byte comparison stays inside the existing presentation and memory gates. A wide-row alternative is still invalid at the two-MiB limit: first final no-improvement round after the storage repair. |
| 24 | Missing/reordered/cross-project chunks, rollback orphans, historical retention, backup/export, and 256-MiB corpus sensitivity | Transactional insertion prevents new dangling refs, the project-scoped key plus full byte comparison rejects collision aliasing, immutable event refs prevent unsafe garbage collection, and complete-root measurement exposes overhead. No challenger improves atomicity, footprint, and failure closure together: second final no-improvement round. |
| 25 | Exact DOI/citekey/provider columns in the worker rowid map versus the actual T0.2 lexical feature surface | T0.2 has no exact-ID candidate union, so copying these values adds unbounded storage/synchronization state with no reachable behavior. They were removed from the worker. |
| 26 | Bounded identity columns now for forward compatibility versus ledger-only identities until T3.1 | Prebuilding an unused schema still creates invalidation and privacy surface. The disposable index is rebuildable, so T3.1 can add its exact bounded identity representation only when the candidate union is specified. |
| 27 | Doubled exact-lookup latency weight against a UUID-only rowid map | There is no promised exact-ID lookup journey in T0.2; retaining unseen columns cannot improve its measured lexical endpoints. Canonical ledger lookup remains available to trusted later code: first final no-improvement round after removal. |
| 28 | Schema migration, rebuild cost, worker compromise, and future rank-fusion sensitivity | Rebuilding the derived namespace from canonical IDs at T3.1 is simpler than migrating premature worker copies, and a compromised worker receives fewer identifiers. No challenger improves current function or future migration: second final no-improvement round. |
| 29 | Hostile whitespace/control ordering, BiDi isolation bytes, title fallback, and elision accounting | TAB/CR/LF were simultaneously C0-to-escape and whitespace-to-collapse; hashes could bless incompatible displays. Froze one Unicode-17 transform, exact ASCII escape atoms, layout-only direction isolation, U+2026 accounting, and canonical UUID fallback. |
| 30 | Hidden Unicode isolate insertion versus DirectWrite layout isolation and visible ASCII control atoms | Embedding isolates changes display bytes/ranges and can leak into accessibility or copy. Layout isolation preserves the exact audited UTF-8 string and range map: first final no-improvement round after the presentation repair. |
| 31 | Doubled visual/latency weights plus all-whitespace, control-dense, 2-KiB, 256-grapheme, and 8-KiB boundary cases | The streaming transform is linear, bounded before allocation, deterministic across UIA/rendering, and retains a usable untitled identity. No alternative improves safety or user clarity without hidden bytes or ambiguity: second final no-improvement round. |
| 32 | Null versus empty content, zero-chunk records, field ordering, and replay digest ambiguity | Typed prose did not freeze bytes. Added exact tags, zero/hash rules, chunk cardinality, and domain-separated field/entity digests over fixed-width little-endian metadata. |
| 33 | Rely only on the authenticated frame MAC versus retain deterministic content/field/entity hashes | The MAC authenticates transport but is session-specific and cannot drive rebuild fixtures or stored-reference validation. Separate deterministic digests retain offline integrity and reproducibility: first final no-improvement round. |
| 34 | Doubled hashing/maintenance weights plus empty, exact-chunk, one-byte-over, reorder, and mixed-revision falsification | Streaming SHA-256 adds bounded linear work already required for content integrity; removing any binding creates alias/replay states. No smaller encoding closes the same oracle: second final no-improvement round. |

Doubling latency favors `detail=full` and bounded off-UI streaming; doubling
footprint makes contentless `detail=column`/`none` credible challengers but
cannot waive rank equivalence, update/delete behavior, latency, or a fresh
reviewed delta. Doubling maintenance weight still retains the generated Zig
pipeline and contentless-delete FTS because neither specialist Unicode library
covers the required profile and neither external content nor a custom index
reduces total ownership. The bounded query-only presentation lane survives the
same sensitivity because removing it reintroduces writer/WAL head-of-line work
while a persistent cache costs more state. The decision has therefore reached the paper plateau;
empirical detail-mode uncertainty is isolated to the reversible T0.2 spike
rather than hidden as an implementation choice. The project-scoped single-copy
content table also survives doubled latency, footprint, and maintenance weights:
at most sixteen bounded rows reconstruct the worst-case entity, while every
wide-row or duplicate-text challenger either violates the trusted connection
limit or exhausts the canonical-root budget. Removing exact identifiers from
the lexical worker remains dominant under the same sensitivity because it drops
state and disclosure while changing no T0.2 result; the derived namespace can be
rebuilt when T3.1 actually owns exact-ID fusion.

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
| SR-10 | Medium | Scintilla C++ exception/allocator and cross-thread boundaries were implicit | Required the upstream status-returning direct function and upstream exception fence, independent ABI probes, and HWND-owner-only direct calls | Closed |
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
| SR-30 | High | Pack hashes could be fetched beside a compromised payload | Required a TExFlow-signed manifest trust root plus exact payload hash and upstream signature where available | Closed |
| SR-31 | Medium | Git could invoke repository helpers, hooks, prompts, or leak credentials | Added inert default environment and separately previewed host/network operations | Closed |
| SR-32 | High | Severity, closed coverage, the then-required independent repeat, legacy-state rollback, and dual CI were not enforceable | Added objective rubric, the then-current repeat isolation, no-skip rule, migration protocol, and Zig-plus-legacy CI condition | Closed |
| SR-33 | High | The performance contract named a global `ReleaseFast` artifact even though TExFlow parses hostile input | Made `ReleaseSafe` the shipped and measured default; prohibited global safety removal and constrained any scoped exception to benchmarked, fuzzed non-trust code | Closed |
| SR-34 | High | A writable link from an external tool's build tree could corrupt the authoritative content-addressed store | Prohibited child-visible writable aliases; required independent read-only inputs, separate disposable outputs, re-hash, and immutable artifact ingestion | Closed |
| SR-35 | Medium | Qualitative low-tier/mainstream machines allowed silent hardware upgrades to hide regressions | Required exact hardware, firmware, thermal, display, power, and equivalence-calibration records | Closed |
| SR-36 | Medium | “Normalized unit” had no interoperable identity or dimensional-conversion rule | Preserved original spelling and added versioned UCUM identity, dimensional checks, exact factors, rounding provenance, and unresolved state | Closed |
| SR-37 | High | A raw copy of a live SQLite database could omit WAL state and invalidate migration rollback | Required a transactionally consistent Online Backup API or proved equivalent snapshot and independent open/integrity verification | Closed |
| SR-38 | High | Recovery-journal append or flush failure had no close-time safety behavior | Separated editor echo from durability acknowledgement and added persistent unprotected state plus save/export/repair/discard close gate | Closed |
| SR-39 | High | Portable distribution, stale signed metadata, binary mitigations, and release-CI trust were incomplete | Added Authenticode and signed archive metadata, anti-replay fields and key rotation, exploit-mitigation audit, immutable CI pins, least privilege, and protected signing | Closed |
| SR-40 | Medium | An evidence file cannot contain its own future commit or tree ID, and no pre-push pass can prove a not-yet-pushed GitHub render | Gave the manifest a non-self-referential path/hash inventory, bound tree and manifest hashes in the commit message, and moved commit/remote confirmation post-push with failure reopening the candidate | Closed |
| SR-41 | Medium | Local possession or indexing of a paper could be mistaken for redistribution permission in source or RO-Crate export | Added access-policy compliance, rights provenance and unknown state, default third-party payload exclusion, and explicit redistribution-basis review | Closed |
| SR-42 | Medium | EPUB conversion simultaneously said active content was sanitized and rejected, leaving artifact mutation semantics ambiguous | Made rejection the sole rule so unsafe content cannot be silently rewritten into a misleading successful export | Closed |
| SR-43 | Medium | Passing Pandoc `title` metadata duplicated the document H1 in the rendered QA artifact | Changed the deterministic preview recipe to `pagetitle`, preserving one semantic H1 while retaining a non-empty HTML title | Closed |
| SR-44 | Medium | The standalone preview left all article content outside a landmark, producing a full-page axe `region` failure | Wrapped the rendered document in one named `main` landmark and made the full axe audit, not a zero-rule filtered run, authoritative | Closed |
| SR-45 | Medium | Cross-document Markdown links resolved to missing `.md` files inside the standalone preview directory | Added a preview-only link rewrite to the corresponding generated HTML companion and made activation plus HTTP success part of browser QA | Closed |
| SR-46 | Medium | A wide findings table became a scrollable region with no keyboard focus target | Made every generated preview table focusable while preserving native table semantics and added keyboard-scroll reachability to the oracle | Closed |
| SR-47 | Medium | Chromium's implicit favicon request returned 404, violating the zero-failed-request browser oracle | Embedded a deterministic data-URI favicon in the standalone preview so the document performs no missing auxiliary fetch | Closed |
| SR-48 | High | The approved spec still named MuPDF after deeper review proved its mandatory error macros unsafe across a strict Zig-only ABI; architecture, threading, preview, roadmap, licensing, references, and residual gates contradicted the new plan | Added the dated PDF ADR, selected conditional PDFium, propagated single-engine-thread/BGRx/source-reconstruction/security/release gates through every affected section, and retained MuPDF only as rejected history | Closed |
| SR-49 | Medium | Review metadata still claimed no Zig scaffold existed after T0.1 had already completed | Split the original and PDF-ADR baselines and stated the exact T0.1-complete/T0.2-not-started boundary | Closed |
| SR-50 | High | Behavioral equivalence alone could not exclude dormant or unexercised code in the unsigned community PDFium DLL, yet the draft still allowed that DLL in the admitted worker | Demoted the community DLL to a provenance/comparison oracle; required Task 5 and every admitted runtime/security probe to load only the sealed exact-source reconstruction and reject the community digest | Closed |
| SR-51 | High | The first T0.2 plan executed PDFium and malformed inputs during Task 2, before Task 5 had proved the AppContainer boundary | Made acquisition/reconstruction/ABI comparison static-only; required a harmless Zig no-engine worker to pass real isolation negatives before a fresh worker may load the reconstructed DLL; prohibited all execution of the community DLL | Closed |
| SR-52 | Medium | The PDF replacement decision omitted the existing requirement for bounded annotation metadata/geometry used by evidence anchors | Added annotation surface to the engine ADR and required static ABI plus contained runtime corpus coverage | Closed |
| SR-53 | Medium | The phrase “the bridge catches exceptions” could require a forbidden TExFlow-owned C++ shim even though Scintilla already exposes an upstream status-returning direct entry whose Win32 message path catches exceptions | Named `SCI_GETDIRECTSTATUSFUNCTION`, made the exception fence explicitly upstream, and prohibited any TExFlow C/C++ bridge | Closed |
| SR-54 | Medium | The product layout required Source+PDF down to 761 logical px while the reviewed 480/360-DIP pane minima plus rail/divider cannot fit there | Aligned spec and T0.2 plan on >=1180 tri-canvas, 880-1180 dual-pane, 760-879 single-focus switcher, and an honest unsupported-width statement below 760 | Closed |
| SR-55 | High | The science AppContainer both processed derived/untrusted data and owned writable `ledger.db`; compromise could rewrite the entire hash chain within its granted directory | Moved canonical SQLite ownership to a narrow trusted broker boundary in the UI process, denied every worker the ledger ACL root, and limited the science worker to authenticated immutable projection records plus a separate disposable-search directory | Closed |
| SR-56 | Medium | After removing ledger access, a compromised search worker could still return invented IDs, stale watermarks, or snippets that the UI might treat as canonical | Bound batches/replies to project, sequence/hash watermark, and generation; required broker revalidation of every canonical entity ID and explicit derived labeling for snippets, scores, and rank | Closed |
| SR-57 | High | An unpredictable pipe name plus a current-user generic-write ACE still allowed a same-user process to enumerate/race the name or gain `FILE_CREATE_PIPE_INSTANCE`, creating a denial/interception surface before HMAC rejection | Made internal worker pipes single-instance and prohibited generic-write/create-instance rights. SR-87 later corrected the incomplete package-SID-only repair: the protected DACL now has mirrored exact-current-logon and exact-role-package ACEs with only the five enumerated client rights, while peer authentication and the honest same-user-malware exclusion remain. | Closed |
| SR-58 | High | The isolation prose treated a classic AppContainer as having no writable filesystem even though Windows always provisions writable profile/TEMP storage; a compromised parser could leave cross-generation residue | Declared the profile as untrusted scratch, required delete/recreate and empty/reparse/ACL verification around every worker generation, prohibited loading any runtime/config/input from it, quarantined failed cleanup, and kept science search in a separate explicit store | Closed |
| SR-59 | High | The editor UIA contract did not define `WM_GETOBJECT` coexistence or provider teardown; a TExFlow subclass could suppress Scintilla's MSAA path or leave callbacks targeting a destroyed document | Froze the Document/Text2/TextEdit/Scroll surface, forwarded every non-UIA-root object ID and unmodified parameters, required STA/MTA threading rules, physical-screen geometry, subscription-aware coalescing, and explicit provider/event-map disconnect before subclass/HWND/COM teardown | Closed |
| SR-60 | Medium | The idle contract counted TExFlow render/poll timers but not Scintilla's own caret, dwell, scroll, widen, and idle-styling `SetTimer` paths; a hidden editor could therefore violate the zero-wake promise while every app-owned timer appeared clean | Included child-HWND tickers in the energy oracle, allowed and separately recorded only the visible focused system-caret blink, and required state-preserving disable/cancel/drain plus ETW proof of zero periodic editor wake after occluded quiescence | Closed |
| SR-61 | High | The design simultaneously required `DXGI_SWAP_EFFECT_FLIP_DISCARD` and dirty-rectangle partial presentation even though that swap effect explicitly does not support partial presentation; merely changing the enum could also expose stale pixels without multi-buffer history tracking | Made two-buffer `FLIP_SEQUENTIAL` plus proved coherent dirty/scroll presentation the sparse-document baseline; required full redraw after first frame or any history-invalidating transition, prohibited mixed presenters on its HWND, and retained `FLIP_DISCARD` only as an empty-metadata full-redraw measured challenger | Closed |
| SR-62 | High | Project source was classified untrusted and the spec claimed parsers were sandboxed, yet production Lexilla C++ lexers were attached inside the privileged UI beside the canonical ledger | Named Scintilla itself as the narrow interactive UI TCB, replaced production Lexilla with bounded revision-stamped Zig container styling, kept semantic/authority-bearing parsing out of process, and retained pinned Lexilla only as a reviewed-fixture comparator that never ships | Closed |
| SR-63 | Medium | The T0.2 plan made `IValueProvider` mandatory for a 10-MiB multiline document, contradicting Microsoft's multiline-provider guidance and creating a whole-document BSTR/mutation path that could monopolize the UI STA | Removed ValuePattern from the editor contract, made TextPattern/TextRange the bounded retrieval surface, retained focused OS input as the sole automation edit route, and required a negative availability assertion | Closed |
| SR-64 | High | Reusable PDF tile sections allowed a compromised or late worker view/duplicate to keep writing while the UI uploaded or after the same object was reassigned to a newer generation; generation metadata and close acknowledgement could not revoke that authority | Made every transfer section generation-unique and one-shot, copied and hashed exact bytes into bounded UI-private staging before upload, separated transfer and GPU-cache caps, prohibited direct/shared upload and object reuse, and classified pixels as non-canonical untrusted display data | Closed |
| SR-65 | High | PDF text/geometry/link/annotation caps were enforced only inside the process that parses hostile PDFs; an authenticated but compromised worker could return oversized or inconsistent output that UIA/layout treated as valid | Required an independent pre-allocation UI-broker decoder and semantic invariant pass over every reply, private immutable reconstruction, authenticated-hostile reply fuzzing, last-good retention, and worker quarantine on any violation | Closed |
| SR-66 | High | The design assigned the reference-machine freeze to completed T0.1 even though that slice explicitly deferred it, and its matrix allowed an undocumented subset or pooled 30-trial distribution to masquerade as both frozen physical machines across both OS lanes | Moved the freeze to T0.2 before measurement; required both machine/OS strata, a predeclared Zig-generated mixed-strength matrix, fixed worst-case cells, cell/profile-specific repetitions, and no cross-stratum pooling | Closed |
| SR-67 | Medium | “Windows screenshots” did not distinguish a DWM-composed visible desktop from `PrintWindow`, an app framebuffer, or window-only capture that omits visible popups and can disagree with what the user sees | Made DXGI Desktop Duplication from an independent Zig controller the timestamped, calibrated authority; made capture perturbation and metadata explicit; prohibited self-render/GDI/browser substitution; retained Windows Graphics Capture only as a non-substituting diagnostic | Closed |
| SR-68 | Medium | The approval footer still said T0.1 had not been planned and user approval was pending after T0.1 was already completed and T0.2 planning had begun | Replaced the stale transition with the actual T0.1-complete boundary and the active reviewed-plan T0.2 implementation gate | Closed |
| SR-69 | Medium | The document header still claimed the approved design awaited user approval and that implementation had never started, contradicting the completed T0.1 evidence and the footer repair | Split original and current implementation baselines and recorded the actual approved/T0.1-complete/T0.2-not-started state | Closed |
| SR-70 | Medium | The authoritative MuPDF error-boundary link had moved and returned HTTP 404, so a core rejection decision no longer had a live primary-source path | Replaced every stale `reference/c/using.html` URL with MuPDF's current official `reference/c/overview.html` page, which documents the same mandatory `setjmp`/`longjmp` error macros | Closed |
| SR-71 | Medium | The standalone browser-review artifact emitted `<html lang="">`; its otherwise clean structure could not satisfy the WCAG 3.1.1 language oracle, and a filtered axe invocation misleadingly reported zero applicable checks | Froze `lang=en` in the Pandoc preview metadata, retained the unfiltered full axe run as authority, and added non-empty document language to every required verification pass | Closed |
| SR-72 | Medium | Moving the standalone HTML preview away from the Markdown source directory left the architecture image as a relative `/assets/...` request that returned HTTP 404; structure and axe checks could therefore pass while visible evidence was missing | Made the deterministic preview self-contained with embedded resources and required every image to complete with non-zero natural dimensions while the failed-request log stays empty | Closed |
| SR-73 | Medium | The roadmap named twelve slices but did not distinguish them from detailed task IDs or state how much later work was still intentionally undecomposed, making `T0.1` and `T0.2a` easy to misread as peers and leaving room for imagined hidden `T6`/`T7` scope | Froze the complete six-train/twelve-slice set, recorded the fourteen tasks detailed so far, identified the ten intentionally undecomposed slices, and prohibited extra top-level scope without an explicit future design-delta review | Closed |
| SR-74 | Medium | The written-spec QA procedure expanded a browser-rendering check into repeated screenshots of prose sections, consuming review effort and risking the false implication that document images prove architecture, native UX, or product performance | Limited prose-document browser work to one deterministic publication smoke in the final pass, removed section screenshots from the oracle, and reserved visual/runtime evidence for an implemented native UI or browser-visible product artifact | Closed |
| SR-75 | High | “Zero-capability AppContainer” was treated as if an empty named-capability list left only brokered authority, but a regular AppContainer can still use Windows resources ACL'd for `ALL APPLICATION PACKAGES`; a compromised PDF/science worker therefore had a larger ambient system surface than the threat contract admitted | Require imperatively created zero-named-capability LPAC with the AAP opt-out, suspended-token verification, exact role-SID grants, and a classic-versus-LPAC canary; keep regular AppContainer diagnostic-only, reject silent fallback, and make full PDF/font/search compatibility an empirical T0 gate | Closed |
| SR-76 | High | The first LPAC repair still called the result “explicit-only,” but LPAC can access resources granted to `ALL RESTRICTED APPLICATION PACKAGES` (`S-1-15-2-2`); the correction would merely have replaced one hidden ambient surface with a smaller hidden surface | Declare ARAP as a residual OS baseline, add AAP/ARAP/exact-role canaries, inventory successful non-product accesses and grant source on both sealed OS lanes, fail user-private/project access or unsafe writable/executable loads, and narrow the product promise instead of claiming LPAC protects broadly granted resources | Closed |
| SR-77 | Medium | The residual-access draft asked ETW to report the SID that authorized each access and risked presenting a finite corpus trace as an exhaustive Windows authority map; ETW records operations/results, not the causal ACE, and unexercised resources remain outside the trace | Record security-descriptor snapshots and matching trustee ACEs without causal attribution, reserve causal claims for controlled canaries, require loss-free workload traces and explicit unknowns, and state that the manifest covers observed workloads rather than every Windows resource or a runtime allowlist | Closed |
| SR-78 | Medium | File-granular LPAC grants and SID canaries ignored path traversal: a correct leaf ACE may still be unreachable through an ancestor, while a canary denial at the parent could falsely appear to prove AAP/ARAP isolation | Give every controlled canary the same traverse/read-attribute parent path, grant runtime ancestors only minimal non-enumerating traverse rights, keep role distinctions at leaf objects, record the actual LPAC traverse privilege, and negative-test list/create/delete/write separately | Closed |
| SR-79 | High | The role-specific runtime ACL omitted AppContainer's dual-principal intersection and inheritance control: a role ACE without a normal-user grant can be unusable, while an inherited ARAP ACE (common under system install roots) can let the wrong LPAC read PDFium despite a nominal PDF-only leaf rule | Use a protected TExFlow-owned staging root; grant exact rights on both current-logon/owner and intended package-SID sides; enumerate management ACEs; reject inherited/broad/default/null/generic DACLs and wrong-role access; never mutate ancestors outside the owned root | Closed |
| SR-80 | High | The single `TExFlow.exe --worker=*` image statically included Scintilla/UI code even though Windows maps load-time imports and initializes DLLs before Zig can dispatch a worker role; UI/graphics imports could therefore prevent or hollow out pre-start Win32k lockdown, and the broad UI code image remained available to a compromised parser | Split the shipping baseline into dedicated Zig UI, PDF-worker, and science-worker PE images; keep Scintilla/UI/graphics imports UI-only; prove each worker's recursive import and live module closure before accepting untrusted bytes; retain any consolidated image only as a separately reviewed measured challenger | Closed |
| SR-81 | High | “Compatible process mitigations” and package-level “where supported” wording did not name required flags, distinguish runtime policy from PE instrumentation, or forbid dropping a failing bit after observing PDF/font behavior; an implementation could claim containment with only a friendly subset | Freeze the exact non-negotiable pre-start DEP/SEHOP/heap/ASLR/handle/Win32k/extension/dynamic-code/font/image/child profile, query each effective policy through the controller's retained `PROCESS_QUERY_INFORMATION` child handle before resume, recheck loaded modules before data admission, separate normal/strict CFG and capability-conditioned CET evidence, reject Microsoft-only CIG as inapplicable, and make any baseline incompatibility reopen the architecture | Closed |
| SR-82 | Medium | The repository lineage still supplied the product name even after the user fixed the application identity as `TExFlow`; without an exact naming grammar, binaries, window/package identity, workspace metadata, telemetry, and protocol domains could drift between `Oleafly`, `TeXFlow`, and `TExFlow` | Freeze exact user-facing/publisher casing `TExFlow`, exact role PE names, lowercase machine namespace `texflow`, `.texflow/` metadata, and an allowlist limiting `Oleafly` to the historical repository/legacy migration/audit paths | Closed |
| SR-83 | Medium | Freezing filenames alone still allowed Explorer, Task Manager, crash UI, window discovery, and LPAC profiles to expose blank, stale, or colliding identities; inventing a legal publisher would be equally incorrect | Freeze main title, ProductName/FileDescription/InternalName/OriginalFilename, machine window class, and distinct versioned PDF/science LPAC monikers; require distinct derived SIDs and migration review on change; leave CompanyName/copyright/signer/MSIX publisher unset until owner-supplied T5.2 release identity | Closed |
| SR-84 | Medium | The inherited shipping icon remained a large green Oleafly leaf; renaming strings and files while retaining that mark would visibly preserve the old product identity and fail the requested TExFlow polish | Exclude the legacy leaf; define a restrained source-to-evidence flow mark, multi-resolution ICO sizes and alpha/padding checks, real Explorer/title-bar/Alt-Tab/taskbar review across themes/DPI, and UI-only icon ownership | Closed |
| SR-85 | Medium | The exact-name allowlist omitted the frozen legacy implementation that the migration section still requires as an oracle, while the completed T0.1 graph installs an `oleafly-t0.1` PE and `oleafly_abi` library; taken literally, the scan was impossible, but taken loosely it could leak legacy-named artifacts into the new product. | Inventory the frozen legacy tree as unshipped comparison-only input; at T0.2c retire the old console artifact, preserve its smoke intent in a test-only `texflow` Zig gate, rename the internal ABI/header/symbol namespace because it has no external consumer, and scan the new install graph separately from the historical oracle. | Closed |
| SR-86 | Medium | The Windows identity repair froze role names but omitted numeric/string file and product versions, locale/codepage, file type/OS, and prerelease/private-build state; Explorer or crash evidence could show blank, inconsistent, or release-like metadata despite a feasibility-only artifact. | Freeze one deterministic `0.0.2` feasibility tuple across all three PEs, mark it prerelease/private and not release-qualified, use one Unicode translation, and require T5.2 to replace the complete tuple from owner-approved release identity rather than retaining or guessing fields. | Closed |
| SR-87 | High | The pipe DACL granted client rights only to the LPAC package SID even though the same specification correctly states that AppContainer access must pass both the normal-token and restricted/package-SID checks. The intended worker could therefore be unable to connect, encouraging an unsafe broad-right fallback during implementation. | Require two mirrored least-right client ACEs—exact current-logon SID and exact role package SID—with only read/write data, read/write attributes, and synchronize rights; prohibit append/create-instance and generic-write rights; retain peer authentication and the explicit same-user threat exclusion. | Closed |
| SR-88 | High | The worker was denied opening `TExFlow.exe` by the role ACL but the detailed IPC contract still required both peers to open and hash the other's executable. Satisfying peer authentication would therefore require weakening the worker boundary or silently skipping its oracle. | Make T0.2 peer proof explicitly asymmetric: the trusted broker fully validates the locked worker image and token, while the worker binds the inherited reduced parent handle, PID, creation time, canonical process image path, shared build identity, one-launch secret, role, and transcript without opening UI bytes. State the unsigned same-user limitation and reserve any stronger signed-parent proof for a reviewed release-manifest handle. | Closed |
| SR-89 | Medium | After restoring the required current-logon ACE, the pipe text did not explicitly state that an uncontained same-logon non-AppContainer process can reach the transport; a test could incorrectly claim the DACL denies this excluded threat. | State the transport-level limitation and require a hostile control that connects but receives no application data because retained-child PID/token/image checks and the one-launch-secret transcript reject it. | Closed |
| SR-90 | Medium | The embedded UI direction remained a raster that visibly said `Oleafly` and showed the legacy mark even after the written product identity was frozen as `TExFlow`; literal source scans could not detect the stale text inside the PNG. | Replace only the 480-by-48 branding rectangle through the image-edit workflow, rename the tracked asset to `texflow-evidence-instrument-direction.png`, verify the original 1672-by-941 dimensions and zero changed pixels outside that rectangle, and retain the explicit warning that the mockup is visual direction rather than runtime/scientific evidence. | Closed |
| SR-91 | Medium | The editor promised deterministic grapheme, word, BiDi, and UTF-8/UTF-16 behavior without freezing a Unicode version, conformance profile, or the exact UIA meaning of Format/Line/Paragraph/Page. Two supported Windows releases could therefore expose different navigation while both appeared to meet the prose. | Pin Unicode 17.0.0 with UAX #29 revision 47 and UAX #15 revision 57 for Zig-owned logical segmentation; define every supported UIA text unit and the Page-to-Document substitution; keep source bytes/logical ranges independent of the OS; and use Scintilla/DirectWrite plus UAX #9 only for tested visual shaping. | Closed |
| SR-92 | High | Search froze SQLite `unicode61 remove_diacritics 2`, whose official contract is based on Unicode 6.1 and intentionally conflates Latin diacritics, while an untrusted worker could still choose snippet bytes and vaguely defined match ranges. That is stale for new scripts, can change Vietnamese meaning, and can visually spoof derived evidence despite canonical-ID validation. | Replace `unicode61` with a Unicode-17 `texflow17` FTS5 tokenizer implemented in Zig, preserve accents with NFD plus full default case fold, keep locale limitations explicit, and remove every presentation byte from the worker reply. The trusted broker re-tokenizes canonical fields, validates literal-AND membership, escapes controls, and alone constructs the bounded snippet and exact half-open UTF-8 highlight ranges. | Closed |
| SR-93 | Medium | The first Unicode repair still said UIA Character/Word used UAX boundaries while leaving the Microsoft-required treatment of control characters and leading/trailing word-break runs to future tests. An implementation could produce different movement counts and normalization at CRLF/LRM or punctuation boundaries without violating the prose. | Keep UAX segmentation untailored but freeze the UIA mapping: control-only clusters do not count and attach left (right at document start), all-control content substitutes Document; lexical word segments own trailing breaks, leading breaks attach to the first word, and no-word content substitutes Document. | Closed |
| SR-94 | Medium | Search bounded queries/replies but not document tokenization. A hostile 1-MiB run or normalization expansion could exhaust the science worker, partially index a field, or let UI and worker use different Unicode tables while all reply caps still passed. | Cap field/source segment/normalized token/emitted-token count and tokenizer scratch; abort the whole derived field transaction with visible `lexical-unindexed` coverage on overflow; and bind the exact implementation/profile/table hash into schema, batches, requests, and replies. | Closed |
| SR-95 | Medium | The exact-name allowlist categorically barred `Oleafly` from shipping payloads even though the rewritten AGPL product may need to retain historical source attribution, and the license section omitted newly embedded Unicode data. A naming test could therefore force removal of required notices or developers could misclassify legal lineage as product identity. | Permit the historical name only inside explicitly audited legally required source-lineage notice text, never as a notice title/product/publisher field; add Unicode data to the license gate; and keep a TExFlow-headed deterministic third-party notice in the implementation contract. | Closed |
| SR-96 | Medium | The search contract named descriptor fields in one order while the dependent plan sorted them in another. Both orders looked locally valid, so a worker and broker could disagree deterministically or a test could bless the wrong canonical encoding. | The later SR-101 repair removes hit descriptors from IPC entirely; field and token order now exist only in the trusted broker's versioned schema and deterministic snippet algorithm. | Closed |
| SR-97 | Medium | Validating that each worker-selected hit was a real occurrence did not prove that the untrusted worker returned the canonical occurrence set. It could cherry-pick a different valid context, lie about truncation, or exploit an unfrozen field/width interpretation while the broker still rendered canonical but worker-directed text. | The later SR-101 repair removes every worker-selected occurrence and truncation value. The broker independently proves literal-AND membership over all bounded canonical fields and derives the complete presentation window itself. | Closed |
| SR-98 | Medium | The literal-query prose required multiple accepted terms but did not define how a human query becomes those terms; the dependent plan simultaneously rejected whitespace, making an ordinary multi-word search either impossible or implementation-defined. | Accept one bounded UTF-8 query string, tokenize the whole string with `texflow17`, route whitespace/punctuation only through its boundary rules, reject controls and token/count overflow, de-duplicate normalized tokens in first-occurrence order, and quote every token so operator-looking input remains literal rather than FTS syntax. | Closed |
| SR-99 | Medium | The product design said BM25 was combined with exact-ID, claim, and anchor boosts without defining candidate union, feature scaling, weights/fusion, missing values, tie-breaks, or a version fingerprint, while T0.2 ordered raw BM25 alone. An implementation could claim “smart ranking” with arbitrary or nonexistent boosts. | Label T0.2's stable `(finite BM25 ascending, binary entity ID)` order as lexical feasibility only; retain exact identities outside folded text; and require T3.1 to freeze and benchmark the typed candidate union, exact-match priority, context features, fusion/weights, missing behavior, tie-breaks, fingerprint, and per-result explanation before enabling smart ranking. | Closed |
| SR-100 | Medium | Cross-process search rank was described only as a finite BM25 value. Without an exact floating representation, byte order, signed-zero rule, and tie-break key, two conforming codecs or replay tools could disagree on canonical payloads and result order. | Freeze bounded IEEE-754 binary64 little-endian rank, normalize computed negative zero to positive zero, reject every non-finite/out-of-bound/noncanonical payload, and sort numerically then by the canonical 16-byte entity ID in unsigned binary order. | Closed |
| SR-101 | Medium | After the broker was required to reconstruct canonical occurrences to prevent cherry-picking, carrying the worker's descriptors became redundant. It added an `xInst` auxiliary ABI, payload fields, mapping states, and fuzz surface without reducing broker work or authority, and still invited future code to trust a “hint.” | Remove hit descriptors, field selection, and truncation from IPC. Return only bounded entity UUIDs and canonical ranks; lazily have the trusted broker validate literal-AND membership and derive the snippet over all fixed canonical fields under explicit batch, memory, time-slice, and cancellation caps. | Closed |
| SR-102 | Medium | Broker revalidation established that each returned row matched, but could not detect a compromised or broken worker omitting valid rows or manipulating bounded ranks. Empty results or low rank could therefore be misread by scientific audits as evidence of absence. | State the asymmetric guarantee explicitly: search is derived navigation/availability, never negative evidence. Freeze exact empty-state copy, test omission/rank manipulation, and require completeness-sensitive audits to scan the canonical ledger or reconcile an independently frozen coverage manifest. | Closed |
| SR-103 | Medium | The architecture promised extreme speed and footprint but had no search-specific corpus, latency, cancellation, memory, database-size, or rebuild gate; it also retained `detail=full` without re-challenging its stored offsets after descriptors left IPC. | Add the exact 10,000-entity/128-MiB `W6-search` corpus, identity/snippet/cancel/rebuild/memory/footprint budgets, physical 30-trial cells, and a preregistered `detail=column`/`detail=none` spike. Keep `detail=full` provisional and require a reviewed delta before any challenger can replace it. | Closed |
| SR-104 | Medium | The first non-completeness repair still said “No indexed matches,” even though its own hostile-worker model allowed a false empty reply, and it did not distinguish rebuilding/unavailable from a completed empty query. The copy asserted more about index contents than the broker could know. | Make the terminal empty copy describe only what the current derived index returned and explicitly deny evidence-of-absence meaning; give rebuilding and unavailable their own states and label nonempty results as capped derived navigation whose omissions/order are not scientific evidence. | Closed |
| SR-105 | Medium | A canonical UUID/title row could appear before literal-AND proof, so a false-positive worker candidate still reached the user; title controls/length were also outside the snippet sanitizer. “First identity rows” and “first eight snippets” had no exact endpoint for 0/1/<8/>100-hit queries, allowing fast-but-incomplete trials. | Publish no row until broker match proof; bound, escape, and direction-isolate canonical titles; define `H` from the independent oracle, use `min(8,H)`/terminal-empty endpoints, and make any membership/order failure invalidate latency. | Closed |
| SR-106 | Medium | The FTS schema left content mode implicit. SQLite's default stores a private copy of all four indexed fields, duplicating up to 128 MiB in the derived worker database even though presentation always comes from the ledger broker. The 192-MiB gate could therefore reject a needless copy rather than the chosen index design. | Use a contentless-delete FTS5 table with `columnsize=1`, a small UUID/rowid map, secure-delete settings, and bounded all-field entity updates; compare detail modes and one stored-content counterfactual under identical inputs. | Closed |
| SR-107 | Medium | One unspecified science-worker loop could be inside SQLite/tokenization and therefore unable to receive the cancel frame whose 50-ms gate it was supposed to meet. Rebuild also lacked generation-staging/activation rules, so a cancelled or crashed partial database could be served as current. | Separate authenticated control I/O from the sole SQLite-owning thread, let progress/tokenizer callbacks observe bounded cancellation atomics, and build in one bounded staging generation that is activated only after replay, integrity, checkpoint, close/reopen, and manifest checks. | Closed |
| SR-108 | Medium | The visible `lexical-unindexed` coverage denominator was described as derived-worker output even though the threat model allows that worker to omit arbitrary eligible content. A reported percentage could be mistaken for completeness. | Have the trusted broker compute only canonical cap eligibility at the exact watermark, label it explicitly as eligibility rather than indexed completeness, reject worker-reported coverage as audit evidence, and keep completeness receipts independent. | Closed |
| SR-109 | Medium | Broker re-tokenization was bounded in CPU chunks but implicitly shared the canonical ledger writer. Fetching a four-MiB entity or retaining a read snapshot across yields could still delay accepted scientific commits, hold a WAL read mark, and make the search latency fix create durability/maintenance stalls. | Add one query-only trusted presentation lane: copy one bounded entity from a short snapshot, finalize before tokenization, publish only after watermark/revision recheck, and race append/checkpoint/search to prove no writer or WAL starvation. | Closed |
| SR-110 | High | The feasibility contract allowed a four-MiB canonical entity but retained a two-MiB ledger row limit and described one projection row. SQLite encodes a complete row as one BLOB under that same limit, so the maximum entity could not be stored; duplicating the 128-MiB corpus in event and projection text would also exhaust the 256-MiB ledger before metadata/WAL overhead. | Store each project-scoped canonical field once as ordered <=256-KiB immutable content chunks; bind typed null/length/SHA-256 references into the small JCS event and normalized field projections in one transaction. Verify bytes before reuse and on read/reopen/backup, reject all dangling/cross-project/corrupt graphs, and include referenced content in portable export. | Closed |
| SR-111 | Medium | The runtime diagram still collapsed canonical writing and search presentation into one broker thread and said the science worker received event snapshots. That contradicted the later no-writer-starvation contract and the complete-field projection protocol, leaving an implementer a plausible but unsafe topology. | Make the broker boundary explicitly contain a dedicated SQLite writer thread and a separate serial read-only presentation lane; describe the science input as authenticated, hash-verified complete-field projection records rather than raw event snapshots. | Closed |
| SR-112 | Medium | The T0.2 rowid map also retained typed DOI/citekey/provider IDs even though this slice exposes only lexical BM25 and explicitly defers exact-ID fusion. Those unused values had no count/size contract, duplicated canonical identifiers into the untrusted worker, and created synchronization state without an acceptance journey. | Keep only `(fts_rowid, entity_uuid)` in the T0.2 derived map. Exact identifiers remain typed canonical ledger fields; T3.1 may add a bounded disposable identity index only together with its candidate-union, fusion, explanation, and benchmark contract. | Closed |
| SR-113 | Medium | Safe presentation said both “escape C0/C1” and “collapse line whitespace,” although TAB/CR/LF are C0; it also left escape spelling, elision bytes/cap accounting, and empty-title fallback unspecified. Two implementations could produce different ranges or a blank/spoofable row while each claimed compliance. | Freeze whitespace-first Unicode-17 transformation, exact uppercase `[U+XXXX]` atoms for remaining controls/BiDi formats, layout-only direction isolation, literal U+2026 markers counted inside caps, and an exact untitled label plus full canonical UUID fallback. | Closed |
| SR-114 | Medium | The new content references and complete-entity protocol still did not freeze null/empty encoding, zero-length chunk behavior, or exact per-field/aggregate digest bytes. Null and empty could alias, and independent worker/broker/rebuild fixtures could disagree on width, byte order, field order, or metadata binding. | Define exact null/non-null tags and chunk shape, SHA-256 over raw content, and domain-separated field/entity digest formulas with fixed field order and little-endian widths; reject every noncanonical representation before SQLite. | Closed |
| SR-115 | Medium | The spec promised literal FTS tokens but did not state how an embedded U+0022 is encoded; UAX #29 can retain a double quote inside a Hebrew word. It also lacked an encoded-expression cap. The dependent plan already doubled quotes, but the authoritative design still admitted incompatible parsers or an oversized normalized expression. | Encode each token as an FTS5 double-quoted string with every U+0022 doubled, join with exact ` AND `, cap the complete bound value at 65,536 bytes, and pass it only as the parameter of a fixed MATCH statement. | Closed |
| SR-116 | Medium | Cross-process performance trials had no frozen external input or worker-propagation contract. A controller could correlate only the UI, accept uppercase/short/reused IDs, or infer worker membership from timing/PID proximity, allowing unrelated or stale worker events to enter an otherwise valid process-tree sample. | Freeze the sole non-authoritative option as `--trace-trial=<32 lowercase hexadecimal digits>`; reject every alternate spelling/width/form, generate 16 CSPRNG bytes when absent, transport the bytes only through each authenticated bootstrap, and require each worker's first event to echo the nonce with role, PID, creation time, and build identity. The nonce grants no test behavior, fixture, policy, or authority. | Closed |
| SR-117 | Medium | The unfiltered publication audit returned an unresolved serious contrast check for two long exact search strings formatted as multi-line inline-code boxes. Zero reported violations could not be called clean while axe could not determine their full background. | Keep the message bytes unchanged but express the frozen resource set as blockquoted `key = value` lines, with an explicit delimiter rule. The default deterministic Pandoc preview now exposes ordinary wrapping text, so the full audit reaches zero violations and zero incomplete checks without preview-only contrast overrides. | Closed |
| SR-118 | Medium | The trace contract required a worker event to match the measured source commit, while the planned shared build identity contained only role/version metadata. A stale binary from another commit could therefore emit the right trial nonce and plausible role/PID data without proving it belonged to the source tree under review. | Define one domain-separated 32-byte build identity over the frozen raw commit ID, raw tree ID, and canonical dependency/tool-lock digest; embed it identically in every role image, keep role separate, and make a Zig-owned pre-build verifier reject dirty/mismatched checkout inputs or unequal PE identities before any admitted trial. | Closed |
| SR-119 | Medium | The first SR-118 repair embedded the future commit ID, but the quality protocol requires the authoritative pre-commit gate before creating that commit. Building against an unattached surrogate commit would produce a different final commit ID and invalidate the measured binary; rebuilding afterward would reverse the required order. | Bind the runtime identity to the exact staged Git tree and dependency-lock bytes, build from a clean export of that tree, then bind the eventual pushed commit to the already measured tree as a separate post-push proof. This preserves pre-commit QA and reproducibility while still rejecting stale binaries. | Closed |
| SR-120 | Medium | The staged-tree repair still included the evidence worklog that must be updated after measurement. That changed the final commit tree and invalidated the identity, recreating the same ordering problem at a different layer; excluding files informally could instead let an unbound input affect the build. | Define an exact domain-separated source-set digest over every staged tracked path/mode/blob except the sole evidence namespace, export and build only that set, forbid any build/package/QA dependency on the excluded namespace, and recompute the same digest from the pushed commit. Evidence may then change after QA without changing any measured input. | Closed |
| SR-121 | Medium | Source-set plus dependency-file bytes did not say that the dependency lock also froze compiler target, CPU features, optimization, strip/subsystem policy, and role switches. Different Debug/native-CPU or role-closure builds could share the same nominal identity and contaminate performance or isolation evidence. | Make the hashed lock contain the exact x64-Windows baseline build profile and role feature closure, forbid host-native CPU selection, require installed product images to use the frozen `ReleaseSafe` profile, and mark Debug/ReleaseFast or any option mismatch explicitly unverified and inadmissible. | Closed |
| SR-122 | Medium | The source-set record used `mode_u32_le` without defining whether Git's six-digit mode text was parsed as decimal or octal, and a normal checkout export could apply line-ending conversion. Path encoding, index stages, symlinks, submodules, and Windows collisions were also open, so two honest verifiers could hash or build different bytes. | Parse NUL-delimited stage-zero SHA-1 index records, encode the allowlisted six-byte mode text verbatim, require canonical collision-free UTF-8 Windows paths, permit only regular/executable blobs, export raw blob bytes without checkout filters, and revalidate every object ID before build and after push. | Closed |
| SR-123 | Medium | The trial-correlation sentence required a generic `source identity`, although the repaired contract defines and transports only one exact 32-byte source/dependency-bound build identity. An implementation could invent a second field, compare only the source-set digest, or disagree across the UI and workers while appearing to satisfy the prose. | Name the exact 32-byte build identity as the sole correlation field and require it, together with nonce, role, PID, and creation time, in every admitted role event. | Closed |
| SR-124 | Medium | The canonical source-set identity wrapped each repository `blob_sha1` in an outer SHA-256. That construction did not strengthen the inner object name: two distinct raw blobs with the same SHA-1 would produce the same entry and therefore the same admitted build identity. Git's own transition design treats SHA-1 as weak and selected SHA-256 for collision-resistant object identity. | Version the source-set grammar to v2 and hash an entry count plus canonical path, mode, raw-content length, and SHA-256 of each exact raw blob payload. Keep the current SHA-1 object ID only as an independently revalidated repository locator, never as the source-set security boundary. | Closed |
| SR-125 | Medium | The source/dependency-bound build identity was treated as sufficient trial identity even though it does not hash the resulting executable bytes. A replaced, corrupted, or divergent binary could preserve the embedded identity and enter a measurement; the adjacent prose also called the unsigned T0.2 feasibility candidate signed/package evidence. | Require two byte-identical complete builds, a canonical complete-payload manifest digest plus every role PE digest, immutable candidate-root rehash before each cell, and process file-ID/hash/module verification after launch. Keep the common build identity as the source/config field, and explicitly distinguish unsigned T0.2 feasibility evidence from later signed-package qualification. | Closed |
| SR-126 | Medium | The source-set grammar named index records and raw blobs but did not freeze the Git plumbing, configuration/environment, index snapshot, or post-push tree traversal. A concurrent stage operation, replacement object, lazy promisor fetch, filter/textconv path, abbreviated OID, or mutable-index replay could make enumeration and export observe different candidate sets. | Resolve and record one absolute Git binary; disable ambient config/discovery/replace/lazy/filter/pager/trace state; hold the conventional index lock across two byte-identical full-OID NUL listings; export only raw `cat-file` blobs; have Zig recompute Git OID, length, and SHA-256; and post-push replay the exact commit with recursive NUL-delimited `ls-tree`. | Closed |
| SR-127 | Medium | Under the former dual-pass policy, the review header said a final closed-coverage rerun had occurred after the latest repair while its authoritative run log still showed every run pending. That status contradiction could be cited as completion evidence without an actual clean pass. | Mark the replacement closed-coverage rerun explicitly pending until every row required by the active policy is populated; the header, gate field, pass log, and decision must advance atomically. | Closed |
| SR-128 | Medium | The support and distribution sections assigned the Windows 11 support freeze, package servicing evidence, and portable/MSIX verification paths to completed T0.1, although that slice proved only the pinned toolchain, target, ABI/miscompile corpora, reproducible graph, and CI lanes. This made already-completed evidence appear to close future native and release gates. | Assign the native OS/support freeze and feasibility evidence to T0.2; assign the signed package support matrix plus portable/MSIX verification, update, rollback, and clean-uninstall proof to T5.2; keep completed T0.1 claims limited to its actual toolchain contract. | Closed |
| SR-129 | Medium | The SR-127 ledger row contained a sixth `Review integrity` cell under a five-column header, so renderers could shift or discard the authoritative state and automated arity checks could not treat the repair ledger as structurally reliable. | Restore every finding row to the exact five-column `ID / Severity / Finding / Repair / State` schema and add table-arity verification to the replacement final pass. | Closed |
| SR-130 | Medium | The approval footer called the independently reviewed T0.2 plan the next gate and made only the plan streak block implementation, while the repaired written-spec review itself still reported a zero-state. Product-direction approval could therefore be mistaken for admission of an unreviewed repaired artifact. | Separate user approval of the direction from written-spec admission; require the spec's fresh final clean pass under the active policy plus corrective commit/push before final plan review, and require both pushed spec and plan gates before T0.2 implementation. | Closed |
| SR-131 | Medium | The runtime architecture defined a dedicated `TExFlow.ResearchWorker.exe`, but the authoritative post-cutover repository tree listed worker entry points only for PDF, science, and intelligence. A later slice could omit or silently merge the research role despite its distinct network/parser trust boundary. | Add the research entry point to the frozen post-cutover worker topology so the runtime diagram, executable grammar, repository shape, and T3.2 ownership agree. | Closed |
| SR-132 | Medium | The architecture called the research worker a Zotero/provider client while the containment contract denied every worker network capability, but it did not name which trusted component opened sockets, resolved redirects/DNS/proxies, or held credentials. Implementations could silently give an untrusted parser ambient network authority or perform network I/O on the UI thread. | Make the research worker a request/response adapter with no sockets; assign loopback/HTTPS I/O and credentials to a trusted Zig background network broker that revalidates consent and egress policy at use time; keep the UI STA and all parser workers network-free. | Closed |

## 4. Source record

Primary sources used for changed decisions:

- [Windows 10 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-10-home-and-pro)
- [Windows 11 release health](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Git hash-function transition and SHA-256 rationale](https://git-scm.com/docs/hash-function-transition)
- [Git raw object access](https://git-scm.com/docs/git-cat-file)
- [Git index enumeration](https://git-scm.com/docs/git-ls-files)
- [Git global isolation options](https://git-scm.com/docs/git)
- [PresentMon console metrics](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)
- [DXGI swap effects and partial-presentation constraint](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ne-dxgi-dxgi_swap_effect)
- [DXGI flip-model dirty/scroll correctness](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-2-presentation-improvements)
- [Named pipe security and access rights](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)
- [Windows app IPC and the `LOCAL` pipe namespace](https://learn.microsoft.com/en-us/windows/apps/develop/communication/interprocess-communication)
- [Launch an AppContainer/LPAC, AAP opt-out, and writable profile mapping](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [`TokenIsLessPrivilegedAppContainer` and the `ALL APPLICATION PACKAGES` distinction](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-token_information_class)
- [Chromium's primary LPAC design record for `ALL RESTRICTED APPLICATION PACKAGES`](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/design/sandbox.md#less-privileged-app-container-lpac)
- [Microsoft account of `S-1-15-2-2` and exact package SIDs](https://devblogs.microsoft.com/oldnewthing/20220502-00/?p=106550)
- [Explicit package-SID ACLs for shared named objects](https://learn.microsoft.com/en-us/windows/apps/develop/communication/sharing-named-objects)
- [File access rights and `FILE_TRAVERSE`](https://learn.microsoft.com/en-us/windows/win32/fileio/file-access-rights-constants)
- [Protected DACL semantics and `SE_DACL_PROTECTED`](https://learn.microsoft.com/en-us/windows/win32/secauthz/security-descriptor-control)
- [Experimental Create Process in Sandbox API and platform/handle limits](https://learn.microsoft.com/en-us/windows/win32/secauthz/createprocessinsandbox)
- [DeleteAppContainerProfile cleanup semantics](https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-deleteappcontainerprofile)
- [UiaReturnRawElementProvider lifecycle](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcoreapi/nf-uiautomationcoreapi-uiareturnrawelementprovider)
- [UI Automation provider COM threading](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/ne-uiautomationcore-provideroptions)
- [UI Automation Document control contract](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-supportdocumentcontroltype)
- [Microsoft `IValueProvider::SetValue` multiline guidance](https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-ivalueprovider-setvalue)
- [File-mapping security and access rights](https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping-security-and-access-rights)
- [Sharing files and memory](https://learn.microsoft.com/en-us/windows/win32/memory/sharing-files-and-memory)
- [`MapViewOfFile` coherence and duplication](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-mapviewoffile)
- [`DuplicateHandle` object lifetime and identity](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-duplicatehandle)
- [`UnmapViewOfFile` calling-process scope](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-unmapviewoffile)
- [Named-pipe overlapped I/O](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-type-read-and-wait-modes)
- [D3D11 `UpdateSubresource1`](https://learn.microsoft.com/en-us/windows/win32/api/d3d11_1/nf-d3d11_1-id3d11devicecontext1-updatesubresource1)
- [DXGI Desktop Duplication](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)
- [`IDXGIOutput5::DuplicateOutput1`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_5/nf-dxgi1_5-idxgioutput5-duplicateoutput1)
- [`IDXGIOutputDuplication::AcquireNextFrame`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutputduplication-acquirenextframe)
- [Windows Graphics Capture](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)
- [`PrintWindow`](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-printwindow)
- [NIST combinatorial testing](https://www.nist.gov/publications/combinatorial-testing)
- [Windows Narrator guide](https://support.microsoft.com/en-us/windows/complete-guide-to-narrator-e4397a0d-ef4f-b386-d8ae-c172f109bdb1)
- [CreateProcess and handle inheritance](https://learn.microsoft.com/en-us/windows/win32/procthread/creating-processes)
- [Windows load-time and run-time dynamic linking](https://learn.microsoft.com/en-us/windows/win32/dlls/about-dynamic-link-libraries)
- [Windows DLL initialization before application entry](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-entry-point-function)
- [`PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY` flags and immutability](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)
- [`GetProcessMitigationPolicy` effective-policy queries](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessmitigationpolicy)
- [Chromium Windows sandbox mitigations and Win32k lockdown](https://chromium.googlesource.com/chromium/src/+/main/docs/design/sandbox.md#process-mitigation-policies)
- [Launch an AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [Tectonic compile and dependency options](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html)
- [Scintilla direct access](https://scintilla.org/ScintillaDoc.html)
- [Scintilla 5.6.6 exact release files](https://sourceforge.net/projects/scintilla/files/scintilla/5.6.6/)
- [Lexilla interface and build model](https://scintilla.org/LexillaDoc.html)
- [Lexilla release history](https://scintilla.org/LexillaHistory.html)
- [MuPDF required error handling](https://mupdf.readthedocs.io/en/latest/reference/c/overview.html)
- [MuPDF error macros](https://github.com/ArtifexSoftware/mupdf/blob/master/include/mupdf/fitz/context.h)
- [PDFium exact-commit view API](https://pdfium.googlesource.com/pdfium/+/6f2272e1f3aaa141305475b83ef4eac2c1f527b8/public/fpdfview.h)
- [PDFium exact-commit text/search API](https://pdfium.googlesource.com/pdfium/+/6f2272e1f3aaa141305475b83ef4eac2c1f527b8/public/fpdf_text.h)
- [PDFium exact-commit progressive API](https://pdfium.googlesource.com/pdfium/+/6f2272e1f3aaa141305475b83ef4eac2c1f527b8/public/fpdf_progressive.h)
- [PDFium feasibility binary](https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/8035)
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
- [Windows VERSIONINFO resource](https://learn.microsoft.com/en-us/windows/win32/menurc/versioninfo-resource)
- [MSIX package signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [Unicode 17.0.0 release](https://www.unicode.org/versions/Unicode17.0.0/)
- [UAX #29 revision 47](https://www.unicode.org/reports/tr29/tr29-47.html)
- [UAX #15 revision 57](https://www.unicode.org/reports/tr15/tr15-57.html)
- [UAX #9 revision 51](https://www.unicode.org/reports/tr9/tr9-51.html)
- [Unicode License v3](https://www.unicode.org/license.txt)
- [Microsoft UI Automation text units](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-uiautomationtextunits)
- [SQLite FTS5 contentless-delete, detail, columnsize, BM25, secure-delete, and custom tokenizers](https://www.sqlite.org/fts5.html)
- [SQLite limits and complete-row encoding](https://www.sqlite.org/limits.html)
- [SQLite progress-handler cancellation contract](https://www.sqlite.org/c3ref/progress_handler.html)
- [SQLite WAL/checkpoint lifecycle](https://www.sqlite.org/wal.html)
- [ICU data footprint and slicing](https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html)
- [Windows `NormalizeString`](https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-normalizestring)
- [utf8proc 2.11.3 public API and Unicode version](https://github.com/JuliaStrings/utf8proc/blob/master/utf8proc.h)
- [libgrapheme 3.0.0 scope and footprint](https://libs.suckless.org/libgrapheme/)

## 5. Final verification contract

The pre-push candidate is accepted only when one final full pass, run after the
last repair, proves every pre-push row below. A failed row resets the streak to zero and is added to
the finding ledger before repair. Commit identity and hosted rendering are then
confirmed from a fresh post-push session; failure there reopens the candidate,
requires a repair and new commit, and restarts the one-pass pre-push gate.

| Surface | Evidence and timing |
| --- | --- |
| Source integrity | Final pre-push pass: clean Pandoc parse with warnings fatal; standalone preview uses `pagetitle`, explicit `lang=en`, and one named `main` rather than a duplicate title block; balanced fences, contiguous Markdown tables with consistent row arity, one H1, ordered numbered sections, no placeholder, and no unresolved internal file link |
| Requirement coverage | Final pre-push pass: deterministic phrase/section checks for Zig ownership, live render, retained EPUB, scientific model, AI diff, security/privacy, accessibility, migration, severity, and quality streak |
| Isolation truth | Final pre-push pass: regular AppContainer and LPAC are not conflated; AAP and ARAP are both disclosed; the opt-out, suspended-token assertions, three-way canary, residual-access inventory, exact role grants, compatibility gate, and no-fallback rule agree across architecture, threat model, roadmap, and T0 acceptance text |
| IPC truth | Final pre-push pass: the internal pipe DACL has mirrored exact-current-logon/exact-role-package client ACEs with only the five enumerated rights; missing halves, broad groups, append/create-instance, and generic-write fail; a same-logon control is rejected by identity/token/secret before application data rather than falsely claimed OS-denied; the broker fully validates the worker while worker-side parent proof remains asymmetric and never opens `TExFlow.exe` bytes |
| Network authority | Final pre-push pass: the research worker owns no socket or network capability; native Zotero/provider I/O and credentials belong to the trusted Zig background broker with point-of-use consent/egress validation; the UI STA remains network-free; separately installed agents that own provider connections are disclosed as external-process egress and never mislabeled native-broker-owned or isolated |
| Unicode, canonical storage, and search truth | Final pre-push pass: Unicode 17/UAX #29/#15 versions, UIA unit semantics, source-byte preservation, OS-shaping boundary, `texflow17` normalization/case-fold profile, accent preservation, locale limitations, project-scoped single-copy <=256-KiB canonical content chunks, exact null/empty/chunk references under the two-MiB ledger-row limit, atomic content/event/projection commit and verified read/reopen/backup/export, domain-separated field/entity transfer digests, descriptor-free worker schema, contentless-delete/UUID-only rowid-map storage, bounded complete-entity transport, exact quoted/doubled-U+0022/` AND `/65,536-byte bound MATCH grammar, control/database thread split, atomic generation activation, short query-only canonical snapshot/finalize/revision-recheck ownership, broker-side literal-AND-before-display validation, whitespace-first `[U+XXXX]`/U+2026/untitled presentation with no hidden direction bytes, exact epistemic states and canonical-eligibility semantics, `H`-based first-use/warm/presentation/cancel/storage gates, FTS-detail spike rules, and UTF-8/UTF-16 range units agree across editor, data, IPC, security, T0 gates, and the implementation plan |
| Worker image and mitigation truth | Final pre-push pass: dedicated UI/PDF/science PE identities agree across architecture and T0; worker recursive imports/live modules exclude UI/Scintilla and cross-role images; every mandatory pre-start mitigation, effective query, CFG/CET evidence class, incompatibility response, and no-downgrade rule is explicit and internally consistent |
| Product identity | Final pre-push pass: user-facing identity is exactly `TExFlow`; shipped PE names and ProductName/FileDescription/InternalName/OriginalFilename resources follow the frozen role grammar; the common numeric/string version, prerelease/private flags, file OS/type, Unicode translation, and non-release label match; the title/window class and distinct LPAC monikers/SIDs match; legal publisher fields remain honestly unset; machine namespaces use lowercase `texflow`; the frozen legacy tree is inventoried and excluded from new install/package outputs; the old console artifact is retired into a test-only smoke gate; the internal ABI namespace migrates to `texflow`; new `Oleafly` literals are absent outside repository/migration/audit and legally required source-lineage notice allowlists; the legacy leaf is excluded and the defined UI-only TExFlow icon contract is explicit |
| Primary references | Final pre-push pass: every distinct HTTP(S) source returns a non-error response or a documented publisher-specific equivalent; redirects resolve |
| Browser publication smoke | Final pre-push pass: one fresh context; one H1 and named main; complete heading hierarchy; self-contained image with non-zero natural dimensions; companion links activate; focusable tables/code; 1264/900/680 CSS-px reflow; full unfiltered axe audit; no horizontal document overflow, console error, or failed request |
| Evidence boundary | Final pre-push pass: no prose screenshot is used to support architecture, native UX, performance, or product-quality claims; browser-visible product evidence begins only for implemented HTML/EPUB surfaces, while the Windows application uses the native lane |
| Git hygiene | Final pre-push pass: only the spec, this review, and the renamed TExFlow design-direction asset are staged; `.superpowers/` and unrelated user files are excluded; staged diff check is clean |
| Commit binding and remote proof | Post-push: `origin/main` resolves to the new commit; external evidence binds that commit to the reviewed tree; a fresh GitHub session renders both Markdown documents and the image |

The live catalog was checked on 2026-09-03 and confirmed the exact completion
scaffold [The quality streak loop](https://signals.forwardfuture.com/loop-library/loops/quality-streak-loop/): a failure is repaired and protected, then the consecutive-success count restarts.
Only that reset discipline is reused here; the user-specific admission target
is the amended single final pass, not the catalog's default streak length.

### 5.1 Replacement clean-pass log after SR-75 through SR-132

| Pass | Independent lens | Result | Medium+ findings | Streak |
| --- | --- | --- | --- | --- |
| Final | Full requirement, traceability, source, failure-order, implementability, and contradiction review after all SR-75 through SR-132 repairs and the one-pass amendment | Passed | None | `1/1` |

Fresh pass `spec-content-final-20260904-1` recorded the following direct
evidence without using screenshots of prose:

- Pandoc parsed the spec, this review, the dependent T0.2 plan, and its review
  with warnings fatal; all four have one H1, balanced fences, no unresolved
  placeholder, 41 Markdown tables with zero row-arity anomaly, and three
  existing local link/image targets. Spec sections 1-29 are consecutive; the
  plan retains exactly eight T0.2 tasks and nineteen unique A01-A19 rows.
- SR-1 through SR-132 and PR-1 through PR-137 are contiguous, unique, and
  closed. Current normative text contains no legacy dual-pass counter or
  Pass-A/Pass-B gate; historical T0.1 evidence remains unchanged.
- A fresh balanced-parenthesis URL inventory found 213 distinct HTTP(S)
  sources. The raw redirect-following client reached 207 directly and resolved
  14 redirects. Browser-backed fetch reached the two SourceForge and four W3C
  pages whose CDNs returned client-specific 403 responses, so all 213 source
  destinations were available and none was treated as a raw-client success.
- The self-contained spec/review previews contain one named `main`, one H1,
  complete heading order, focusable tables/code, an embedded 1672-by-941 image,
  and a working companion link. Fresh Chrome checks at 1264, 900, and 680 CSS
  pixels found no document overflow, console error, page error, failed local
  request, axe violation, or axe incomplete result.
- The staged set contains only the spec, this review, deletion of the former
  design-direction asset path, and the new TExFlow asset path. The staged asset
  equals the working-tree object, its SHA-256 is
  `440174dbdfc04ee5384e42fdb87ed6fa00e84767e19a26c019728de75da365b2`, and
  `git diff --cached --check` is clean. Plans and `.superpowers/` remain
  unstaged.

The former `spec-content-final-a-20260904` and
`spec-content-final-b-20260904` results predate SR-75 and no longer count. They
also predate the 2026-09-04 one-pass amendment and cannot substitute for its
post-repair final pass.

## 6. Residual empirical decisions

The written-spec pre-push decision is `ACCEPTED (1/1)`. This admits the repaired
document candidate and authorizes its corrective commit/push only. It does not
authorize T0.2 implementation, which remains blocked until the separately
rebound and reviewed plan reaches its own `1/1` gate and is pushed.

No open Medium-or-higher design finding is intentionally accepted. The
following are not paper-approved facts and therefore remain explicit T0 gates:

- the exact Zig patch pin and compiler/ABI corpus;
- Scintilla accessibility, IME/BiDi, memory, and per-HWND latency on the matrix;
- PDFium independent source reconstruction, sealed reconstructed-runtime identity, ABI/feature equivalence,
  single-engine-thread latency, dedicated-worker image/import closure,
  zero-named-capability LPAC and complete mandatory-mitigation compatibility,
  strict-CFG/CET capability results, hostile-corpus isolation, and tile-cache
  behavior;
- signed MSIX/portable startup, memory, GPU, RDP, and idle budgets;
- SQLite power-loss recovery and ledger/search split behavior;
- dependency licenses, hashes, source offers, and packaged binary inventory.

Failure of one of these gates stops the next train or activates the documented
fallback. It does not get reclassified as a Low issue merely because the written
spec passed review.
