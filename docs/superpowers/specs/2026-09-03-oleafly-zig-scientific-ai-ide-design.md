# Oleafly Zig Scientific AI IDE Design

| Field | Decision |
| --- | --- |
| Status | Approved system design; T0.1 complete; T0.2 plan under adversarial review; T0.2 implementation has not started |
| Decision date | 2026-09-03 |
| Original repository baseline | `2b389eaf7379531e661fabbce22918b123c805ea` |
| Current implementation baseline | T0.1 evidence commit `4898f33c88ca93e95295d2da5c4ffa367b90a8d6` |
| Target | Windows-first native desktop application |
| Product source of truth | Plain-folder LaTeX source, with `.tex` authoritative |
| Product loop | Research -> Evidence -> Write -> Cite -> Compile -> Review -> Publish |
| Publishing boundary | PDF, LaTeX source package, and EPUB |
| Architecture label | C+ event-driven native instrument |

This document records the four approved design checkpoints for rewriting
Oleafly. It is a design contract, not a claim that the rewrite already exists.
The legacy React, TypeScript, Tauri, and Rust application remains the behavioral
comparison oracle until a verified Zig slice replaces each journey. It is not
normative: this specification, explicit acceptance criteria, and user intent
override legacy bugs, accidental behavior, and removed scope.

`C+` is only the name of the selected architecture option. It does not mean
that Oleafly will be implemented in C++. Oleafly-owned executable logic is Zig.
Reviewed C or C++ libraries may be linked as native dependencies, and reviewed
external tools may run out of process.

![C+ Evidence Instrument direction](../../assets/zig-evidence-instrument-direction.png)

_Visual direction, not a runtime screenshot. Section 4 contains the
authoritative performance gates._

## 1. Executive decision

Oleafly will become a focused Scientific AI IDE for research writing rather
than a general publishing suite. The application will be a native Windows
desktop program built in Zig with direct Win32, D3D11, DXGI, Direct2D,
DirectWrite, DWM, UI Automation, and Windows process APIs. It will not ship a
browser engine, WebView2 dependency, React runtime, Tauri runtime, Rust-owned
service, or Windows App SDK runtime.

The selected design is intentionally event driven:

- the GPU presents only after observable state changes;
- the UI thread never performs filesystem, database, compiler, network, or
  model work;
- each mutable subsystem has one owner;
- scientific truth is stored separately from disposable indexes;
- PDF, compiler, parser, and intelligence work is bounded and isolated;
- expensive capabilities load only when first used;
- the interface changes its arrangement for the scientific task instead of
  keeping every panel open.

The architecture was compared with the original native option, a fully custom
GPU editor, WinUI 3, Qt 6, Slint, and a WebView/Tauri design. The weighted
comparison and challenger review retained C+ as the leader. Earlier exploratory
point scores and Monte Carlo counts are intentionally not repeated as evidence
because their complete input matrix and seed were not preserved in the
repository. This removes false precision: only the dated review log and Train
T0 runtime evidence can support the choice. Train T0 can reject the architecture
if measured behavior does not satisfy the gates in this document.

## 2. Product laws

These rules are invariant across every implementation slice.

1. `.tex` is the source of truth. A visual representation, PDF, index, model
   answer, checkpoint, or database projection never silently replaces source.
2. A project is a normal folder. Open Folder works directly without import or
   conversion into a private document format.
3. Local authoring, evidence inspection, compilation through an installed
   toolchain, Git, checkpoints, and publishing remain useful without an AI
   account or network connection.
4. Model output is an untrusted proposal. It becomes source only through a
   visible diff and explicit accept action against the exact base revision.
5. Scientific verification reports what is known, unknown, stale, conflicting,
   or unverifiable. It never converts a confidence score into a verified fact.
6. Optional capability must not tax startup, idle memory, input latency, or
   privacy when it is not enabled.
7. Automatic checkpoints are recovery records, not hidden Git commits. Git
   history changes only through an explicit user action.
8. EPUB remains a publishing target, but EPUB requirements do not expand the
   core into a general-purpose book or layout application.
9. Accessibility, low-end hardware, RDP, high contrast, and device-loss paths
   are release contracts rather than later polish.
10. A slice is complete only after two consecutive closed-coverage QA passes
    contain no open or newly discovered medium-or-higher finding.
11. Network, account-backed, paid, or credentialed capabilities start disabled.
    Enabling one requires an explicit provider configuration and a disclosure
    decision; local functionality never depends on that decision.

## 3. Scope

### 3.1 Core authoring

- Open Folder and recent workspaces
- LaTeX source editing
- TexLab through LSP
- multi-file project discovery, outline, labels, includes, and root selection
- structured compile diagnostics
- PDF preview
- bidirectional SyncTeX
- Tectonic, with latexmk and TeX Live or MiKTeX compatibility fallback
- `.bib` parsing and citation picker
- Git operations
- automatic recovery checkpoints
- immutable AI patch, accept, reject, and rollback
- MCP and external-agent integration

### 3.2 Scientific research

- Zotero Local API and Better BibTeX JSON-RPC integration
- arXiv, Semantic Scholar, Crossref, PubMed, and OpenAlex search
- local PDF paper library and full-text index
- Work, Expression, Manifestation, and Artifact identity model
- claim-evidence-argument graph
- exact evidence anchors and citation verification
- literature review workspace
- consistency, methodology, experiment, and statistics audits
- Reviewer 2 simulation with explicit model provenance
- rebuttal workspace linked to reviewer comments, evidence, and source diffs
- Scientific Submission Preflight
- source-first scientific figure and TikZ workspace

Scientific computation in the core does not embed Python, R, JavaScript, or a
notebook runtime. A future domain adapter may invoke a separately installed tool
through the same declared-snapshot, consent, process, provenance, and receipt
boundary as other external tools; adding one is a new reviewed slice rather than
an implicit exception to the all-Zig policy.

### 3.3 Publishing

- accepted compiler PDF
- deterministic LaTeX source package
- EPUB
- RO-Crate 1.3 research package metadata where requested
- Word import as an optional utility through the Pandoc pack

### 3.4 Removed from the core

- Typst and Markdown project engines; the rewritten authoring source model is
  LaTeX, while Pandoc may use intermediate formats inside a publishing worker
- resume and ATS workflows
- generic presentation creation
- PowerPoint export
- book, letter, resume, and generic template ecosystems
- generic drawing canvas
- conference-deadline browser
- full WYSIWYG LaTeX
- a home-grown generic autonomous-agent framework

Small scientific starter projects and journal submission profiles may remain
as versioned data packs. They do not recreate the generic template ecosystem.

Existing behavior in these removed areas may be retained as fixtures only when
it helps prove that an unrelated retained journey has not regressed. It must
not survive in the production dependency graph after cutover.

## 4. Measurable product contract

### 4.1 Reference environments

Every performance release gate runs on both of these Windows machines:

- low tier: 4 physical CPU cores, 8 GiB RAM, integrated GPU, SSD;
- mainstream: current 6-8 physical CPU cores, 16 GiB RAM, integrated or
  entry discrete GPU, SSD.

T0.2, before the first measured native campaign, freezes the exact CPU and GPU models, firmware and driver revisions,
memory configuration, storage model and free-space floor, display path, cooling
policy, and AC/battery state for both reference machines. A replacement machine
must first pass a recorded equivalence calibration against the retired one;
quietly upgrading hardware cannot make a regression disappear.

The functional compatibility floor is x64 Windows 10 22H2 build 19045, with
solid, WARP, and non-Mica fallbacks. Because ordinary Windows 10 support ended
on 2025-10-14, it is a release-supported security lane only on an edition and
device receiving Microsoft Extended Security Updates. The primary supported
lane is the latest generally available, servicing-supported x64 Windows 11
release frozen by T0.1; as of this decision it is Windows 11 25H2. An older OS
may remain technically compatible, but Oleafly does not label an unserviced OS
as secure or supported.

APIs are resolved by capability rather than an obsolete Windows-version check.
T0.1 records the exact minimum build and servicing evidence used for each
package, and every release refreshes that evidence before signing. macOS,
Linux, native ARM64, and Windows on ARM performance are outside this rewrite;
adding any of them requires a separate design and benchmark decision.

The matrix covers the Windows 10 compatibility/ESU lane and supported Windows
11 lane on both frozen reference machines, 1920x1080/2560x1440/3840x2160,
60/120/144 Hz, 100/150/200 percent DPI, hardware rendering, WARP, clean and
established profiles, and RDP. It is a predeclared constrained mixed-strength
matrix rather than an undocumented Cartesian sample: every pair of declared
factors is covered, display/renderer/OS risk groups receive three-way coverage,
and fixed worst-case cells are added explicitly. A repository-owned Zig
generator and verifier materialize the rows and prove coverage before any
measurement; rows cannot be deleted after results are seen. Thirty-trial
performance distributions belong to named benchmark cells and profile strata,
not to a pooled grab bag of matrix rows. Results never pool different machine,
OS, renderer, profile, power, or RDP strata to pass a budget.

Interaction metrics report p50, p95, p99, worst, dropped presentation ratio,
intentional coalescing, refresh rate, present mode, and trace-loss count. A mean
alone, a trace with lost events, an undeclared replacement trial, or an
aggregate whose constituent stratum fails is not release evidence.

Local-display photon gates apply to the physical-display rows. RDP cannot be
given the same absolute photon promise because network, client display, and
codec latency are outside the process. Its controlled lane records RTT, codec,
client refresh, host and client builds, then requires the same host-side input
and state-mutation gates, zero app polling, no lost current state, and no more
than one additional refresh period of app-attributable latency relative to a
native text-control reference in the same session. End-to-end RDP latency is
reported, not silently compared with a local-display threshold.

### 4.2 Release budgets

| Metric | Gate |
| --- | --- |
| Core installer, excluding optional packs | <= 30 MiB |
| Installed core footprint, excluding optional packs and user data | <= 90 MiB |
| Cold interactive start p95 | <= 400 ms |
| Warm interactive start p95 | <= 150 ms |
| Empty-shell aggregate private working set | <= 45 MiB |
| Empty-shell idle private commit | <= 55 MiB |
| Aggregate private working set with a 30-page PDF open | <= 100 MiB |
| Private commit with a 30-page PDF open | <= 120 MiB |
| App-owned committed GPU bytes | <= `3P + T + 16 MiB`, where `P` is one RGBA viewport and `T` is the active PDF tile limit or zero |
| Cached editor input to source-mutation acknowledgement p95 | <= 4 ms |
| Dirty shell/PDF state to app frame submission p95 | <= 4 ms |
| All-input to photon p95, editor and app-compositor lanes | <= `min(25 ms, 2R)`, where `R` is one refresh period |
| Dropped presentations during a 10,000-edit trace | <= 0.1 percent |
| Empty-shell idle CPU after quiescence | <= 0.5 percent of one logical processor |
| Fixed render, polling, or editor-child wake timers while minimized/fully occluded after quiescence | zero |
| Live-render scheduling delay in Auto mode | adaptive 220-750 ms |
| Superseded compiler grace before cancellation | 75 ms |
| Visible stale artifact presented as current | zero |

The former idea of an 8 ms input-to-screen gate is rejected. A 60 Hz display
has a 16.67 ms refresh period, so that number would be physically dishonest.
Oleafly measures input QPC, state mutation, layout, frame submission, present,
display, and photon-oriented latency separately. The Scintilla child HWND and
the app-owned DXGI swap chain are separate measurement lanes; a fast shell
present cannot hide a stale editor glyph. TraceLogging and ETW provide
application events; PresentMon supplies per-presentation metrics such as
`MsUntilDisplayed` and `MsAllInputToPhotonLatency` for supported modes.

Every trace correlates process, thread, HWND or swap chain, input sequence,
state hash, present ID, and display event. `NA`, ambiguous cross-window
correlation, or a lost GDI/DWM/RDP event is missing evidence, never zero latency.
T0 validates PresentMon against a timestamped visual-toggle fixture for both
lanes. Where a presentation mode cannot be correlated reliably, the release
matrix uses WPR/DWM evidence plus a calibrated high-speed-camera or latency
instrument run rather than borrowing the DXGI result.

