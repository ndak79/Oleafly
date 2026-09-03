# Oleafly Zig Scientific AI IDE Design

| Field | Decision |
| --- | --- |
| Status | Architecture checkpoints approved; written spec pending review; implementation has not started |
| Decision date | 2026-09-03 |
| Baseline | `2b389eaf7379531e661fabbce22918b123c805ea` |
| Target | Windows-first native desktop application |
| Product source of truth | Plain-folder LaTeX source, with `.tex` authoritative |
| Product loop | Research -> Evidence -> Write -> Cite -> Compile -> Review -> Publish |
| Publishing boundary | PDF, LaTeX source package, and EPUB |
| Architecture label | C+ event-driven native instrument |

This document records the four approved design checkpoints for rewriting
Oleafly. It is a design contract, not a claim that the rewrite already exists.
The legacy React, TypeScript, Tauri, and Rust application remains the behavioral
oracle until a verified Zig slice replaces each journey.

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
decision model scored C+ at 90.84/100. In 100,000 bounded sensitivity trials,
C+ won 99,876 and the original native option won 124. This is decision
evidence, not runtime benchmark evidence. Train T0 can reject the architecture
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
    contain no new medium-or-higher finding.

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

The first release target is x64 Windows 10 22H2 build 19045 and x64 Windows 11
build 22621 or newer. APIs are resolved by capability and retain the documented
solid, WARP, and non-Mica fallbacks. macOS, Linux, native ARM64, and Windows on
ARM performance are outside this rewrite; adding any of them requires a
separate design and benchmark decision.

The matrix covers both target Windows families, 60/120/144 Hz,
100/150/200 percent DPI, hardware rendering, WARP, and RDP. Startup metrics use
30 fresh processes per machine. Interaction metrics report p50, p95, p99,
dropped presentation ratio, refresh rate, and present mode. A mean alone is not
release evidence.

### 4.2 Release budgets

| Metric | Gate |
| --- | --- |
| Core installer, excluding optional packs | <= 30 MiB |
| Cold interactive start p95 | <= 400 ms |
| Warm interactive start p95 | <= 150 ms |
| Empty-shell idle working set | <= 45 MiB |
| Working set with a 30-page PDF open | <= 100 MiB |
| Cached edit input to frame submission p95 | <= 4 ms |
| All-input to photon p95 | <= `min(25 ms, 2R)`, where `R` is one refresh period |
| Dropped presentations during a 10,000-edit trace | <= 0.1 percent |
| Fixed render or polling timers while occluded | zero |
| Live-render scheduling delay in Auto mode | adaptive 220-750 ms |
| Superseded compiler grace before cancellation | 75 ms |
| Visible stale artifact presented as current | zero |

The former idea of an 8 ms input-to-screen gate is rejected. A 60 Hz display
has a 16.67 ms refresh period, so that number would be physically dishonest.
Oleafly measures input QPC, state mutation, layout, frame submission, present,
display, and photon-oriented latency separately. TraceLogging and ETW provide
application events; PresentMon supplies presentation metrics such as
`MsUntilDisplayed` and `MsAllInputToPhotonLatency`.

### 4.3 Energy contract

- Foreground interaction uses normal or high quality of service only while
  necessary to satisfy input latency.
- Indexing, embedding, and maintenance work uses EcoQoS and low memory
  priority when the platform supports it.
- Minimized or fully occluded windows do not wake for fixed rendering,
  animation, indexing, or status polling.
- Compilation may continue while occluded only when the user requested it or
  an active publish operation depends on it.

## 5. Shipped-code policy

### 5.1 What "all Zig" means

All new Oleafly-owned runtime logic, worker logic, CLI behavior, migrations,
protocol adapters, parsers written by the project, benchmark harnesses, and
native UI automation harnesses are Zig. After cutover, the shipped application
contains no Oleafly-owned TypeScript, JavaScript, Rust, C#, or C++ executable
logic.

Declarative assets are not executable-language exceptions. The repository may
contain GitHub Actions YAML, MSIX XML, Windows resources, JSON/TOML schemas,
icons, test fixtures, licenses, and documentation. Reviewed upstream native
libraries and external tools are also not rewritten merely to satisfy a label.

### 5.2 Native dependency candidates

