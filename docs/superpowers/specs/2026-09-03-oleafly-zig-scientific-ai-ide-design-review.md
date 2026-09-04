# Oleafly Zig Scientific AI IDE Spec Review Evidence

| Field | Value |
| --- | --- |
| Review window | 2026-09-03 to 2026-09-04 |
| Original reviewed baseline | `3a499fb292c4e63bd90fbec33c7e2585494ace77` |
| PDF ADR review baseline | T0.1 evidence commit `4898f33c88ca93e95295d2da5c4ffa367b90a8d6` |
| Reviewed artifact | [Oleafly Zig Scientific AI IDE Design](2026-09-03-oleafly-zig-scientific-ai-ide-design.md) |
| Review mode | Original seven challenger rounds; PDF decision reset with eight rounds; presenter reset with six rounds; lexer-boundary reset with five rounds; cross-contract repair; final closed-coverage rerun after the latest repair |
| Completion bar | Zero open Critical, High, or Medium findings in each of two consecutive passes |
| Implementation state | T0.1 toolchain/evidence is complete; T0.2 implementation and native dependency acquisition have not started |
| Current written-spec streak | `2/2`; fresh passes `spec-content-final-a-20260904` and `spec-content-final-b-20260904` both ran after SR-74 and this final metadata edit with no open Medium-or-higher finding |

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
| SR-48 | High | The approved spec still named MuPDF after deeper review proved its mandatory error macros unsafe across a strict Zig-only ABI; architecture, threading, preview, roadmap, licensing, references, and residual gates contradicted the new plan | Added the dated PDF ADR, selected conditional PDFium, propagated single-engine-thread/BGRx/source-reconstruction/security/release gates through every affected section, and retained MuPDF only as rejected history | Closed |
| SR-49 | Medium | Review metadata still claimed no Zig scaffold existed after T0.1 had already completed | Split the original and PDF-ADR baselines and stated the exact T0.1-complete/T0.2-not-started boundary | Closed |
| SR-50 | High | Behavioral equivalence alone could not exclude dormant or unexercised code in the unsigned community PDFium DLL, yet the draft still allowed that DLL in the admitted worker | Demoted the community DLL to a provenance/comparison oracle; required Task 5 and every admitted runtime/security probe to load only the sealed exact-source reconstruction and reject the community digest | Closed |
| SR-51 | High | The first T0.2 plan executed PDFium and malformed inputs during Task 2, before Task 5 had proved the AppContainer boundary | Made acquisition/reconstruction/ABI comparison static-only; required a harmless Zig no-engine worker to pass real isolation negatives before a fresh worker may load the reconstructed DLL; prohibited all execution of the community DLL | Closed |
| SR-52 | Medium | The PDF replacement decision omitted the existing requirement for bounded annotation metadata/geometry used by evidence anchors | Added annotation surface to the engine ADR and required static ABI plus contained runtime corpus coverage | Closed |
| SR-53 | Medium | The phrase “the bridge catches exceptions” could require a forbidden Oleafly-owned C++ shim even though Scintilla already exposes an upstream status-returning direct entry whose Win32 message path catches exceptions | Named `SCI_GETDIRECTSTATUSFUNCTION`, made the exception fence explicitly upstream, and prohibited any Oleafly C/C++ bridge | Closed |
| SR-54 | Medium | The product layout required Source+PDF down to 761 logical px while the reviewed 480/360-DIP pane minima plus rail/divider cannot fit there | Aligned spec and T0.2 plan on >=1180 tri-canvas, 880-1180 dual-pane, 760-879 single-focus switcher, and an honest unsupported-width statement below 760 | Closed |
| SR-55 | High | The science AppContainer both processed derived/untrusted data and owned writable `ledger.db`; compromise could rewrite the entire hash chain within its granted directory | Moved canonical SQLite ownership to a narrow trusted broker thread in the UI process, denied every worker the ledger ACL root, and limited the science worker to authenticated immutable event snapshots plus a separate disposable-search directory | Closed |
| SR-56 | Medium | After removing ledger access, a compromised search worker could still return invented IDs, stale watermarks, or snippets that the UI might treat as canonical | Bound batches/replies to project, sequence/hash watermark, and generation; required broker revalidation of every canonical entity ID and explicit derived labeling for snippets, scores, and rank | Closed |
| SR-57 | High | An unpredictable pipe name plus a current-user generic-write ACE still allowed a same-user process to enumerate/race the name or gain `FILE_CREATE_PIPE_INSTANCE`, creating a denial/interception surface before HMAC rejection | Made internal worker pipes single-instance with protected non-inherited DACLs granting only the exact role SID minimal client rights; removed explicit current-user data/create-instance rights, prohibited generic-write for workers, separated later same-user integration pipes behind the current logon SID, and retained the honest same-user-malware exclusion because object owners have implicit `WRITE_DAC` | Closed |
| SR-58 | High | The isolation prose treated a classic AppContainer as having no writable filesystem even though Windows always provisions writable profile/TEMP storage; a compromised parser could leave cross-generation residue | Declared the profile as untrusted scratch, required delete/recreate and empty/reparse/ACL verification around every worker generation, prohibited loading any runtime/config/input from it, quarantined failed cleanup, and kept science search in a separate explicit store | Closed |
| SR-59 | High | The editor UIA contract did not define `WM_GETOBJECT` coexistence or provider teardown; an Oleafly subclass could suppress Scintilla's MSAA path or leave callbacks targeting a destroyed document | Froze the Document/Text2/TextEdit/Scroll surface, forwarded every non-UIA-root object ID and unmodified parameters, required STA/MTA threading rules, physical-screen geometry, subscription-aware coalescing, and explicit provider/event-map disconnect before subclass/HWND/COM teardown | Closed |
| SR-60 | Medium | The idle contract counted Oleafly render/poll timers but not Scintilla's own caret, dwell, scroll, widen, and idle-styling `SetTimer` paths; a hidden editor could therefore violate the zero-wake promise while every app-owned timer appeared clean | Included child-HWND tickers in the energy oracle, allowed and separately recorded only the visible focused system-caret blink, and required state-preserving disable/cancel/drain plus ETW proof of zero periodic editor wake after occluded quiescence | Closed |
| SR-61 | High | The design simultaneously required `DXGI_SWAP_EFFECT_FLIP_DISCARD` and dirty-rectangle partial presentation even though that swap effect explicitly does not support partial presentation; merely changing the enum could also expose stale pixels without multi-buffer history tracking | Made two-buffer `FLIP_SEQUENTIAL` plus proved coherent dirty/scroll presentation the sparse-document baseline; required full redraw after first frame or any history-invalidating transition, prohibited mixed presenters on its HWND, and retained `FLIP_DISCARD` only as an empty-metadata full-redraw measured challenger | Closed |
| SR-62 | High | Project source was classified untrusted and the spec claimed parsers were sandboxed, yet production Lexilla C++ lexers were attached inside the privileged UI beside the canonical ledger | Named Scintilla itself as the narrow interactive UI TCB, replaced production Lexilla with bounded revision-stamped Zig container styling, kept semantic/authority-bearing parsing out of process, and retained pinned Lexilla only as a reviewed-fixture comparator that never ships | Closed |
| SR-63 | Medium | The T0.2 plan made `IValueProvider` mandatory for a 10-MiB multiline document, contradicting Microsoft's multiline-provider guidance and creating a whole-document BSTR/mutation path that could monopolize the UI STA | Removed ValuePattern from the editor contract, made TextPattern/TextRange the bounded retrieval surface, retained focused OS input as the sole automation edit route, and required a negative availability assertion | Closed |
| SR-64 | High | Reusable PDF tile sections allowed a compromised or late worker view/duplicate to keep writing while the UI uploaded or after the same object was reassigned to a newer generation; generation metadata and close acknowledgement could not revoke that authority | Made every transfer section generation-unique and one-shot, copied and hashed exact bytes into bounded UI-private staging before upload, separated transfer and GPU-cache caps, prohibited direct/shared upload and object reuse, and classified pixels as non-canonical untrusted display data | Closed |
| SR-65 | High | PDF text/geometry/link/annotation caps were enforced only inside the process that parses hostile PDFs; an authenticated but compromised worker could return oversized or inconsistent output that UIA/layout treated as valid | Required an independent pre-allocation UI-broker decoder and semantic invariant pass over every reply, private immutable reconstruction, authenticated-hostile reply fuzzing, last-good retention, and worker quarantine on any violation | Closed |
| SR-66 | High | The design assigned the reference-machine freeze to completed T0.1 even though that slice explicitly deferred it, and its matrix allowed an undocumented subset or pooled 30-trial distribution to masquerade as both frozen physical machines across both OS lanes | Moved the freeze to T0.2 before measurement; required both machine/OS strata, a predeclared Zig-generated mixed-strength matrix, fixed worst-case cells, cell/profile-specific repetitions, and no cross-stratum pooling | Closed |
| SR-67 | Medium | “Windows screenshots” did not distinguish a DWM-composed visible desktop from `PrintWindow`, an app framebuffer, or window-only capture that omits visible popups and can disagree with what the user sees | Made DXGI Desktop Duplication from an independent Zig controller the timestamped, calibrated authority; made capture perturbation and metadata explicit; prohibited self-render/GDI/browser substitution; retained Windows Graphics Capture only as a non-substituting diagnostic | Closed |
| SR-68 | Medium | The approval footer still said T0.1 had not been planned and user approval was pending after T0.1 was already completed and T0.2 planning had begun | Replaced the stale transition with the actual T0.1-complete boundary and the two-clean-review T0.2 implementation gate | Closed |
| SR-69 | Medium | The document header still claimed the approved design awaited user approval and that implementation had never started, contradicting the completed T0.1 evidence and the footer repair | Split original and current implementation baselines and recorded the actual approved/T0.1-complete/T0.2-not-started state | Closed |
| SR-70 | Medium | The authoritative MuPDF error-boundary link had moved and returned HTTP 404, so a core rejection decision no longer had a live primary-source path | Replaced every stale `reference/c/using.html` URL with MuPDF's current official `reference/c/overview.html` page, which documents the same mandatory `setjmp`/`longjmp` error macros | Closed |
| SR-71 | Medium | The standalone browser-review artifact emitted `<html lang="">`; its otherwise clean structure could not satisfy the WCAG 3.1.1 language oracle, and a filtered axe invocation misleadingly reported zero applicable checks | Froze `lang=en` in the Pandoc preview metadata, retained the unfiltered full axe run as authority, and added non-empty document language to both verification passes | Closed |
| SR-72 | Medium | Moving the standalone HTML preview away from the Markdown source directory left the architecture image as a relative `/assets/...` request that returned HTTP 404; structure and axe checks could therefore pass while visible evidence was missing | Made the deterministic preview self-contained with embedded resources and required every image to complete with non-zero natural dimensions while the failed-request log stays empty | Closed |
| SR-73 | Medium | The roadmap named twelve slices but did not distinguish them from detailed task IDs or state how much later work was still intentionally undecomposed, making `T0.1` and `T0.2a` easy to misread as peers and leaving room for imagined hidden `T6`/`T7` scope | Froze the complete six-train/twelve-slice set, recorded the fourteen tasks detailed so far, identified the ten intentionally undecomposed slices, and prohibited extra top-level scope without an explicit future design-delta review | Closed |
| SR-74 | Medium | The written-spec QA procedure expanded a browser-rendering check into repeated screenshots of prose sections, consuming review effort and risking the false implication that document images prove architecture, native UX, or product performance | Limited prose-document browser work to one deterministic publication smoke per pass, removed section screenshots from the oracle, and reserved visual/runtime evidence for an implemented native UI or browser-visible product artifact | Closed |