Release measurements use the signed, packaged `ReleaseSafe` binary and a
versioned fixture set. ETW process start is time zero. "Interactive" means the
first non-placeholder shell and editor frame has been displayed and a harness
keystroke can mutate the source model; a splash, empty swap chain, or merely
created HWND does not qualify. A warm trial starts after one unmeasured priming
launch, full process termination, and five seconds of quiescence while OS caches
remain intact. Each cold trial follows an independent clean boot with no prior
Oleafly launch. Cold and warm distributions each contain 30 trials per reference
machine. OS build, power plan, battery state, Defender state, driver versions,
DPI, display mode, and signer are recorded.

Both the signed MSIX-installed and signature-verified portable distributions
run the gate; the slower result governs. Trials cover a clean user profile and
an established profile reopening a versioned multi-file workspace. Workspace
discovery may continue asynchronously after the interactive point, but restored
source text, selection, and commands shown at that point must already be real
and usable.

Memory is sampled after five minutes of an unchanged visible shell and again
over a ten-minute window. Gates aggregate private working set and private commit
across the entire Oleafly-owned process tree, so moving work into a worker cannot
hide it; shared pages and GPU allocations are reported separately. The harness
also records peak commit, handles, threads, and worker processes. Explicit
working-set trimming or preloading is forbidden. Installer size is not allowed
to hide expansion, which is why installed footprint is a separate gate.

GPU accounting records committed and resident app-owned allocations by heap and
resource. The formula above permits the two-buffer swap chain, at most one
viewport-sized intermediate, bounded PDF tiles, and 16 MiB of other app-owned
graphics resources. DWM and driver allocations are reported separately because
the process cannot own their policy, but a T0 comparison still rejects an
architecture that creates disproportionate redirected-surface cost.

The 10,000-edit trace contains paced typing, bursts, IME composition, selection,
scroll, undo, diagnostics, and live-render completions. Each intended visible
state has an ID and content hash. Coalescing before the next eligible frame is
recorded but is not a drop; a scheduled state that misses its declared display
deadline without occlusion, device loss, or a newer superseding state is a drop.
The denominator, superseded-state count, and every exclusion are emitted with
the trace so the ratio cannot be improved by silently discarding samples.

### 4.3 Energy contract

- Foreground interaction uses normal or high quality of service only while
  necessary to satisfy input latency.
- Indexing, embedding, and maintenance work uses EcoQoS and low memory
  priority when the platform supports it.
- Minimized or fully occluded windows do not wake for fixed rendering,
  animation, indexing, status polling, or editor-child work. The timer inventory
  includes Scintilla's caret, dwell, scroll, widen, and idle-styling tickers, not
  only timers created by Oleafly.
- A visible, focused Scintilla caret may use the current Windows system blink
  period; that expected wake is recorded separately and is not mislabeled as
  application polling. On minimized or fully occluded transition, Oleafly
  disables caret blink, dwell, and idle styling and cancels or boundedly drains
  pending scroll/widen/idle work. It restores the exact visible-state settings
  without losing focus, selection, IME composition, or pending edits. After the
  declared occluded quiescence point, no such periodic timer may wake.
- Compilation may continue while occluded only when the user requested it or
  an active publish operation depends on it.
- Empty-shell CPU is measured after the quiescence point above. Background work
  must expose its reason, deadline, QoS, cancellation state, and completion; an
  idle budget cannot be met by deferring an unbounded queue until later.

## 5. Shipped-code policy

### 5.1 What "all Zig" means

All new Oleafly-owned runtime logic, worker logic, CLI behavior, migrations,
protocol adapters, parsers written by the project, benchmark harnesses, and
native UI automation harnesses are Zig. After cutover, the shipped application
contains no Oleafly-owned TypeScript, JavaScript, Rust, C#, or C++ executable
logic.

No embedded general-purpose scripting runtime is part of the core. External
scientific or publishing tools remain separate processes with typed adapters;
their executable bytes, versions, inputs, outputs, and authority are visible in
the resulting receipt.

Declarative assets are not executable-language exceptions. The repository may
contain GitHub Actions YAML, MSIX XML, Windows resources, JSON/TOML schemas,
icons, test fixtures, licenses, and documentation. Reviewed upstream native
libraries and external tools are also not rewritten merely to satisfy a label.

The shipped Zig build defaults to `ReleaseSafe`. Process-wide runtime-safety
removal is prohibited. A scoped unchecked hot loop is eligible only after a
reproducible benchmark proves material need and property, fuzz, sanitizer, and
differential tests cover its complete input domain; it is never allowed in
path, archive, protocol, persistence, authorization, or untrusted-input
decoding code. The evidence manifest names every approved exception.

### 5.2 Native dependency candidates

| Capability | Candidate | Boundary |
| --- | --- | --- |
| Source editor | Scintilla 5.6.6 plus an Oleafly-owned Zig LaTeX/BibTeX container lexer | Native C++ editing core through the upstream status-returning direct interface; styling through bounded Zig `SCN_STYLENEEDED` handling; Lexilla 5.5.3 is test-only comparison evidence and is not shipped |
| PDF | PDFium 154.0.8035.0 (`chromium/8035`) feasibility pin | Public C ABI, no V8/XFA, isolated single-engine-thread worker |
| Database and full-text search | SQLite 3.53.4 or newer reviewed patch release | Pinned amalgamation, FTS5 enabled |
| Graphics | D3D11, DXGI, Direct2D, DirectWrite, DWM | Windows system APIs |
| Accessibility | UI Automation and Text Services Framework | Windows system APIs |

Candidate versions are frozen only after Train T0 reproduces their source,
license, ABI, binary size, security, and performance evidence. Dependency
archives and generated binaries are checksum pinned. Dynamic libraries load
only by absolute path with the appropriate `LOAD_LIBRARY_SEARCH_*` policy and
verified hash or signature.

The PDF candidate changed after approval because source-level review found a
hard all-Zig boundary violation in the original MuPDF proposal. MuPDF's serious
operations require its `fz_try`/`fz_catch` macros, whose `setjmp`/`longjmp`
control flow cannot safely cross Zig stack frames without an Oleafly-owned C
bridge. Process isolation contains a crash but cannot make an unguarded call a
valid error boundary. PDFium is the replacement candidate because its upstream
public C ABI exposes the required render, text, search, character geometry,
link, annotation, and progressive-pause surface without an owned non-Zig shim.
T0.2 must still reject it unless exact official root commit
`6f2272e1f3aaa141305475b83ef4eac2c1f527b8` and its resolved source graph can be
independently reconstructed, statically matched to the provenance-checked
reference's ABI/enabled surface, and shown to pass independent correctness,
resource, and performance oracles. The community binary is reference evidence only: no admitted T0.2
worker may load it after reconstruction. Runtime/security probes use the sealed
reconstructed artifact and record its digest. That artifact is still not
release-qualified; the shipping DLL requires a later protected
Oleafly-controlled build, repeat equivalence/security evidence, and Authenticode
signing. This paragraph is the 2026-09-04 PDF-engine ADR and supersedes the
original candidate wherever historical review evidence names MuPDF.

No PDFium DLL executes during acquisition, source reconstruction, or static ABI
audit. T0.2 first launches a Zig-only dummy role and proves the zero-capability
AppContainer, Job, peer identity, handle allowlist, sealed runtime, and negative
access probes. Only then may a fresh worker load the sealed source-reconstructed
artifact. The community reference DLL is never executed; runtime correctness is
judged against independently generated semantic/pixel oracles and the exact
upstream API contract.

The Scintilla boundary uses its documented C-compatible
`SCI_GETDIRECTSTATUSFUNCTION` and fixed-width public types, not C++ object
ownership. Scintilla's upstream Win32 message entry catches its own exceptions
and the direct-status function returns that error status; Oleafly declares and
calls the function in Zig and adds no C/C++ bridge. C++ exceptions, allocators,
RTTI objects, and standard-library types never cross into Zig. T0 builds the
upstream source with the reviewed compiler/runtime policy used for packaging and
runs independent ABI probes in both `ReleaseSafe` and `ReleaseFast`.

Scintilla's text storage, layout, input, and paint path is the one deliberate
native C++ component inside the UI trust boundary; the threat model names it
rather than claiming every parser is sandboxed. Oleafly does not attach Lexilla
to the production document. It selects container styling with
`SCI_SETILEXER(NULL)` and handles `SCN_STYLENEEDED` through a bounded,
revision-stamped Zig lexical scanner for LaTeX and BibTeX. Line-state
checkpoints, edit invalidation until state convergence, byte-exact full-versus-
incremental differential tests, long-line/invalid-input/fuzz cases, and a strict
per-dispatch work cap prevent styling from becoming an unbounded UI task.
Semantic parsing, language intelligence, and every parser that can produce
authority-bearing output remain outside the UI process. Pinned Lexilla may run
only in a test executable over reviewed fixtures to expose behavioral gaps; it
is never linked into or loaded by the shipped app.

### 5.3 External tool packs

Tectonic, TexLab, Pandoc, and an optional portable Git distribution may be
downloaded as explicit packs. Every in-app download requires an Oleafly-signed
manifest rooted in an embedded, rotatable trust key plus the exact payload hash;
an upstream signature is also verified when one exists. A bare hash fetched
from the same untrusted location as its payload is not authentication. An
installed TeX Live, MiKTeX, latexmk, Git, or Pandoc can be used through a clearly
labeled host-access mode. These tools are never loaded into the UI process.

The core remains usable when no pack exists. A missing pack creates a precise
capability state and one clear installation action; it does not create a crash,
spinner without a bound, or silent fallback to an unreviewed executable.

Host-tool discovery never executes a basename found through the project current
directory or an ambiguous `PATH`. It inventories canonical absolute candidates
from reviewed locations, records origin, file identity, signature or hash, and
shows the selection. A version probe runs only after selection under the same
contained host-access launcher. If the bytes later change, the approval and
capability fingerprint expire before the next execution.

## 6. Runtime architecture

```text
oleafly.exe
|
+-- UI process
|   +-- Win32/DWM shell
|   +-- D3D11/DXGI/Direct2D/DirectWrite compositor
|   +-- Scintilla host and Oleafly UIA provider
|   +-- immutable application snapshots
|   +-- trusted ledger broker on a dedicated database thread
|   +-- typed worker clients
|
+-- oleafly.exe --worker=pdf
|   +-- PDFium public-C document engine
|   +-- progressive, cancellable tile rendering
|   +-- text/search/selection extraction
|
+-- oleafly.exe --worker=science
|   +-- derived FTS indexer
|   +-- deterministic audits
|
+-- oleafly.exe --worker=research           on demand
|   +-- Zotero and Better BibTeX clients
|   +-- bounded literature-provider clients
|   +-- untrusted metadata normalization
|
+-- oleafly.exe --worker=intelligence       optional, on demand
|   +-- pinned ONNX runtime/model
|   +-- exact vector scan and reranking
|
+-- bounded external jobs
    +-- Tectonic or latexmk/TeX engine
    +-- TexLab
    +-- Pandoc
    +-- Git
    +-- Codex, Claude Code, or OpenCode adapter
```

One signed executable can expose worker entry points so isolation does not
multiply installation size. Workers use typed, versioned, length-delimited
messages over named pipes. Each message includes protocol version, request ID,
project ID, project revision, payload length, and a bounded deadline. Unknown
message types, oversized fields, invalid UTF-8, and stale revisions fail
closed.

Every pipe has a protected, non-inherited, least-right DACL, an unpredictable
name, and a one-launch capability secret delivered through an explicitly
inherited bootstrap handle. An internal single-worker endpoint has exactly one
server instance and grants client data/attribute/synchronize rights only to the
exact role AppContainer SID; it contains no current-user data/create-instance
ACE and never uses a generic-write ACE that also implies
`FILE_CREATE_PIPE_INSTANCE`. A later same-user integration endpoint that cannot
use a role SID is separately scoped to the current logon SID, not every session
of the account, and still receives only its required client rights. Name entropy
is defense in depth, not authentication. This least-right descriptor narrows
normal access but does not override the section 21.1 exclusion for malicious
same-user code: the Windows object owner implicitly has `WRITE_DAC`. The broker
verifies the canonical DACL, peer PID/creation time, expected executable
identity, role, and protocol before
accepting application data. Per-role request count, byte, in-flight, and
outbound-result caps implement credit-based backpressure. Logs use bounded rings
with an explicit truncation record; progress is coalescible, but terminal
results are not. A peer that floods, stalls after its deadline, or violates
framing is disconnected and its job is terminated.