| Capability | Candidate | Boundary |
| --- | --- | --- |
| Source editor | Scintilla/Lexilla 5.6.6 candidate pin | Native C++ source, direct interface, wrapped by a narrow Zig ABI |
| PDF | MuPDF 1.28.x candidate pin | Minimal PDF-only C build in an isolated worker |
| Database and full-text search | SQLite 3.53.4 or newer reviewed patch release | Pinned amalgamation, FTS5 enabled |
| Graphics | D3D11, DXGI, Direct2D, DirectWrite, DWM | Windows system APIs |
| Accessibility | UI Automation and Text Services Framework | Windows system APIs |

Candidate versions are frozen only after Train T0 reproduces their source,
license, ABI, binary size, security, and performance evidence. Dependency
archives and generated binaries are checksum pinned. Dynamic libraries load
only by absolute path with the appropriate `LOAD_LIBRARY_SEARCH_*` policy and
verified hash or signature.

### 5.3 External tool packs

Tectonic, TexLab, Pandoc, and an optional portable Git distribution may be
downloaded as explicit, signed or checksum-pinned packs. An installed TeX Live,
MiKTeX, latexmk, Git, or Pandoc can be used through a clearly labeled host
access mode. These tools are never loaded into the UI process.

The core remains usable when no pack exists. A missing pack creates a precise
capability state and one clear installation action; it does not create a crash,
spinner without a bound, or silent fallback to an unreviewed executable.

## 6. Runtime architecture