## 4. Source record

Primary sources used for changed decisions:

- [Windows 10 lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/windows-10-home-and-pro)
- [Windows 11 release health](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [PresentMon console metrics](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)
- [DXGI swap effects and partial-presentation constraint](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ne-dxgi-dxgi_swap_effect)
- [DXGI flip-model dirty/scroll correctness](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-2-presentation-improvements)
- [Named pipe security and access rights](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)
- [Windows app IPC and the `LOCAL` pipe namespace](https://learn.microsoft.com/en-us/windows/apps/develop/communication/interprocess-communication)
- [Launch an AppContainer and its writable profile mapping](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
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
- [Launch an AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [Tectonic compile and dependency options](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html)
- [Scintilla direct access](https://scintilla.org/ScintillaDoc.html)
- [Scintilla 5.6.6 exact source tree](https://sourceforge.net/p/scintilla/code/ci/rel-5-6-6/tree/)
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
| Source integrity | Pre-push A/B: clean Pandoc parse with warnings fatal; standalone preview uses `pagetitle`, explicit `lang=en`, and one named `main` rather than a duplicate title block; balanced fences/tables; one H1; ordered numbered sections; no placeholder or unresolved internal file link |
| Requirement coverage | Pre-push A/B: deterministic phrase/section checks for Zig ownership, live render, retained EPUB, scientific model, AI diff, security/privacy, accessibility, migration, severity, and quality streak |
| Primary references | Pre-push A/B: every distinct HTTP(S) source returns a non-error response or a documented publisher-specific equivalent; redirects resolve |
| Browser publication smoke | Pre-push A/B: one fresh context per pass; one H1 and named main; complete heading hierarchy; self-contained image with non-zero natural dimensions; companion links activate; focusable tables/code; 1264/900/680 CSS-px reflow; full unfiltered axe audit; no horizontal document overflow, console error, or failed request |
| Evidence boundary | Pre-push A/B: no prose screenshot is used to support architecture, native UX, performance, or product-quality claims; browser-visible product evidence begins only for implemented HTML/EPUB surfaces, while the Windows application uses the native lane |
| Git hygiene | Pre-push A/B: only the spec and this review evidence are staged; `.superpowers/` and unrelated user files are excluded; staged diff check is clean |
| Commit binding and remote proof | Post-push: `origin/main` resolves to the new commit; external evidence binds that commit to the reviewed tree; a fresh GitHub session renders both Markdown documents and the image |

The live catalog was checked on 2026-09-03 and confirmed the exact completion
scaffold [The quality streak loop](https://signals.forwardfuture.com/loop-library/loops/quality-streak-loop/): a failure is repaired and protected, then the consecutive-success count restarts.

## 6. Residual empirical decisions

No open Medium-or-higher design finding is intentionally accepted. The
following are not paper-approved facts and therefore remain explicit T0 gates:

- the exact Zig patch pin and compiler/ABI corpus;
- Scintilla accessibility, IME/BiDi, memory, and per-HWND latency on the matrix;
- PDFium independent source reconstruction, sealed reconstructed-runtime identity, ABI/feature equivalence,
  single-engine-thread latency, hostile-corpus isolation, and tile-cache behavior;
- signed MSIX/portable startup, memory, GPU, RDP, and idle budgets;
- SQLite power-loss recovery and ledger/search split behavior;
- dependency licenses, hashes, source offers, and packaged binary inventory.

Failure of one of these gates stops the next train or activates the documented
fallback. It does not get reclassified as a Low issue merely because the written
spec passed review.