Classic AppContainer creation necessarily exposes a per-profile writable
`LOCALAPPDATA`/`TEMP` tree. Oleafly therefore treats that tree as an explicit
untrusted scratch boundary, not as absent storage: the stable role moniker/SID
is delete-and-recreated before each worker generation, no executable, DLL,
configuration, project input, or canonical state is ever loaded from it, and it
is deleted after every clean/crash/timeout exit only after all handles close.
Failed or partial deletion quarantines that profile and blocks another launch
until a reparse-safe cleanup and empty/ACL verification succeeds. The science
worker's separately ACL-brokered disposable search database is the sole declared
persistent worker-writable exception; its AppContainer profile remains scratch.

Aside from its declared scratch profile and the science-search exception, an
isolated worker receives only duplicated handles, shared read-only sections, or
brokered bytes for the declared snapshot. It does not receive ambient access to
the project folder. A compatibility compiler that cannot consume brokered
inputs receives a revision-specific snapshot directory and an honestly labeled
host-access boundary.

### 6.1 Ownership and scheduling

- The UI STA owns HWNDs, the D3D11 immediate context, swap chain, D2D device
  context, DirectWrite resources, focus, and the current immutable view model.
- A private Windows thread pool handles short overlapped file I/O, waits, and
  timers. Completion callbacks publish immutable results and never touch UI
  objects.
- A bounded CPU pool has `max(1, min(physical_cores - 1, 4))` workers, never
  underflows on a one-core environment, and lowers its active width under memory
  or foreground-latency pressure.
- `ledger.db` has one writer on a dedicated trusted broker thread in the UI
  process. The UI STA never calls SQLite, and no parser/research/science worker
  can open the ledger directory. Readers use independent read-only connections
  under the same broker boundary.
- The PDF worker has one engine thread that owns PDFium initialization and every
  PDFium object and call. Other threads exchange only bounded immutable
  requests/results; progressive rendering yields and cancels on the engine
  thread rather than entering the library concurrently.
- Compiler, language server, model, and provider work never holds a UI lock.
- No lock is held across IPC, filesystem, network, database, or process waits.
- Every Scintilla direct call occurs on the HWND-owning UI thread. Other threads
  publish immutable edit requests instead of calling the editor control.
- Worker restarts are bounded by role and time window. Repeated failure opens a
  visible circuit breaker while source editing and last-good artifacts remain
  available; there is no infinite crash loop.

`CancelIoEx` targets the exact overlapped operation. Every subprocess is
assigned to a Job Object with kill-on-close, process count, memory, CPU, and
wall-clock bounds appropriate to the task. An active-job watchdog also enforces
cumulative I/O, output-file count, output bytes, log bytes, and staging
free-space floors; it has no idle polling lifetime. Queues are sized in the
owning subsystem's contract and reject or supersede work explicitly when full;
no producer can create an unbounded memory or disk obligation for the UI
process.

### 6.2 Presentation path

The compositor baseline uses a two-buffer
`DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL` swap chain with a frame-latency waitable
object and maximum frame latency of one. This is deliberate: Oleafly is a
sparse-update document UI, and `DXGI_SWAP_EFFECT_FLIP_DISCARD` does not support
partial presentation. The app waits on the latency object before the first and
every later rendered frame, submits only when state is dirty, and uses
`Present1` dirty/scroll metadata only after proving the current back buffer
coherent. It tracks intersections across both buffers; first frame, resize,
DPI/adapter transition, device recovery, invalid history, or uncertain coverage
forces a complete redraw and zero dirty-rectangle count. It never mixes GDI or
another presenter into the swap-chain HWND. The application does not run a
fixed 60 or 120 fps loop.

T0 also measures a two-buffer `DXGI_SWAP_EFFECT_FLIP_DISCARD` full-redraw
challenger with empty partial-present metadata. It may replace the baseline only
after the same hardware/WARP/RDP matrix proves a material net improvement in
latency, GPU/CPU work, memory bandwidth, energy, and correctness without
weakening any budget; the ADR is updated before T1. A Windows 11 composition
swap chain remains a specialist challenger rather than a compatibility
baseline.

Scintilla remains a native child HWND and draws source text through its
DirectWrite path. Oleafly does not copy editor pixels through an intermediate
texture. The D3D11/Direct2D compositor owns shell chrome, panels, overlays, and
PDF tiles. Custom-drawn controls participate in one UIA fragment tree; standard
Win32 menus or dialogs are retained where they provide a better system-native
accessibility contract.

An immutable frame description crosses from application state to the renderer.
The render owner consumes it at a frame boundary. Device-removed or reset
errors discard and rebuild the entire dependent graphics graph. WARP is a
tested fallback. `DXGI_STATUS_OCCLUDED` switches the application to present
testing and sleep until visibility returns.

DirectComposition is not a default dependency. It may be spiked only when ETW
proves that independent composition would repair a missed release budget.

## 7. Repository shape after cutover

```text
build.zig
build.zig.zon
src/
  main.zig
  app/                 lifecycle, immutable state, commands
  platform/windows/    Win32, DWM, graphics, UIA, process and filesystem APIs
  ui/                  layout, controls, themes, task lenses, command palette
  editor/              Scintilla host, source model, LSP client, BibTeX
  project/             folder policy, root discovery, snapshots, watchers
  compile/             scheduler, engine adapters, diagnostics, artifacts
  preview/             PDF worker client, tiles, selection, SyncTeX
  science/             identities, ledger, graph, anchors, verification
  research/            Zotero and literature-provider adapters
  ai/                  patch protocol, consent, external-agent adapters
  quality/             deterministic and assisted audits, preflight
  versioning/          recovery journal, checkpoints, Git adapter
  publish/             PDF, source package, EPUB, RO-Crate
  protocols/           versioned schemas and bounded codecs
  workers/             pdf, science, intelligence entry points
tests/
  unit/
  contract/
  property/
  fuzz/
  golden/
  native_ui/
  performance/
fixtures/
vendor/                reviewed source snapshots and license manifests
packs/                  signed manifests only; payloads are not committed
docs/
```

Files remain small and capability focused. A module cannot import another
subsystem's private storage or platform handle. Cross-subsystem work uses a
command, query, immutable value, or versioned protocol defined at the narrowest
stable boundary.

## 8. Workspace and source model

Open Folder accepts a user-selected directory without copying it. Project root
discovery examines explicit configuration, magic-root comments, include
relationships, and candidate main documents. When more than one root remains
valid, Oleafly asks once and persists the choice as project metadata without
modifying source.

Opening a folder for inspection does not write into it. Until portable project
metadata is requested, a local registry maps the canonical path and folder
fingerprint to an internal project UUID. The first portable project-checkpoint
or scientific-state export creates `.oleafly/project.toml` with that UUID and a
schema version after a visible confirmation. Moving a folder with this file
preserves identity; an absent or conflicting identity produces a choice rather
than an automatic merge.

Each in-memory buffer has:

- canonical absolute path and project-relative display path;
- monotonic buffer revision;
- saved-content hash;
- current-content hash;
- encoding and newline policy;
- clean, dirty, conflicted, or missing state;
- references to the project revision that consumed it.

An attached Scintilla document is the sole mutable UTF-8 editing endpoint for
that open buffer and is owned by the UI thread. Zig owns identity, revision,
saved base, encoding/newline policy, and an ordered edit journal. Every
Scintilla modification carries a contiguous sequence and updates a
structurally-shared Zig source value from the same inserted or deleted bytes
before dependent work is published. The Zig value is a derived snapshot, never
a second independently editable copy; all programmatic edits return through the
same Scintilla transaction and notification path.

Snapshot and save operations reference the derived value at an exact sequence,
so a normal keystroke does not copy the document. Bounded idle-time and pre-save
hash audits compare it with exact Scintilla bytes. Raw Scintilla pointers never
escape the UI-thread read window. A missing sequence, failed delta, or hash
divergence blocks save/compile publication, marks the buffer conflicted, and
reconstructs through a bounded resynchronization instead of blessing either
copy silently.

Files without an attached editor are immutable disk blobs or Zig-owned staged
values. Attaching, detaching, save, undo, external merge, and crash recovery have
explicit state transitions; `clean` is set only after the atomically replaced
disk bytes hash to the saved-content hash.

UTF-8 is the default source encoding. BOM and newline policy are detected and
preserved. A non-UTF-8 text file opens for editing only with an explicit,
lossless decoder choice while original bytes remain the saved base. If an edit
cannot round-trip to that encoding, save stops and offers a reviewed conversion
to UTF-8; it never inserts replacement characters or changes line endings
silently. Binary or undecodable files remain inspectable artifacts rather than
text buffers.

The filesystem watcher uses `ReadDirectoryChangesW` with overflow recovery by
bounded rescan. A clean externally changed buffer reloads. A dirty buffer enters
a three-way merge using saved base, local buffer, and external file. Oleafly
never discards either version automatically.

Path handling is case-aware, long-path aware, reparse-point aware, and rooted
in a user-approved workspace. Every write uses a same-directory temporary file,
flush policy appropriate to the data, and atomic replacement where the target
filesystem supports it.

When the filesystem exposes them, volume and file IDs supplement paths. Two
hard-link or case aliases to the same file share one buffer owner; conflicting
aliases do not open as independent writable documents. Filesystem capabilities
and remote/cloud placeholders are detected before mutation. If durable atomic
replacement cannot be proved, save retains a verified recovery copy, labels the
weaker guarantee, and requires an explicit compatibility decision instead of
pretending the operation was atomic.

## 9. Editor and language intelligence

Scintilla is retained provisionally because it provides a mature source-editor
surface, large-file behavior, indicators, completion, wrapping, and DirectWrite
rendering without a browser runtime. Oleafly calls its direct interface for
high-frequency operations instead of sending synchronous window messages.
Styling and diagnostics are batched.

Oleafly supplies its own server-side UI Automation Document provider with
TextPattern/TextPattern2, TextEdit, and Scroll support;
selections, visible ranges, caret, line and document navigation, editable state,
names, roles, states, and keyboard accelerators are exact. The multiline source
document deliberately does not expose `IValueProvider`; clients retrieve bounded
or whole text through TextPattern ranges and edit through normal focused input,
so no giant whole-document BSTR or second mutation endpoint is introduced. Its
`WM_GETOBJECT` subclass handles only `UiaRootObjectId`, forwards all other IDs
and unmodified parameters so Scintilla's MSAA path survives, and disconnects the
provider/event map before HWND and COM-apartment teardown. Provider calls obey
STA COM threading; independent UIA clients and event handlers use one non-UI MTA
thread. Bounding rectangles are physical screen coordinates while text movement
uses logical document order. Train T0 tests Vietnamese, CJK, Arabic, IME
composition, surrogate pairs, combining marks, bidirectional selection, screen
readers, and Accessibility Insights. Scintilla does not pass merely because
ordinary Latin typing works.

TexLab runs as a bounded external process over JSON-RPC/LSP. The client:

- validates message size and schema;
- associates diagnostics with document and project revisions;
- cancels superseded requests;
- restarts with exponential backoff and a visible status;
- never blocks editing when unavailable;
- does not let an LSP workspace edit bypass the normal diff and path policy.

TexLab receives the approved read-only project snapshot plus explicit
`didOpen`/`didChange` text, not ambient writable project authority. Its own
builder, forward-search command launcher, and arbitrary external-command
features are disabled because Oleafly owns those boundaries. Network access is
absent. A requested dynamic registration or capability expansion is rejected
unless a later reviewed adapter contract permits it.

The editor is source first. There is no full WYSIWYG mode. Equations, citations,
references, figures, tables, and TikZ can have focused assistants, previews, or
structured insertion tools, but the resulting `.tex` remains visible and
editable.

## 10. Live render and compilation

### 10.1 User modes

- **Auto** is the default. A scheduler adapts between 220 and 750 ms using
  recent edit cadence, compiler duration, and cancellation rate.
- **On Save** compiles only an accepted save revision.
- **Manual** compiles only through an explicit command.

The current mode is always visible. Battery, large-project, or compatibility
conditions may suggest a less aggressive mode but never change it silently.

### 10.2 Revision model

Every source-affecting change increments `project_revision`. A compile consumes
an immutable `CompileSnapshot` containing:

- project ID and revision;
- root document;
- exact content hashes and immutable staged bytes for every input;
- engine, arguments, environment policy, and pack version;
- bibliography and generated-input hashes;
- trust mode and network policy.