```text
oleafly.exe
|
+-- UI process
|   +-- Win32/DWM shell
|   +-- D3D11/DXGI/Direct2D/DirectWrite compositor
|   +-- Scintilla host and Oleafly UIA provider
|   +-- immutable application snapshots
|   +-- typed worker clients
|
+-- oleafly.exe --worker=pdf
|   +-- minimal MuPDF document server
|   +-- display-list and tile rendering
|   +-- text/search/selection extraction
|
+-- oleafly.exe --worker=science
|   +-- ledger writer
|   +-- derived FTS indexer
|   +-- deterministic audits
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

An isolated worker receives only duplicated handles, shared read-only sections,
or brokered bytes for the declared snapshot. It does not receive ambient access
to the project folder. A compatibility compiler that cannot consume brokered
inputs receives a revision-specific snapshot directory and an honestly labeled
host-access boundary.

### 6.1 Ownership and scheduling

- The UI STA owns HWNDs, the D3D11 immediate context, swap chain, D2D device
  context, DirectWrite resources, focus, and the current immutable view model.
- A private Windows thread pool handles short overlapped file I/O, waits, and
  timers. Completion callbacks publish immutable results and never touch UI
  objects.
- A bounded CPU pool has at most `min(physical_cores - 1, 4)` workers.
- `ledger.db` has one writer. Readers use independent read-only connections.
- The PDF worker has one document-server thread that creates display lists and
  cloned MuPDF contexts for bounded raster workers.
- Compiler, language server, model, and provider work never holds a UI lock.
- No lock is held across IPC, filesystem, network, database, or process waits.

`CancelIoEx` targets the exact overlapped operation. Every subprocess is
assigned to a Job Object with kill-on-close, process count, memory, CPU, and
wall-clock bounds appropriate to the task.

### 6.2 Presentation path

The compositor uses a two-buffer DXGI flip-discard swap chain with a frame
latency waitable object and maximum frame latency of one. It waits before
rendering, submits only when a dirty region exists, and uses `Present1` dirty
and scroll rectangles when correct. The application does not run a fixed 60 or
120 fps loop.

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

The filesystem watcher uses `ReadDirectoryChangesW` with overflow recovery by
bounded rescan. A clean externally changed buffer reloads. A dirty buffer enters
a three-way merge using saved base, local buffer, and external file. Oleafly
never discards either version automatically.

Path handling is case-aware, long-path aware, reparse-point aware, and rooted
in a user-approved workspace. Every write uses a same-directory temporary file,
flush policy appropriate to the data, and atomic replacement where the target
filesystem supports it.

## 9. Editor and language intelligence

Scintilla is retained provisionally because it provides a mature source-editor
surface, large-file behavior, indicators, completion, wrapping, and DirectWrite
rendering without a browser runtime. Oleafly calls its direct interface for
high-frequency operations instead of sending synchronous window messages.
Styling and diagnostics are batched.

Oleafly supplies its own UI Automation provider with TextPattern and
TextPattern2 support, selections, visible ranges, caret, line and document
navigation, editable state, names, roles, states, and keyboard accelerators.
Train T0 tests Vietnamese, CJK, Arabic, IME composition, surrogate pairs,
combining marks, bidirectional selection, screen readers, and Accessibility
Insights. Scintilla does not pass merely because ordinary Latin typing works.

TexLab runs as a bounded external process over JSON-RPC/LSP. The client:

- validates message size and schema;
- associates diagnostics with document and project revisions;
- cancels superseded requests;
- restarts with exponential backoff and a visible status;
- never blocks editing when unavailable;
- does not let an LSP workspace edit bypass the normal diff and path policy.

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
store while their hashes are verified. The revision build tree consists only of
read-only links or copies to those verified blobs. The compiler never reads a
mutating user project tree. A changed or newly discovered dependency creates a
new project revision instead of modifying an active snapshot.

Build directories are revision specific. At most one compiler job is active and
one latest request is pending. A new edit supersedes the active job. The job
receives a 75 ms cooperative grace period and is then terminated through its
Job Object if still alive. Intermediate logs and diagnostics are coalesced to at
most 30 UI updates per second.

### 10.3 Artifact acceptance

An artifact can become current only if all of these checks pass:

1. compiler termination and output contract are valid;
2. PDF header, size, page tree, and bounded parse succeed;
3. source fingerprints match the compile snapshot;
4. artifact revision is still the latest accepted revision;
5. SyncTeX, when declared, belongs to the same artifact set;
6. the immutable artifact hash has been recorded.

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

Tectonic runs with a pinned bundle and, where supported, `--untrusted`,
`--only-cached`, and `--synctex`. System TeX and latexmk are compatibility mode
because their package and shell behavior cannot be represented as equally
isolated. Shell escape is off by default and requires a precise, project-scoped
approval.

## 11. PDF preview

MuPDF is built for PDF only. JavaScript, EPUB reading, HTML, XPS, OCR, barcode,
and unrelated converters are disabled. The worker applies input size, page,
object, recursion, allocation, CPU, and wall-clock limits before content reaches
the UI process.

The document-server thread creates immutable display lists. Bounded render
workers use cloned MuPDF contexts to raster visible pages. The cache uses 512 px
RGBA tiles, prioritizes viewport plus or minus one page, and enforces a 32-64
MiB adaptive LRU limit. Upload work per frame is bounded so a new page cannot
starve typing or scrolling.

Search, selection, links, annotations used for evidence, page geometry,
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

- normalized quotation plus preserved original text;
- leading and trailing context;
- byte and character offsets when available;
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

### 13.1 `ledger.db`

- single writer;
- WAL mode with `synchronous=FULL`;
- immutable canonical events and normalized projections written in the same
  transaction;
- UUIDv7 event IDs;
- previous-event hash and SHA-256 event hash;
- canonical JSON compatible with RFC 8785 JCS for portable event material;
- schema version and deterministic migrations;
- no model-generated overwrite of an accepted human assessment.

If a projection write fails, the event does not commit. If recovery detects a
hash-chain or database integrity failure, the ledger becomes read only until a
verified repair or restore completes.

### 13.2 `search.db`

- derived and fully rebuildable;
- FTS5 with BM25, phrases, prefix terms, NEAR, and a reviewed scientific
  tokenizer;
- WAL mode with `synchronous=NORMAL`;
- batched commits;
- indexed-ledger watermark;
- content and schema fingerprints;
- corruption or deletion cannot change the ledger.

Core ranking combines lexical BM25 with exact DOI, citekey, provider ID, claim,
and anchor boosts. This is the always-available smart path.

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

### 14.2 Provider federation

Each provider adapter returns a normalized record plus raw provenance. Requests
use bounded concurrency, backoff, `Retry-After`, conditional caching where
supported, and a user-visible provider state. One failing or rate-limited
provider cannot erase successful results from another.

Provider-specific fields remain namespaced. Crossref, PubMed, OpenAlex, arXiv,
and Semantic Scholar are not treated as equivalent authorities for every
field. Scholarly status records both value and check time.

Literature review groups works, records inclusion and exclusion decisions,
links notes to exact expressions or artifacts, and makes model-written summaries
visibly distinguishable from quotations and human notes.

### 14.3 PDF paper library

The library can reference files in place or copy them into a user-selected
managed directory. Deduplication uses artifact hashes and exact identifiers.
Full text is derived data and can be deleted or rebuilt without deleting the
paper record, note, claim, or evidence edge.

Scanned papers use an optional, explicitly invoked OCR pack rather than adding
OCR to MuPDF or the core. Every OCR text layer records artifact hash, engine and
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
- MCP starts from the reviewed 2026-07-28 protocol candidate and negotiates an
  explicit, compatibility-tested fallback rather than guessing capabilities.

The adapter layer normalizes session, progress, diff, tool request, citation,
usage, cancellation, and error events. It does not pretend providers have
identical semantics.

### 15.3 Tool surface

Default tools are narrow and typed: read an approved source snapshot, read a
selection, search literature or the local index, query evidence, propose a
patch, compile, run a named audit, and inspect a declared artifact. There is no
default generic shell, arbitrary filesystem write, delete, registry, or process
tool.

Every patch carries base hashes and exact ranges. Accept applies only unchanged
hunks; reject changes nothing. A stale patch is recomputed or merged visibly.
Rollback is a first-class operation and records its provenance.

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

Startup recovery validates records, reconstructs into a temporary state, and
shows exact recoverable files before overwriting disk. A corrupt tail is
quarantined while the last valid prefix remains usable.

Git uses a typed Zig adapter over a discovered executable or optional verified
portable pack. Arguments are passed as an array without shell interpolation.
Repository root, worktree state, operation, paths, output, and exit code are
normalized. Destructive actions require exact previews and user intent. Oleafly
does not auto-commit, auto-push, rewrite history, or combine recovery
checkpoints with Git commits.

## 18. Publishing

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

### 18.3 EPUB

EPUB 3.3 is the intentional retained target. Pandoc is an optional, pinned
external pack for semantic conversion. Zig orchestration supplies explicit
inputs and arguments, disables implicit shell behavior, validates every
produced path, sanitizes active content, verifies manifest and spine
references, and performs a deterministic final ZIP assembly with `mimetype`
first and uncompressed.

The EPUB checker covers container structure, OPF metadata, navigation, media
types, internal links, image bounds, language, title, author, accessibility
metadata, and archive traversal. Browser QA opens the unpacked reading order at
the supported viewport matrix and checks console, network, keyboard navigation,
reflow, reduced motion, and high contrast.

Release fixtures and every release-candidate EPUB also pass the official
EPUBCheck command in CI. EPUBCheck and its Java runtime are not bundled with the
desktop core; interactive publishing uses the native Zig checks, while an
optional verified validation pack can provide the same deep conformance check
on the user's machine.

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
- 761-1180 logical px: Source + PDF, with Project as a flyout.
- At or below 760 logical px: one focus surface plus a clear switcher.
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
- Keyboard-only operation covers every primary journey and drawer.
- Focus is never hidden by a panel transition or async result.
- High contrast does not depend on custom color tokens.
- Reduced motion removes nonessential animation without removing status change.
- Screen reader announcements are coalesced and never repeat compiler log spam.
- Vietnamese, composed and decomposed Unicode, CJK, Arabic, bidirectional text,
  surrogate pairs, and IME composition are test fixtures.

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

### 21.2 Process containment

Compatible parsers and intelligence workers run in AppContainer with explicit
capabilities. External compilers run under the strongest compatible restricted
token and Job Object policy, and the UI labels any remaining host access
honestly. `CreateProcessW` receives an absolute executable path, quoted argument
array, minimal environment block, declared working directory, and handle
allowlist. Oleafly does not invoke `cmd.exe` or PowerShell for product actions.

Archive extraction rejects absolute paths, drive changes, device names,
alternate streams, traversal, unexpected symlinks, duplicate normalized names,
and declared-size or compression-ratio bombs. Downloads verify reviewed hash or
signature before extraction into staging and atomic activation.

Network providers are opt in. The UI shows destination and data class before
first disclosure and when capability expands. Telemetry is off unless a later,
separately approved design introduces it.

## 22. Distribution and updates

The application ships as a signed MSIX and a first-class portable ZIP. MSIX
uses block-level differential update support and clean uninstall behavior. The
portable build stores mutable data outside its executable directory unless the
user explicitly selects portable-data mode.

There is no custom updater in the core. MSIX/App Installer or the distribution
channel handles updates. Optional packs have separate signed manifests,
versions, licenses, source offers where required, hashes, size, and revocation
state. Packs activate atomically and can roll back independently of the core.

Startup loads only the shell, editor boundary, and settings required for the
first frame. The science worker, MuPDF, TexLab, compiler, Git pack, Pandoc,
provider adapters, and model runtime start after the first frame and only when
the current journey needs them.

### 22.1 Licensing and source obligations

The rewritten project remains AGPL-3.0-or-later. MuPDF's AGPL option is
compatible with that distribution model. Scintilla/Lexilla, SQLite, ONNX
Runtime, models, compiler packs, language servers, and every transitive native
component receive an audited license record, source location, version, hash,
notices, and source-offer treatment before packaging. A technically attractive
dependency does not ship until license compatibility and redistribution terms
are proved for both MSIX and portable ZIP.

## 23. Migration strategy

The rewrite proceeds beside the legacy tree as a vertical walking skeleton.
The legacy app is a development oracle only. No release packages both runtimes,
and there is no long-lived Zig shell around a React/Tauri application.

This document is the umbrella system design. Each table row below is a bounded
delivery subproject with its own implementation plan, acceptance evidence, and
commit. A later slice returns to a focused design-delta review only when it
introduces a decision not resolved here. The first writing-plans phase covers
T0.1 only; it does not create one unreviewable plan for the entire rewrite.

### 23.1 Six trains, twelve bounded slices

| Slice | Shippable proof |
| --- | --- |
| T0.1 Toolchain | Pinned Zig build, Windows executable, reproducible dependency graph, ABI and miscompile corpus |
| T0.2 Native feasibility | Waitable flip presentation, startup/working-set trace, Scintilla direct API/UIA/IME, minimal MuPDF, split SQLite crash tests |
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

Each slice is end to end. For example, T1.2 is not "write the PDF module"; it
proves that a user edit can compile, produce validated current output, navigate
in both directions, survive failure, and remain responsive.

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
   medium-or-higher finding.
6. **Commit and push**: create one atomic commit with an evidence manifest and
   push it before beginning the next slice.

Any new medium-or-higher bug or gap, unexplained flake, crash, console error,
budget regression, accessibility blocker, stale evidence represented as
current, or mutation that the intended test fails to catch resets the streak to
zero. Fixing a finding is followed by the full affected matrix, not only the
single failing test.

### 24.1 Five-pass test-effectiveness review

1. Verify that each test oracle matches the user-visible contract.
2. Verify that the portfolio covers happy, error, boundary, concurrency,
   cancellation, recovery, security, accessibility, and performance surfaces.
3. Add adversarial inputs for parsers, processes, revisions, and external tools.
4. Falsify the suite with targeted mutations or fault injection.
5. Prove runtime reality using the packaged or release-equivalent binary.

Coverage percentage alone is never evidence that faults are detected.

### 24.2 Dual QA lane

The native lane uses a repo-owned Zig harness over `IUIAutomation` for launch,
Open Folder, edit, save, compile, SyncTeX, research, evidence, diff, accept,
reject, recovery, and publish journeys. It captures Windows screenshots at the
defined DPI, theme, renderer, RDP, and viewport matrix.

The browser lane validates browser-visible artifacts: design companions,
evidence reports, generated HTML, unpacked EPUB reading order, documentation
previews, source links, console and network behavior, keyboard traversal,
reflow, and accessibility semantics. Browser tests never stand in for native
Windows interactions.

An evidence manifest records commit, toolchain and dependency versions,
commands, machine profile, test results, screenshots, traces, logs, budget
table, findings and closure, streak counter, and explicitly unverified items.

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
| Ledger write fails | Event and projection both roll back; scientific state remains at prior revision |
| Search index corrupts | Rebuild from ledger; no accepted evidence is lost |
| Provider returns 429 | Honor retry policy; retain other providers; label freshness |
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
| Native intelligent assistant and external agents | Section 15 | patch safety, consent, adapter contracts, and no-AI fallback |
| Scientific audits and Reviewer 2 | Section 16 | deterministic/model separation and benchmarked finding corpus |
| Git and automatic checkpoints | Section 17 | recovery corruption tests and explicit Git operation journeys |
| PDF, source, EPUB | Section 18 | deterministic artifact hashes, validators, and browser EPUB QA |
| Word import utility | Section 18.4 | fixture imports and ambiguity report |
| Easy and visually distinctive | Section 19 | UIA task journeys, visual matrix, usability and onboarding checks |
| Strict review and two clean passes per part | Section 24 | per-commit evidence manifest and streak state |
| Removed generic product areas | Section 3.4 | final production graph and route/command inventory |

## 28. Decision evidence and primary references

The research plateau was reached after 18 distinct challenger rounds covering
renderer, editor, PDF, I/O, compiler, data and search, local intelligence,
startup and distribution, scientific UX, low-end/RDP/power, and supply chain.
The final two rounds found no better architecture and only strengthened WARP,
device-loss, occlusion, compiler, and ABI tripwires.

- [Zig 0.16 release notes](https://ziglang.org/download/0.16.0/release-notes.html)
- [Zig build system](https://ziglang.org/learn/build-system/)
- [Microsoft: DXGI flip model](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model)
- [Microsoft: waitable swap-chain latency](https://learn.microsoft.com/en-us/windows/uwp/gaming/reduce-latency-with-dxgi-1-3-swap-chains)
- [Microsoft: `Present1` dirty rectangles](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgiswapchain1-present1)
- [PresentMon console metrics](https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md)
- [Microsoft: Direct2D overview and software/RDP behavior](https://learn.microsoft.com/en-us/windows/win32/direct2d/direct2d-overview)
- [Microsoft: device-loss handling](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
- [Microsoft: Windows thread pools](https://learn.microsoft.com/en-us/windows/win32/procthread/thread-pools)
- [Microsoft: process quality of service](https://learn.microsoft.com/en-us/windows/win32/procthread/quality-of-service)
- [Scintilla documentation](https://scintilla.org/ScintillaDoc.html)
- [Microsoft RichEditD2D challenger](https://devblogs.microsoft.com/math-in-office/richeditd2d-window-controls/)
- [MuPDF C overview](https://mupdf.readthedocs.io/en/latest/reference/c/overview.html)
- [MuPDF build switches](https://github.com/ArtifexSoftware/mupdf/blob/master/Makerules)
- [SQLite FTS5](https://sqlite.org/fts5.html)
- [SQLite WAL](https://www2.sqlite.org/wal.html)
- [SQLite release history](https://sqlite.org/changes.html)
- [Tectonic compile CLI](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html)
- [latexmk](https://www.ctan.org/pkg/latexmk/)
- [ONNX Runtime custom build](https://onnxruntime.ai/docs/build/custom.html)
- [BEIR retrieval benchmark](https://arxiv.org/abs/2104.08663)
- [SciFact-Open generalization study](https://aclanthology.org/2022.findings-emnlp.347/)
- [Reciprocal rank fusion paper](https://research.google/pubs/reciprocal-rank-fusion-outperforms-condorcet-and-individual-rank-learning-methods/)
- [Microsoft: MSIX differential updates](https://learn.microsoft.com/en-us/windows/msix/app-package-updates)
- [Microsoft: secure DLL loading](https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-security)
- [Windows typography](https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography)
- [Windows accessibility](https://learn.microsoft.com/en-us/windows/apps/develop/accessibility)
- [Overleaf source and PDF workflow](https://docs.overleaf.com/getting-started/how-do-i-use-overleaf/redesigned-overleaf-editor)
- [Zotero collections and tags](https://www.zotero.org/support/collections_and_tags/)
- [RFC 8785 JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)
- [RO-Crate 1.3](https://www.researchobject.org/ro-crate/specification/1.3/index.html)
- [W3C EPUB 3.3](https://www.w3.org/TR/epub-33/)
- [W3C EPUBCheck](https://www.w3.org/publishing/epubcheck/)

## 29. Approval and next gate

The architecture, live-render model, scientific data and AI boundaries,
migration strategy, QA protocol, performance contract, and Evidence Instrument
direction were approved through four design checkpoints. This written spec must
now receive a separate review. Only after that review is approved may the
writing-plans phase create the executable plan for T0.1. Every subsequent slice
receives its own plan after the previous slice has passed its gates, committed,
and pushed.

No production scaffold, dependency installation, or rewrite code is authorized
by this document alone.