Dirty buffers and disk inputs are copied into an app-local content-addressed
store while their hashes are verified. A child tool never receives a writable
hard link, reparse link, or other alias to the authoritative store. The revision
build tree uses independent input copies with read-only policy or brokered
read-only sections; writable working and output paths are separate and
disposable. The compiler never reads a mutating user project tree. Acceptance
re-hashes every consumed input and copies validated output bytes into a new
immutable artifact object. A changed or newly discovered dependency creates a
new project revision instead of modifying an active snapshot.

TeX dependency discovery is dynamic, so a cache of dependencies is never the
authority for a first or changed build. The initial closure contains every
regular file beneath the approved project root except explicit `.git`, Oleafly
cache/build, and user-configured exclusions. Enumeration, file count, individual
file size, total bytes, and traversal time are bounded. Reparse points and paths
outside the root are excluded until the user approves each additional root; the
snapshot stores the resolved file identity and bytes, never a live link. A
project that exceeds a bound receives a precise choice to narrow the roots or
use honestly labeled host-access compilation rather than a partial silent
snapshot.

After a successful run, Tectonic makefile rules or a TeX recorder `.fls` file
may optimize later closures only after every reported input is normalized,
policy checked, content hashed, and matched to the exact engine and bundle.
Generated inputs enter the next revision. An engine that cannot prove its full
dependency closure may still produce a compatibility preview, but the artifact
is labeled `dependency closure unproven`; it cannot satisfy reproducibility,
source-package, or green preflight claims. External package-tree inputs are
represented by a pinned tool or distribution fingerprint rather than omitted
from provenance.

Build directories are revision specific. Per project, at most one interactive
compiler job is active and one latest request is pending. The global default is
one compiler slot on the low-tier machine; T0 may admit a second slot on the
mainstream machine only when input, memory, thermal, and foreground-latency
budgets still pass. A new edit supersedes an interactive job. The job receives a
75 ms cooperative grace period and is then terminated through its Job Object if
still alive. Intermediate logs and diagnostics are coalesced to at most 30 UI
updates per second, and queued projects expose position and cancellation.

An explicit publish job is pinned to its accepted snapshot and is not
superseded by later edits; only the user or a declared fatal condition cancels
it. Its result remains labeled with that older revision while interactive live
render waits or uses another admitted slot. Snapshot blobs, build trees, and
accepted artifacts are reference counted. Garbage collection runs only after
all jobs, viewers, receipts, and recovery roots release them, and startup
mark-and-sweep repairs leaked references after a crash.

### 10.3 Artifact acceptance

An artifact can become current only if all of these checks pass:

1. compiler termination and output contract are valid, and resolved output
   handles are regular files inside the revision build root rather than a
   reparse or hard-link escape;
2. PDF header, size, page tree, and bounded parse succeed;
3. a fresh acceptance fence confirms every open-buffer sequence and current
   disk-input file identity and hash still match the compile snapshot;
4. artifact revision is still the latest accepted revision;
5. SyncTeX, when declared, belongs to the same artifact set;
6. the immutable artifact hash has been recorded.

The acceptance fence runs off the UI thread, consumes watcher notifications
through a captured barrier, and hashes any disk input whose identity or metadata
cannot be proved unchanged. It publishes one immutable verdict back to the UI.
An uncertain filesystem state is stale, not green. This final fence closes the
race between snapshot creation, delayed external-change notification, compiler
exit, and preview swap.

The current preview swaps only at a frame boundary after the first visible
viewport has rendered offscreen. A failed, cancelled, corrupt, or stale build
keeps the last-good PDF. A recoverable partial artifact may be opened only in a
separate amber preview that names its revision and cannot be published. The UI
labels last-good state in amber and shows the exact source revision; it never
displays stale or partial output as green current output.

### 10.4 SyncTeX

Forward and inverse search use the SyncTeX file from the accepted artifact.
Exact mappings are green. A stale mapping can be offered in amber only when the
anchor remains unambiguous after source edits. Ambiguous or mismatched mappings
do not navigate automatically.

Each snapshot carries a bijective map from staging paths to approved
project-relative file identities and source hashes. SyncTeX paths are resolved
only through that map; absolute staging paths, package-tree paths, reparse
targets, and entries absent from the snapshot never become clickable project
paths. Mapping back to a dirty buffer requires the exact base hash or the same
conservative reattachment rule used by evidence anchors.

Tectonic runs with a pinned bundle and, where supported, `--untrusted`,
`--only-cached`, and `--synctex`. System TeX and latexmk are compatibility mode
because their package and shell behavior cannot be represented as equally
isolated. Shell escape is off by default and requires a precise, project-scoped
approval.

## 11. PDF preview

The sealed source-reconstructed PDFium artifact is loaded dynamically only
after the isolated PDF-worker role is established, and only through the
reviewed public C function table; the community comparison DLL is never an
admitted runtime input. The build
has V8 and XFA disabled; Oleafly never initializes form fill or JavaScript/XFA,
never supplies network or upload callbacks, and treats URI, launch, attachment,
and form actions as inert bounded data. EPUB reading, HTML, XPS, OCR, barcode,
and unrelated conversion are outside this engine. The worker applies input
size, page, text, link, geometry, allocation, CPU, and wall-clock limits before
content reaches the UI process; an outer watchdog terminates a non-progressing
parse or extraction call.

Worker-side limits are defense in depth, not authority. The UI broker parses
every authenticated worker reply with its own pre-allocation byte/count caps,
then revalidates artifact/document generation, page identity, UTF-8, monotonic
and in-range text offsets, finite checked transforms/rectangles, dimensions,
link/action/annotation allowlists, and cross-field counts before constructing a
private immutable snapshot. No worker pointer, object address, unbounded string,
or worker-owned view reaches UIA, layout, navigation, or canonical science
state. A malformed, oversized, internally inconsistent, stale, or unexpected
reply is discarded, retains the last good artifact, and quarantines or restarts
the worker; authenticated-hostile reply fuzzing is a T0 gate.

The single engine thread uses PDFium's progressive render pause/continue API so
newer document generations can cancel stale work between bounded slices. The
cache uses 512 px opaque BGRx tiles, prioritizes viewport plus or minus one page,
and enforces a measured 32/48/64-MiB adaptive LRU limit. Tile memory is initialized
before rendering, format/stride/dimensions are validated, and bounded upload
work per frame prevents a new page from starving typing or scrolling.

Every decoded tile crosses the trust boundary through a fresh unnamed,
pagefile-backed, non-executable one-MiB section that is unique to one slot
generation and is never pooled or reused. The broker state machine is
`created -> writing -> ready -> consuming -> retired`: the worker initializes
all bytes, computes the exact-byte SHA-256 digest, unmaps its declared view,
closes its declared write handle, and authenticates the generation/dimensions/
stride/digest in `ready`. The UI maps only read access, copies exactly one
validated tile into one of at most two private staging buffers, hashes that
private copy, and unmaps/closes and permanently retires the section before any
GPU upload. It uploads only from the private buffer and clips content to the
PDF viewport beneath UI-owned chrome. At most four tile-transfer sections may
be live, independent of the resident 32/48/64-MiB GPU tile LRU.

Closing one declared handle cannot revoke a hidden duplicate or mapped view in
a compromised process, so neither the close acknowledgement nor the worker's
digest is treated as a security proof. One-shot object identity prevents a
retained writer from corrupting any later generation; digest mismatch, a late
write, an invalid state, or unreclaimed worker handles quarantines the result
and restarts or latches the worker. A compromised renderer can still choose
arbitrary pixels, so raster tiles are explicitly untrusted derived display data:
they never establish artifact identity, evidence truth, citation truth, or any
canonical scientific state. A bounded overlapped-pipe copy into the same UI
staging pool is the measured fallback if one-shot section creation fails a T0
correctness or performance gate; direct upload from shared worker-writable
memory and reusable writable tile sections are forbidden.

Search, selection, links, bounded annotation metadata/geometry used for evidence, page geometry,
CropBox, rotation, and text extraction retain document and artifact hashes.
Active PDF content never executes.

## 12. Scientific identity and evidence model

### 12.1 Stable entities

Each scientific entity receives an internal UUID independent of a citation key
or provider identifier.

| Entity | Meaning |
| --- | --- |
| Work | The intellectual work independent of version or file |
| Expression | A version, edition, preprint revision, or accepted manuscript |
| Manifestation | A publisher, repository, or media realization |
| Artifact | Exact local or remote bytes identified by cryptographic hash |
| Claim | A bounded scientific assertion in source or literature |
| Evidence | Data, method, result, quotation, figure, table, or calculation used to assess a claim |
| Argument | A structured connection among claims and evidence |

DOI, PMID, PMCID, arXiv ID, OpenAlex ID, Semantic Scholar ID, Zotero key, and
citekey are typed aliases. Exact normalized identifiers may merge records
automatically. Fuzzy title, author, or year similarity only proposes a merge
for confirmation.

### 12.2 Claim-evidence graph

Graph edges are typed and directional. Initial edge types are `supports`,
`refutes`, `qualifies`, `contextualizes`, `derived_from`, `replicates`,
`contradicts`, and `cites_without_support`. Each edge records assessor, method,
time, source revision, artifact version, rationale, and confidence category.

The verification vector is not collapsed into one misleading score:

- identity match;
- artifact and expression version match;
- anchor integrity;
- scholarly-status freshness;
- support or contradiction assessment;
- citation binding to the exact source claim;
- assessor type: deterministic, computable, model assisted, or external.

Dashboards expose denominators and unknowns. `7/8 verified, 1 stale` is valid;
`verified` without a denominator is not.

### 12.3 Exact anchors

An evidence anchor stores:

- source kind, project-relative source path, source revision, and content hash;
- normalized quotation plus preserved original text;
- leading and trailing context;
- byte and character offsets when available;
- syntax context such as LaTeX command, environment, label, or macro expansion
  receipt when relevant;
- PDF page, quads, CropBox, and rotation;
- artifact SHA-256;
- extractor name and version;
- OCR provenance and confidence when OCR was explicitly used;
- creation and last-validation revisions.

Anchor reattachment is conservative. Exact artifact and coordinates are
preferred. Text and context recovery can propose a new location; it does not
silently rewrite the authoritative anchor after an ambiguous match.

## 13. Durable ledger and derived search

SQLite state lives in local app data rather than inside a network or OneDrive
project folder. The project has a stable local identity mapped to its canonical
path. Portable scientific state is exported explicitly to the project.

The privileged UI process contains a narrow ledger broker on its own database
thread. It accepts only typed, size-bounded event proposals, performs canonical
validation itself, and owns the canonical directory. The science AppContainer
cannot open that directory; it receives authenticated immutable event snapshots
and writes only disposable `search.db`/derived cache in a separate ACL root.
Compromising an indexer therefore cannot rewrite accepted scientific history.
Search replies carry a ledger watermark and canonical entity IDs; the broker
revalidates both against its read-only projection before the UI consumes them.
Worker-returned snippets, scores, and ordering remain labeled derived data.

### 13.1 `ledger.db`

- single writer;
- WAL mode with `synchronous=FULL`;
- immutable canonical events and normalized projections written in the same
  transaction;
- UUIDv7 event IDs;
- a per-project monotonic sequence number that is authoritative for order;
- previous-event hash and SHA-256 event hash;
- canonical JSON compatible with RFC 8785 JCS for portable event material;
- schema version and deterministic migrations;
- no model-generated overwrite of an accepted human assessment.

Wall-clock UTC and UUIDv7 time are provenance metadata, not ordering authority;
clock rollback cannot reorder accepted events. The hash chain detects accidental
corruption and divergent history. It is not a signature, proof of authorship, or
protection from a malicious process running as the same user, and the UI never
describes it as such.

Canonical scientific quantities store the author-supplied decimal token as
text, normalized unit, uncertainty or interval, significant-figure intent,
missingness reason, and transformation provenance. Binary floating point is
permitted only for explicitly derived display or computation values whose
method, rounding policy, inputs, and implementation version are recorded. It is
never the sole canonical representation of an accepted measurement.

The original unit spelling is preserved beside a typed unit identity from a
versioned registry, using UCUM where the quantity is representable. Dimensional
compatibility is checked before conversion. Exact scale factors remain rational
or decimal; an approximate conversion records precision and rounding. An
unknown, contextual, or non-UCUM unit stays explicitly unresolved instead of
being guessed from typography.

If a projection write fails, the event does not commit. If recovery detects a
hash-chain or database integrity failure, the ledger becomes read only until a
verified repair or restore completes.

Before a ledger schema migration, Oleafly creates a transactionally consistent
same-user backup through SQLite's Online Backup API (or an equivalently proved
SQLite snapshot), never by copying a live database file while WAL state is
active. It opens and verifies the backup, records the source schema and logical
database hash, migrates in a transaction, and then checks SQLite integrity,
event hashes, sequence continuity, and rebuilt projections before deleting the
rollback point under retention policy. A newer unsupported major schema opens
read only; downgrade never mutates it. Migration failure leaves the previous
database usable and surfaces the exact recovery path.

### 13.2 `search.db`

- derived and fully rebuildable;
- FTS5 with BM25, phrases, prefix terms, NEAR, and a reviewed scientific
  tokenizer;
- WAL mode with `synchronous=NORMAL`;
- batched commits;
- indexed-ledger watermark;
- content and schema fingerprints;
- semantic-model, tokenizer, quantization, and dimension fingerprints for every
  vector namespace;
- corruption or deletion cannot change the ledger.

Core ranking combines lexical BM25 with exact DOI, citekey, provider ID, claim,
and anchor boosts. This is the always-available smart path.

Semantic vectors from different model or tokenizer fingerprints are never
mixed. Changing any fingerprint creates a new derived namespace and a bounded,
resumable rebuild; until it completes, search falls back to compatible vectors
or lexical ranking and labels the coverage denominator.

### 13.3 Portable checkpoint

`.oleafly/science.checkpoint.jsonl` is a deterministic, reviewable export of
accepted scientific events. Export uses canonical ordering and hashes. Import
detects common ancestry; divergent histories produce an explicit conflict
workflow rather than last-writer-wins merging.

## 14. Research layer

### 14.1 Zotero

Oleafly uses the documented Zotero Local API and Better BibTeX JSON-RPC. It does
not read or write Zotero's SQLite database directly. Collections are aliases,
not filesystem ownership. Attachments retain Zotero item identity, local path,
artifact hash, and availability state.

The connector is off until the user links the local Zotero instance. It accepts
only loopback endpoints, validates bounded response schemas, and is read only by
default. A library mutation, Better BibTeX refresh, attachment copy, or citekey
rewrite is a separately previewed action; loss of Zotero never blocks editing or
corrupts the last synchronized record.

### 14.2 Provider federation

Each provider adapter returns a normalized record plus raw provenance. Requests
use bounded concurrency, backoff, `Retry-After`, conditional caching where
supported, and a user-visible provider state. One failing or rate-limited
provider cannot erase successful results from another.

Anonymous public endpoints may be enabled individually. Login-backed, API-key,
quota-billed, or paid endpoints remain disabled until the user configures that
provider and accepts its destination and data policy. Oleafly never acquires a
key, opens an account, or upgrades a plan on the user's behalf.

Provider-specific fields remain namespaced. Crossref, PubMed, OpenAlex, arXiv,
and Semantic Scholar are not treated as equivalent authorities for every
field. Scholarly status records expression/version, correction,
expression-of-concern, retraction, withdrawal, and check time with the provider
that asserted it. Failure to find a status at one provider is `unknown`, not
proof that no status exists.

Every literature-search run has a reproducibility receipt: human query,
provider-specific normalized queries, filters, sort, page or cursor state,
request time, provider/version, returned identifiers, errors, rate limits,
cache hits, and dedup decisions. Model reranking or summarization is a separate
visible layer and never silently removes records from the reproducible result
set. Inclusion and exclusion decisions retain actor, reason, source set, and
revision so a review flow can be audited or resumed.

Acquisition never bypasses a paywall, login, access control, robots policy, or
provider terms. Each metadata or full-text record retains retrieval source,
time, applicable license or rights statement, and an explicit `unknown` when
rights cannot be established. Local indexing does not imply permission to
redistribute the bytes.

Literature review groups works, records inclusion and exclusion decisions,
links notes to exact expressions or artifacts, and makes model-written summaries
visibly distinguishable from quotations and human notes.

### 14.3 PDF paper library

The library can reference files in place or copy them into a user-selected
managed directory. Deduplication uses artifact hashes and exact identifiers.
Full text is derived data and can be deleted or rebuilt without deleting the
paper record, note, claim, or evidence edge.

Scanned papers use an optional, explicitly invoked OCR pack rather than adding
OCR to the PDF engine or the core. Every OCR text layer records artifact hash, engine and
version, language, page mapping, confidence, and invocation receipt. OCR text
is searchable derived data and is never presented as an exact quotation until
the anchor has been checked against the page image.

## 15. Native intelligence and external agents

The native lightweight assistant is Zig orchestration, context selection,
policy, patching, provenance, and UI. It is not a hidden large language model in
the core installer.

### 15.1 Optional Intelligence Pack

The pack may contain a reduced-operator ONNX Runtime build and a pinned,
licensed embedding or reranking model. It runs on demand in the intelligence
worker. Vectors are normalized int8 values. Zig exact SIMD scan remains the
default until a measured corpus threshold proves that an approximate index is
necessary. Ranking can combine lexical and semantic lists through reciprocal
rank fusion and records why each result surfaced.

The pack is accepted only if it improves a versioned scientific retrieval
benchmark without breaking memory, startup, licensing, or failure-isolation
budgets. Absence or failure of the pack leaves exact and BM25 search intact.

### 15.2 External adapters

- Codex uses its supported app-server protocol.
- Claude Code uses structured streaming output.
- OpenCode uses ACP.
- MCP targets the final 2026-07-28 protocol and negotiates an explicit,
  compatibility-tested fallback rather than guessing capabilities.

The adapter layer normalizes session, progress, diff, tool request, citation,
usage, cancellation, and error events. It does not pretend providers have
identical semantics.

Oleafly is an outbound MCP client by default. An optional inbound local MCP
server is a separate, off-by-default capability: it binds only to an
ACL-protected named pipe or explicit loopback endpoint, requires a per-launch
capability token, advertises only the narrow tools below, rate limits calls, and
never listens on LAN interfaces. Remote HTTP authorization follows the selected
protocol revision, validates the authorization issuer, binds credentials to
that issuer and resource, uses PKCE for public-client flows, and stores tokens
through the Windows credential boundary.

### 15.3 Tool surface

Default tools are narrow and typed: read an approved source snapshot, read a
selection, search literature or the local index, query evidence, propose a
patch, compile, run a named audit, and inspect a declared artifact. There is no
default generic shell, arbitrary filesystem write, delete, registry, or process
tool.

Project text, papers, provider data, model messages, MCP resources, tool
descriptions, and tool results are all untrusted data. Instructions embedded in
them cannot expand capability, change policy, approve a disclosure, or invoke a
tool. The broker derives authority only from the typed request, current UI
consent, and policy state. A URL or tool name emitted by a model is inert until
the broker validates it against the destination allowlist and, when disclosure
or cost expands, obtains a new user decision. There is no automatic recursive
fetch or tool execution from model output.

Every patch carries base hashes and exact ranges. Its parser rejects absolute or
root-escaping paths, device names, alternate streams, reparse-point transitions,
case-collision aliases, undeclared binary content, invalid encoding, oversized
hunks, and a base-hash mismatch. Accept applies only unchanged hunks through the
normal atomic-write and merge policy; reject changes nothing. A stale patch is
recomputed or merged visibly. Binary replacement requires a separate artifact
preview and explicit approval. Rollback is a first-class operation and records
its provenance.

Multi-file accept validates every base first, stages every result, and creates a
recovery checkpoint plus a checksummed transaction journal before replacing any
file. Since Windows does not provide a general cross-file atomic rename, the
contract is crash-consistent rather than falsely atomic: startup completes or
rolls back the declared set, and a failure never labels a partially applied set
as accepted. The final receipt contains all pre/post hashes under one operation
ID.

### 15.4 Execution modes

| Mode | Meaning |
| --- | --- |
| Isolated | AppContainer worker with declared capabilities and no ambient project access |
| Brokered | Typed Oleafly tools mediate every read, write, compile, and audit |
| Host access | External agent receives ambient host capability; UI displays an unconfined red state |

The UI never calls host access a sandbox. Credentials live in Windows
Credential Manager or DPAPI-protected app state. Child processes receive an
explicit environment and handle allowlist. Consent names the provider, data,
purpose, destination, duration, and capability. Approval tokens are one use
and bound to request, project, revision, tool, and expiry.

Brokered is the default external-agent mode. Even in host-access compatibility
mode, Oleafly starts the agent in a disposable snapshot or worktree and does not
offer the live project as its working directory. Resulting files are harvested
as an immutable patch against the base snapshot. Because a same-user unconfined
process can still discover and mutate other paths, any live-project change that
arrives during the session is quarantined as an untrusted external change and
must pass the visible three-way diff before Oleafly compiles or publishes it.
Host access is never eligible for an "isolated" or "policy enforced" receipt.

Network egress is brokered by destination and data class. Redirects, DNS
rebinding, loopback/private-address transitions, proxy changes, and a new upload
body are revalidated at the point of use. Provider and tool output cannot add an
egress destination. Cancellation closes request bodies and response streams
without silently retrying a disclosure.

Remote providers require HTTPS with normal Windows certificate and hostname
validation; certificate errors are never bypassed by a retry. Plain HTTP is
limited to an explicitly linked loopback connector. Each adapter caps redirect
count, headers, compressed and decoded bytes, pagination, time, and content type,
and writes cache entries only after validation under the owner-only data policy.

AI disclosure receipts record provider, model, adapter, data classes sent,
source revision, tool calls, output hash, accepted hunks, and resulting source
revision. They exclude secrets and raw private content not required for the
receipt.

## 16. Quality layer

### 16.1 Audit taxonomy

Each finding declares how it was produced:

- deterministic: syntax, structure, exact identity, hash, missing citation,
  broken reference, policy, or reproducible rule;
- computable: a calculation with explicit inputs, assumptions, units, method,
  and result;
- model assisted: an untrusted suggestion with provider and model provenance;
- external: a result imported from a named service or reviewer.

The initial audit families are compile diagnostics, claim audit, citation audit,
internal consistency, method completeness, experiment completeness, statistics,
Reviewer 2 simulation, rebuttal support, and Scientific Submission Preflight.

Model-assisted methodology, statistics, or reviewer findings never use the same
visual state as a deterministic failure. A user can inspect the evidence,
scope, limitations, and source revision behind every finding.

A model-assisted audit cannot mark a claim verified, alter accepted evidence,
or block publish by itself. Each model and prompt version must pass a versioned
finding corpus that reports precision, recall, abstention, false-citation rate,
run-to-run variance, cost, and latency by audit family. A provider or model
change invalidates the prior benchmark until rerun. The UI exposes unsupported
languages/domains and benchmark coverage instead of generalizing from one
aggregate score.

### 16.2 Submission preflight

Preflight checks accepted PDF and source together. It covers compile state,
artifact freshness, missing files, bibliography resolution, claim-evidence
coverage, stale scholarly status, figure and table references, metadata,
reproducibility declarations, disclosure receipts, privacy review, source
package contents, and EPUB requirements when EPUB is selected.

Journal-specific rules are explicit profiles, not guessed from document text.
No generic conference-deadline browser is part of preflight.

### 16.3 Figures and TikZ

The figure workspace edits standalone TikZ or figure source beside its compiled
preview. It supports source-aware insertion, artifact hashes, labels, captions,
and evidence links. It is not a generic drawing program. Every accepted visual
change produces reviewable source.

## 17. Versioning and recovery

The recovery journal appends bounded, checksummed edit records outside the
project Git history. Checkpoints compact the journal into content-addressed
snapshots under app-local storage. Retention is size and age bounded and never
deletes the only recoverable copy of a dirty buffer.

An edit schedules a one-shot durability deadline rather than a polling loop.
The writer flushes at no more than one second or 256 KiB of new journal data,
whichever comes first, and before clean close, sleep, explicit checkpoint, or
publish. The tested power-loss recovery-point objective loses no more than one
second and no more than 256 KiB of acknowledged edits; clean close has zero
pending records. A 100 MiB recovery fixture must enumerate recoverable files
within ten seconds on the low-tier machine while the UI remains responsive.
T2.1 may tighten these bounds but cannot weaken them without a new design
decision.

Editor echo and recovery durability are separate acknowledgements. An append,
flush, or space-reservation failure keeps the in-memory buffer editable but
shows a persistent red `recovery unprotected` state and never advances the
durable sequence. Clean close then requires a successful normal save or export,
recovery repair, or an explicit discard decision; the process cannot silently
exit as if recent edits were protected.

Ledger, recovery, cache, receipt, and diagnostic directories are created with
an owner-only DACL rather than inheriting a broad parent ACL. Recovery content
can contain an unpublished manuscript, so settings expose its age, size,
retention rule, and a delete action. Deletion is immediate from Oleafly's index
and normal filesystem view, but the UI does not promise forensic erasure from
an SSD or backup system it does not control.

Startup recovery validates records, reconstructs into a temporary state, and
shows exact recoverable files before overwriting disk. A corrupt tail is
quarantined while the last valid prefix remains usable.

Git uses a typed Zig adapter over a discovered executable or optional verified
portable pack. Arguments are passed as an array without shell interpolation.
Repository root, worktree state, operation, paths, output, and exit code are
normalized. Destructive actions require exact previews and user intent. Oleafly
does not auto-commit, auto-push, rewrite history, or combine recovery
checkpoints with Git commits.

The default Git environment disables pagers, editors, terminal prompts,
external diff/text-conversion commands, hooks, and implicit submodule recursion.
A network operation or a repository feature that executes user-configured code
is a separate host-access action with destination and command preview. Secrets,
credential-helper output, authenticated URLs, and private source are redacted
from logs; credentials are never placed on the command line.

## 18. Publishing

A publish transaction selects one immutable project snapshot. PDF, source
package, EPUB, RO-Crate metadata, validation results, and receipt all reference
that snapshot and their own hashes. Oleafly never combines an older accepted PDF
with newer source under one unlabeled release. Each target commits independently
to staging and becomes visible only after its validators pass; failure cannot
overwrite a previous published artifact.

### 18.1 PDF

Publish accepts only the latest validated compiler artifact or asks the user to
publish an explicitly labeled older artifact. The exported file hash and source
revision enter the receipt.

### 18.2 Source package

The source package is deterministic. It contains project-relative declared
inputs, bibliography, figures, license or metadata files selected by policy,
and an export manifest. It excludes credentials, local databases, recovery
journals, build caches, Git internals unless explicitly requested, external
paths, symlinks escaping the root, and temporary files.

Third-party paper bytes and provider records are excluded from source and
RO-Crate payloads by default. Adding one requires an explicit member preview and
a recorded redistribution basis; an unknown license remains a blocking unknown,
not an inferred permission from the existence of a citation or local copy.

Given the same accepted snapshot and exporter version, archive bytes are
reproducible: member order, path separators, Unicode normalization policy,
timestamps, permissions, compression settings, and manifest serialization are
fixed while source-file bytes remain unchanged. The manifest records the
compiler, bundle or external-distribution fingerprint, exporter, every member
hash, and whether dependency closure was proved.

### 18.3 EPUB

EPUB 3.3 is the intentional retained target. Pandoc is an optional, pinned
external pack for semantic conversion. Zig orchestration supplies explicit
inputs and arguments, disables implicit shell behavior, validates every
produced path, rejects active content, verifies manifest and spine
references, and performs a deterministic final ZIP assembly with `mimetype`
first and uncompressed. Member order, timestamps, permissions, path encoding,
and compression parameters are normalized.

The EPUB checker covers container structure, OPF metadata, navigation, media
types, internal links, image bounds, language, title, author, accessibility
metadata, and archive traversal. Browser QA opens the unpacked reading order at
the supported viewport matrix and checks console, network, keyboard navigation,
reflow, reduced motion, and high contrast.

EPUB Accessibility 1.1 is the release conformance target. Conversion preserves
heading hierarchy, document language and direction, table relationships,
footnotes, link purpose, alternative text, reading order, and native MathML for
mathematics when the source semantics are sufficient. Every export includes a
discoverability metadata report. Oleafly claims accessibility conformance only
when all machine-checkable requirements pass and every required human judgment
is resolved; otherwise it names the unknowns and does not mint a false claim.
The 2026 EPUB Accessibility 1.2 Candidate Recommendation is tracked but is not a
normative target until it becomes a reviewed Recommendation.

Release fixtures and every release-candidate EPUB also pass the official
EPUBCheck command in CI. EPUBCheck and its Java runtime are not bundled with the
desktop core; interactive publishing uses the native Zig checks, while an
optional verified validation pack can provide the same deep conformance check
on the user's machine.

An unpacked EPUB may not make an automatic network request. External links stay
inert until the reader activates them, and scripted or remote active content is
rejected rather than silently weakened into a misleading artifact.

EPUB does not introduce page-layout editing, book templates, presentation
exports, or a second source model.

### 18.4 Word import

Word import remains an optional utility through Pandoc. Import creates a normal
reviewable LaTeX project and an import report for unsupported or ambiguous
constructs. It never creates a hidden Word-backed editing mode.

## 19. User experience: Evidence Instrument

### 19.1 Stable frame and task lenses

The stable frame contains the activity rail, command and search surface,
workspace identity, contextual status, and primary work area. A task lens changes
tool context and layout without changing the data model:

| Lens | Primary arrangement |
| --- | --- |
| Write | source ↔ PDF, with evidence shown only for the selection |
| Research | library ↔ paper ↔ evidence |
| Review | findings ↔ source diff |
| Publish | preflight ↔ accepted artifacts and receipts |

Research, Evidence, Write, Cite, Compile, Review, and Publish remain visible as
the product loop, but they are not separate applications. Context and selection
survive lens changes. The `.tex` source is always visible or one deterministic
shortcut away.

Wide Write uses rail, Project, Source, and PDF. Evidence appears as a contextual
lens. AI diff, reviewer, and preflight are temporary drawers or task surfaces,
not a permanent fourth panel.

### 19.2 Responsive desktop layouts

- Above 1180 logical px: tri-canvas Project + Source + PDF.
- 880-1180 logical px: Source + PDF, with Project as a flyout and pane ratios
  clamped to their readable minima.
- 760-879 logical px: one focus surface plus a clear Source/PDF switcher and
  Project flyout; 760 logical px is the supported minimum window width.
- Below 760 logical px: preserve access and reflow without claiming a supported
  production layout.
- Zen mode leaves a clean source editor.
- Detached PDF is available for a second monitor.
- Pane and window state restores exactly, with an escape path to defaults.

### 19.3 Visual system

- calibrated scientific instrument structure with paper-neutral reading areas;
- one accent family for current focus;
- emerald plus icon/text for verified;
- amber plus icon/text for unknown, stale, or partial;
- red plus icon/text for error or unconfined capability;
- no meaning communicated by color alone;
- no gradients, decorative cards, excessive rounding, or ambient motion;
- System, Light, and Dark are first-class themes with the same hierarchy;
- Mica only on supported Windows 11 frame or rail surfaces;
- opaque content surfaces and first-class solid fallbacks for Windows 10,
  transparency off, high contrast, WARP, and RDP.

Chrome uses Segoe UI Variable where available. Regular UI text is at least 12
logical px. Source fonts are user selectable. Compact controls are 28-32 px;
touch mode uses at least 44 px targets. Motion is 80-160 ms only when it explains
continuity and is disabled under reduced motion.

### 19.4 Ease of use

First use begins with Open Folder, not an account or template wizard. Oleafly
detects candidate main files, installed compilers, Git, Zotero, and optional
packs, then shows honest capability states. One recommended action appears for
each missing requirement.

`Ctrl+K` unifies commands, files, claims, citations, and settings while familiar
editor, save, search, compile, and navigation shortcuts remain available.
Errors state what failed, which revision is affected, whether the last-good
artifact is safe, and the next recovery action.

## 20. Accessibility and international text

- Per-Monitor V2 DPI awareness and `WM_DPICHANGED` are mandatory.
- Every interactive element exposes UIA name, role, state, value, accelerator,
  focus, and correct control pattern.
- Source exposes TextPattern2 and exact caret or selection ranges.
- PDF preview exposes document/page structure, selectable extracted text,
  current page, links, and selection through UIA when the artifact supplies
  them; an image-only page announces that exact text is unavailable and whether
  reviewed OCR exists.
- Claim-evidence graphs, audit dashboards, figures, and color-coded status have
  a keyboard-navigable structured list or table with the same information.
- Keyboard-only operation covers every primary journey and drawer.
- Focus is never hidden by a panel transition or async result.
- High contrast does not depend on custom color tokens.
- Reduced motion removes nonessential animation without removing status change.
- Screen reader announcements are coalesced and never repeat compiler log spam.
- Vietnamese, composed and decomposed Unicode, CJK, Arabic, bidirectional text,
  surrogate pairs, and IME composition are test fixtures.

WCAG 2.2 Level AA supplies the numeric visual floor even though the production
surface is native: normal text is at least 4.5:1, large text at least 3:1, and
required UI boundaries, state indicators, and focus cues at least 3:1 against
adjacent colors. Pointer targets are at least 24 by 24 logical px or meet the
documented spacing exception; the existing 44 px touch target remains the touch
floor. Keyboard focus is visible, not obscured, and has a system/high-contrast
equivalent. Automated contrast checks cover every semantic token pair, while
native runtime inspection covers composition, focus, and system overrides.

All user-visible strings, plural rules, dates, numbers, units, shortcuts, and
reading directions pass through versioned locale resources; no feature module
hardcodes UI prose. English is the baseline resource. A locale is advertised
only after translation completeness, truncation, BiDi, screen-reader, search,
and terminology QA pass; unsupported locales fall back explicitly rather than
mixing languages unpredictably.

Accessibility failures affecting authoring, compile recovery, evidence status,
diff acceptance, or publishing are medium or higher and reset the quality
streak.

## 21. Security and privacy

### 21.1 Trust boundaries

- Untrusted inputs: project source, PDF, ZIP, EPUB, BibTeX, compiler output,
  LSP/MCP/ACP messages, provider responses, model output, and downloaded packs.
- Privileged brokers: UI-approved filesystem operations, credentials, network
  consent, process launch, patch application, and publishing.
- Durable truth: accepted source bytes, ledger events, artifact hashes,
  approvals, and receipts.
- Derived data: indexes, thumbnails, tiles, summaries, embeddings, and caches.

The threat model covers malicious or malformed project bytes, documents,
archives, model/provider/tool output, network peers, downloaded payloads,
confused-deputy requests, accidental corruption, and compromised child tools
within the granted boundary. It does not claim to contain an administrator,
kernel compromise, debugger, or arbitrary malicious process already executing
as the same user. Owner-only ACLs, capability secrets, isolation, receipts, and
hashes reduce exposure and detect classes of failure; they are not marketed as
an OS security boundary where Windows does not provide one.

### 21.2 Process containment

Non-interactive document parsers and intelligence workers run in AppContainer
with explicit capabilities. The one interactive exception is the declared
Scintilla editing/layout/paint TCB; its production syntax scanner is bounded Zig,
not Lexilla, and cannot grant authority. External compilers run under the
strongest compatible restricted-token and Job Object policy, and the UI labels
any remaining host access honestly. `CreateProcessW` receives a non-null
absolute `lpApplicationName`, a
writable command-line buffer produced from a typed argument vector by the
reviewed serializer for that executable, a minimal environment block, declared
working directory, and a `PROC_THREAD_ATTRIBUTE_HANDLE_LIST` allowlist. The
serializer is tested against spaces, quotes, trailing backslashes, empty
arguments, Unicode, and each external tool's actual parser. Oleafly does not
invoke `cmd.exe` or PowerShell for product actions.

The package audit verifies DEP, ASLR, control-flow protection, stack-protection,
and hardware-enforced stack compatibility for Oleafly and native dependencies
where the selected compiler and target support them. No executable page is both
writable and executable unless a separately reviewed dependency proves that it
is essential and the worker boundary records the exception.

Archive extraction rejects absolute paths, drive changes, device names,
alternate streams, traversal, unexpected symlinks, duplicate normalized names,
and declared-size or compression-ratio bombs. Downloads verify reviewed hash or
signature before extraction into staging and atomic activation.

Network providers are opt in. The UI shows destination and data class before
first disclosure and when capability expands. Telemetry is off unless a later,
separately approved design introduces it.

Operational logs are local, bounded, redacted, correlation-ID based, and
owner-readable only. They omit source text, quotations, credentials, request
bodies, authenticated URLs, and model prompts by default. A diagnostic bundle is
an explicit export with a file inventory and second redaction pass; sending it
anywhere is a separate user action. Oleafly-created crash dumps containing
project memory are off by default and follow the same retention and disclosure
boundary when enabled. Windows Error Reporting remains governed by OS or
administrator policy and is shown as an external privacy dependency rather than
silently claimed as disabled.

## 22. Distribution and updates

The application ships as a signed MSIX and a first-class portable ZIP. Every
shipped executable and DLL is Authenticode signed. The portable ZIP is bound to
an Oleafly-signed release manifest and exact archive hash; HTTPS or an adjacent
hash alone is not treated as publisher identity. MSIX uses block-level
differential update support and clean uninstall behavior. The portable build
stores mutable data outside its executable directory unless the user explicitly
selects portable-data mode.

There is no custom updater in the core. MSIX/App Installer or the distribution
channel handles updates. Optional packs have separate signed manifests,
versions, licenses, source offers where required, hashes, size, and revocation
state. Release and pack trust metadata contains a monotonic version, channel,
expiry, minimum safe version, and current/next signing-key identities so a
validly signed stale manifest cannot silently replay a revoked payload. Packs
activate atomically and can roll back independently of the core; an explicit
downgrade never inherits a newer version's approval or receipt.

Release automation pins third-party CI actions by immutable commit, grants the
minimum job permissions, exposes no signing secret to untrusted pull-request
code, inventories build inputs, and signs only from the protected release path.
T0.1 proves the portable and MSIX verification paths before either is called a
distribution artifact.

Startup loads only the shell, editor boundary, Zig container lexer, and settings required for the
first frame. The science worker, PDF worker/PDFium, TexLab, compiler, Git pack, Pandoc,
provider adapters, and model runtime start after the first frame and only when
the current journey needs them.

### 22.1 Licensing and source obligations

The rewritten project remains AGPL-3.0-or-later. PDFium's license and complete
transitive notice/source obligations are audited before distribution; the
feasibility binary alone does not satisfy that release gate. Scintilla,
SQLite, ONNX Runtime, models, compiler packs, language servers, and every transitive native
component receive an audited license record, source location, version, hash,
notices, and source-offer treatment before packaging. A technically attractive
dependency does not ship until license compatibility and redistribution terms
are proved for both MSIX and portable ZIP. Test-only Lexilla retains its own
source/license record but is excluded from both distribution inventories.

## 23. Migration strategy

The rewrite proceeds beside the legacy tree as a vertical walking skeleton.
The legacy app is a development oracle only. No release packages both runtimes,
and there is no long-lived Zig shell around a React/Tauri application.

This document is the umbrella system design. Each table row below is a bounded
delivery subproject with its own implementation plan, acceptance evidence, and
commit. A later slice returns to a focused design-delta review only when it
introduces a decision not resolved here. The first writing-plans phase covered
T0.1 only; subsequent phases remain one reviewed slice at a time rather than
creating one unreviewable plan for the entire rewrite.

### 23.1 Six trains, twelve bounded slices

| Slice | Shippable proof |
| --- | --- |
| T0.1 Toolchain | Pinned Zig build, Windows executable, dual CI lanes, reproducible dependency graph, ABI and miscompile corpus |
| T0.2 Native feasibility | Waitable flip presentation, startup/working-set trace, Scintilla direct API/Zig container lexer/UIA/IME, PDFium source-reconstruction/ABI/isolation proof, split SQLite crash tests |
| T1.1 Source workspace | Open Folder, project/root discovery, edit, save, external-change handling, multi-file outline |
| T1.2 Write loop | TexLab, revision scheduler, contained compile, diagnostics, PDF, exact bidirectional SyncTeX, last-good behavior |
| T2.1 Reliable state | recovery journal, automatic checkpoints, conflict recovery, settings, error surfaces |
| T2.2 Authoring utilities | `.bib` picker, Git adapter, command/search, accessibility baseline, compiler packs and fallback |
| T3.1 Scientific ledger | identities, immutable events, projections, claims, evidence, exact anchors, verification vector |
| T3.2 Research | Zotero/Better BibTeX, provider federation, PDF library, FTS index, literature review |
| T4.1 AI change control | immutable patch/diff, accept/reject/rollback, consent, Codex/Claude/OpenCode, narrow MCP tools |
| T4.2 Scientific quality | deterministic and assisted audits, Reviewer 2, rebuttal, statistics/methodology workflows, TikZ figures |
| T5.1 Publish | preflight, accepted PDF, deterministic source, EPUB, RO-Crate, Word import utility |
| T5.2 Cutover | signed MSIX and ZIP, performance/a11y/i18n/security audit, parity decision, legacy production graph deletion |

This is the complete approved top-level roadmap: six trains and twelve slices,
from `T0.1` through `T5.2`. `T0.1` has six completed implementation tasks and
the current `T0.2` plan has eight tasks (`T0.2a` through `T0.2h`), so fourteen
detailed tasks exist today. The ten slices from `T1.1` through `T5.2` are
intentionally not decomposed until their own reviewed planning phase; their
future task count is therefore unknown, not hidden. Labels such as `T0.2a` are
tasks inside a slice, not extra trains or slices. No `T6`, `T7`, unnumbered
delivery train, or additional top-level slice is approved without a future
design-delta review that changes this table explicitly.

Each slice is end to end. For example, T1.2 is not "write the PDF module"; it
proves that a user edit can compile, produce validated current output, navigate
in both directions, survive failure, and remain responsive.

T0.1 created a dedicated pinned-Zig Windows CI lane before production Zig code
could accumulate. While the legacy tree remains, its impacted CI and the Zig lane
must both pass; path filters cannot turn a changed runtime into a docs-only
green result. Removing a legacy lane requires the corresponding journey to be
replaced, traced to new evidence, and absent from the production dependency
graph.

### 23.2 Legacy extraction

Only neutral evidence crosses from legacy:

- user journeys and expected outcomes;
- source, PDF, SyncTeX, bibliography, import, export, and error fixtures;
- normalized protocol samples;
- accessibility expectations;
- adversarial inputs and regression cases;
- measured behavior worth retaining.

Runtime code is rewritten. A copied algorithm is accepted only after license,
behavior, complexity, and Zig ownership are explicit.

Legacy durable state is inventoried by format and version before migration.
Each retained format has an idempotent dry run, pre-migration backup, explicit
field mapping, unknown-field report, post-migration invariant check, and tested
rollback. Removed-scope state remains exportable or is declared unsupported; it
is never silently discarded. A newer unknown schema is preserved and opened
read only rather than downgraded.

### 23.3 Cutover condition

Cutover requires retained-scope acceptance evidence, budget compliance on both
reference machines, clean migration of supported local state, signed package
proof, recovery proof, and two final clean whole-product passes. The React,
TypeScript, Tauri, and Rust production graph is then deleted rather than left as
an unused fallback.

## 24. Slice quality protocol

Every slice follows this state machine:

1. **Contract**: map intent to observable acceptance criteria, performance
   budget, UIA tree, trust boundary, failure surfaces, and rollback.
2. **TDD**: create unit, contract, property, fuzz, golden, or UI tests selected
   by the failure surface.
3. **Runtime proof**: run the real Zig binary, real worker boundary, real tool
   where applicable, UIA journey, screenshots, logs, and resource traces.
4. **Review**: review code, architecture, security, accessibility, scientific
   honesty, visual behavior, licenses, and test effectiveness.
5. **Quality streak**: obtain two consecutive closed-coverage passes with no
   open or newly discovered medium-or-higher finding.
6. **Commit and push**: create one atomic commit with an evidence manifest and
   push it before beginning the next slice.

Any new medium-or-higher bug or gap, unexplained flake, crash, console error,
budget regression, accessibility blocker, stale evidence represented as
current, or mutation that the intended test fails to catch resets the streak to
zero. Fixing a finding is followed by the full affected matrix, not only the
single failing test.

### 24.1 Severity and closed coverage

| Severity | Objective threshold |
| --- | --- |
| Critical | credible data loss, arbitrary code execution or containment escape, credential/private-source disclosure, supply-chain compromise, or fabricated scientific truth represented as accepted |
| High | a retained primary journey is blocked; repeatable crash, hang, corruption, wrong-source publish, unsafe patch, inaccessible primary journey, or release-gate breach has no safe bounded workaround |
| Medium | user-visible correctness, provenance, accessibility, security defense-in-depth, recoverability, performance measurement, or spec ambiguity can produce a wrong implementation or requires a non-obvious workaround, but does not meet High |
| Low | bounded cosmetic, wording, or maintainability issue with no plausible effect on a retained contract, scientific interpretation, safety decision, or release gate |

A repeated or systemic Low pattern is promoted when its aggregate impact meets
Medium. Reviewers cannot downgrade a finding to preserve a streak. A pass has
closed coverage only when its predeclared requirement, risk, platform/state,
tool, fixture, and negative-case matrix completed with no unexplained skip. An
unavailable required environment is `unverified`, not clean.

Pass A is an adversarial full affected-matrix run after the last fix. Pass B
repeats the same oracle from a fresh process and fresh disposable user/project
state, rebuilds or verifies generated evidence by hash, changes scenario order,
and assigns new trace and screenshot IDs. It may reuse immutable fixtures and
tool binaries whose hashes are recorded, but it cannot reuse Pass A's mutable
cache, database, worker, browser context, or verdict. Any medium-or-higher
finding in either pass resets the streak to zero and invalidates later partial
passes until the finding is fixed.

### 24.2 Five-pass test-effectiveness review

1. Verify that each test oracle matches the user-visible contract.
2. Verify that the portfolio covers happy, error, boundary, concurrency,
   cancellation, recovery, security, accessibility, and performance surfaces.
3. Add adversarial inputs for parsers, processes, revisions, and external tools.
4. Falsify the suite with targeted mutations or fault injection.
5. Prove runtime reality using the packaged or release-equivalent binary.

Coverage percentage alone is never evidence that faults are detected.

### 24.3 Dual QA lane

The native lane uses a repo-owned Zig harness over `IUIAutomation` for launch,
Open Folder, edit, save, compile, SyncTeX, research, evidence, diff, accept,
reject, recovery, and publish journeys. It captures Windows screenshots at the
defined DPI, theme, renderer, RDP, and viewport matrix. Authoritative visual
evidence comes from an independent Zig controller using DXGI Desktop
Duplication after DWM composition, with compositor timestamps, output/adapter,
rotation, color-space, crop, protected-content, and frame-loss metadata. It is
captured in dedicated visual trials outside timed performance intervals and is
calibrated against a known-pixel fixture. `PrintWindow`, a screen-DC copy, an
app-exported framebuffer, or a browser rendering cannot close this native
oracle. Windows Graphics Capture may corroborate an isolated window, but it
cannot replace visible-desktop evidence for popups, overlays, occlusion, or the
Windows 10 lane. Any capture fallback or cross-oracle disagreement is explicit
and leaves the affected state unverified.

The same native lane runs the built-in Windows Narrator on both supported OS
lanes through a predeclared keyboard-only journey and records the operator
oracle; Narrator is not optional because it ships with Windows. A second screen
reader may add diversity when already installed, but its absence neither
weakens nor substitutes for the mandatory Narrator and independent UIA-client
checks.

The browser lane validates browser-visible artifacts: design companions,
evidence reports, generated HTML, unpacked EPUB reading order, documentation
previews, source links, console and network behavior, keyboard traversal,
reflow, and accessibility semantics. Browser tests never stand in for native
Windows interactions.

For prose-only design and plan documents, that lane is a minimal publication
smoke: parse, links, embedded assets, landmarks, reflow, keyboard reachability,
accessibility, console, and failed requests. Repeated screenshots of document
sections are not architecture review, product-visual evidence, or native-app QA
and are not a completion requirement. Architecture and plan correctness come
from primary-source decisions, cross-contract review, feasibility gates, and
executable acceptance criteria; product screenshots begin only when the
corresponding native UI or browser-visible product artifact exists.

The repository evidence manifest records the parent commit, an explicit
path-and-hash inventory of reviewed inputs and outputs (excluding any impossible
self-hash), toolchain and dependency versions, commands, machine profile, test
results, screenshots, traces, logs, budget table, findings and closure, streak
counter, and explicitly unverified items. The commit message binds the final
staged Git tree ID and manifest hash; post-push CI or verification evidence then
binds the resulting commit ID to both without rewriting the committed tree.

## 25. T0 architecture kill switches

| Gate | Required evidence | If it fails |
| --- | --- | --- |
| Zig compiler and ABI | Differential C ABI fixtures, ReleaseSafe/ReleaseFast known answers, reproducible build, SIMD corpus | Pin a verified stable or reviewed patch release; stop T1 if a reproducible miscompile remains |
| Editor | 10 MiB source behavior, IME/BiDi corpus, TextPattern2, screen reader, batched styling, startup and working set | Spike RichEdit or a narrower custom text host; do not mask failure with a wrapper |
| Presentation | ETW/PresentMon submission, photon, dropped-frame, occlusion, WARP, RDP, and device-loss evidence | Profile first; spike DirectComposition or a custom text path only for a proved bottleneck |
| PDF | Minimal binary size, hostile corpus, search, selection, SyncTeX geometry, bounded memory, isolation | Move preview into a lazy verified pack or select a different engine; do not remove isolation |
| Data | Power-loss, WAL recovery, hash-chain, projection atomicity, search rebuild, divergence import | Reopen the ledger design before scientific features depend on it |

The current candidate remains selected only while these gates pass. This makes
"fast and light" a falsifiable engineering claim rather than a style slogan.

## 26. Error and recovery contract

Errors have a stable code, user-facing summary, technical context for logs,
affected project and revision, retryability, retained safe state, and recovery
action. Secrets and unnecessary source content are redacted.

Representative behavior:

| Failure | Required result |
| --- | --- |
| Compiler hangs | Cancel or kill bounded job; keep last-good PDF; show affected revision |
| New edit supersedes compile | Discard stale result even if it exits successfully |
| PDF is malformed | Isolated worker fails; UI remains alive; previous artifact remains available |
| GPU device removed | Recreate resources; preserve source and selection; fall back to WARP if necessary |
| Watcher overflow | Bounded rescan and explicit merge state; no silent overwrite |
| Snapshot exceeds count, size, or external-root policy | Stop isolated staging; offer exact exclusions/root approval or labeled host access; never compile a silent partial tree |
| Ledger write fails | Event and projection both roll back; scientific state remains at prior revision |
| Ledger migration fails | Preserve verified pre-migration database; open prior state or read only; report failed invariant |
| Recovery journal cannot append or flush | Keep the live buffer, mark recovery unprotected, stop durable acknowledgement, and require save/export/repair or explicit discard before close |
| Search index corrupts | Rebuild from ledger; no accepted evidence is lost |
| Provider returns 429 | Honor retry policy; retain other providers; label freshness |
| Untrusted content requests a tool or new URL | Treat it as inert data; preserve current authority; require broker validation and new consent where scope expands |
| Worker floods or violates IPC | Apply backpressure, disconnect and terminate bounded job; keep UI and last safe state alive |
| External agent returns stale patch | Reject automatic apply; recompute or show merge |
| EPUB contains traversal or active content | Reject publish artifact and report exact member |

## 27. Requirement traceability

| Requested outcome | Design evidence | Final implementation proof |
| --- | --- | --- |
| Entire Oleafly runtime in Zig | Sections 5 and 7 | Cutover source inventory and packaged-binary dependency audit |
| Extremely fast, light, smooth, efficient | Sections 4, 6, and 25 | 30-run startup/WS traces, PresentMon, energy and low-tier matrix |
| Live render | Section 10 | revision/cancellation fault tests and source-to-photon runtime journey |
| LaTeX, TexLab, multi-file | Sections 8 and 9 | T1.1/T1.2 native journeys |
| PDF and bidirectional SyncTeX | Sections 10 and 11 | exact artifact/anchor navigation corpus |
| Tectonic plus traditional fallback | Sections 5 and 10 | isolated pack and host-access compatibility tests |
| Zotero and literature search | Section 14 | provider contracts, rate-limit, offline, dedup, and provenance tests |
| Claim-evidence graph and citation verification | Sections 12 and 13 | ledger invariants, anchor corpus, verification-vector UIA journey |
| Exact and honest scientific quantities | Sections 12 and 13 | decimal/unit/uncertainty round trips, calculation receipts, clock rollback and chain tests |
| Native intelligent assistant and external agents | Section 15 | patch safety, consent, adapter contracts, and no-AI fallback |
| Scientific audits and Reviewer 2 | Section 16 | deterministic/model separation and benchmarked finding corpus |
| Git and automatic checkpoints | Section 17 | recovery corruption tests and explicit Git operation journeys |
| PDF, source, EPUB | Section 18 | deterministic artifact hashes, validators, and browser EPUB QA |
| Word import utility | Section 18.4 | fixture imports and ambiguity report |
| Easy and visually distinctive | Section 19 | UIA task journeys, visual matrix, usability and onboarding checks |
| Accessible and international-text safe | Sections 19 and 20 | contrast-token audit, UIA/screen-reader/keyboard journeys, IME/BiDi/locale matrix |
| Local-first privacy and bounded authority | Sections 15, 17, and 21 | process/IPC/egress adversarial tests, ACL inspection, disclosure and redaction journeys |
| Strict review and two clean passes per part | Section 24 | per-commit evidence manifest and streak state |
| Removed generic product areas | Section 3.4 | final production graph and route/command inventory |

## 28. Decision evidence and primary references

The original design exploration covered renderer, editor, PDF, I/O, compiler,
data and search, local intelligence, startup and distribution, scientific UX,
low-end/RDP/power, and supply chain. The reproducible adversarial re-review is
recorded in
[the spec review evidence](2026-09-03-oleafly-zig-scientific-ai-ide-design-review.md).
It found no replacement that satisfies the full constraint set, but it did find
contract gaps that this revision closes. Because a paper comparison cannot prove
runtime behavior, C+ remains provisional behind the T0 kill switches rather
than being presented as mathematically certain.

- [Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html)
- [Zig build system](https://ziglang.org/learn/build-system/)
- [Microsoft: DXGI flip model](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model)
- [Microsoft: DXGI swap effects and partial-presentation constraint](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ne-dxgi-dxgi_swap_effect)
- [Microsoft: flip model, dirty rectangles, and scrolled areas](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-2-presentation-improvements)
- [Microsoft: waitable swap-chain latency](https://learn.microsoft.com/en-us/windows/uwp/gaming/reduce-latency-with-dxgi-1-3-swap-chains)
- [Microsoft: `Present1` dirty rectangles](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgiswapchain1-present1)
- [PresentMon console metrics](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)
- [Microsoft: Direct2D overview and software/RDP behavior](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-overview)
- [Microsoft: device-loss handling](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
- [Microsoft: Desktop Duplication API](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api)
- [Microsoft: `IDXGIOutput5::DuplicateOutput1`](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_5/nf-dxgi1_5-idxgioutput5-duplicateoutput1)
- [Microsoft: Desktop Duplication frame acquisition](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutputduplication-acquirenextframe)
- [Microsoft: Windows Graphics Capture](https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture)
- [Microsoft: `PrintWindow` behavior](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-printwindow)
- [NIST: combinatorial testing](https://www.nist.gov/publications/combinatorial-testing)
- [Microsoft: Windows thread pools](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-pools)
- [Microsoft: process quality of service](https://learn.microsoft.com/en-us/windows/win32/procthread/quality-of-service)
- [Microsoft: creating processes and explicit handle inheritance](https://learn.microsoft.com/en-us/windows/win32/procthread/creating-processes)
- [Microsoft: launching an AppContainer](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)
- [Microsoft: access-control lists](https://learn.microsoft.com/en-us/windows/win32/secauthz/access-control-lists)
- [Microsoft: named-pipe security and access rights](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)
- [Microsoft: file-mapping security and access rights](https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping-security-and-access-rights)
- [Microsoft: shared-memory synchronization and lifetime](https://learn.microsoft.com/en-us/windows/win32/memory/sharing-files-and-memory)
- [Microsoft: `MapViewOfFile` access and cross-process coherence](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-mapviewoffile)
- [Microsoft: `DuplicateHandle` object identity](https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-duplicatehandle)
- [Microsoft: `UnmapViewOfFile` process-local scope](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-unmapviewoffile)
- [Microsoft: D3D11 `UpdateSubresource1`](https://learn.microsoft.com/en-us/windows/win32/api/d3d11_1/nf-d3d11_1-id3d11devicecontext1-updatesubresource1)
- [Microsoft: `CryptProtectData`](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)
- [Microsoft: Windows 10 end of support](https://learn.microsoft.com/en-us/lifecycle/products/windows-10-home-and-pro)
- [Microsoft: Windows 11 release health](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
- [Scintilla documentation](https://scintilla.org/ScintillaDoc.html)
- [Scintilla 5.6.6 exact source tree](https://sourceforge.net/p/scintilla/code/ci/rel-5-6-6/tree/)
- [Microsoft RichEditD2D challenger](https://devblogs.microsoft.com/math-in-office/richeditd2d-window-controls/)
- [PDFium source and public ABI](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/README.md)
- [PDFium view API](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdfview.h)
- [PDFium text/search API](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_text.h)
- [PDFium progressive API](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_progressive.h)
- [Rejected MuPDF error boundary](https://mupdf.readthedocs.io/en/latest/reference/c/overview.html)
- [SQLite FTS5](https://sqlite.org/fts5.html)
- [SQLite WAL](https://www2.sqlite.org/wal.html)
- [SQLite floating-point numbers](https://sqlite.org/floatingpoint.html)
- [SQLite Online Backup API](https://sqlite.org/backup.html)
- [SQLite release history](https://sqlite.org/changes.html)
- [UCUM unit specification](https://ucum.org/ucum)
- [Tectonic compile CLI](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html)
- [latexmk](https://www.ctan.org/pkg/latexmk/)
- [ONNX Runtime custom build](https://onnxruntime.ai/docs/build/custom.html)
- [BEIR retrieval benchmark](https://arxiv.org/abs/2104.08663)
- [SciFact-Open generalization study](https://aclanthology.org/2022.findings-emnlp.347/)
- [Reciprocal rank fusion paper](https://research.google/pubs/reciprocal-rank-fusion-outperforms-condorcet-and-individual-rank-learning-methods/)
- [Microsoft: MSIX differential updates](https://learn.microsoft.com/en-us/windows/msix/app-package-updates)
- [Microsoft: MSIX package signing](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview)
- [Microsoft: secure DLL loading](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-security)
- [GitHub Actions security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [Windows typography](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography)
- [Windows accessibility](https://learn.microsoft.com/en-us/windows/apps/develop/accessibility)
- [Microsoft: Windows Narrator guide](https://support.microsoft.com/en-us/windows/complete-guide-to-narrator-e4397a0d-ef4f-b386-d8ae-c172f109bdb1)
- [Overleaf source and PDF workflow](https://docs.overleaf.com/getting-started/how-do-i-use-overleaf/redesigned-overleaf-editor)
- [Zotero collections and tags](https://www.zotero.org/support/collections_and_tags/)
- [MCP 2026-07-28 release](https://blog.modelcontextprotocol.io/posts/2026-07-28/)
- [MCP tool security considerations](https://modelcontextprotocol.io/specification/draft/server/tools)
- [RFC 8785 JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)
- [RO-Crate 1.3](https://www.researchobject.org/ro-crate/specification/1.3/index.html)
- [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/)
- [W3C EPUB Accessibility 1.1](https://www.w3.org/TR/epub-a11y-11/)
- [W3C EPUBCheck](https://www.w3.org/publishing/epubcheck/)
- [W3C WCAG 2.2](https://www.w3.org/TR/WCAG22/)

## 29. Approval and next gate

The architecture, live-render model, scientific data and AI boundaries,
migration strategy, QA protocol, performance contract, and Evidence Instrument
direction are approved. The written spec's separate adversarial review and
repair record is captured in the linked review evidence. T0.1 is complete on
`main`; the next gate is the independently reviewed T0.2 plan. T0.2
implementation remains unauthorized until that plan records two consecutive
closed-coverage reviews with no Medium-or-higher finding. Every later slice
receives its own plan only after the previous slice has passed its gates,
committed, and pushed.
