# TExFlow T0.2 Native Feasibility Implementation Plan

| Review gate | State |
| --- | --- |
| Plan review | `APPROVED` |
| Final clean-pass gate | `1/1` |
| Implementation permission | `T0.2a MAY START`; T0.2b-T0.2h remain sequentially gated by each preceding task's clean review, push, and required remote CI |

The shipped product identity is exactly `TExFlow`. The existing GitHub
repository name `Oleafly` is historical source lineage only and is not a binary,
window-title, package, protocol, telemetry-provider, or user-data-root name.
Legally required source-lineage attribution may retain that historical name in a
shipping notice, but never as the notice title or product/publisher identity.
The frozen legacy implementation remains an unshipped comparison oracle only.
T0.2c retires the installed legacy console artifact, moves its smoke intent to
a test-only Zig gate under the lowercase `texflow` test namespace, and renames
the internal T0.1 ABI/header/symbol namespace to `texflow`; no compatibility
alias is needed because T0.1 has no external ABI consumer.
The main window/ProductName/FileDescription are exactly `TExFlow`; PE
OriginalFilename/InternalName values are role-exact. Declarative version
resources omit legal company/copyright/signer fields until the owner supplies
them for T5.2. Machine identities include `texflow.main.v1` for the window class
and distinct LPAC monikers `texflow.pdfworker.v1` and
`texflow.scienceworker.v1`; a moniker change requires an ACL/profile migration
review.
All three T0.2 images share an explicitly non-release VERSIONINFO tuple:
numeric `0,0,2,0`, `FileVersion=0.0.2.0`,
`ProductVersion=0.0.2-feasibility`, prerelease/private-build flags,
`VOS_NT_WINDOWS32`, `VFT_APP`, Unicode translation `040904B0`, and
`PrivateBuild=T0.2 architecture feasibility; not release-qualified`. T5.2 must
replace the complete tuple from an owner-approved release contract.
The legacy green-leaf icon is explicitly excluded. The UI embeds a reviewed
multi-resolution TExFlow source-to-evidence flow mark; headless workers embed no
UI icon.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:executing-plans` to implement this plan sequentially with
> test-first behavior, review after every task, and fresh verification before
> any completion claim. Do not start T1 while a T0.2 admission gate is failed
> or unverified.

**Goal:** Prove, with measured Windows evidence, that dedicated Zig-owned
TExFlow UI, PDF-worker, and science-worker executables can host a responsive
native scientific-writing shell, a
Scintilla-based UTF-8 editor with a bounded Zig container lexer, real
accessibility, and IME behavior, an
isolated minimal PDF worker using PDFium only through its public C ABI, and
split SQLite durable/search stores while remaining inside the approved
footprint, latency, safety, and provenance budgets.

**Architecture:** The UI process owns Win32, D3D11/DXGI, Direct2D, DirectWrite,
the Scintilla child window, UI Automation providers, and the event loop. The
shipping baseline uses separate `TExFlow.PdfWorker.exe` and
`TExFlow.ScienceWorker.exe` images so no worker maps the Scintilla/UI/graphics
image or the other role's native closure before entry. Shared Zig code remains
source-shared. Versioned named-pipe
protocols, an explicit bootstrap handle, bounded brokered section handles, peer
verification, bounded queues, and per-role sandboxing keep process boundaries
narrow. SQLite's canonical ledger
and disposable search projection remain separate. External C/C++ projects are
compiled from exact pinned upstream sources where this slice owns the build.
The PDF spike statically compares an exact-digest, provenance-checked community
reference binary with an independently rebuilt exact source/recipe artifact. After T0.2b,
only the sealed source-reconstructed artifact may be loaded by the admitted PDF
worker; the community DLL remains reference evidence and never becomes an
admitted runtime dependency. ABI, behavior, size, and performance equivalence
are mandatory before architecture admission. The protected shipping rebuild and
signing gate remains separate. Every new TExFlow-owned runtime, worker, protocol, parser, migration,
benchmark, fixture generator, and native QA client is Zig.

**Tech stack:** Zig 0.16.0 ReleaseSafe; Win32/DPI v2; a UI COM STA plus a
dedicated editor-provider COM STA over immutable Zig snapshots; D3D11; DXGI
two-buffer flip-sequential partial-present baseline plus a flip-discard
full-redraw challenger; Direct2D/DirectWrite; DWM; UI Automation; Scintilla
5.6.6 with a TExFlow Zig LaTeX/BibTeX container lexer; Lexilla 5.5.3 as an
unshipped QA comparator only; PDFium 154.0.8035.0 (`chromium/8035`) without V8/XFA as a
feasibility-only PDF worker dependency; SQLite 3.53.4 with FTS5; ETW/WPR;
WPAExporter; DXGI 1.5 Desktop Duplication plus WIC for native visual evidence;
Windows Narrator; PresentMon 2.5.1 and GitHub CLI 2.100.0 as QA-only tools.
Accessibility Insights for Windows 1.1.2924.01 is a separately installed,
QA-only accessibility cross-oracle and never enters the product or timed
process tree.

---

## 1. Scope, language boundary, and non-goals

T0.2 is a feasibility and admission slice, not the finished IDE. It builds a
representative editor/PDF shell and proves its hard native seams. It does not
add TexLab, Tectonic, SyncTeX, Zotero, literature providers, the claim-evidence
graph, AI providers, Git UX, EPUB export, installer/signing, or production data
migration. Those remain later slices in the approved specification.

The user's "all Zig" constraint means:

- all TExFlow-authored executable behavior is Zig;
- all UI and worker process entry points are Zig; the role-specific PE split is
  a security and working-set boundary, not a non-Zig exception;
- all test harnesses, fixture generators, parsers, fault injectors, UIA clients,
  and benchmark orchestration are Zig;
- declarative files such as manifests, ETW/WPR profiles, JSON lock data, and C
  ABI headers are allowed but contain no application behavior;
- the CI runner may use only the irreducible platform-shell bootstrap needed to
  acquire and verify the pinned Zig executable before Zig exists, then to invoke
  named `zig build` steps. That glue contains no product behavior, dependency
  extraction, parser, fixture, test oracle, result aggregation, or campaign
  decision; all such owned behavior moves behind Zig steps in T0.2a/b;
- the exceptional PDFium reconstruction executes an upstream Chromium/PDFium
  build graph, not TExFlow-owned product behavior. Its controller, policy,
  acquisition ledger, patch verifier, process audit, result parser, and verdict
  remain Zig. A pinned upstream Python/CIPD tool or Windows batch wrapper may run
  only inside the isolated reconstruction environment and only when its exact
  path, content identity, argv source, parent, and purpose are enumerated; no
  TExFlow-authored shell script or ambient interpreter is allowed;
- upstream Scintilla and SQLite remain their original C/C++ source, compiled by
  the Zig build graph behind narrow upstream ABI surfaces; pinned Lexilla may
  execute only in a test comparator over reviewed fixtures and is never linked
  into or loaded by the product;
- the exact PDFium feasibility DLL remains upstream C++ implementation and is
  consumed only through an allowlisted public C ABI that is declared, loaded,
  and lifecycle-managed in Zig; TExFlow adds no C/C++ bridge;
- no TExFlow-owned C/C++ shim, Rust, TypeScript, JavaScript, WebView2, React,
  Tauri, .NET, Qt, WinUI 3, or Windows App SDK runtime is introduced.

ReleaseSafe is the product mode. Debug and ReleaseFast may be built only to
falsify ABI and optimizer assumptions. A dependency that cannot be integrated
without a new TExFlow-owned non-Zig runtime shim fails its gate and triggers its
documented fallback or architecture review.

### 1.1 Roadmap accounting

The approved umbrella roadmap has exactly six trains and twelve named slices:
`T0.1`, `T0.2`, `T1.1`, `T1.2`, `T2.1`, `T2.2`, `T3.1`, `T3.2`, `T4.1`,
`T4.2`, `T5.1`, and `T5.2`. No `T6`, `T7`, hidden slice, or unnumbered delivery
train is approved. T0.1 contains six completed implementation tasks; this T0.2
plan contains eight (`T0.2a` through `T0.2h`), for fourteen detailed tasks so
far. The remaining ten slices receive their task counts only through later
reviewed plans, so fourteen is not represented as the final project total.
Task 7's preregistration and result commits are two atomic checkpoints inside
one task and do not create an undeclared roadmap task.

The representative shell proves layout, rendering, input, accessibility,
worker integration, and measurement. It must not be described as full live
LaTeX render. T0.2 proves versioned edit-to-preview invalidation and replacement
of a visible PDF artifact; later compiler slices connect that path to real
incremental TeX compilation.

## 2. Baseline and admission truth

- T0.1 source and corrected evidence are on `main`. The approved T0.2
  architecture specification at
  `docs/superpowers/specs/2026-09-03-oleafly-zig-scientific-ai-ide-design.md`,
  including SR-75 through SR-132's isolation,
  worker-image, mitigation, naming, transition, IPC, visual-identity, Unicode,
  search, storage, licensing, measurement, publication, build-provenance,
  review-integrity, roadmap/gate ownership, worker-topology, and
  network-ownership corrections, is bound exactly to commit
  `ed30f0adc44aee7fd8a50d9984a690fcd083f511`. The specification's final
  closed-coverage review is accepted at `1/1`; later specification changes
  invalidate this binding and require a reviewed plan delta before execution.
- The current machine is Windows 11 Pro build 26200, Ryzen 7 7700 (8C/16T),
  32 GiB RAM, AMD integrated graphics plus NVIDIA RTX 5060 Ti, SSD, High
  performance power plan. It is a mainstream/high-tier development host.
- CPU affinity, memory limits, WARP, virtual machines, and throttling are useful
  stress conditions; none is accepted as proof from a physical 4-core/8-GiB
  low-tier iGPU machine.
- GitHub-hosted Windows runners prove build/test portability, not display,
  input-to-photon latency, energy, RDP, or low-tier GPU behavior.
- T0.2 may produce a green provisional implementation on the current host, but
  this 32-GiB high-tier configuration does not silently become either reference
  machine. Architecture admission to T1 remains `UNVERIFIED-HARDWARE` until
  exact physical low-tier and mainstream profiles are frozen, both supported OS
  lanes run on both profiles, and their independent cold-boot campaigns pass.
- Browser QA cannot exercise a native HWND/DXGI/UIA surface. Native black-box
  QA is authoritative. Browser QA is required only if the slice emits an HTML
  evidence report; it never substitutes for native UIA, screenshot, ETW, or
  compositor evidence.
- Rendering this prose plan/spec in a browser is at most an optional publication
  smoke test. Its screenshots are not architecture, feasibility, visual-product,
  or quality-streak evidence and are not repeated as a review lane.

## 3. Confirmed representative-shell design brief

This brief implements the already approved option C and constrains T0.2; it is
not a request to broaden the product into a general publishing suite.

| Dimension | Locked direction |
| --- | --- |
| Primary user and job | A researcher repeatedly writing and validating a multi-file LaTeX manuscript during long, focused sessions. |
| Mood | A quiet midnight laboratory desk: deep graphite chrome, paper-white manuscript, restrained cyan/teal evidence signals, warm warning amber only for actionable risk. |
| Visual anchors | Windows-native clarity, Linear/Arc-like compact density, and scientific-journal typography; borrow principles, never copy a product shell. |
| Hierarchy | Editor dominates; PDF is a secondary equal-height work surface; evidence/status is a thin contextual rail rather than a dashboard. |
| Window chrome | System title bar and standard caption controls for Snap, keyboard, DPI, and accessibility reliability. No custom title bar in T0.2. |
| Surfaces | Opaque solid colors, hairline separators, no acrylic/mica dependency, no ornamental gradient, no glass, no floating-card grid. |
| Typography | DirectWrite system UI text for chrome and a crisp scientific monospace editor face; no font download or bundled decorative font. |
| Motion | Motion communicates state only, respects reduced-motion settings, and never drives a fixed idle timer. |
| States | Light, dark, Windows high contrast, 100/125/150/200% DPI, narrow and wide windows, empty/loading/error/worker-crash/occluded/device-loss states. |
| Accessibility | WCAG 2.2 AA contrast (4.5:1 normal text, 3:1 large text/icons/focus), color never sole meaning, >=24x24 effective-pixel pointer targets, visible keyboard focus, deterministic focus restoration, and a complete UIA tree. |
| T0.2 polish bar | Deliberate proportions, baseline alignment, visible focus, coherent tokens, stable resize, and readable captured output; not a fake web dashboard inside a native window. |

The initial sRGB tokens are implementation inputs, not screenshot-picked
approximations. Dark shell/pane are `#10161C`/`#151D24`, primary/muted text
`#E8EFF5`/`#AAB7C2`, structural divider `#607384`, evidence accent `#4FD1C5`,
warning `#F4B860`, and error `#FF7A85`. Light shell/pane are
`#EEF3F6`/`#FFFFFF`, primary/muted text `#16212B`/`#52616D`, divider `#778793`,
accent `#006C67`, warning `#7A4800`, and error `#B42335`. Dark syntax adds
math `#B7A6FF`, citation/link `#7CC4FF`, and comment `#90A0AC`; light syntax
uses `#5E43A6`, `#005EA8`, and the muted text token. The PDF remains opaque
paper `#FBFCFE` with ink `#16212B`. Precomputed relevant token contrast ranges
from 3.47:1 for structural dividers to 16.32:1 for primary text, but runtime
linear-sRGB checks are authoritative. Windows high contrast replaces this
palette with system colors rather than remapping it cosmetically.

Above 1180 DIPs the default workspace is Project + Source + PDF, with a
240-DIP Project minimum and a 58/42 Source/PDF allocation after fixed chrome.
From 880 through 1180 DIPs, Project becomes an accessible flyout and the
Source/PDF ratio clamps while preserving 480-DIP and 360-DIP pane minima. A
6-DIP visible divider sits inside a >=24-DIP keyboard and pointer hit target,
with a 28-DIP status/evidence rail and an 8-DIP spacing rhythm. From 760 through
879 DIPs, Project remains a flyout and PDF collapses behind an explicit
accessible Source/PDF switcher instead of crushing text; focus returns to the
switcher/pane deterministically. Below 760 DIPs, access and reflow remain
available but T0.2 does not claim a supported production layout. The supported
minimum window is 760x520 DIPs. UI text uses Segoe UI Variable with Segoe UI
fallback at no less than 12 DIPs; source uses Cascadia Mono with Consolas
fallback at a measured 13-15-DIP size/line height. Compact controls are 28-32
DIPs and switch to >=44-DIP targets in touch mode; icon-only affordances still
meet the >=24-DIP spacing floor. No font is downloaded or silently bundled.
Focus is a two-DIP non-color-only ring using the theme accent plus shape/state
cue.

The representative shell may use generated scientific fixture bytes only when
the selected workload loads those exact hashed bytes into the real Scintilla/
source model and they are immediately editable; painted sample prose or a
display-only placeholder is forbidden. `W0` is genuinely empty and `W1` loads
its declared corpus. All controls and status text shown must represent real
state. No placeholder button may imply a working AI, citation audit, compile,
or SyncTeX feature.

## 4. Architecture and trust boundaries

```text
TExFlow.exe (UI role, medium integrity, COM STA)
|-- Win32 HWND + system title bar
|   |-- Scintilla child HWND (UTF-8 source truth; UI thread only)
|   |-- D3D11/DXGI waitable flip presenter
|   `-- Direct2D/DirectWrite native chrome and PDF tile composition
|-- TExFlow UIA provider (STA-marshaled; UTF-8 <-> UTF-16 map)
|-- UI-private verified tile staging -> adaptive 32/48/64-MiB GPU LRU
|-- bounded PDF client ---------------------------------------------.
|-- bounded science client -------------------------------------.   |
|-- ETW events + aggregate process-tree accounting              |   |
|                                                               |   |
|   trusted ledger broker boundary (UI process)                |   |
|   |-- writer thread -> canonical ledger.db (WAL/FULL)        |   |
|   `-- serial query-only presentation lane                    |   |
|                                                               |   |
|   TExFlow.ScienceWorker.exe (zero-named-capability LPAC)    |   |
|   |-- authenticated hash-verified complete-field records      |   |
|   `-- disposable search.db (WAL/NORMAL, separate ACL root)    |   |
|                                                               |   |
`-> TExFlow.PdfWorker.exe (zero-named-capability LPAC) <------'   |
    |-- typed/authenticated pipe <-----------------------------------'
    |-- one engine thread owns every PDFium call and object
    |-- priority queue + progressive render pause/cancellation
    `-- generation-unique one-shot 512 px opaque BGRx tile output
```

The UI process does not parse PDF bytes. The PDF worker receives only the
bounded anonymous PDF/tile mappings, its authenticated control pipe, and
read/execute access to a sealed staged runtime containing its verified
role-specific executable and PDFium DLL. Runtime leaf access is file-granular:
the PDF SID may read/execute only `TExFlow.PdfWorker.exe` and read/map/load the
PDFium closure; the science SID may read/execute only
`TExFlow.ScienceWorker.exe` and its SQLite/search closure. Neither role can
open/map/load `TExFlow.exe`, Scintilla/UI/graphics files, or the other worker
image. Inside the TExFlow-owned staging root, every ancestor grants only the measured
traverse/read-attribute/synchronize mask, with no list/create/delete/write;
the controlled product root and leaves set `SE_DACL_PROTECTED` and reject every
inherited, `Everyone`, `Users`, AAP, ARAP, default, null, or generic-mask ACE.
Because Windows intersects the normal user/group check with the AppContainer
restricted-SID check, every required operation is granted to both the exact
current-logon/owner SID and the intended role package SID; management ACEs for
`SYSTEM`/Administrators are separately enumerated. Neither role gets directory
write/delete or ambient product-file access,
and the science role must be denied PDFium enumeration/open/map/load. The PDF role
cannot open the repository or project folder, contact the network, write
arbitrary files, or spawn children. The UI verifies and locks executable/DLL
identity across hashing and load, and rechecks the loaded module identity. The
science worker gets only its verified role image and SQLite/search closure, its
separate derived-search directory, and protocol; it cannot open the canonical-ledger
root. Both
roles are assigned to kill-on-close Job Objects and are included in aggregate
memory, CPU, handle, and startup accounting.

Every worker launch is race-free: construct and fully configure the Job first;
create the LPAC process with `CREATE_SUSPENDED`, the exact inherited-
handle list, and `PROCESS_CREATION_CHILD_PROCESS_RESTRICTED`; assign the retained
process handle to the Job; query back the effective job/active-process/memory/
breakaway state; and only then call `ResumeThread`. Neither breakaway flag is
permitted. Assignment, verification, or resume failure terminates the still-
suspended process, closes the generation, and proves that no worker instruction
ran. A parent-job/nested-job incompatibility is an explicit isolation failure,
not permission to launch outside the intended Job.

Windows gives both regular AppContainer and LPAC profiles a writable
`LOCALAPPDATA`/`TEMP` tree. For both roles this is explicit untrusted scratch, never an input/runtime/
configuration source. Before every worker generation the controller closes all
old handles, calls `DeleteAppContainerProfile` until its documented state is
resolved, recreates the stable role moniker/SID, and verifies an empty,
reparse-free expected profile tree and canonical ACL. It repeats deletion after
clean, crash, and timeout exits; a partial/failed cleanup quarantines the profile
and blocks relaunch. Only the science worker's separately brokered disposable
search directory may persist, and it is never inside or recovered from the
LPAC profile.

An empty named-capability list does not remove ambient OS grants. A regular
AppContainer can use `ALL APPLICATION PACKAGES` resources; LPAC removes that
grant but still uses resources ACL'd for `ALL RESTRICTED APPLICATION PACKAGES`
(`S-1-15-2-2`) or its exact package SID. Both product workers must therefore use
the narrower LPAC, created imperatively by setting
`PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES` with the exact package SID and
zero capabilities plus `PROC_THREAD_ATTRIBUTE_ALL_APPLICATION_PACKAGES_POLICY`
to `PROCESS_CREATION_ALL_APPLICATION_PACKAGES_OPT_OUT`. Before the sole resume,
the controller queries the suspended token and requires the exact values for
`TokenIsAppContainer`, `TokenIsLessPrivilegedAppContainer`,
`TokenAppContainerSid`, `TokenCapabilities`, low integrity, and child-process
restriction. A diagnostic three-way canary matrix creates fresh leaf objects
under one controlled parent with identical minimal traverse/read-attribute
access for both roles. Every leaf DACL grants the current logon SID and exactly
one restricting-side trustee: `ALL APPLICATION PACKAGES`, `ALL RESTRICTED
APPLICATION PACKAGES`, or one role package SID. The regular control must pass
AAP; LPAC must fail AAP and pass
ARAP; the regular control's ARAP result is recorded rather than assumed. LPAC
must pass only its own exact-role object, while a wrong-role LPAC must fail it.
The regular control receives no project/PDF/
scientific bytes and cannot become a product fallback.

ARAP is an honest residual OS authority, not a brokered grant. During the
no-engine probe and complete PDF/font/search corpus on each sealed physical OS
image, kernel file/registry/image-load/process/network evidence inventories
every successful access outside the profile and explicit product roots. Each
entry records the requested/result operation, canonical identity, a frozen
security-descriptor snapshot and matching AAP/ARAP/role trustee ACEs, and
signer/hash plus writable/executable classification where relevant. ETW cannot
name the causal ACE; only the controlled canaries may attribute a result to one
SID. This is complete for the traced workload, not an exhaustive Windows ACL
map or a runtime allowlist. Any project/private-user access, unexpected write,
user-writable executable or configuration load, unreadable required descriptor,
unexplained success, or trace loss fails A10. The product security statement
explicitly excludes a resource whose owner grants ARAP.

Any PDF/font/data dependency needed by the worker must be staged, hashed, and
granted explicitly to the exact role SID. Neither worker receives
`registryRead`, `lpacCom`, network, or another named capability. Failure of the
PDF/font/search corpus under those constraints rejects worker admission and
reopens the architecture. The Windows 11-only
`Experimental_CreateProcessInSandbox` API remains a measured challenger, not a
baseline: it is explicitly unstable, has no public header, rejects inherited
handles, and therefore cannot satisfy the Windows 10 floor or TExFlow's
authenticated two-handle bootstrap.

### Worker images and process mitigations

Windows performs load-time import resolution and DLL initialization before an
application argument dispatcher can select a role. T0.2 therefore emits three
distinct Zig-owned PE images: GUI `TExFlow.exe`, headless
`TExFlow.PdfWorker.exe`, and headless `TExFlow.ScienceWorker.exe`. Scintilla
is statically linked only into the UI image. The two worker images may share Zig
source modules but may not import or map `user32.dll`, `gdi32.dll`,
`win32u.dll`, DWM/D3D/DXGI/D2D/DWrite, Scintilla, or each other's
role-specific third-party closure. A consolidated headless-worker image is a
measured challenger only; `TExFlow.exe --worker=*` is rejected because it
cannot erase the UI image/import surface before entry.

Each product worker receives this exact first-`DWORD64` creation-mitigation
profile; no task may select a smaller subset after observing a failure:

- `PROCESS_CREATION_MITIGATION_POLICY_DEP_ENABLE` with ATL thunk emulation
  absent, plus `PROCESS_CREATION_MITIGATION_POLICY_SEHOP_ENABLE`;
- `PROCESS_CREATION_MITIGATION_POLICY_HEAP_TERMINATE_ALWAYS_ON`;
- `PROCESS_CREATION_MITIGATION_POLICY_FORCE_RELOCATE_IMAGES_ALWAYS_ON_REQ_RELOCS`,
  `PROCESS_CREATION_MITIGATION_POLICY_BOTTOM_UP_ASLR_ALWAYS_ON`, and
  `PROCESS_CREATION_MITIGATION_POLICY_HIGH_ENTROPY_ASLR_ALWAYS_ON`;
- `PROCESS_CREATION_MITIGATION_POLICY_STRICT_HANDLE_CHECKS_ALWAYS_ON`;
- `PROCESS_CREATION_MITIGATION_POLICY_WIN32K_SYSTEM_CALL_DISABLE_ALWAYS_ON`;
- `PROCESS_CREATION_MITIGATION_POLICY_EXTENSION_POINT_DISABLE_ALWAYS_ON`;
- `PROCESS_CREATION_MITIGATION_POLICY_PROHIBIT_DYNAMIC_CODE_ALWAYS_ON` with no
  thread opt-out or remote downgrade;
- `PROCESS_CREATION_MITIGATION_POLICY_CONTROL_FLOW_GUARD_ALWAYS_ON`;
- `PROCESS_CREATION_MITIGATION_POLICY_FONT_DISABLE_ALWAYS_ON`; and
- `PROCESS_CREATION_MITIGATION_POLICY_IMAGE_LOAD_NO_REMOTE_ALWAYS_ON`,
  `PROCESS_CREATION_MITIGATION_POLICY_IMAGE_LOAD_NO_LOW_LABEL_ALWAYS_ON`, and
  `PROCESS_CREATION_MITIGATION_POLICY_IMAGE_LOAD_PREFER_SYSTEM32_ALWAYS_ON`.

`PROC_THREAD_ATTRIBUTE_CHILD_PROCESS_POLICY` separately carries
`PROCESS_CREATION_CHILD_PROCESS_RESTRICTED`. The second mitigation `DWORD64`
sets `PROCESS_CREATION_MITIGATION_POLICY2_ALLOW_DOWNGRADE_DYNAMIC_CODE_POLICY_ALWAYS_OFF`.
On OS/CPU combinations that report user-shadow-stack support it also requests
`PROCESS_CREATION_MITIGATION_POLICY2_CET_USER_SHADOW_STACKS_ALWAYS_ON`.
Strict CFG, CET strict mode, and blocking non-CET binaries are predeclared
challengers and may become required only if every non-system image in that
role's frozen closure carries compatible load configuration. Microsoft/Store-
only binary-signature policy is explicitly rejected for T0.2 because it would
exclude TExFlow's own portable and source-built dependency images; hash-bound
protected ACLs, fixed absolute loads, dynamic-code prohibition, and module
inventory are the applicable controls.

While the primary thread remains suspended, the controller uses the child
process handle returned by `CreateProcessW` (which must retain
`PROCESS_QUERY_INFORMATION` until this gate completes) to call
`GetProcessMitigationPolicy` separately for DEP, ASLR, strict-handle, system-
call-disable, extension-point, dynamic-code, CFG, font, image-load, child-
process, and supported user-shadow-stack policies and compares semantic fields,
not a self-authored aggregate mask. A supported mandatory bit that is absent is
fatal; a genuinely unsupported capability is retained as typed evidence and
cannot be mislabeled enabled. After loader initialization but before any
untrusted or project-derived input is admitted, the worker emits a canonical
loaded-module receipt and the independent controller enumerates the same
process. The PDF receipt is repeated after the sealed PDFium load. Recursive PE
imports, module path/file identity/hash/signer, executable/writable state, CFG
instrumentation/load configuration, relocations, and CET compatibility must
match the role lock. Any UI/cross-role/unexpected image, policy downgrade, or
inventory disagreement kills and quarantines the generation. The test suite
mutates or removes every policy and module assertion independently so one
friendly launch cannot cover the matrix.

### Whole-process lifetime

The UI thread owns one monotonic `starting -> running -> closing -> terminated`
lifecycle; re-entrant close/session-end/crash notifications cannot move it
backward or start a second teardown. Entering `closing` first rejects new user,
IPC, render, search, and database admission while keeping the message pump
responsive. It then cancels live-render/search work, resolves every already
accepted ledger request to a committed or explicit failed state within its hard
deadline, retires brokered mappings/private staging, requests bounded
authenticated worker shutdown and closes each kill-on-close Job Object on
timeout. Derived search state may be discarded; an acknowledged canonical event
may not be silently lost.

Closing first stops new UIA snapshot/action admission, revokes the editor
provider's Global Interface Table registration, drains or fails its revision-
bound UI commands, invalidates ranges/events, calls `CoDisconnectObject`, and
joins the dedicated provider STA. Only then, on the UI owner thread, is the
Scintilla document/subclass and child HWND destroyed. D2D/DWrite targets,
swap-chain buffers, wait handles, device/context,
top-level HWND, and COM apartment are then released in their documented reverse
ownership order. Secrets are zeroized and handles/profiles are closed only by
their owners. Tests pause/fail every barrier and cover double `WM_CLOSE`, worker
hang/crash, slow/failing ledger sync, device loss, outstanding UIA calls, and
process/session-end pressure; exit must be bounded, leak-free, and report which
accepted durable operation, if any, could not be confirmed. A force-killed
process is crash evidence and relies on the reopen oracle, never a clean close.

### IPC envelope

Every message has a fixed-width little-endian header with magic, protocol
major/minor, role, message type, flags, channel sequence, request ID, payload
length, project UUID, project revision, absolute QPC deadline, and a full
HMAC-SHA-256 over header plus payload. Only explicitly enumerated handshake,
shutdown, and health-control types may use a zero project/revision/deadline;
work messages must bind all three and deadlines are rejected when expired or
beyond the per-type maximum horizon. After OS peer checks,
both sides exchange independent 256-bit CSPRNG challenges and authenticate the
complete handshake transcript, including both retained process identities and
creation times. Pipe-name entropy, challenges, and bootstrap secrets come from
fail-closed Windows CNG system-preferred randomness. HKDF-SHA-256 derives distinct keys for
UI-to-role and role-to-UI: extract uses the inherited one-launch 256-bit master
secret as IKM and SHA-256 of the protocol label plus both ordered challenges as
salt; expand info binds role, negotiated version, and direction. The frame MAC
covers the canonical header with its MAC field zeroed followed by the exact
payload bytes. Sequence numbers are
unsigned 64-bit, start at zero per direction, never wrap, and are compared with
the MAC in constant time.
The implementation must reject unknown required flags, unsupported major
versions, invalid role/type combinations, duplicate request IDs, oversized
payloads, replay/reordered channel sequence, invalid MAC, integer overflow,
trailing bytes, wrong project, stale/future revision, invalid deadline, and queue
overflow before parsing a payload. The hard caps are
recorded with each protocol and are covered by boundary and property tests.

Named pipes use an unpredictable per-launch name under the LPAC-compatible
`\\.\pipe\LOCAL\` namespace and a protected, non-inherited DACL with two
mirrored least-right client ACEs: the exact current-logon SID and the exact role-
specific package SID. Each ACE grants only `FILE_READ_DATA`, `FILE_WRITE_DATA`,
`FILE_READ_ATTRIBUTES`, `FILE_WRITE_ATTRIBUTES`, and `SYNCHRONIZE`, because the
LPAC token must pass both the normal and restricted/package-SID access checks.
The existing UI server handle needs no reopen ACE. Neither client ACE grants
append/create-instance rights or uses a generic-write mapping that implies
`FILE_CREATE_PIPE_INSTANCE`. The Windows owner still has implicit `WRITE_DAC`, so this is
not represented as containment against malicious same-user/same-integrity code.
The server sets `nMaxInstances=1`, `FILE_FLAG_FIRST_PIPE_INSTANCE`,
and `PIPE_REJECT_REMOTE_CLIENTS` before child launch, then validates the
connected PID against the retained launch-process handle and creation time to
defeat pipe squatting and PID reuse. Pipe-name entropy is not treated as an
authentication boundary. A 256-bit
one-launch secret is delivered exactly once through an explicit inherited
anonymous-pipe handle, never command-line text or environment state, and both
unused pipe ends are closed immediately. The worker does not rely on an
LPAC `OpenProcess` attempt: the UI creates a real self-process handle
with exactly `PROCESS_QUERY_LIMITED_INFORMATION`, marks only its duplicate for
inheritance, and includes it in the explicit handle list. The worker compares
that handle's PID with `GetNamedPipeServerProcessId`, then uses the handle to
verify creation time, canonical process image path, and the shared compile-time
build identity, then closes the reduced parent handle immediately after the
authenticated transcript. It never opens or hashes `TExFlow.exe`, whose bytes
remain denied by the role ACL. The UI binds `GetNamedPipeClientProcessId` to the
retained `CreateProcessW` child handle and fully validates the already locked
staged worker path, volume/file identity, SHA-256, role token, and module receipt.
This asymmetric proof binds the intended launch, one-launch secret, challenges,
role, and protocol under the explicit same-user-code exclusion; it does not claim
that an unsigned T0.2 worker cryptographically attests its parent binary. A future
signed build may strengthen that direction only through a separately reviewed
signed-manifest handle, not worker read access to UI bytes. Only the UI retains
the verified child process handle through channel teardown.
`PROC_THREAD_ATTRIBUTE_HANDLE_LIST` contains exactly the one-shot secret
read handle and reduced parent-query handle at launch; both are closed in the
worker after handshake, and every ambient/extra inheritable handle is a test
failure. Bootstrap and channel
key material is never logged/dumped intentionally and is cleared with a
compiler-resistant zeroization primitive immediately after derivation or at
channel teardown.

The pipe is a bounded control plane. After authenticated launch, the trusted UI
creates exact-size pagefile-backed sections and brokers reduced-access handles
into the already verified worker with `DuplicateHandle`; raw project-file
handles and paths never cross the boundary. At most two PDF input generations
may be outstanding, each and their combined live bytes are <=128 MiB, the UI
creates a reduced read-only replacement handle and closes every writable view
and write-capable handle before publishing it. The worker maps only the declared
read-only size, hashes the complete mapping, and rejects it unless the digest
matches the authenticated request. Each decoded 512-pixel opaque BGRx tile uses
a fresh unnamed, non-executable, pagefile-backed one-MiB section unique to one
slot generation; a tile section is never pooled or reused. The worker gets only
section-map-write access and the UI only section-map-read access. The broker
owns the monotonic `created -> writing -> ready -> consuming -> retired` state
machine. `ready` authenticates exact type/access/size/stride/slot/generation and
SHA-256 digest after the worker unmaps and closes its declared writer. The UI
copies the exact bytes into one of two private one-MiB staging buffers, hashes
and validates that copy, permanently retires the section, and uploads only the
private bytes. A close acknowledgement is lifecycle evidence, not proof that a
compromised process did not retain a mapped view or duplicate; one-shot object
identity prevents such a writer from reaching later generations. At most four
tile-transfer sections are live, separately from the measured 32/48/64-MiB
resident GPU tile LRU.

Every transfer binds object kind, exact access, size/stride, slot, generation,
content digest where applicable, state transition, and close acknowledgement to
an authenticated request. Timeouts close known local and remote handles; leak,
late-write, duplicate, and stale-generation probes must retire the object and
return the worker generation to the baseline handle count or quarantine and
restart it. Raster output is untrusted derived display data and cannot establish
artifact identity or scientific truth. No message may create an unbounded
section, accept an arbitrary numeric handle, or transfer an ambient handle. A
bounded overlapped-pipe tile copy into the same private staging pool is the
measured fallback if one-shot sections fail the native gate; shared-memory GPU
upload and reusable writable tile sections are forbidden. Science-worker
traffic is small and remains on the bounded pipe. It is still untrusted: before
display or navigation, the UI-side science decoder validates the exact reply
type, project/generation/watermark/hash, bounded result count and bytes,
canonical entity IDs, finite canonical BM25 rank value, and stable
`(rank, entity_id)` order. Search
replies cannot carry presentation text, markup, SQL, paths, commands, pointers,
handles, byte offsets, field selectors, token descriptors, hit-truncation
claims, or a canonical-ledger mutation. For each visible result, the trusted
broker reads all frozen canonical fields, replays the same pinned Zig tokenizer,
rejects the result unless their union satisfies every literal-AND token, and
alone derives the deterministic occurrence window, hit truncation, escaped
safe title/snippet, and half-open UTF-8 highlight ranges. Nothing is rendered as
a result before that proof. A rank and snippet are
derived navigation metadata, not a scientific quantity, quotation, or
confidence claim. Broker validation proves only that a returned row really
matches; the worker may still omit matching rows or manipulate the order of
otherwise valid rows. Search is therefore an availability/navigation aid, not
a negative-evidence oracle. The exact English resource values are:

- `search.results.notice`: `Derived-index navigation — up to 100 candidates; visible rows are verified matches; omissions and order are not scientific evidence.`
- `search.empty`: `No matches returned by the current derived index. This is not evidence of absence.`
- `search.rebuilding`: `Search index rebuilding`
- `search.unavailable`: `Search index unavailable`
- `search.eligibility`: `Canonical fields eligible for indexing: {eligible}/{total}; derived-index completeness is not verified.`
- `search.untitled`: `Untitled record`

Rebuilding and unavailable are distinct from a terminal empty reply. No claim,
citation, reviewer, or preflight audit may infer absence from
search rank, omission, or the broker-computed canonical-cap eligibility ratio.
Any later audit requiring complete coverage must scan the canonical ledger or
reconcile a separately frozen coverage manifest.

T0.2 freezes these protocol/resource caps before implementation:

| Resource | Hard cap and overflow behavior |
| --- | --- |
| Wire/control | 64 KiB payload per frame, 2 MiB per reassembled logical message, 8 MiB queued bytes per direction, 128 live request IDs; reject before allocation and close immediately on protocol abuse. |
| Brokered sections | Two live PDF-input sections with <=128 MiB combined bytes; four live generation-unique one-MiB tile-transfer sections plus two UI-private one-MiB staging buffers; no tile section reuse, no other brokered section kind, and no unexplained handle-count growth after retirement. The resident GPU tile LRU is independently selected from 32/48/64 MiB. |
| PDF structure | 128 MiB input, 10,000 pages, 1,000,000 UTF-16 units per page, 16,000,000 cached units per document, 4,096 links per page, and 10,000 streamed search hits; rendering may continue with a precise text/link-unavailable state when an accessibility extraction cap is exceeded. |
| Geometry/raster | Finite checked transforms only; geometry batches <=4,096 characters; each buffer is exactly 512x512x4 bytes with 2,048-byte stride; edge pixels are initialized and no full-page raster is allocated. |
| Science search | The exact four T0.2 canonical fields total <=4 MiB/entity; each field <=1 MiB, each emitted source segment <=1,024 UTF-8 bytes, each normalized token <=256 bytes, <=65,536 emitted tokens/field, and <=64 KiB tokenizer scratch. Overflow aborts the entity's derived transaction; the trusted broker records only canonical cap eligibility. A begin/four-field/commit transfer keeps every logical message <=2 MiB and one assembly <=4 MiB. Query <=4 KiB and <=64 de-duplicated normalized tokens; <=100 descriptor-free `(entity UUID, rank)` worker candidates. Broker validation/presentation is lazy: <=8 visible IDs/batch, <=16 pending, one <=4-MiB entity materialized at a time, cancellation/yield checks every <=64 KiB and <=2 ms, title <=256 graphemes/2 KiB, and snippet <=8 KiB/64 tokens. No unproved candidate is visible; search absence/rank/eligibility is never scientific evidence. |
| Worker containment | One child per role; PDF Job private-commit hard limit 256 MiB; science Job private-commit hard limit 128 MiB; cooperative PDF render slice target <=8 ms; hard non-progressing operation deadline 5 s; and at most three crash restarts per role per 60 s before a latched recovery state. Performance budgets remain stricter than containment caps. |

## 5. Exact dependency and QA-tool lock

Normal `zig build` is network-free and fails with a precise cache-remediation
message when sources are absent. Explicit `zig build deps-fetch` downloads the
  small locked archives through the Zig fetcher. One separate protected command,
  `zig build deps-reproduce-pdfium -Dphase=resolve|reproduce
  -Dallow-network=true -Drepro-root=<absolute-ntfs-path>`, may resolve or replay
  the exact PDFium DEPS graph in
a dedicated ephemeral VM or clean build machine with no mounted user data,
credentials, repository-write authority, or reusable account state for the
independent source-rebuild gate;
no other build step may use the network. The controller rejects a root inside
the repository, a reparse-backed/non-NTFS root, a path containing whitespace,
non-ASCII text, shell metacharacters, or an unsafe length, less than 100 GiB free space,
or less than 16 GiB physical memory before download, then enforces a 180-minute wall limit,
a 15-minute no-progress limit, bounded logs, and a 10-GiB free-space abort
floor. These are feasibility ceilings, not performance targets.

GitHub's standard Windows runner is not a qualified reconstruction host: its
published 14-GiB SSD allocation is below the 100-GiB upstream Windows build
floor. Standard Linux/Windows CI verifies portable/static contracts and must
never report source reconstruction or PDF runtime as covered. A same-run
reconstruction lane may run only on an explicitly authorized larger or
self-hosted ephemeral runner that passes the same resource/security preflight;
an everyday developer host/account is forbidden even when it has enough disk.
The lane treats every synced hook as untrusted build code, confines all writable
state to the disposable root, freezes outbound endpoints from the reviewed
Git/DEPS/CIPD graph, and records the complete descendant image/path/hash/argv/
parent tree. An unexpected executable, shell, endpoint, or write outside the
root fails the lane. Otherwise
the required T0.2 reconstruction evidence comes from a qualified dedicated
clean local build machine and the later protected shipping rebuild remains
open. `deps-fetch`
validates the allowlisted scheme/host/path, expected byte count, and reviewed
archive digest before extracting byte-stable assets into a staging directory.
Gitiles exact-commit archives have nondeterministic transport/tar metadata, so
their manifest instead sets strict compressed/expanded caps and verifies a
canonical extracted-file tree digest before activation; transport bytes are
never mistaken for source identity.
A hardened Zig tar+gzip extractor handles source archives; a separate restricted
Zig ZIP reader handles exactly two locked shapes: the Unicode UCD data input and
the GitHub CLI QA archive. The ZIP reader accepts only each dependency's exact
reviewed inventory and stored/deflate, non-encrypted, non-Zip64 shape and
accepts the archive's data-descriptor form only when the central directory gives
one unambiguous bounded range. It cross-checks local headers, central-directory
records, descriptor signature/CRC-32, compressed and expanded sizes,
non-overlapping data ranges, exact member inventory, and archive end/trailing
bytes. Both paths reject absolute/drive/device/ADS paths, `..`,
links, special/device/FIFO/sparse entries, duplicate Windows-normalized paths,
member/expanded-byte limits, and excessive compression ratios; tar additionally
rejects unsafe PAX/GNU long-name overrides. Redirects are revalidated against
the same allowlist and bounded; URLs never carry credentials.

The UCD shape is narrower still: one disk, exactly 74 ASCII-named entries,
stored or normal deflate only, no encryption, Zip64, data descriptor, comment,
or extended local header. Its only accepted extra-field IDs are structurally
valid non-duplicated `0x5455` extended timestamp and `0x7875` Unix UID/GID;
directory records are zero-length and only the exact `auxiliary/`, `emoji/`, and
`extracted/` inventory positions may be directories. These permissions/times/
UIDs are metadata to validate and discard, never authority or extracted ACLs.
The GitHub CLI shape retains its separately frozen inventory/flag/extra-field
contract; permissiveness needed by one shape is not inherited by the other.

| Item | Exact source | Bytes | Integrity lock | Product role |
| --- | --- | ---: | --- | --- |
| Scintilla 5.6.6 | `https://www.scintilla.org/scintilla566.tgz?download=1` | 1,822,062 | SHA-256 `b6b08598c68fac90990d010c1142494d707530602b5320753274d045c2b02189`; exactly 296 archive entries under `scintilla/` | Static product editor only; production styling is TExFlow Zig. |
| Lexilla 5.5.3 | `https://www.scintilla.org/lexilla553.tgz?download=1` | 1,116,541 | SHA-256 `4d9e64263c337034a06f9c67f330c605764cac02aee83c06f6c21f9527a71628`; exactly 993 archive entries under `lexilla/` | Test-only LaTeX/BibTeX comparison oracle over reviewed fixtures; never linked, loaded, or distributed with `TExFlow.exe`. |
| Unicode Character Database 17.0.0 | `https://www.unicode.org/Public/17.0.0/ucd/UCD.zip` | 9,101,877 | SHA-256 `2066d1909b2ea93916ce092da1c0ee4808ea3ef8407c94b4f14f5b7eb263d28e`; exactly 74 ZIP entries and 41,500,790 expanded bytes; version marker `2025-08-15`; single-disk stored/deflate archive with no descriptor/Zip64 and only extra IDs `0x5455`/`0x7875` | Build-only input for Zig-generated UAX #29 rev. 47 segmentation, UAX #15 rev. 57 normalization/case-fold, path-collision, and conformance tables. The archive never ships; Unicode License v3 notice is retained in associated documentation/package notices. |
| PDFium 154.0.8035.0 (`chromium/8035`) x64 | `https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/8035/pdfium-win-x64.tgz?download=1` | 3,772,597 | Archive SHA-256 `61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41`; official branch head `6f2272e1f3aaa141305475b83ef4eac2c1f527b8`; reviewed attestation bundle is 18,096 bytes, SHA-256 `1f84f3d920a8c3ad5dc480899631eef877c43f99d1e85b634af55570f51e2ee6`, identifying builder commit `5453f3afc4785cbad82c05f6ceb4dabea0cb81a0` and run `33383157207/1`; contained unsigned `pdfium.dll` is 7,266,816 bytes, SHA-256 `ccfac1aad9e78624ebfb3f54f3f4ddb77af6db2f52803f150e2f9876beda49fe` | Non-V8/XFA reference/comparator only. Community builder is unaffiliated with PDFium; this DLL is never the admitted Task 5 runtime. |
| PDFium x64 SLSA bundle | `https://api.github.com/repos/bblanchon/pdfium-binaries/attestations/sha256:61513d611ad200a383456140739be77d156f1e3a2eef22bd89f6c3bda79bdd41?predicate_type=provenance&per_page=100` with `Accept: application/vnd.github+json`, API version `2026-03-10`, and no authorization header | Exactly one repository-ID `103962638` result; selected raw-Snappy body 17,297 bytes, SHA-256 `ae84cc3ca94398519f7f67bdd33a7d29f589a74d88734f544efa815e1f39046c`; decompressed JSON 18,095 bytes | Append exactly one LF to form the locked 18,096-byte JSONL whose SHA-256 is `1f84f3d920a8c3ad5dc480899631eef877c43f99d1e85b634af55570f51e2ee6`; its 45-subject SLSA v1 statement contains exactly one `pdfium-win-x64.tgz` subject with the archive digest above | Declarative offline provenance input. The release's generic `pdfium-attestation.json` asset is not this lock and is rejected. |
| PDFium root source snapshot | `https://pdfium.googlesource.com/pdfium/+archive/6f2272e1f3aaa141305475b83ef4eac2c1f527b8.tar.gz?download=1` | Variable transport <=16 MiB; exactly 5,548 logical tar entries / 5,400 files and 40,484,895 content bytes <=48 MiB, with an independent 64 MiB raw-tar envelope | Exact commit timestamp 2026-08-28; canonical tree SHA-256 `eb5b5b34b65e795379f55a3109cc31b843395e8e6be737b2d2c35f2725c2e499` over ordinal `path<TAB>size<TAB>file_sha256<LF>` records | Root-source/inventory anchor for the independent rebuild; transitive DEPS commits are captured separately. |
| PDFium community build recipe | `https://github.com/bblanchon/pdfium-binaries/archive/5453f3afc4785cbad82c05f6ceb4dabea0cb81a0.tar.gz?download=1` | 142,719 | SHA-256 `00d9ef134460216465b19e11e59cf982dd1a4391d12be0f5ccf94466abcb84e6` | Reviewed patches/configuration used to reconstruct and compare the attested artifact; never trusted as source identity by itself. |
| Chromium depot_tools | Git commit `a0fd6e66af74304c9b4605665435f4e88849e046` from `https://chromium.googlesource.com/chromium/tools/depot_tools.git` | Git checkout only | Exact commit/tree plus internal-link allowlist: `cros_sdk -> cros`, `gerrit -> cros`, `luci-auth-fido2-plugin -> luci_auth_fido2_plugin.py`; auto-update disabled | Disposable PDFium source-rebuild orchestrator only; never enters the normal archive cache or ships. |
| SQLite 3.53.4 | `https://www.sqlite.org/2026/sqlite-autoconf-3530400.tar.gz?download=1` | 3,283,177 | SHA-256 `0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c`; upstream archive SHA3-256 `454e45f61c6bd75b7420e7190732dea03ce6639c63ada47bbc592f67fc340338` | Ledger/search amalgamation with FTS5. |
| zigwin32 42.0.39-preview | `https://github.com/marlersoft/zigwin32/archive/9f15c276b4e9d05afd34a10d8662a7dfc34647ea.tar.gz?download=1` | 7,358,806 | Git commit `9f15c276b4e9d05afd34a10d8662a7dfc34647ea`; Zig package hash `win32-42.0.39-preview-mX5pFS564gPTezZn4v3TMxRnfJUrZNx1B_F2p2HKXOeG`; archive SHA-256 `6fec64480a16e7797e0a010faef67a5fc22561551a955fcb73a023f0a114f8d7` | Compile-time Win32 declarations behind a TExFlow facade; no root/everything import. |
| PresentMon 2.5.1 x64 | `https://github.com/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe?download=1` | 956,768 | GitHub release SHA-256 and verified local SHA-256 `9bec3083069f58f911e6a512f4806db51a27bd096103087bc1d05ef54c80a191`; valid Authenticode signer `CN=Intel Corporation, O=Intel Corporation, S=California, C=US`, certificate thumbprint `4B923D748E9EBE27252FDBA244342C1888A2D23E` | Direct QA-cache executable only; never shipped or installed. Pin supersedes 2.4.1 because 2.5.x fixes percentile calculation, Intel adapter LUID, metric, ETW, and IPC/backpressure defects that affect this oracle. |
| Accessibility Insights for Windows 1.1.2924.01 production | `https://github.com/microsoft/accessibility-insights-windows/releases/download/v1.1.2924.01/AccessibilityInsights.msi?download=1` | 8,732,672 | SHA-256 `bf4de9ac631bdac8a6cd5f5e7963bc6f9c1bc6261371ae7cd7170531ca6ba9a5`; valid Microsoft Authenticode subject `CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US`, signer thumbprint `8F985BE8FD256085C90A95D3C74580511A1DB975` at review time | Operator-provisioned QA-only cross-oracle. Never auto-installed, updated, shipped, or included in footprint/timed trials. |
| GitHub CLI 2.100.0 x64 | `https://github.com/cli/cli/releases/download/v2.100.0/gh_2.100.0_windows_amd64.zip?download=1` | 15,326,700 | Archive SHA-256 `227e35230b25db3fa1b997bab7cf4d67df0470a3b75b99e4ee66bce1a7cd4e72`; exact members: `LICENSE` 1,089 bytes/SHA-256 `8999137010582da29456c10e0a628bf3fa7ead05ab3ae5f424ad25cd0dd94574` and `bin/gh.exe` 42,992,952 bytes/SHA-256 `2ae2b350c227a618f2d8965b1900aeee13446ff42e17ef0bd5a0b6405c593cfb`; valid Authenticode signer `CN="GitHub, Inc.", O="GitHub, Inc.", L=San Francisco, S=California, C=US`, certificate thumbprint `2E3D67018EE2980D0C7910A24BB60E195E7068F2` | QA-cache-only offline attestation verifier acquired by the Zig fetcher; never installed, shipped, or silently bootstrapped. Version 2.94.0 is rejected because it is within the `<=2.96.0` range affected by CVE-2026-64655/GHSA-mm27-mwq9-fr5g. |
| GitHub/Sigstore trusted-root snapshot (2026-09-04) | Exact stdout of pinned `gh 2.100.0 attestation trusted-root --hostname github.com`, acquired twice from independent empty profiles | 34,636 | SHA-256 `db07310827da2ae2798ec7eefc5daf8432506ce458d5bc30cd2feba03708d239`; exactly two newline-terminated JSON objects with media type `application/vnd.dev.sigstore.trustedroot+json;version=0.1`, covering Sigstore Public Good and GitHub's Sigstore instance; the two acquisitions were byte-identical | Committed declarative trust input for this fixed historical bundle only; never fetched implicitly by `deps-audit`. |

The Unicode/search choice passed five distinct challenger angles: current UCD
and conformance behavior, UIA unit semantics, search correctness for Vietnamese
and newly assigned scripts, runtime/package cost, and untrusted-result failure
modes. SQLite `unicode61` is rejected because upstream defines it against
Unicode 6.1 and its diacritic-removal modes conflate meaningful Vietnamese
tokens. Windows `NormalizeString`/`ScriptBreak` stays a runtime cross-oracle,
not identity, because its documented version and behavior are OS-bound. ICU is
the mainstream locale/dictionary leader but its C/C++ runtime and standard data
footprint exceed the all-Zig and ultra-light boundary. The selected specialist
path is a table-driven Zig `texflow17` tokenizer generated from the locked UCD:
untailored UAX #29 word boundaries, only word segments containing a Unicode
Letter or Number, and token bytes
`NFD(full-default-case-fold(NFD(token)))` with no accent removal. Exact identity
fields remain separately binary-searchable. The generated read-only tables must
fit <=512 KiB in each consuming UI/science image and are absent from the PDF
worker; exceeding that cap reopens the decision instead of silently importing
ICU or falling back to `unicode61`. Doubling the footprint/complexity weights
does not displace this choice while that cap and conformance suite hold.

The reviewed lock is a reproducibility control, not a blanket claim that an
unsigned archive is publisher-authenticated. In particular, the PDFium
attestation proves that the subject digest came from the named community
workflow and builder commit; it does not prove an independent reconstruction
from the official PDFium source commit. Updates require a separate ADR that
rechecks release notes, licenses, archive contents, host/path, digests from
official publication where available, build switches, binary imports, size,
provenance, and all affected tests. Dependencies never float merely because a
newer patch exists.

The PDFium SLSA-bundle acquisition is part of `deps-fetch`, but it never reads
`GH_TOKEN`, `GITHUB_TOKEN`, GitHub CLI configuration, cookies, or another
account-backed profile. GitHub documents that the public-repository attestation
endpoint permits unauthenticated reads. The Zig fetcher requires the exact
digest-keyed API URL/headers and a bounded JSON response, then accepts exactly
one provenance result for repository ID `103962638`. Its `bundle_url` must be
HTTPS on `tmaproduction.blob.core.windows.net`, have exact path
`/attestations/103962638/2026/08/31/44147842.json.sn`, and contain only the
documented SAS query fields; the expiring query
is transport authority, never identity. A bounded hostile-tested raw-Snappy
decoder checks the advertised uncompressed length, every literal/copy range and
overlap, compressed/decompressed caps, exact transport digest, exact canonical
JSONL digest, predicate, subject set, and workflow identity before activation.
The release asset named `pdfium-attestation.json` is a different generic bundle
whose first subject is `pdfium-android-arm.tgz`; neither that asset nor an
ambient-authenticated `gh attestation download` command may substitute for the
digest-keyed bundle. Pinned `gh` is used only later for offline verification.

The trusted-root snapshot is reproducibility evidence, not a forever-current
revocation oracle. GitHub documents that this JSONL has no built-in expiry and
cannot reveal a revocation that occurred after export. It may verify only the
locked attestation, whose verified transparency timestamp predates the snapshot.
Every dependency update and protected release qualification must acquire a fresh
root through the pinned command/TUF path in a no-secret online lane, compare and
review it, and create a dated ADR before changing the committed snapshot. A stale
freshness receipt blocks release qualification but does not make ordinary builds
silently contact the network.

### Dependency-specific build policy

- **zigwin32:** `deps-fetch` materializes the reviewed content-hash tree in the
  explicit TExFlow dependency cache. The normal build creates a module directly
  from that verified local path; it does not declare a remote `build.zig.zon`
  URL that Zig could auto-fetch. Import only explicit namespaces through
  `platform/windows/api.zig`. A source scan fails if `everything.zig` or the
  package root is imported. If preview churn or compile-time/source cost breaches
  the gate, curate the required generated declarations behind the same facade.
- **Unicode data:** fetch and verify the exact UCD ZIP first, accept only its
  exact ASCII inventory, and retain only the twelve named build inputs. The Zig
  generator validates version/member hashes and official normalization,
  grapheme, and word vectors before emitting one deterministic cache module.
  The UI and science images consume that module through `text/unicode.zig`; the
  PDF worker, source archive, HTML test pages, PDFs, and unused UCD properties
  are absent from the product. The package carries the Unicode License v3
  permission notice. No OS, ICU, or SQLite Unicode table substitutes for this
  identity.
- **Scintilla/Zig container lexer:** build Scintilla's Win32 static source list
  for the `TExFlow.exe` UI image only; no worker target links it or inherits its
  import closure. Build it using Zig's C++ compiler path, C++17, no TExFlow
  shim, and only the system
  libraries used upstream (`kernel32`, `user32`, `gdi32`, `imm32`, `ole32`,
  `oleaut32`, `advapi32`). The product sets `SCI_SETILEXER(NULL)` and performs
  LaTeX/BibTeX styling in bounded Zig through `SCN_STYLENEEDED`, line-state
  checkpoints, and `SCI_SETSTYLINGEX`; no Lexilla object or catalogue is linked
  or loaded. Build pinned unmodified Lexilla only into a separately named
  test comparator over reviewed fixtures, using its upstream C ABI and opaque
  lexer pointer without a TExFlow C++ shim. Its process is absent from product,
  startup, memory, import, and distribution inventories. Differential results
  expose regressions but do not force TExFlow to reproduce a known Lexilla bug.
- **PDFium:** T0.2 uses the exact x64 archive, attestation bundle, and DLL above
  only as provenance-checked reference evidence. The normal build verifies their
  hashes and extracted inventory, then declares the required public C types and
  function table in Zig. Task 2 independently builds and seals the admitted
  T0.2 DLL from the exact source graph; Task 5 rejects the community DLL digest.
  TExFlow must not link PDFium
  into the UI role: the worker uses restricted DLL search plus
  `LoadLibraryExW`/`GetProcAddress`, validates every required export, and rejects
  every unknown binary digest before initialization. The reviewed bundle and
  dated trusted-root JSONL are committed as declarative evidence. A
  Zig-orchestrated QA provenance lane runs pinned `gh attestation verify` with
  `--bundle`, `--custom-trusted-root`, `--repo bblanchon/pdfium-binaries`, exact
  `--cert-identity`, exact `--source-ref`, `--source-digest`, and
  `--signer-digest`, `--deny-self-hosted-runners`, and `--format json`.
  `--cert-identity` is used instead of the mutually exclusive
  `--signer-workflow` flag. The child receives an empty isolated
  `GH_CONFIG_DIR`/home/config/cache/AppData tree, no GitHub tokens, and fail-fast
  loopback proxy variables; it cannot reuse ambient trust, credentials,
  configuration, or a user TUF cache and it never fetches an attestation or
  trusted root implicitly.

  The Zig controller treats exit zero as necessary but insufficient. Its bounded
  JSON parser requires one SLSA v1 result and rechecks the exact artifact subject
  name/digest, verified timestamp, certificate SAN/OIDC issuer,
  `githubWorkflowRepository`, workflow/source/signer digests and ref,
  `runnerEnvironment=github-hosted`, source repository identifiers, and run
  invocation `33383157207/attempts/1`. Predicate metadata is recorded but never
  elevated above the certificate and verified-timestamp fields. Altered
  artifact, bundle, trusted root, lookalike SAN/repository, wrong ref/digest,
  self-hosted runner, duplicate result, absent timestamp, network/cache reliance,
  or an unknown JSON/schema value must fail closed.
  The runner accepts `gh.exe` only through an explicit path after exact version,
  file digest, and Authenticode-signer checks; it never installs or updates it.
  The ordinary product build remains offline and reproducible from the verified
  cache; only the explicitly authorized source-rebuild lane has additional
  network authority.
  Inspect and assert `VERSION`, `args.gn`, PE architecture, imports, exports,
  license inventory, `pdf_enable_v8=false`, `pdf_enable_xfa=false`, and the
  absence of V8/XFA runtime dependencies. The current binary may import only
  `KERNEL32.dll`, `ADVAPI32.dll`, `GDI32.dll`, and `USER32.dll`.

  PDFium is not thread-safe, so one PDF worker engine thread owns library
  initialization/destruction and every `FPDF_*` handle/call. Other threads may
  only exchange bounded immutable requests/results. Rendering uses the pinned
  progressive APIs and `IFSDK_PAUSE` on that thread; a process watchdog contains
  non-progressive parse/load hangs. Use only the reviewed stable API allowlist;
  any unavoidable experimental API is recorded by name, tested against this
  exact binary, and cannot float across upgrades. Read `FPDF_GetLastError()`
  immediately on the same engine thread after a documented failure.

  The worker never initializes the form-fill environment, V8, JavaScript, or
  XFA, and never calls JavaScript/XFA extraction APIs. The exported
  `FPDF_LoadXFA` symbol is an upstream compatibility stub when XFA is disabled
  and must return false in the ABI probe. URI, launch, attachment, and form
  actions are inert bounded data; TExFlow never executes them or supplies
  network/upload callbacks. `FPDF_SetSandBoxPolicy()` disables machine-time
  access as defense in depth only and is never represented as an OS sandbox.

  This community binary is unsigned and not independently source-bound by its
  attestation. T0.2b therefore rebuilds the exact official root commit with the
  exact reviewed recipe/patch set and pinned no-auto-update depot_tools in a
  disposable no-secret lane, records the complete resolved DEPS graph and host
  compiler/SDK identities, and requires matching public ABI, disabled-feature
  state, imports, corpus behavior, resource bounds, and performance class. Byte
  identity is recorded but is not required across different compiler/SDK paths.
  A missing or divergent reconstruction blocks architecture admission.

  The community DLL still is not release-qualified. Before T5.2, a protected
  TExFlow-controlled build must produce the actual shipping DLL from the locked
  graph, repeat the equivalence/security suite, and Authenticode-sign it. A new
  supply-chain ADR is required if that model changes.
- **SQLite:** compile the exact amalgamation with FTS5, serialized thread
  safety, memory accounting, defensive API use, and required diagnostics.
  Compile out loadable extensions, shared-cache mode, deprecated APIs, legacy
  double-quoted string literals, and memory-mapped I/O; do not mistake an
  `sqlite3_db_config()` default for a sealed build boundary. Task 6 freezes and
  tests the lower per-connection, process-memory, database-size, broker-queue,
  and WAL-maintenance caps.

### PDF-engine decision delta and sensitivity

The original MuPDF candidate was rejected after source-level review showed that
serious API calls require `fz_try`/`fz_catch`, whose `setjmp`/`longjmp` control
flow cannot cross Zig frames safely without a TExFlow-owned C bridge. Process
isolation contains a crash but does not turn an unguarded throwing call into a
valid error boundary. This material finding reset the PDF decision plateau.

Eight distinct challenger rounds then compared error ABI, required
render/text/search/geometry/link features, build/deployment weight,
threading/cancellation, security/servicing, provenance, specialist alternatives,
and the downloaded PE's actual imports/exports. PDFium is the only candidate
that passes both mandatory gates: a Zig-callable upstream C ABI and the complete
preview feature surface. Windows.Data.Pdf fails text/search/selection geometry;
Poppler's primary renderer is C++ and its C binding brings GLib/Cairo; PoDoFo is
C++ and has no renderer. The final two rounds found no better challenger.

Sensitivity weights are strict ABI 25%, required features 20%, footprint 15%,
latency/cancellation 15%, security/servicing 15%, and provenance/maintenance
10%, with mandatory-gate failure taking precedence over a weighted total.
Doubling performance weight does not rehabilitate an unsafe ABI; it makes the
single-thread PDFium runtime probe decisive. Doubling provenance weight keeps
PDFium viable only if the T0.2 independent reconstruction passes; it does not
make the community binary release-ready or waive the protected shipping-build
and signing gate.
If the user later permits a small owned C bridge, MuPDF becomes a fresh
challenger and requires a new ADR rather than silently returning.

## 6. Performance and correctness admission budgets

All timing distributions retain raw samples and report median, p95, p99, worst,
trial order, power plan, OS build, CPU, RAM, storage, display refresh, adapter
LUID/driver, DPI, renderer path, and process-tree membership. Missing, `NA`, or
lost-correlation samples invalidate that metric; they are never converted to
zero or silently dropped.

| Surface | Gate |
| --- | --- |
| Package footprint | Exact required runtime payload <= 90 MiB; the same payload in the one canonical Zig 0.16.0 tar+gzip/Deflate-level-9 probe <=30 MiB. The real signed installer remains a later product gate and is recorded unverified rather than conflated with the probe. |
| Startup | 30 independent full-kernel-boot cold launches p95 <= 400 ms; 30 warm trials p95 <= 150 ms, process-start ETW to first displayed frame. The cold method, post-logon launch offset, and boot-state oracle are preregistered per cell; power-off and Restart samples are never pooled. |
| Empty shell memory | Aggregate process-tree private working set <= 45 MiB and private commit <= 55 MiB. |
| 30-page PDF memory | Aggregate private working set <= 100 MiB and private commit <= 120 MiB after steady-state interaction. |
| 10-MiB editor feasibility | On `W2-large-editor`, warm open to first real editable viewport p95 <= 750 ms; after the fixed journey and five-minute unchanged settling point, aggregate private working set <= 140 MiB and private commit <= 170 MiB; TExFlow-owned UTF/range/checkpoint/snapshot metadata beyond Scintilla's document/style storage <= 24 MiB; with no newer edit, full Zig styling converges p95 <= 2 s while every owner-thread styling continuation is <= 4 ms. |
| Search memory | Across on-demand launch, clean rebuild, query, presentation, and cancellation on `W6-search`, the maximum sampled aggregate process-tree private working set <= 110 MiB and private commit <= 135 MiB; shared pages and complete derived-root storage are reported separately. |
| Search first use | With the interactive UI established, no science-worker process, and no open search connection, command activation reaches the first `min(8, H)` broker-proven identity/title rows—or the terminal honest empty state for `H=0`—p95 <= 400 ms. |
| Search warm identity latency | With the worker ready/database open and no TExFlow result/presentation cache for the selected query, submission reaches the first `min(8, H)` broker-proven identity/title rows—or the terminal honest empty state for `H=0`—p95 <= 75 ms. |
| Search presentation latency | The first `min(8, H)` broker-validated snippets complete p95 <= 200 ms for representative rows and <= 750 ms for the explicit four-MiB adversarial entity; every broker slice yields/cancels within two ms and the UI STA executes no slice above four ms. |
| Search cancellation | A new query/scroll or rebuild cancel receives cooperative acknowledgement within 50 ms on the non-faulting corpus, zero stale row/snippet is attached to the new query, and no cancelled staging generation activates. |
| Search storage/rebuild | After integrity, truncating checkpoint, clean close/reopen, and with no stage, the complete active generation is <=192 MiB in both recursive logical and allocated bytes. Empty-root rebuild peak is <=224 MiB; the complete derived root permits at most one active plus one staging generation and <=400 MiB. Clean rebuild p95 <=30 s and never blocks the UI STA. |
| GPU memory | <= `3 * P + T + 16 MiB`, where `P` is visible presentation-surface bytes and `T` is admitted tile-cache GPU bytes. |
| Editor mutation | Input event to committed Scintilla mutation p95 <= 4 ms. |
| Renderer submit | Dirty notification to frame submit p95 <= 4 ms. |
| Visible latency | All-input to photon p95 <= `min(25 ms, 2 * refresh_interval)`; record Scintilla child HWND and composed shell/PDF lanes separately. PresentMon's supported photon field must first pass the timestamped visual-toggle calibration; otherwise use WPR/DWM plus calibrated camera/instrument evidence. |
| Reliability | <= 0.1% dropped/coalesced-without-equivalent-result events over 10,000 deterministic edits; zero lost latest-version render. |
| Idle | <= 0.5% of one logical processor after quiescence; a visible focused system-caret blink is recorded separately, while minimized/fully occluded quiescence has zero fixed periodic app or editor-child wake timers. |
| Live-render scheduler | Auto-mode delay adapts within 220-750 ms; a superseded job gets at most 75 ms grace before cancellation; a visible stale artifact is never labeled current. |

The budgets use named, generated, hash-locked T0.2 workloads rather than an
operator-selected convenient document:

| Workload | Frozen state and action oracle |
| --- | --- |
| `W0-clean-start` | Sealed post-first-logon QA-user base plus restored empty TExFlow/project-state roots, empty editable source, no PDF/database/worker preload; the first frame must expose real shell/editor commands and accept the harness mutation. |
| `W1-established-start-proxy` | The same sealed QA-user base plus restored established state with 32 generated LaTeX/BibTeX files totaling exactly 2 MiB, a 256-KiB active `main.tex`, nonzero caret/selection/scroll state, and a real read-only fixture outline. The hashed bytes/state are loaded before the interactive point; optional discovery and every worker remain deferred. This is a T0.2 feasibility proxy, not T1 Open-Folder or final release-startup proof. |
| `W2-large-editor` | The >=10-MiB generated semantic book with fixed start/middle/end edits, paste/delete, jump, scroll, selection, undo/redo, lexer convergence, UIA reads, and final byte/style/range hashes. |
| `W3-pdf-steady` | `W1` source state plus the hashed 30-page scientific PDF; complete a fixed page 1/15/30 navigation, search, selection, zoom, rotation, and return-to-page-1 sequence, then sample only after the declared five-minute steady state while retaining all processes and admitted caches. |
| `W4-edit-storm` | Fixed seeded 10,000-edit trace over `W2`, including cancellation/coalescing pressure and a final exact source/style/artifact version oracle. |
| `W5-idle` | Measure both unchanged visible focused empty shell and minimized/fully occluded shell after the declared quiescence point; the caret allowance applies only to the former and no hidden optional worker may be prestarted. |
| `W6-search` | Exactly 10,000 generated canonical entities and four fixed fields totaling 128 MiB of valid UTF-8, including Unicode-17 additions, Vietnamese NFC/NFD distinctions, Greek, Cyrillic, Arabic, CJK, emoji/control boundaries, duplicate tokens, 0/1/10/100/>100-hit queries, a 64-term query, and one exact four-MiB adversarial entity. The generator freezes entity IDs, project-scoped content/chunk records, ledger/event hashes, projection references, query order, expected literal-AND membership and capped order, BM25 bits for the provisional contentless-delete `detail=full` baseline, safe-title/snippet/range hashes, the <=256-MiB canonical-ledger root, and clean-rebuild search database/complete-root manifests before timing. For each query `H=min(100, expected_match_count)` comes only from this oracle. |

Every `W6-search` timing sample first proves the expected capped membership and
order. Missing, extra, duplicate, false-positive, or misordered rows invalidate
correctness and the sample rather than shortening its latency. The 0/1/10/100/
greater-than-100-hit, 64-term, and four-MiB classes retain separate
distributions. The quiescent storage endpoint recursively inventories every
database, WAL, SHM, journal, pointer, manifest, temporary, staging, and residue
file and gates both logical length and allocated bytes; sparse/compressed files
and omitted sidecars cannot manufacture a pass.

Task 7's preregistered manifest records each generator version, seed, file/state
digest, exact action sequence, timing point, expected final hash, and the budget
rows it exercises. A content, action, settling, or endpoint change creates a new
workload version and resets affected cells; it cannot be made after observing a
result. T1/T5 replace the explicitly labeled startup proxy with the implemented
real-workspace and signed-package workloads and rerun the release gates.

ETW kernel process-start is time zero. TExFlow ETW events segment initialization,
window creation, first submit, editor mutation, PDF decode, and worker readiness;
they do not replace the kernel start event. PresentMon proves displayed frames
and is correlated by PID, timestamps, adapter, and trial ID. WPR/WPAExporter
proves startup and process/resource traces. The harness must fail closed if
privileges, providers, exporter tables, or PresentMon fields are unavailable;
it must not invoke `--restart_as_admin`.

T0.2 first validates PresentMon's supported photon metric against a timestamped
visual-toggle fixture for both the Scintilla child and app compositor lanes. If
that field is `NA`, unavailable, or cannot be correlated reliably, WPR/DWM plus
a calibrated high-speed-camera or latency-instrument lane observes the same
marker. The fallback records sampling rate, synchronization/error bound, refresh
phase, raw captures, and analysis. Without either valid route, the result is
labeled `input-to-displayed-frame`, and the photon budget remains unverified.

## 7. Closed acceptance matrix

Every row requires direct evidence, an explicit direct-evidence owner in the
last column, and one final clean closed-coverage pass after the last repair.
Slash-separated
owners are additive; `all` means T0.2a through T0.2h. T0.2g additionally owns
the integrated campaign revalidation stated in Task 7, and T0.2h owns the final
A01-A19 replay/admission gate stated in Task 8. Those overlays do not replace,
silently transfer, or manufacture evidence missing from a row's direct owner.
A new Medium/High/Critical finding resets the streak to zero. Low findings are
either fixed or explicitly accepted with rationale and must not accumulate into
a Medium systemic gap.

| ID | Requirement | Direct acceptance evidence | Direct-evidence owner(s) |
| --- | --- | --- | --- |
| A01 | Network-free reproducible build | Cold dependency-cache failure is actionable; explicit fetch succeeds; on a sealed disposable runner whose only usable interface/routes are loopback, a Zig-owned oracle records the isolation preflight, proves `deps-fetch` cannot receive bytes, performs two clean builds in disjoint local/global caches, and requires byte-identical canonical path/type/size/SHA-256 manifests for the complete install payload—every exact shipping TExFlow PE, admitted DLL/data/font/resource, and notice/license file, with no extra member. It separately compares the test-only portable `texflow_abi` artifact without placing it in an install/package manifest. Missing detached-NIC/network-none evidence is `UNVERIFIED-NETWORK-ISOLATION`, never an offline pass. | T0.2a/b/c/e/f/h |
| A02 | Hardened acquisition | Positive locks plus hostile tar and per-dependency ZIP cases for traversal, links, ADS/device paths, Windows-case/Unicode-normalized collisions, inventory disagreement, oversize members, expansion limit, bad digest, truncated transfer, and interrupted activation; the exact UCD is acquired before it supplies normalization tables for later archives. | T0.2a |
| A03 | Narrow dependency/ABI boundary | Exact versions, license/source inventory, independent PDFium source reconstruction/equivalence, sealed reconstructed-runtime identity plus community-DLL rejection, ABI size/offset/calling-convention probes, recursive import scan, exact UI/PDF/science PE and version-resource identity, no root `zigwin32`, no TExFlow non-Zig runtime, no product Lexilla linkage/load, no Scintilla/UI closure in workers, and no unexpected DLL/import. | T0.2b/c/d/e/f/h |
| A04 | Native presentation | Real Win32 window; per-monitor DPI v2; two-buffer flip-sequential baseline, waitable object, max latency 1, coherent dirty/scroll history with full redraw on invalidation; flip-discard full-redraw challenger uses no partial metadata; distinct shell hardware/WARP and editor DirectWrite/DirectWriteDC paths; stable occlusion/resize/device loss; no occluded fixed app or editor-child timer after quiescence. | T0.2c/d |
| A05 | Representative visual quality | Captures for all required DPI/themes/states; exact TExFlow title and non-leaf multi-resolution app mark in Explorer/title bar/Alt-Tab/taskbar; focus, contrast, clipping, resize, and typography checks; multi-round design review followed by one final human/runtime pass with no Medium+. | T0.2c/g |
| A06 | Scintilla direct path | UI-image-only static class registration, status-returning direct API, every call on owner UI thread, valid-UTF-8-only non-lossy mutation boundary, bounded Zig container styling with full/incremental equivalence and no product Lexilla, update batching, 10 MiB semantic document, deterministic edit/undo/jump/scroll stress. | T0.2d |
| A07 | Accessibility and Unicode | Separate-process Zig UIA client proves Document Text/Text2/TextEdit/Scroll patterns, explicit ValuePattern absence, ranges, caret, selection, visible ranges, events, exact Unicode-17/UAX-29 grapheme and word units, Format/presented-Line/source-Paragraph/Page-to-Document semantics, UTF-8/UTF-16 mapping, Vietnamese NFC/NFD byte preservation, surrogate/combining/BiDi units, ranges across edits, dedicated-provider-STA marshaling/snapshot consistency, and zero provider-thread Scintilla access; official normalization/grapheme/word conformance data and pinned Accessibility Insights automated/FastPass are cross-oracles, not substitutes for the real client. | T0.2a/d |
| A08 | Real IME behavior | At least one installed non-Latin Windows IME drives composition/commit/cancel/reconversion through the real OS path with UIA/caret evidence; synthetic messages are supplemental only. | T0.2d |
| A09 | Authenticated bounded IPC | Parser/property/fuzz corpus plus live positive/negative peers prove framing, keyed MAC/sequence, nonce, mirrored exact-current-logon/exact-role-package-SID least-right DACL and one-instance pipe, direction-appropriate asymmetric peer proof (full worker file/hash/token proof at the broker; inherited parent-handle/PID/creation-time/path/build-identity proof at the worker without UI-image read access), handle and shared-section allowlist, caps, cancellation, timeout, crash, and backpressure. Science entity transfer additionally proves exact null/empty tags, fixed field order, little-endian widths, and domain-separated field/entity digests. | T0.2e/f |
| A10 | Role isolation | Both product workers are dedicated role-specific Zig PE images imperatively created as LPACs with zero named capabilities, the `ALL APPLICATION PACKAGES` opt-out, and the complete frozen mitigation profile; suspended token/policy queries prove exact mode/SID/capability/integrity/child/mitigation state, while AAP/ARAP/exact-role canaries distinguish denied, residual-OS, and product-specific authority. Recursive imports plus independent live-module inventories exclude UI/Scintilla/graphics and cross-role images before input admission. Outside the disclosed workload-observed `ALL RESTRICTED APPLICATION PACKAGES` OS surface, PDF product authority is limited to the authenticated pipe, its exact verified worker image, PDF-role-only sealed PDFium/font/data closure, erased per-generation scratch, read-only PDF-input sections, and bounded generation-unique tile-transfer sections. Science has the same scratch discipline, its exact verified worker/SQLite closure, and only its separately brokered disposable-search directory; it cannot open/map/load the PDF worker or PDFium. Neither can read project or canonical-ledger paths, use registry/COM/network capabilities, persist through its profile, write elsewhere, spawn children, inherit ambient handles, or silently lose a mandatory mitigation; any unexpected successful access or regular-AppContainer/restricted-token/single-UI-image fallback is failed isolation. | T0.2e/f |
| A11 | PDF correctness/resilience | The selected error-safe PDF engine is PDF-only; mixed sizes/rotation/UserUnit, selection/search geometry, non-embedded fonts, Latin/CJK/Arabic and image-only accessibility state, malformed/oversize/hang/crash corpus, stale cancellation, previous artifact retention, independent UI-broker validation of every worker reply, bounded 512-px GPU tile LRU, and one-shot section/private-copy handoff with late-write/duplicate/crash-state negatives. | T0.2b/e |
| A12 | Ledger durability | WAL/FULL, per-project sequence and SHA-256 chain, project-scoped immutable <=256-KiB content chunks stored once, typed null/length/hash event and projection references, and content+event+projection same transaction; every reference and byte stream is revalidated. Contract-compliant VFS failure/process-kill cases reopen to the complete old or new transaction, while device-contract-violation cases are detected and quarantined rather than silently served. | T0.2f |
| A13 | Disposable search correctness | Separate WAL/NORMAL contentless-delete FTS5 database with a UUID-only rowid map, secure-delete, `columnsize=1`, provisional `detail=full`, preregistered smaller-detail and stored-content counterfactuals, the Zig `texflow17` Unicode-17 tokenizer, committed-ledger watermark, bounded complete-entity transport, atomic staging-generation activation, accent-preserving canonical-equivalent matching, explicit non-dictionary locale limits, bounded literal queries and descriptor-free ranks, independent broker literal-AND-before-display validation, and exact whitespace/control/elision/untitled safe-title/snippet construction from every canonical field. Typed exact IDs remain ledger-only; trusted eligibility/not-completeness semantics, delete/corrupt/rebuild tests, idempotent replay, divergence detection, and no search failure corrupts or visually impersonates the ledger are mandatory. | T0.2f |
| A14 | Measurement validity | Zig harness, immutable mixed-strength matrix and coverage proof, named 30-trial cells, exact non-authoritative 128-bit trial correlation across UI/workers, exact shared canonical-source-set/dependency-lock-bound build identity across every role PE/event plus post-push commit-to-source-set proof, two byte-identical builds and a canonical complete-payload manifest/candidate receipt, per-cell root rehash, per-process image/file-ID and loaded-module match, ETW/WPR/WPAExporter/PresentMon strict parsers, raw samples, privacy-safe frozen machine/physical-OS/profile/boot manifest, adapter/output identity, process-tree aggregation, invalid-sample rejection, and separate editor/shell display lanes. | T0.2c/d/e/f/g |
| A15 | Performance budgets | Both frozen physical reference machines run both supported OS lanes; cell/profile-specific warm and independently verified hiberboot-ineligible full-kernel-boot distributions plus hardware/WARP and controlled RDP campaigns meet every applicable budget—including search first-use/validated-identity/safe-title/snippet/cancel/rebuild/peak-memory/complete-root gates—without pooling. Current-host or unavailable hardware evidence remains explicitly provisional and blocks admission. | T0.2f/g/h |
| A16 | UI black-box reality | Independent Zig process uses UIA and OS input; calibrated QPC-bound DXGI Desktop Duplication proves the visible DWM-composed desktop; no unproved search candidate appears. Canonical broker-built titles/snippets/ranges exercise whitespace/control transform, visible `[U+XXXX]`, U+2026 caps, UUID fallback, layout-only BiDi isolation, worker omission/rank manipulation, exact nonempty/empty/rebuilding/unavailable epistemic copy, and eligibility-not-completeness labels as hostile-worker UI states. Mandatory Narrator, pinned Accessibility Insights automated/FastPass, and real-IME journeys, console/ETW/process error scan, and explicit RDP gaps remain required. Browser is used only for any HTML evidence artifact. | T0.2d/e/f/g |
| A17 | CI and scope safety | The T0.1 smoke intent plus ABI/miscompile/SIMD known answers remain explicit Zig regression gates; the obsolete installed console artifact and old brand-only output are intentionally retired, while the internal ABI/header/symbol namespace becomes `texflow`. The ABI library and every test runner remain cache-only and absent from install/package manifests. Linux emits no installed product artifact; Windows alone emits the exact x64 GUI `TExFlow.exe`, headless `TExFlow.PdfWorker.exe`, and headless `TExFlow.ScienceWorker.exe` PE set with exact role resources and no invented legal publisher fields. Recursive import/module/package inventories prove role separation; the frozen legacy tree is comparison-only and absent from install/package outputs; CI actions remain commit-pinned; every post-bootstrap hash/parser/oracle/verdict is Zig; no generated binary/archive/cache is committed. | all |
| A18 | Honest closure | Evidence binds source commit/tree, the canonical source-set/build identity, complete-payload manifest and role-PE digests, dependency digests, machine/trial data, command results, unverified items, streak, and admission decision without a self-referential hash claim. | T0.2h |
| A19 | Live-render and energy discipline | Synthetic versioned render jobs prove adaptive 220-750 ms scheduling, 75 ms supersession grace, zero stale-current artifact, foreground QoS only while interactive, background EcoQoS/low-memory priority where supported, and no persistent timer-resolution escalation. Source inventory plus ETW separate the permitted visible focused system-caret blink and prove zero caret/dwell/scroll/widen/idle-styling wake after minimized/fully occluded quiescence. | T0.2c/d/e/g |

## 8. Planned file map

Paths may be split only when a file becomes mechanically unwieldy; a split must
preserve the responsibilities and cannot introduce a new abstraction layer.

| Path | Responsibility |
| --- | --- |
| `build.zig`, `build.zig.zon` | Preserve the T0.1 smoke/ABI/miscompile/SIMD regression graph without installing any test executable/library; rename the cache-only internal ABI library to `texflow_abi`; add the exact target-gated TExFlow UI/PDF/science PE set, dependencies, portable tests, native QA, and benchmark steps. |
| `.gitignore` | Exclude dependency caches, extracted sources, generated fixtures, build/install outputs, native QA captures/traces, temporary evidence roots, and raw or secret-bearing machine artifacts while leaving only bounded reviewed manifests and redacted evidence trackable. |
| `docs/development.md` | Document the exact stable Zig build steps, Windows-native prerequisites, explicit network/reconstruction lanes, generated-output locations, provisional-versus-admission limits, and TExFlow naming transition without advertising an unverified workflow as complete. |
| `tools/zig/native-deps.json` | Exact source/tool lock, archive roots, digests, byte and extraction limits, licenses, and the admitted build profile: `x86_64-windows-msvc`, Zig baseline CPU model/default features rather than host-native selection, `ReleaseSafe`, stripped installed images, GUI-subsystem UI/headless workers, and exact per-role compile/link feature closures. |
| `native/zig/THIRD_PARTY_NOTICES.txt` | Deterministic shipping notice headed by TExFlow, retaining required AGPL source-lineage attribution and exact Scintilla/SQLite/Unicode/PDFium-runtime closure notices without inventing a legal publisher; test-only Lexilla is excluded. |
| `tools/zig/pdfium-repro-toolchain.json` | Reviewed fail-closed PDFium reconstruction receipt: sealed host image, Visual Studio/SDK components, resolved DEPS/CIPD graph, compiler/linker and build-tool identities, exact GN arguments, and permitted upstream wrapper/process graph. |
| `tools/zig/attestations/pdfium-chromium-8035-win-x64.jsonl` | Reviewed immutable GitHub/Sigstore bundle for offline PDFium provenance verification; declarative evidence only. |
| `tools/zig/attestations/github-attestation-trusted-root-2026-09-04.jsonl` | Reviewed two-line trusted-root snapshot for deterministic offline verification of the locked historical bundle; declarative evidence only. |
| `tools/zig/deps.zig` | HTTPS allowlist, streaming digest/size check, hardened tar+gzip extraction, staging, atomic activation, cache audit. |
| `tools/zig/unicode_gen.zig` | Strict parser/generator for the locked Unicode-17 UCD subset and official conformance files; emits deterministic <=512-KiB cache-only tables plus a source/archive/member-hash receipt. |
| `tools/zig/pdfium_reproduce.zig` | Explicit-network, no-secret source reconstruction controller; preflights a qualified >=100-GiB NTFS host, pins root/recipe/depot_tools, records DEPS/toolchain, applies reviewed build-only patches, and compares outputs. |
| `tools/zig/package_probe.zig` | Canonical runtime-payload inventory and deterministic tar+gzip size probe; it cannot exclude, reorder, rename, precompress, or dictionary-transform files. |
| `tools/zig/repro_check.zig` | Zig-owned two-clean-build controller: exact compiler path/typed argv, sealed-runner interface/route/proxy/process preflight, negative fetch canary, disjoint caches/prefixes, complete canonical install-manifest validation/hash comparison, generated candidate receipt with every role PE digest/common build identity, separate cache-only test-artifact comparison, and machine-readable verdict. It validates rather than mutates host network policy. |
| `native/zig/src/main.zig` | UI-only GUI entry and stable exit/status behavior; no worker dispatch. |
| `native/zig/src/abi.zig`, `native/zig/include/texflow_abi.h` | Cache-only portable T0.1 ABI corpus under the new machine namespace; no legacy compatibility exports and no ABI library in an install/package manifest. |
| `native/zig/src/pdf_main.zig`, `science_main.zig` | Minimal dedicated headless worker entry points; authenticate their exact bootstrap/internal probe mode before role-specific initialization. |
| `native/zig/src/app/role.zig` | Compile-time UI/PDF/science identity and strict internal probe-state validation; no runtime role substitution. |
| `native/zig/src/app/build_identity.zig` | Canonical role-name and prerelease VERSIONINFO tuple plus the common 32-byte `SHA-256("texflow:build:v1\0" || source_set_sha256[32] || dependency_lock_sha256[32])`; role remains separate and no legal publisher is guessed. |
| `native/zig/src/app/live_render.zig` | Versioned adaptive scheduler, supersession/cancellation, artifact-currentness state and QoS transitions. |
| `native/zig/src/app/lifecycle.zig` | Monotonic app/worker/database/UIA/graphics shutdown admission, ownership order, deadlines, and crash-versus-clean-close result. |
| `native/zig/src/app/theme.zig`, `layout.zig`, `strings.zig` | Measured semantic colors/type/spacing, responsive pane model, high-contrast/touch modes, and versioned locale resources. |
| `native/zig/src/app/uia_shell.zig` | Root/pane/status/splitter/action UIA fragments and focus/pattern semantics for custom native chrome. |
| `native/zig/src/app/search_view.zig` | T0.2 native search-state model, broker-proven row publication, safe-title/snippet presentation, exact epistemic resources, keyboard/focus/UIA semantics, and stale-generation suppression. |
| `native/zig/src/platform/windows/api.zig` | Narrow zigwin32 namespace facade and compile-time declaration checks. |
| `native/zig/src/platform/windows/argv.zig` | Exact typed-argv to writable CreateProcessW command-line serialization with NUL/overflow rejection and round-trip probes. |
| `native/zig/src/platform/windows/com.zig` | COM apartment ownership, pointers, HRESULT handling, and owner-thread assertions. |
| `native/zig/src/platform/windows/process.zig` | Peer identity, imperative LPAC launch/AAP opt-out, suspended-token verification, handle list, mitigations, Job Object, aggregate accounting. |
| `native/zig/src/platform/windows/shell.zig` | DPI-aware Win32 lifecycle, input, layout, theme/high contrast, occlusion and device-loss state. |
| `native/zig/src/platform/windows/presenter.zig` | D3D11/DXGI waitable flip state, coherent two-buffer dirty/scroll history, full-redraw challenger, frame pacing, D2D/DWrite composition, WARP fallback. |
| `native/zig/src/platform/windows/telemetry.zig` | ETW provider/events and monotonic trial correlation. |
| `native/zig/src/ipc/frame.zig`, `pipe.zig`, `peer.zig` | Versioned framing, bounded I/O, authentication, ACL, handshake, cancellation and backpressure. |
| `native/zig/src/editor/scintilla.zig` | Class registration, direct status API, UI-thread-only façade, notifications and document lifetime. |
| `native/zig/src/editor/lexer.zig` | Revision-stamped bounded LaTeX/BibTeX container styling, line-state checkpoints, invalidation, and convergence. |
| `native/zig/src/text/unicode.zig` | Shared pure-Zig Unicode-17 UTF validation, normalization/case-fold, UAX-29 segmentation, compact generated-table access, and deterministic token iteration; imported by UI and science only. |
| `native/zig/src/editor/text_units.zig` | Exact UTF-8 byte to UTF-16 unit mapping, frozen UIA Format/grapheme/word/presented-line/source-paragraph/Page-to-Document boundaries and edit transforms. |
| `native/zig/src/editor/uia/thread.zig`, `snapshot.zig`, `provider.zig`, `range.zig` | Dedicated provider STA, immutable revision/viewport snapshots, marshaled raw/fragment/text/text-edit providers, bounded ranges/events and revision-bound UI commands; no multiline ValuePattern and no non-UI Scintilla call. |
| `native/zig/src/pdf/protocol.zig`, `client.zig`, `worker.zig`, `uia.zig` | PDF messages, UI client, accessible document snapshot, document thread, cancellation/versioning and failure recovery. |
| `native/zig/src/pdf/pdfium.zig` | Worker-only dynamically loaded PDFium public-ABI table, single-engine-thread ownership, progressive rendering, and bounded 512-px raster production. |
| `native/zig/src/pdf/tile_handoff.zig`, `tile_cache.zig` | UI-side one-shot section/private-copy validation and adaptive bounded resident GPU tile LRU; no worker-writable object reuse or direct shared upload. |
| `native/zig/src/data/sqlite.zig`, `ledger.zig`, `search.zig` | Narrow SQLite ABI, single-copy project-scoped canonical content chunks, event/projection reference transaction, trusted query-only presentation lane, bounded projection protocol, and staged contentless-delete FTS generations. |
| `native/zig/src/bench/events.zig`, `runner.zig`, `presentmon_csv.zig`, `wpa_csv.zig`, `machine.zig`, `matrix.zig`, `evidence_pack.zig` | Trial protocol, tool orchestration, strict parsing, privacy-safe frozen machine identity, immutable mixed-strength matrix/coverage proof, per-cell aggregation, and content-addressed evidence retention/restore verification. |
| `native/zig/qa/uia_client.zig`, `journey.zig`, `capture.zig`, `capture_dxgi.zig`, `capture_wic.zig` | Independent black-box UIA/SendInput journey plus calibrated, QPC-correlated DXGI Desktop Duplication and built-in WIC evidence encoding. |
| `native/zig/qa/campaign/t0_2_campaign.json`, `reference_machines.json` | Reviewed immutable mixed-strength campaign preregistration and privacy-safe physical reference-machine slot contract; Task 7 commits and verifies these before observing measured results. |
| `native/zig/fixtures/t0_2/` | Zig source fixture and hash-locked campaign-workload generators plus small declarative expectations; generated PDF/DB/archive artifacts stay in caches. |
| `native/zig/tests/t0_1_smoke.zig`, `repro_check_test.zig` | Test-only replacement for the former console smoke plus hostile/oracle tests for the clean-build controller; no installed test executable. |
| `native/zig/tests/` | Other portable unit/property tests and Windows-only ABI/runtime/fault/security/QA tests. |
| `native/zig/manifests/TExFlow.exe.manifest` | UI per-monitor-v2 DPI, supported OS and requested execution-level declaration. |
| `native/zig/manifests/TExFlow.PdfWorker.exe.manifest`, `TExFlow.ScienceWorker.exe.manifest` | Role-bound supported-OS/requested-level manifests embedded independently in the corresponding headless image; no UI declaration. |
| `native/zig/assets/texflow_icon.zig`, `tools/zig/icon_gen.zig`, `docs/assets/texflow-app-mark.svg` | Canonical numeric mark geometry, pure-Zig supersampled raster/ICO generator, and deterministically regenerated text SVG. The 16/24/32/48/256-pixel ICO exists only in the build cache; no binary asset is committed. |
| `native/zig/manifests/TExFlow.rc`, `TExFlow.PdfWorker.rc`, `TExFlow.ScienceWorker.rc` | Declarative manifest/version resources with exact ProductName, FileDescription, InternalName, and OriginalFilename; UI RC alone consumes the generated ICO through a build-defined quoted path and the pinned Zig resource compiler; no ambient RC tool, invented legal publisher, or executable behavior. |
| `native/zig/manifests/texflow.wprp` | Minimal ETW collection profile used by the Zig benchmark harness. |
| `.github/workflows/zig.yml` | Preserve T0.1 and add portable versus Windows-native T0.2 lanes with timeouts/artifact evidence. |
| `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md` | Append-only per-task commands, artifact digests, findings, streak transitions, CI run IDs, and unverified items; never a self-hash or substitute for final replay. |
| `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-native-feasibility.md` | Final/provisional evidence manifest and explicit T1 admission decision. |
| `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-artifacts.json` | Bounded redacted canonical inventory of raw-artifact IDs, sizes, hashes, durable-copy receipts, and retention deadline; no secret paths or credentials. |

---

## 9. Implementation protocol shared by every task

For each task below:

1. Convert its acceptance rows into failing tests or a failing runtime probe.
2. Run the narrow command and record the expected failure; do not commit red.
3. Implement only enough owned Zig behavior to close the defined slice.
4. Run the five-pass effectiveness loop: verify the oracle against the written
   contract; choose a portfolio by failure surface; add adversarial boundaries;
   deliberately falsify each critical invariant in the working copy and prove
   the intended test fails before restoring it; then prove the real runtime path
   rather than a mock-only path. Record deterministic seeds and replay data.
   Every owned allocating parser/state machine also runs deterministic fail-at-N
   allocation tests through and one past its successful allocation count. OOM
   must leave no leak, partial protocol/database/artifact commit, stale-current
   label, corrupted source, or restart loop; the last good user-visible state
   remains usable or a typed terminal error is shown.
5. Run formatter, narrow tests, all affected regression tests, and direct
   runtime evidence. A retry that passes does not erase a flake; retain its
   diagnostics and fix it or mark the criterion unverified.
6. Perform one full closed-coverage review pass after the last repair from a
   clean cache/profile with a fresh committed trial-order seed. Reset the task
   streak to zero on any Medium+ gap, fix it, then restart the full pass.
7. Update the evidence worklog, commit one coherent green slice, and push
   `main`. A partial/provisional commit message must not say T0.2 is complete.
8. Re-read remote CI result before starting the next task. A queued or missing
   required job is not green.

Task 1 creates the tracked append-only worklog at
`docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`; Tasks 2-7 append
their command/exit-code summary, fresh-profile identities, raw-artifact paths
and digests, findings/fixes, streak transitions, remote run IDs, and explicit
unverified items before their task commit (and before each of Task 7's two
commits). It never predicts or claims its own
future commit hash. Raw/binary artifacts remain ignored; Task 8 independently
replays the gates and distills the final evidence manifest rather than treating
the worklog as proof by assertion.

Every command introduced below must be implemented as a named `zig build` step
with bounded timeouts in its controller. A test that hangs is a failure, not a
reason to remove coverage. Generated archives, PDFs, databases, traces, CSVs,
screenshots, and dependency sources remain in ignored cache/evidence-output
directories; the final evidence document records their digests and retention
location rather than committing large binaries. Admission-grade raw evidence is
not ephemeral cache: a Zig evidence packer writes a canonical content-addressed
manifest and two byte-verified copies in independent failure domains. For two
local roots it resolves every volume through
`IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS` and requires disjoint physical-disk sets;
two partitions, mount points, aliases, or pooled extents over any common disk do
not qualify. The alternative is one local root plus an explicitly authorized
durable artifact service. The packer performs a full restore/rehash before the
final admission pass and retains the copies until the T0.2 decision is
superseded plus 90 days. No external upload, credential use, or paper/user data
is implied; all campaigns use generated fixtures, and unavailable durable
retention leaves A18 unverified.

Task 7 is the sole intentional two-commit exception: its harness, matrix, and
machine-slot preregistration must complete the multi-round adversarial review,
then be committed, pushed, and CI verified before measured results exist; the
later result/evidence commit has its own one-pass final gate. This preserves one roadmap task while preventing an observed
result from changing its test design. Neither commit advances the final T0.2
architecture-admission streak unless its required coverage is closed.

## Task 1 (T0.2a): Lock and acquire native sources safely

**Files:**

- Create `tools/zig/native-deps.json`
- Create `tools/zig/attestations/pdfium-chromium-8035-win-x64.jsonl`
- Create `tools/zig/attestations/github-attestation-trusted-root-2026-09-04.jsonl`
- Create `tools/zig/deps.zig`
- Create `tools/zig/unicode_gen.zig`
- Create `native/zig/src/text/unicode.zig`
- Create `native/zig/tests/deps_manifest_test.zig`
- Create `native/zig/tests/archive_security_test.zig`
- Create `native/zig/tests/unicode_data_test.zig`
- Create `native/zig/tests/attestation_test.zig`
- Create `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `build.zig`, `build.zig.zon`, `.gitignore`, `docs/development.md`

**Acceptance rows:** A01, A02, A07 Unicode data/runtime subset, A17.

- [ ] Add schema tests that reject duplicate IDs, non-HTTPS URLs, unapproved
  hosts/paths, missing license/source identity, bad hexadecimal digests, zero or
  impossible sizes/caps, an integrity mode inconsistent with its host/source,
  inconsistent archive roots, unknown build switches, and dependency cycles.
  Byte-stable assets require archive size/SHA-256; the one exact-commit Gitiles
  source uses compressed/expanded caps plus the defined canonical tree digest.
  Lock and hash the exact PDFium attestation bundle and dated two-line trusted
  root as declarative source evidence; a changed/malformed/duplicate root or
  bundle, a missing or duplicate matching subject, or a wrong
  predicate/identity/timestamp is rejected. Schema validation also locks the
  exact GitHub CLI archive inventory, executable version/hash, and Authenticode
  signer/thumbprint. Lock the Unicode-17 UCD archive's exact 74-entry inventory,
  total expanded bytes, version marker, selected data/test members, and Unicode
  License v3 notice obligation. It also records the exact Accessibility Insights production
  MSI/version/hash/signer as an operator-provisioned QA-tool lock, but no Zig
  dependency step executes or installs that MSI.
- [ ] Generate hostile tar+gzip cases entirely in Zig: `/absolute`, `C:\drive`,
  UNC/device paths, ADS colons, `..`, symlink/hardlink, duplicate exact path,
  special/FIFO/sparse entry, PAX/GNU long-name override, duplicate
  Windows-case/trimmed-dot path, reserved DOS name/8.3 alias, Unicode-normalized
  collision, NUL/control name, invalid tar checksum/base-256 number/overflow,
  concatenated gzip/trailing bytes, too many members, oversized member/total,
  compression-ratio breach, redirect to a non-allowlisted host, TLS/name failure,
  truncated stream, digest mismatch, content-length mismatch, and interruption
  before activation.
- [ ] Generate a restricted-ZIP hostile corpus entirely in Zig for both locked
  UCD and GitHub CLI shapes: local/central name or size disagreement, duplicate records,
  overlapping data ranges, encryption, unsupported method/flags, Zip64 or
  multi-disk markers, data-descriptor ambiguity, CRC/digest failure, truncated
  deflate, forged expansion ratio, symlink/reparse attributes, traversal and all
  Windows name collisions above, malformed/duplicate/unknown extra fields,
  nonzero or unexpected directory records, extra/missing member, comments, and
  trailing bytes. Only
  the exact per-dependency reviewed inventory may activate. For GitHub CLI only
  `gh.exe` plus required notices remain in the QA cache; for UCD only
  `ReadMe.txt`, `UnicodeData.txt`, `CaseFolding.txt`,
  `DerivedCoreProperties.txt`, `DerivedNormalizationProps.txt`,
  `CompositionExclusions.txt`, `NormalizationTest.txt`,
  `auxiliary/GraphemeBreakProperty.txt`,
  `auxiliary/GraphemeBreakTest.txt`, `auxiliary/WordBreakProperty.txt`,
  `auxiliary/WordBreakTest.txt`, and `emoji/emoji-data.txt` remain as build
  inputs. Every selected member's exact size/hash is recorded after extraction.
- [ ] Add bounded raw-Snappy and attestation-API fixtures: truncated/overlong
  varint, zero/backward/out-of-range copy, overlapping-copy boundary, literal or
  output overflow, decompression bomb, trailing bytes, oversized/duplicate API
  result, wrong repository ID/host/path/query/predicate/subject/digest, expired
  or malformed bundle URL, changed compressed/canonical hash, generic
  release-asset substitution, and any ambient credential/config access. A fixture made
  from the locked 17,297-byte transport must expand to 18,095 JSON bytes and the
  canonical one-LF JSONL hash above without invoking GitHub CLI.
- [ ] Add paired Gitiles-style fixtures whose gzip/tar metadata and transport
  bytes differ but extracted regular-file path/size/content records are equal;
  both must produce the same tree digest. Changing a path, byte, size, duplicate,
  type, Unicode/control name, link, or file count must fail before activation.
- [ ] Implement streaming HTTPS download to a unique staging file, size and
  digest verification before extraction for byte-stable assets, or bounded
  staging extraction plus canonical tree verification for the exact-commit
  Gitiles source. Use a verified cache root and dependency-specific top-level
  allowlists. The Scintilla archive permits only the exact 296-entry
  `scintilla/` root and the separate Lexilla comparator archive only the exact
  993-entry `lexilla/` root;
  UCD is acquired first: its already-verified whole-archive digest and exact
  ASCII member inventory make bootstrap extraction independent of Unicode
  normalization; `unicode_gen.zig` must pass the official normalization,
  grapheme, and word test files before its tables may police normalized path
  collisions in every later archive. The conservative collision key is computed
  per path component as `NFD(full-default-case-fold(NFD(component)))`, followed
  by the separately defined Windows trailing-dot/space and reserved-name checks;
  it is comparison-only and never renames extracted bytes. The PDFium archive
  permits only its locked metadata/license files plus `bin/`,
  `include/`, `lib/`, and `licenses/`; the PDFium root-source and builder-recipe
  snapshots each use an exact manifest root/file inventory. Depot_tools is not
  sent through this archive path. Record a post-extraction inventory and
  atomically activate only after every check passes. Create a unique owner-only
  staging root on the target volume, reject reparse points in every cache/staging
  ancestor and entry, resolve/verify each created child through directory/file
  handles, and rename on the same volume while holding the concurrency lock.
- [ ] Make `zig build deps-fetch` the sole ordinary dependency-download step.
  The only other network-capable command is the separately gated T0.2b PDFium
  reconstruction. Add `zig build deps-audit` and `zig build deps-test`. Normal
  build/test steps must neither initialize a network client nor mutate the
  dependency lock. Import zigwin32 from the verified explicit cache path, not a
  remote package-manager dependency capable of automatic fetching.
  Add `zig build unicode-audit`; it regenerates tables in two disjoint cache
  roots, compares exact bytes, rejects an unknown UCD property/value/rule input,
  proves every official conformance vector, and enforces a <=512-KiB read-only
  table blob. Generated UCD tables and the source archive remain cache-only;
  the package includes the required Unicode License v3 notice but not the UCD
  archive.
  `deps-audit` orchestrates offline PDFium attestation verification against the
  committed bundle and custom trusted root. It creates a new empty child profile,
  scrubs token/config/cache/home/AppData inheritance, poisons every standard
  proxy path with a fail-fast loopback endpoint, uses no shell or `PATH`, and
  never fetches an attestation or root implicitly. The test matrix requires one
  valid baseline plus failures for a one-byte artifact mutation,
  signature/bundle mutation, malformed or modified root, missing Public Good root,
  lookalike exact SAN, wrong repository/ref/source or signer digest, self-hosted
  identity, duplicate result, missing verified timestamp, implicit user-cache
  dependence, incompatible CLI version, and mutually exclusive identity flags.
  Parse and revalidate the bounded JSON result rather than matching human text.
- [ ] Test concurrent fetch, interrupted staging cleanup, already-valid cache,
  cache tamper, and read-only cache. Prove the offline clean-build case only on
  the shared sealed-runner contract: Windows uses a disposable VM with its
  virtual NIC detached; Linux uses an operator-provisioned disposable container
  or network namespace with network mode `none`. The Zig verifier requires only
  loopback-capable interfaces/routes, empty proxy/auth variables, the frozen
  process/listener baseline, and a `deps-fetch` negative canary that receives
  zero bytes before it permits the prefilled-cache build. It records the
  external isolation receipt but never disables/re-enables a user's adapter or
  firewall. If that runner is absent, return
  `UNVERIFIED-NETWORK-ISOLATION`. Error text must name the exact remediation
  command without echoing secrets or proxy state.
- [ ] Record the lock provenance limitation for unsigned upstream archives and
  the explicit dependency-update ADR procedure.
- [ ] Run the shared final-pass protocol, then commit and push as
  `build(zig): lock hardened native dependency acquisition`.

**Kill switch:** Any extraction escape, ambiguous Windows path, implicit
network/auth/trust-cache access, attestation acceptance with a wrong identity or
root, cache activation before full verification, UCD member/version/hash or
official conformance disagreement, Unicode table nondeterminism/oversize, or
non-Zig owned fetch/extract/generation behavior blocks all later T0.2 tasks.

## Task 2 (T0.2b): Prove build, ABI, licenses, and binary closure

**Files:**

- Modify `build.zig`, `build.zig.zon`, `tools/zig/native-deps.json`
- Create `tools/zig/pdfium_reproduce.zig`
- Create `tools/zig/package_probe.zig`
- Create `tools/zig/repro_check.zig`
- Create `tools/zig/pdfium-repro-toolchain.json`
- Create `native/zig/src/platform/windows/api.zig`
- Create `native/zig/src/platform/windows/argv.zig`
- Create `native/zig/src/pdf/pdfium.zig` with the declarative public-C ABI table
- Create `native/zig/tests/native_abi_test.zig`
- Create `native/zig/tests/windows_argv_test.zig`
- Create `native/zig/tests/pdf_engine_boundary_test.zig`
- Create `native/zig/tests/pdfium_equivalence_test.zig`
- Create `native/zig/tests/pdfium_repro_toolchain_test.zig`
- Create `native/zig/tests/package_probe_test.zig`
- Create `native/zig/tests/repro_check_test.zig`
- Create `native/zig/tests/lexilla_comparator_test.zig`
- Create `native/zig/tests/binary_import_test.zig`
- Create `native/zig/tests/source_inventory_test.zig`
- Create `native/zig/THIRD_PARTY_NOTICES.txt`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `.github/workflows/zig.yml`, `docs/development.md`

**Acceptance rows:** A01, A03, A11, A17.

- [ ] Add the pinned zigwin32 content hash and import only required Foundation,
  COM, Win32 UI/Input, Graphics, Security, System/Threading, Pipes, Job Objects,
  ETW, and UIA namespaces through `api.zig`. Add a source check that fails on
  root-package or `everything.zig` imports outside the dependency itself. The
  narrow graphics surface must include D3D11, DXGI 1.5 Desktop Duplication,
  DWM visible-frame attributes, and WIC PNG encoding used by Task 7; assert the
  required interfaces, vtable slots, GUIDs, enums, structures, and x64 layouts
  against the installed Windows SDK before the QA harness depends on them.
- [ ] Implement one Zig-owned Windows argv serializer for every raw
  `CreateProcessW` launch. Reject embedded NUL, length/UTF-16 overflow, and an
  absent absolute `lpApplicationName`; produce a distinct writable command-line
  buffer and minimal explicit environment/current directory. Round-trip empty,
  space, quote, consecutive/trailing backslash, Unicode/combining, and long
  arguments through an independent Zig child that uses Windows' actual argv
  parser. No product or QA path may invoke `cmd.exe`, PowerShell, a
  basename/PATH candidate, or a concatenated shell command. The reconstruction controller
  directly launches canonical absolute Python, Git, GN, Ninja/Siso, and CIPD
  entry points where upstream supports it. The pinned `gclient.py` is known to
  translate Windows `vpython3` hooks to `vpython3.bat`; only that and other
  separately enumerated hash-locked upstream wrappers may cause a fixed system
  `cmd.exe` descendant inside the isolated lane. Reject every unrecorded wrapper,
  shell descendant, mutable argument, or unsafe reconstruction-root character.
- [ ] Compile SQLite's exact amalgamation with `SQLITE_ENABLE_FTS5=1`,
  `SQLITE_THREADSAFE=1`, `SQLITE_DEFAULT_MEMSTATUS=1`,
  `SQLITE_OMIT_LOAD_EXTENSION=1`, `SQLITE_OMIT_SHARED_CACHE=1`,
  `SQLITE_OMIT_DEPRECATED=1`, `SQLITE_DQS=0`,
  `SQLITE_TRUSTED_SCHEMA=0`, `SQLITE_MAX_MMAP_SIZE=0`,
  `SQLITE_TEMP_STORE=3`, `SQLITE_MAX_LENGTH=6291456`,
  `SQLITE_MAX_ALLOCATION_SIZE=8388608`, and
  `SQLITE_PRINTF_PRECISION_LIMIT=100000`. Keep the default allocator/page cache
  so the hard-heap limiter covers them; do not enable an alternative page-cache
  pool that bypasses that accounting. Assert runtime version/source ID, every
  expected compile option and prohibited API/symbol, integer widths, destructor
  calling conventions, and all exposed ABI layouts. Task 6 applies and proves
  the narrower connection limits rather than relying on compile defaults.
- [ ] Mirror the upstream Scintilla Win32 static source inventory in `build.zig`
  and compile C++17 with the narrowest upstream-supported flags into a UI-only
  static library that no worker target can reference. Register and
  release the window class in a tiny native probe; obtain the status-returning
  direct function; create/destroy a document; select the null/container lexer;
  and prove styling notifications and batched byte styles without an `ILexer5`
  object. Build pinned Lexilla only as a separately named, unshipped test
  comparator over reviewed LaTeX/BibTeX fixtures. Assert by link map, imports,
  module enumeration, binary string/symbol scan, and distribution inventory that
  neither Lexilla nor its catalogue is reachable from `TExFlow.exe`; separately
  prove Scintilla and its recursive UI imports are unreachable from both worker
  PE graphs. Record the
  comparator's source/license identity and measured size separately.
- [ ] Verify the PDFium archive and contained DLL digests, exact extracted
  inventory, `VERSION`, `args.gn`, license tree, x64 PE identity, and unsigned
  Authenticode status. In a separately labeled provenance lane, verify the
  GitHub/Sigstore attestation and exact workflow identity, builder commit, run,
  subject name, and subject digest. Record explicitly that this proves the
  community build event, not independent source reproduction from the locked
  official branch head. Run verification from the committed `--bundle` with
  credentials removed and network denied, and prove no socket/API fallback; an
  implicit online lookup is failure.
- [ ] Implement a Zig-controlled `deps-reproduce-pdfium` lane that refuses to
  start without `-Dallow-network=true`, an explicit absolute
  `-Drepro-root`, a fresh disposable root outside the repository, >=100 GiB
  free NTFS space, >=16 GiB physical memory, and an explicitly authorized
  ephemeral VM/runner or dedicated clean build machine. Reject an everyday
  developer account/host, mounted user data or write-capable repository,
  reusable credentials, reparse-backed ancestors, and a root with whitespace,
  non-ASCII text, shell metacharacters, or unsafe length;
  abort below 10 GiB free, after 15 minutes without progress, or after 180
  minutes total, while preserving bounded diagnostics. Give the child toolchain a disposable `HOME`,
  `USERPROFILE`, temp, Git config, credential-store, and cache namespace; disable
  system/global Git config, credential helpers, user hooks/templates, interactive
  prompts, and ambient proxy/auth variables. Materialize the locked builder
  recipe, Git-checkout
  depot_tools at its exact commit, reject every link except the three declared
  internal targets, disable depot_tools auto-update, and prove its commit/tree
  is unchanged before and after the build,
  sync PDFium at exact commit `6f2272e1f3aaa141305475b83ef4eac2c1f527b8`
  rather than a branch name. Treat the community recipe's `windows-2022`
  runner selector and `https://go.microsoft.com/fwlink/?linkid=2370315`
  Windows-SDK downloader as historical evidence only: neither is an admissible
  reconstruction input. The authorized reconstruction host must boot a sealed,
  content-identified image and expose an exact Visual Studio 2022 Build Tools
  instance/component inventory plus Windows SDK `10.0.28000.0`; hash and signer
  inventory the consumed SDK `Include`, `Lib`, and `bin` closure. Give the lane
  no package installer or mutable SDK URL. Record every resolved Git/CIPD
  dependency, upstream hook, remote URL, Python/Git/CIPD client, Chromium Clang,
  linker, GN, Ninja/Siso, Visual Studio component, Windows SDK, OS build, and
  runner-image identity in `pdfium-repro-toolchain.json`.
- [ ] Split source resolution from compilation through the required
  `-Dphase=resolve|reproduce` mode. `resolve` writes a canonical candidate receipt
  only inside the ignored disposable evidence root, proves no GN/compiler/linker
  descendant ran, and never overwrites the tracked lock. Review the candidate
  and promote its exact bytes/hash to `pdfium-repro-toolchain.json` before
  discarding that root. `reproduce` refuses a missing/dirty/unreviewed tracked
  receipt, records its SHA-256 in every child/event/result, and never changes it.
  A resolver pass may discover the
  exact commit/instance/digest closure but may not invoke GN, a compiler, or a
  linker. Canonicalize and review that closure, the allowed
  endpoint/write/process graph, and the exact sorted GN arguments; then discard the root. The
  evidentiary reconstruction starts from a second fresh root and must match the
  approved receipt before the first `gn gen` or compile process. Any unresolved
  package/tag, mutable runner label, ambient Visual Studio/SDK selection,
  different signer/hash/component, or post-compile receipt update aborts and
  resets the reconstruction; it cannot be accepted merely by recording what
  happened afterward. Do not run the builder recipe's mutable Windows-SDK
  downloader or give the lane repository-write credentials. Apply only the hash-locked
  build/public-header patches needed for the shared library and the exact
  non-V8/non-XFA GN arguments; a patch fuzz/offset or dirty unexpected source
  tree is failure.
- [ ] Launch every source-rebuild tool by canonical absolute path and typed argv,
  after fingerprinting its file identity/hash/version; use bounded captured
  stdout/stderr and wall/output limits. Any upstream child interpreter/tool is
  resolved inside the recorded disposable depot_tools/CIPD graph, never from the
  user's PATH, shell associations, or App Execution Aliases. Record and enforce
  the complete descendant process/image/hash/argv/parent inventory and all
  writes/endpoints. Direct Python/GN/Ninja/CIPD execution is preferred; permit
  a fixed system `cmd.exe` only as the interpreter selected transitively by an
  enumerated hash-locked upstream `.bat` wrapper, never for TExFlow logic or a
  constructed free-form command. Mutation tests add an unexpected wrapper,
  descendant, endpoint, outside-root write, and shell-metacharacter path and
  require fail-closed results.
- [ ] Compare the independently built DLL with the attested reference DLL using
  static evidence only: exact public headers/build flags, ABI layouts, required
  and forbidden exports, recursive imports, PE architecture/mitigations/sections,
  disabled-feature surface, license inventory, and size. Record byte identity
  but do not require it across different compiler/SDK paths. Task 2 must never
  load or execute either PDFium DLL; runtime correctness moves to Task 5 after a
  Zig-only isolation baseline. Any static ABI, security-surface, or license
  divergence fails A03 and blocks Task 5/T1. On success, copy only the
  independently built DLL into a content-addressed, owner-only admitted cache,
  record its digest/source graph/pre-compilation-approved toolchain receipt, and prove Task 5 rejects the
  community DLL hash even though it passed static comparison.
- [ ] Declare the smallest reviewed PDFium public-C function table in Zig for
  initialization, memory-backed open, password/error handling, page/render,
  progressive pause/continue/close, text/search/character boxes, links/actions,
  bounded annotation count/subtype/rectangle/string extraction, and cleanup.
  Load it dynamically only inside the authenticated dedicated PDF-worker entry
  after its no-engine bootstrap with safe DLL
  search. Assert every function type/layout against the pinned public headers,
  exact required exports, absence of V8 exports/runtime imports, and rejection of
  a missing/extra-in-allowlist function or wrong binary digest. Experimental
  progressive and annotation functions are exact-pin exceptions named in the lock.
- [ ] Prove by build-graph and process-observation tests that Task 2 performs
  PE/header/source analysis only: no `LoadLibrary*`, DLL import, worker launch, or
  PDFium code execution is reachable from `deps-audit`, ABI, reconstruction, or
  equivalence steps. Runtime known-answer/error probes belong exclusively to
  Task 5 after its isolation baseline passes.
- [ ] Prove that the product UI role neither imports nor loads `pdfium.dll`, does
  not initialize form fill/JavaScript/XFA, supplies no network/upload callbacks,
  and treats URI/launch/attachment actions as inert bounded data. The PDF worker
  may load only the exact DLL under restricted search; machine-time sandbox
  policy is supplemental and never substitutes for Task 5 LPAC proof.
- [ ] Build Debug, ReleaseSafe, and diagnostic ReleaseFast on Windows x64. Run
  independent Zig extern probes rather than importing implementation modules.
  Implement the test-first `repro_check.zig` controller and exercise bad compiler
  identity, recursive-child invocation, missing/extra/duplicate artifact,
  unexpected legacy/product artifact, cache overlap, network-capable child,
  differing bytes, malformed result, timeout, and interrupted-cleanup cases.
  It launches the exact current Zig binary with typed argv and an explicit
  child-only build mode, uses disjoint prefix/local/global-cache roots, validates
  the same sealed-runner interface/route/proxy/process receipt and negative
  fetch canary without mutating host networking, validates the target-specific
  complete canonical installed-payload manifest with no extra/missing path,
  and compares path/type/size/SHA-256 records in Zig; PE bytes are already built
  stripped, and DLL/data/font/resource/notice/license members are equally
  covered. Task 2 alone may select an exact
  `t0.1-transition` manifest bound to the current baseline commit and the
  existing console/library names; its result is labeled historical and cannot
  satisfy T0.2 admission. A synthetic hostile case proves the same names fail
  every `t0.2*` manifest. Repeat two clean ReleaseSafe builds of the complete
  install payload and separate cache-only ABI test artifact available in this
  task; Task 3 makes `t0.2c` the CI/default phase
  and removes all transition selection from its install path, while Tasks 5, 6,
  and 8 rerun the oracle as each final role image appears. PowerShell/bash may
  bootstrap Zig and invoke named steps only; they never calculate or decide the
  verdict.
- [ ] Implement the reusable recursive PE auditor and apply it to every PE
  available in this task; Tasks 3, 5, 6, and 8 make the corresponding product
  image mandatory. Inspect imported DLL/function allowlists,
  architecture, subsystem, NX/ASLR/CFG compatibility where available, section
  flags, embedded manifest, absence of debug/source paths, and no unexpected
  third-party runtime DLL. Generate and parse back the deterministic
  `native/zig/THIRD_PARTY_NOTICES.txt`, headed by TExFlow, with required AGPL
  source-lineage attribution and exact PDFium/transitive-runtime, Scintilla,
  SQLite, and Unicode License v3 notices/source locations. Do not infer a
  company/copyright owner. Keep the separately labeled test-only Lexilla license
  record out of the shipping notice/payload inventory. The canonical package
  includes root `LICENSE` plus this notice; the stale legacy dependency report
  is not silently repurposed as TExFlow's runtime inventory.
- [ ] Inventory the exact required ReleaseSafe runtime payload and require it to
  stay within 90 MiB. Feed that byte-identical, no-exclusion inventory to the
  sole T0.2 compression oracle: Zig 0.16.0 writes a POSIX-ustar-compatible stream
  with UTF-8 paths in unsigned-byte ordinal order, normalized regular-file mode,
  uid/gid/mtime/owner/group fields zeroed, no PAX/GNU extensions, exact file
  sizes/bytes, and two 512-byte zero end blocks, then wraps it with
  `std.compress.flate` gzip at `Options.level_9` with its deterministic zero-time
  header and no preset dictionary. Reject unsafe/unrepresentable paths rather
  than renaming them; record the input inventory hash, tar hash, gzip hash, and
  exact byte counts; regenerate twice from independent output roots and require
  byte identity plus gzip round-trip to the payload manifest. The result must be
  <=30 MiB as T0.2 feasibility evidence. It is a fixed comparison proxy, not an
  MSIX/portable package or installer result, and no alternate compressor,
  precompression, dictionary, excluded symbol/license/runtime file, or changed
  metadata may replace it after observing size.
- [ ] Review official release notes and public upstream advisories for each exact
  pin on the execution date. Record applicable fixes and known risks, and reject
  a pin with an unresolved vulnerability on the enabled attack surface. An
  absence of a matching advisory is never described as proof of absence.
- [ ] Keep Linux CI on portable manifest/archive/protocol tests only. Standard
  `windows-2022` CI compiles the Windows graph and runs deterministic static and
  non-display native tests, but its published 14-GiB storage makes it ineligible
  for the >=100-GiB reconstruction gate; it must emit `not-in-scope` for that
  non-job rather than a skip that can be mistaken for coverage. On Task 2, Task
  5, and final Task 8 commits, both required standard jobs verify the lock,
  reconstruction-receipt schema, community-DLL rejection rule, product import
  boundary, and all applicable portable/static tests. Only an explicitly
  approved larger/self-hosted Windows job that passes the resource/security
  preflight may reconstruct and run contained PDF runtime probes in the same
  fresh job; never consume a cross-run DLL artifact. Pin every action by commit,
  keep permissions read-only, use a 45-minute timeout for standard jobs and the
  controller's 180-minute ceiling for a qualified reconstruction job, record
  actual runner/image/disk identity, and retain only bounded JSON/text
  receipts—not the DLL—as CI artifacts. Preserve all T0.1 commands and ensure
  Zig/native changes cannot select a docs-only lane. Hosted CI never replaces
  local physical Windows, display, LPAC, or PDF-runtime evidence it did
  not execute.
- [ ] Reduce `.github/workflows/zig.yml` after its pinned-Zig bootstrap to
  declarative setup plus named `zig build` invocations. Move the existing hash,
  output, ABI, manifest, dependency, and result-verdict logic into tested Zig
  steps; shell glue may check only bootstrap failure/exit status and must not
  interpret product or QA results.
- [ ] Run the shared final-pass protocol, require both remote jobs green, then
  commit and push as `build(zig): prove native dependency ABI closure`.

**Kill switches:** Fall back to a curated zigwin32 facade if preview bindings
breach compile/maintenance cost. Fall back from Scintilla to a separately
planned RichEdit spike if its upstream source cannot be statically compiled and
called safely without a TExFlow C++ shim. Reject the PDFium pin if its digest,
attestation identity, public ABI, disabled-feature state, imports, license tree,
independent source-reconstruction equivalence, worker-only load boundary, or
single-thread ownership cannot be proved. MuPDF cannot return under the current
all-Zig rule merely because process isolation contains crashes. Do not progress
with a mysterious DLL, ABI mismatch, license gap, or active-content execution
path.

## Task 3 (T0.2c): Build the native shell and waitable presenter

**Files:**

- Modify `native/zig/src/main.zig`
- Modify `native/zig/src/abi.zig`
- Rename `native/zig/include/oleafly_abi.h` to `native/zig/include/texflow_abi.h`
- Modify `native/zig/tests/abi_probe.zig`
- Create `native/zig/tests/t0_1_smoke.zig`
- Modify `native/zig/fixtures/abi_layout.c`
- Modify `docs/development.md`
- Modify `build.zig.zon`
- Create `native/zig/src/app/role.zig`
- Create `native/zig/src/app/build_identity.zig`
- Create `native/zig/src/app/live_render.zig`
- Create `native/zig/src/app/lifecycle.zig`
- Create `native/zig/src/app/theme.zig`
- Create `native/zig/src/app/layout.zig`
- Create `native/zig/src/app/strings.zig`
- Create `native/zig/src/app/uia_shell.zig`
- Create `native/zig/src/platform/windows/com.zig`
- Create `native/zig/src/platform/windows/shell.zig`
- Create `native/zig/src/platform/windows/presenter.zig`
- Create `native/zig/src/platform/windows/telemetry.zig`
- Create `docs/assets/texflow-app-mark.svg`
- Create `native/zig/assets/texflow_icon.zig`
- Create `tools/zig/icon_gen.zig`
- Create `native/zig/manifests/TExFlow.exe.manifest`
- Create `native/zig/manifests/TExFlow.rc`
- Create `native/zig/tests/role_test.zig`
- Create `native/zig/tests/build_identity_test.zig`
- Create `native/zig/tests/live_render_scheduler_test.zig`
- Create `native/zig/tests/lifecycle_test.zig`
- Create `native/zig/tests/theme_layout_test.zig`
- Create `native/zig/tests/strings_test.zig`
- Create `native/zig/tests/presenter_state_test.zig`
- Create `native/zig/tests/shell_runtime_test.zig`
- Create `native/zig/tests/shell_uia_test.zig`
- Create `native/zig/tests/capture_test.zig`
- Create `native/zig/tests/icon_gen_test.zig`
- Create `native/zig/qa/journey.zig`
- Create `native/zig/qa/capture.zig`
- Create `native/zig/qa/capture_dxgi.zig`
- Create `native/zig/qa/capture_wic.zig`
- Modify `tools/zig/repro_check.zig`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `build.zig`, `.github/workflows/zig.yml`

**Acceptance rows:** A01/A03 first-UI-image subsets, A04
shell-presentation/timer subset, A05 shell subset, A14 event-schema subset,
A17, and A19 scheduler/QoS/app-timer subset. Task 4 closes the Scintilla
child-ticker portions of A04/A19; Task 7 reruns the complete rows.

- [ ] Test UI entry parsing first: the GUI image has no worker selector;
  `--worker=*`, internal probe switches, duplicate/unknown/malformed arguments,
  or an inherited worker bootstrap handle fail before window, database, or
  network initialization. The only T0.2 option is
  `--trace-trial=<32 lowercase hexadecimal digits>`; it changes only local
  ETW/log correlation. Duplicate, uppercase, wrong-width, nonhex,
  separated-value, or trailing forms fail. When absent, generate 16 bytes with the Windows
  CSPRNG. It never enables fixtures, test seams, policy changes, or acceptance
  logic. Tasks 5 and 6 carry those bytes only inside the authenticated worker
  bootstrap and require the first worker event to echo them with
  role/PID/creation-time/build identity. Tasks 5 and 6 independently test their dedicated
  worker entry points and reject cross-role substitution.
- [ ] Test the shared build identity before creating a window. Its exact bytes
  are `SHA-256("texflow:build:v1\0" || source_set_sha256[32] ||
  SHA-256(raw repository bytes of tools/zig/native-deps.json))`. Extend the
  Zig-owned reproducibility controller to enumerate every staged tracked entry
  except `docs/superpowers/evidence/**`, sort by canonical UTF-8 slash path, and
  hash `texflow:source-set:v2\0 || entry_count_u64_le ||
  (path_length_u32_le || path_bytes || mode_ascii[6] ||
  content_length_u64_le || blob_sha256[32])*`. Define `blob_sha256` as SHA-256
  over the exact raw Git blob payload without its object header, so the outer
  identity does not inherit SHA-1 collision strength. Read NUL-delimited index
  records, require
  Git object format `sha1`, stage zero, mode exactly `100644` or `100755`, and
  valid nonempty UTF-8 relative slash paths with no
  absolute/backslash/ADS/device/dot-segment/trailing-dot-or-space/case-insensitive/NFC collision.
  Reject symlink, submodule, sparse-placeholder, unmerged, duplicate, or missing
  records. Export raw verified blob bytes without checkout filters or line-ending
  conversion into a clean temporary source root; revalidate each Git object ID,
  byte length, and raw-content SHA-256; re-hash the lock there; and inject the
  raw values
  through validated build options. Reject absent, malformed, duplicate or
  noncanonical paths, exported-input mismatch, zero/sentinel campaign
  identities, a mutated dependency lock, unequal UI/PDF/science embedded
  identities, or any build/package/QA dependency on the excluded evidence
  namespace. Resolve one canonical absolute Git executable and record its
  version/SHA-256. Scrub system/global config, repository-discovery,
  replace-object, lazy-fetch, alternates, filter/textconv, pager/trace, and ambient Git
  path state. Acquire the resolved repository index's conventional lock; capture
  byte-exact full-OID NUL output from `ls-files --cached --stage --full-name -z`;
  feed only full 40-hex IDs to unfiltered raw `cat-file --batch`; then recapture
  and require an identical listing. In Zig, recompute each SHA-1 Git blob OID
  from its type/decimal-length/NUL/raw-byte stream as a locator check plus the v2
  raw-content length/SHA-256 before releasing the lock. After push, enumerate
  the exact full commit with recursive NUL-delimited `ls-tree --full-tree`, not
  the mutable index or checkout, and require the identical v2 entry stream and
  source-set digest; a mismatch reopens the task.
  Compare every target/CPU/optimization/strip/subsystem/role option against the
  hashed lock. Debug and diagnostic ReleaseFast builds carry an explicit
  unverified identity and are rejected by campaign/evidence parsers; no
  native-CPU or widened-role build can inherit the admitted identity.
  Debug developer builds may carry an explicit unverified identity, but no
  A14/A18 measurement or evidence claim can consume them. Keep role as a
  separate authenticated field, and give `build_identity_test.zig` fixed known
  answers plus entry-count and one-bit
  source-path/mode/content-length/raw-blob/dependency-lock mutations.
- [ ] Before replacing the console entry, move its toolchain-smoke intent into
  `native/zig/tests/t0_1_smoke.zig`, expose stable portable step
  `zig build t0-1-smoke`, and lock the renamed known answer to
  `TExFlow toolchain ok`. This is a Zig test artifact in the cache only: it is
  never installed, packaged, or counted as a product executable. Run it in both
  Windows and Linux lanes. Retire the former `run` step and every direct
  invocation/hash of the installed `oleafly-t0.1` console binary only after the
  replacement gate passes. Rename the internal static library, header, extern
  symbols, and fixture references from `oleafly_abi` to `texflow_abi`; prove the
  ABI layout/status/arithmetic known answers are byte/behavior equivalent and
  that neither the old nor renamed ABI library nor a compatibility export is
  present in the default install/package graph; only the explicit `abi` and
  reproducibility-test paths build it into isolated cache/test output.
  Rename the Zig package manifest to lowercase `.texflow` while preserving the
  already-issued package fingerprint unless the pinned Zig tool proves that the
  name change requires a new one; any fingerprint replacement must be generated
  by the pinned tool, justified in the worklog, and checked against accidental
  dependency-identity fork. The T0.2 package/path inventory rejects an
  `.oleafly` name in the new Zig graph.
  Update `docs/development.md` and the CI workflow/job/artifact labels in the
  same commit: documented commands use `t0-1-smoke`/`t0-2-repro`, no removed
  `run` command or legacy console path remains, and no shell snippet retains a
  hidden hash or known-answer verdict.
- [ ] In Task 3—not earlier—replace the T0.1 console install graph with the
  x64-Windows GUI-subsystem product `TExFlow.exe` and its real Unicode entry
  path. The build graph adds/installs that product only for the supported
  Windows target; a non-Windows target runs portable models, acquisition,
  smoke, ABI, miscompile, and SIMD tests without emitting a lookalike TExFlow
  product. Assert PE subsystem/name/architecture/imports and ensure no
  worker selector or worker-only module is reachable from the UI entry graph.
  Reserve the exact `TExFlow.PdfWorker.exe` and
  `TExFlow.ScienceWorker.exe` product names for Tasks 5 and 6; neither exists as
  a renamed/copy-equivalent UI binary.
  In the same cutover, set the main title and PE `ProductName`/
  `FileDescription`/`InternalName` to exact `TExFlow`, set
  `OriginalFilename=TExFlow.exe`, embed the manifest/version/icon resources,
  and register machine-facing class `texflow.main.v1`. Leave legal company,
  copyright, signer, and MSIX-publisher fields absent rather than invented.
  Encode and parse-back the common T0.2 VERSIONINFO contract: numeric
  `0,0,2,0`, strings `0.0.2.0`/`0.0.2-feasibility`, prerelease/private flags,
  Windows/app type, `040904B0`, and the exact non-release PrivateBuild label.
  Test missing, duplicate, wrong-locale, release-flag, cross-role-name, and
  malformed-string-table mutations against both source RC and final PE.
  Protocol, hash-domain, ETW, and workspace namespaces use lowercase `texflow`.
  A source, PE-resource, and payload scan rejects new `Oleafly` product
  literals except the inventoried frozen legacy-oracle tree, historical
  repository URL, migration fixtures, legally required source-lineage notice
  text, and pre-rename audit-document paths. The
  scan treats that legacy tree as a separate unshipped input and fails if any of
  it enters the new install/package graph or if a modified/new Zig source adds
  an old product literal. It also rejects the legacy green-leaf icon and any UI
  icon resource in either headless worker. Preserve the `test`, `abi`,
  `miscompile-corpus`, and `simd-corpus` steps and their semantic known answers;
  add `t0-1-smoke`, then run `t0-2-repro` so the new Windows UI plus
  `texflow_abi`, and the Linux portable library-only set, replace both former
  shell-authored clean-hash gates without losing coverage.
- [ ] Create the reviewed TExFlow source-to-evidence mark from one canonical
  text/numeric geometry source, with an open paper/bracket form, one continuous
  teal flow stroke, one evidence node, deep-graphite/paper contrast, no text, no
  gradient, and no leaf. A pure-Zig, fail-at-N-tested generator emits the
  deterministic text SVG and supersampled 16/24/32/48/256-pixel alpha ICO into
  the build cache; CI regenerates the SVG byte-for-byte and never commits the
  binary ICO. Test ICO directory/count/range/offset/size, DIB
  dimensions/alpha/mask, non-overlap, exact hash, malformed geometry, overflow, short write, and
  deterministic two-root output in Zig. Pass its canonical quoted cache path to
  the UI RC without mutating the source tree. Compile that tracked RC only via
  the pinned Zig 0.16 `addWin32ResourceFile` path with resource auto-includes
  disabled/ignored; no ambient `rc.exe`, `windres`, SDK `INCLUDE`, or PATH tool
  may participate. The RC is self-contained: it imports no ambient header,
  defines the required numeric resource constants explicitly, and a Zig test
  compares those values with the pinned Windows declarations. A
  pinned-toolchain compile probe locks the exact API/flags, and the PE auditor verifies
  the manifest/version/icon resource tree and
  rejects duplicate/default/stale resources. Then visually verify the real
  embedded resource in Explorer, the
  system title bar, Alt-Tab, and taskbar at required DPI and
  light/dark/high-contrast states. A generic/default or legacy icon fails A05.
- [ ] Test the monotonic app lifecycle and reverse ownership teardown before
  native resources exist: re-entrant close/session-end, failure or pause at each
  barrier, cancellation admission, owner-thread release, typed clean/crash exit,
  and bounded completion may not leak or resurrect work. Tasks 4-6 extend the
  same state machine; they may not introduce private competing shutdown paths.
- [ ] Add pure Zig state-machine tests for visible, resized, minimized, occluded,
  resumed, DPI-changed, device-lost, device-restored, hardware, and WARP paths.
  Assert ownership, lifetime order, dirty-region union, two-buffer history and
  overlap propagation, first-frame/resize/DPI/adapter/device-recovery full
  redraw, invalid-history fallback, no presents while occluded, and no
  timer-driven wake after quiescence.
- [ ] Test a versioned live-render scheduler independently of TeX: Auto delay
  adapts within 220-750 ms from edit cadence and observed job cost, superseded
  work gets no more than 75 ms grace, only the latest completed version may be
  labeled current, manual/off modes are exact, and cancellation storms remain
  bounded. Drive waits from deadlines/events rather than a periodic timer.
- [ ] Initialize COM as STA on the UI thread, opt into per-monitor-v2 DPI before
  creating HWNDs, restrict DLL search to approved application/System32 paths
  before loading optional system components, use the system title bar/caption
  buttons, and implement the confirmed Project/Source/PDF/status layout and
  its Project-flyout/Source-PDF-switcher reductions with shared semantic
  color/spacing/type tokens and explicit
  light/dark/high-contrast/reduced-motion handling.
- [ ] Encode the locked token palette and layout breakpoints as pure Zig data;
  test every foreground/background/boundary/focus pair in linear sRGB, pane
  minima/collapse/focus restoration at boundary widths, 28-32-DIP compact and
  >=44-DIP touch controls, and system-color replacement under high contrast.
  Route every visible string through a versioned English resource table, with
  missing-key/fallback failure and expanded/combining/BiDi pseudo-locale tests;
  no feature module may hardcode shell prose.
- [ ] Use standard native controls when they meet the visual/behavior contract.
  For every custom D2D interactive surface, expose a stable shell UIA fragment
  with name, control type, state, bounds, focus, keyboard shortcut, and required
  Invoke/Toggle/RangeValue patterns. The editor/PDF panes, mode/status region,
  keyboard-resizable splitter, and recovery action must form one deterministic
  root tree; no click target may exist only as painted pixels.
- [ ] Create a D3D11 hardware device and two-buffer
  `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL` baseline with a frame-latency waitable
  object and maximum frame latency 1. Wait before the first and every rendered
  frame. Use `Present1` dirty/scroll metadata only when the tracked back buffer
  is coherent and every reported pixel was updated; otherwise redraw the full
  client and pass zero dirty rectangles. Rebind the back buffer after each
  successful present, and release all buffer references before resize/rebuild.
  Never target the swap-chain HWND with GDI or another presenter. Use
  Direct2D/DirectWrite on the same device path and wait on frame/input/worker
  handles rather than polling.
- [ ] Implement a deterministic, build-time/test-selectable two-buffer
  `DXGI_SWAP_EFFECT_FLIP_DISCARD` challenger that always redraws the complete
  client and passes no dirty/scroll metadata. Compare it with the baseline on
  identical state traces across hardware, WARP, RDP, current-host, and physical
  low-tier lanes for correctness, latency, CPU/GPU work, memory bandwidth,
  energy, and capture behavior. Do not silently choose per machine; changing the
  admitted default requires a recorded ADR and a full acceptance rerun.
- [ ] Implement deterministic WARP fallback, resize without use-after-free,
  display/adapter/DPI changes, occlusion suspension, and complete device-loss
  rebuild. Preserve the last valid visible frame until replacement succeeds.
- [ ] Emit stable ETW events with trial ID, PID/TID, QPC, adapter LUID, render
  path, dimensions, dirty pixels, and version; never emit source text, project
  paths, secrets, or paper contents.
- [ ] Keep the first interactive frame limited to shell/editor/settings state;
  do not preload PDFium, SQLite, PDF/science workers, or optional packs. Apply
  foreground QoS only around latency-sensitive input/presentation and return to
  normal promptly; background work uses EcoQoS and low-memory priority when the
  OS supports them, with capability-tested fallback and no persistent 1-ms timer
  resolution.
- [ ] Runtime-test actual swap-chain descriptors and waitable handle, force WARP,
  trigger resize/minimize/occlusion/theme/DPI/device rebuild paths, and prove the
  TExFlow message loop becomes wait-only with no polling/render timer. A visible,
  focused system caret is not present until Task 4 and therefore cannot be
  counted as Task 3 evidence. Task 3 proves only its owned shell/app timer
  subset; Task 4 must rerun occlusion with the real child HWND and prove the full
  Scintilla ticker contract before A04/A19 can close.
- [ ] Inject Zig allocator failure through
  shell model/layout/string/scheduler/capture state and force native `E_OUTOFMEMORY`/device-allocation failures.
  Preserve editable source and the last good frame where possible, release all
  partial COM/DXGI objects in reverse ownership order, surface one bounded typed
  recovery action, and prove no busy retry or crash/recreate storm.
- [ ] Implement the SDR foundation of the authoritative visible-capture contract
  before judging Task 3 visuals: the independent Zig QA process uses
  `IDXGIOutput5::DuplicateOutput1`, correlates a post-state-marker frame by QPC,
  records adapter/output/mode/rotation/DPI and DWM physical bounds, preserves the
  full-output raw digest, crops only by recorded physical coordinates, and
  round-trips BGRA through WIC PNG. Known-pixel, stride, rotation, stale-frame,
  crop, access-loss, frame-release, and encoded-digest tests must pass. Task 7
  extends this foundation with the full multi-output/HDR/calibration campaign;
  no browser, `PrintWindow`, screen-DC, or app framebuffer can close Task 3 A05.
- [ ] Capture the representative shell at 100/125/150/200% DPI, narrow/wide,
  light/dark/high contrast, loading/error/worker-crash/device-loss/recovery, and
  keyboard-focus states. Check clipping, contrast, visible focus, baseline grid,
  standard Snap behavior, caption accessibility, and stable resize.
- [ ] From a separate process, enumerate the full shell UIA tree, tab/shift-tab
  order, arrow/splitter operation, accelerators, disabled/busy/error state,
  focus restoration after worker/device failure, and pointer hit targets at every
  DPI. Assert 4.5:1/3:1 contrast thresholds, >=24x24 effective targets, non-color
  status cues, and no inaccessible custom-painted action.
- [ ] Run the shared final-pass protocol, then commit and push as
  `feat(native): add waitable scientific workspace shell`.

**Kill switch:** A composition swap chain is only a post-profile reversible
spike on supported Windows 11/WDDM systems; it cannot replace the portable flip
model without beating it across latency, memory, occlusion, WARP/RDP, capture,
and low-tier gates. `FLIP_DISCARD` cannot receive partial-present metadata, and
`FLIP_SEQUENTIAL` cannot present from unproved buffer history. If a custom title
bar or acrylic is needed to make the design work, the design has failed this
slice.

## Task 4 (T0.2d): Integrate Scintilla, Unicode mapping, UIA, and IME

**Files:**

- Create `native/zig/src/editor/scintilla.zig`
- Create `native/zig/src/editor/lexer.zig`
- Create `native/zig/src/editor/text_units.zig`
- Create `native/zig/src/editor/uia/thread.zig`
- Create `native/zig/src/editor/uia/snapshot.zig`
- Create `native/zig/src/editor/uia/provider.zig`
- Create `native/zig/src/editor/uia/range.zig`
- Create `native/zig/fixtures/t0_2/large_book.zig`
- Create `native/zig/tests/editor_model_test.zig`
- Create `native/zig/tests/lexer_test.zig`
- Create `native/zig/tests/text_units_test.zig`
- Create `native/zig/tests/uia_provider_test.zig`
- Create `native/zig/qa/uia_client.zig`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `native/zig/src/app/lifecycle.zig`, `native/zig/src/platform/windows/shell.zig`, `build.zig`, `.github/workflows/zig.yml`

**Acceptance rows:** A03, A04 editor-presentation/ticker subset, A06, A07, A08,
A14, A16, A17, and A19 editor-ticker subset. Task 7 reruns the integrated rows.

- [ ] Generate a deterministic, structurally well-formed and semantically
  varied LaTeX book fixture of
  at least 10 MiB in Zig: chapters/sections, commands, comments, math, tables,
  citations, labels/references, Vietnamese in precomposed and canonically
  decomposed forms, CJK, Arabic/Hebrew BiDi, emoji, long lines, mixed line endings, and
  repeated but uniquely indexed paragraphs. Record byte/line/section hashes.
  T0.2 validates the editor/lexer structure only and must not label the fixture
  compiler-proved; pinned TeX compilation begins in T1.2.
- [ ] Import only the deterministic cache-generated Unicode-17 table module and
  implement UTF validation/mapping, UAX #15 rev. 57 NFD/full-default-case-fold,
  and untailored UAX #29 rev. 47 extended-grapheme/default-word segmentation in
  Zig. Re-run every locked `NormalizationTest`, `GraphemeBreakTest`, and
  `WordBreakTest` vector against the runtime API, plus one-byte table corruption,
  unknown property, unassigned scalar, streaming-chunk, random-access, and
  forward/reverse equivalence tests. Source text and anchor bytes are never
  normalized; normalization exists only for declared derived comparison/search
  keys. Neither Windows NLS, ICU, `unicode61`, nor a network/runtime data file is
  the production identity.
- [ ] Test exact UTF-8 byte offsets against UIA UTF-16 units for ASCII, CRLF/LF,
  Vietnamese NFC/NFD and multi-mark sequences without silent normalization,
  surrogate pairs, combining marks, emoji ZWJ sequences, Arabic/Hebrew BiDi,
  tabs, word punctuation, and empty/trailing lines. Freeze
  `TextUnit_Character` as UAX-29 extended grapheme clusters and
  count only clusters not made solely of C0/C1 or directional-format controls;
  excluded runs add no movement count and attach left, or right at document
  start, while an all-control document substitutes Document. Freeze
  `TextUnit_Word` as lexical UAX-29 segments plus their trailing break segments,
  with a leading break run attached to the first lexical segment and a no-word
  document substituting Document. `TextUnit_Format` is a maximal equal-exposed-attribute run;
  `TextUnit_Line` follows the actual wrapped Scintilla viewport;
  `TextUnit_Paragraph` follows source newline structure; unsupported
  `TextUnit_Page` substitutes `TextUnit_Document`. Test every unit's degenerate,
  control/CRLF, boundary, end-of-document, forward/reverse, expand/move/endpoint
  behavior plus endpoint ordering and edit transforms for UIA ranges held before
  insert/delete/replace/undo. No locale-specific dictionary quality is claimed
  for Thai/Lao/Khmer/Myanmar/CJK; an unimplemented tailoring cannot be advertised.
- [ ] Implement a sequence-stamped, incrementally updated line/chunk index so a
  normal edit does not scan or copy the 10 MiB document. Freeze complexity and
  enforce the 24-MiB TExFlow-owned metadata cap plus the 750-ms open, 140-MiB
  private-working-set, 170-MiB private-commit, two-second full-convergence, and
  four-millisecond owner-thread styling-slice gates for local edits, offset lookup, range transform, and
  bounded resynchronization; benchmark adversarial edits at start/middle/end,
  line-ending changes, long lines, and large paste/delete. Idle/pre-QA hash
  audits compare the index/snapshot with exact Scintilla bytes and fail closed on
  a missing sequence or divergence.
- [ ] Register the static Scintilla class, attach one document as the only
  mutable UTF-8 endpoint, obtain the status-returning direct function, and wrap
  every call with the HWND owner thread ID. Other threads post typed commands;
  raw Scintilla pointers never cross threads or processes. Check the status of
  every direct call and instrument a test assertion that no high-frequency path
  falls back to synchronous `SendMessage` after direct-interface acquisition.
- [ ] Put one non-lossy UTF-8 gate in front of every initial, paste, drop, and
  programmatic mutation. Accept only shortest-form well-formed scalar sequences;
  reject overlong encodings, UTF-8 encodings of surrogate code points, isolated
  continuation bytes, truncation at every boundary, embedded NUL where the
  target API cannot carry it, and checked-length overflow before Scintilla sees
  bytes. A rejected input retains its original bytes/hash outside the editor and
  produces a typed `invalid-encoding/non-text` state; it is never normalized,
  replaced with U+FFFD, partially inserted, or marked repaired. Windows UTF-16
  input must reject unpaired surrogates before exact UTF-8 conversion. The
  spec's explicit lossless legacy-decoder choice and BOM/newline save policy are
  T1.1 work, not a T0.2 lossy shortcut.
- [ ] Select Scintilla container styling with `SCI_SETILEXER(NULL)`. Implement
  LaTeX/BibTeX lexical states in Zig and service `SCN_STYLENEEDED` from the owner
  UI thread using `SCI_GETENDSTYLED`, `SCI_STARTSTYLING`, and bounded
  `SCI_SETSTYLINGEX` batches. Store revision-stamped line-state checkpoints;
  invalidate forward after edits until state convergence; cap bytes/time per
  dispatch; and schedule event-driven continuations without a polling/idle
  timer. An unfinished region remains honest default styling and never blocks
  input or changes source semantics.
- [ ] Differential-test full versus incremental Zig styling after seeded random
  edits and compare a reviewed common-behavior subset with the separate pinned
  Lexilla fixture oracle. Add exact expected cases for commands, comments,
  escaped `%`, math delimiters/environments, verbatim/comment environments,
  braces/optional arguments, citations/labels/references, BibTeX
  entries/fields/strings/comments, malformed input, jump/scroll/selection,
  insert/delete/paste/undo/redo, the exact no-repair invalid-UTF-8 rejection boundary, very long lines, and the
  deterministic 10,000-edit load. Known comparator bugs or intentional visual
  improvements require a fixture-level rationale; they do not become silent
  mismatches.
  Use Scintilla's DirectWrite technology with ClearType/grayscale behavior chosen
  from actual display/high-contrast settings; compare retained versus ordinary
  DirectWrite plus `SC_TECHNOLOGY_DIRECTWRITEDC` under the 10-MiB memory/latency
  gate and admit retained layout only if it improves tails without breaking the
  footprint. On every frozen adapter/driver and for the DirectWriteDC fallback,
  run at least 100 same-size
  create/load/destroy/recreate cycles for each viable technology, measure
  app-attributed committed/resident GPU bytes and D2D live-object diagnostics,
  then repeat the cycle to distinguish a bounded reusable pool from monotonic
  growth. Any unexplained growth past a preregistered plateau rejects that
  technology; Task 7 repeats the selected mode across the physical matrix. Lock font fallback,
  ligature/caret behavior, zoom, tab width, line height, and DPI transitions with
  Latin/Vietnamese-NFC-NFD/CJK/Arabic/combining/emoji screenshot,
  byte-preservation, caret/range/undo/search, and position oracles.
  Treat Scintilla/DirectWrite as the visual UAX-9 shaping path only: logical
  ranges remain in source order, and both supported OS lanes cross-check
  visual-caret/selection/rectangle geometry against the pinned logical
  grapheme boundaries without allowing an OS result to rewrite source or
  generated Unicode tables.
- [ ] Treat upstream Scintilla tickers as part of the energy contract. Record and
  restore the visible system caret period/dwell/idle-styling state; on minimized
  or fully occluded transition set the caret period to zero, mouse dwell to
  `SC_TIME_FOREVER`, idle styling to `SC_IDLESTYLING_NONE`, and cancel or
  boundedly drain scroll/widen/queued-idle work. Resume without losing focus,
  selection, IME composition state, or a pending latest edit. Source-level tests
  lock the 5.6.6 ticker inventory, and ETW/runtime tests prove that no caret,
  dwell, idle, scroll, or widen timer wakes after the declared occluded
  quiescence point. A visible focused caret blink remains allowed and separately
  accounted.
- [ ] Expose the editor as a UIA Document and implement server-side
  `IRawElementProviderSimple`, fragment/root support, `IScrollProvider`,
  `ITextProvider2`, `ITextEditProvider`, and compatible `ITextRangeProvider`
  behavior. Do not expose `IValueProvider` for this multiline document; assert
  that querying ValuePattern reports unavailable. TextRange `GetText` honors its
  requested limit, and whole-document retrieval is stress-tested without adding
  a second mutation endpoint or monopolizing the UI STA.
  Create the editor provider and all of its range objects on one dedicated COM
  STA with its own message pump. The UI thread publishes structurally shared,
  immutable, revision-stamped UTF-8/UTF-16-index and visible-geometry snapshots;
  the provider STA owns those references and never reads Scintilla, a raw HWND
  model pointer, or mutable UI storage. Include retained snapshot bytes and COM
  objects in the 24-MiB metadata and aggregate-memory gates.
  Return the provider from `UiaReturnRawElementProvider` only for
  `UiaRootObjectId` through a TExFlow-owned, safely removed Scintilla
  child-window subclass for `WM_GETOBJECT`; pass unmodified `wParam`/`lParam` and
  every other object ID to the upstream chain so its MSAA provider survives.
  Never replace or patch the upstream window procedure. Advertise
  `ProviderOptions_ServerSideProvider | ProviderOptions_UseComThreading` so COM
  marshals callbacks to the dedicated provider STA. Register the owning-STA
  interface in the system Global Interface Table and let the UI STA pass only
  its apartment-correct proxy to `UiaReturnRawElementProvider`; never share a raw
  COM pointer across apartments. Revoke before provider teardown.
- [ ] Route UIA operations that mutate UI state (`SetFocus`, Select/add/remove,
  caret movement, and ScrollIntoView) through a bounded typed command to the UI
  owner with request ID, provider snapshot generation/revision, arguments, and
  deadline. The UI rejects stale revisions before touching Scintilla and returns
  one typed result; timeout/cancel/re-entrant close yields no partial action.
  The provider STA waits with COM/window-call dispatch enabled and an explicit
  reentrancy guard, never `SendMessage` or a raw callback into the UI. Read-only
  text/range/attribute queries run only over one retained immutable snapshot, so
  a concurrent edit publishes a new revision without mutating the query's view.
  Assert all actual Scintilla calls remain on the UI owner thread.
- [ ] Implement selection, caret/active endpoint, visible ranges, range from
  point/child/annotation, attributes, bounding rectangles, GetText limits,
  scrolling, comparison/movement, cloning, and subscribed
  text/text-edit/selection/caret/structure events. Define empty and offscreen rectangle behavior
  explicitly; movement is in logical document order and rectangles are physical
  screen coordinates with per-monitor-DPI/scroll/wrap/BiDi tests. Coalesce event
  storms without losing the latest sequence or composition boundary and honor
  `IRawElementProviderAdviseEvents` subscriptions.
- [ ] Bound live UIA text state independently of document size. Permit at most
  1,024 live editor `ITextRangeProvider` objects across all clients and return a
  precise allocation failure from constructors/Clone/FindText beyond the cap;
  release decrements exactly once under foreign-apartment and shutdown races.
  Each range stores its creation generation/revision and two typed anchors.
  Retain at most 4,096 edit records or four MiB, whichever is reached first.
  Within that window transform anchors deterministically: positions strictly
  before an edit stay fixed, positions strictly after it move by the checked
  UTF-8/UTF-16 delta, a nondegenerate start has before affinity, its end has
  after affinity, a degenerate caret keeps both endpoints together with after
  affinity, and deleted/replaced interior anchors collapse to the corresponding
  replacement boundary. If the generation changed, history was evicted, a
  transform is inconsistent, or the owner-thread call cannot finish inside its
  bounded slice, invalidate that range with `UIA_E_ELEMENTNOTAVAILABLE`; never
  read stale offsets. Raise the required text-change event so clients reacquire.
  Fuzz edit/clone/release/event races and prove the cap, journal, latency, and
  24-MiB metadata budgets.
- [ ] Launch `uia_client.zig` as a separate process with one non-UI COM MTA
  thread owning discovery, calls, event subscription, and matching removal. It
  discovers the editor by
  runtime ID, exercises each required pattern and range operation while the UI
  is busy, verifies event order and thread marshaling, and cross-checks returned
  text/offsets/rectangles against exact fixture truth. Direct in-process calls
  cannot satisfy A07.
- [ ] Run the external UIA client concurrently with paced typing and worst-case
  `GetText`, range enumeration, bounding rectangles, and event subscription on
  the 10 MiB fixture. Input latency/deadlock budgets still apply; a technically
  conformant provider that blocks the UI STA, exposes a mixed-revision result,
  or starves its own provider STA fails the editor gate.
- [ ] Stress provider lifetime across window destroy/recreate, worker activity,
  outstanding/range-cap references, journal eviction, client disconnect, UI shutdown, and COM release
  from a foreign apartment. On destroy, forward required native cleanup, call
  `UiaReturnRawElementProvider(hwnd, 0, 0, null)`, disconnect providers, drain or
  invalidate subscribed callbacks, remove the subclass, and release COM objects
  before apartment teardown. After shutdown, calls return the specified UIA
  element-not-available error without touching a destroyed HWND/document.
- [ ] Detect—never install or update—the operator-provisioned exact production
  Accessibility Insights build by version, MSI receipt, executable hash, and
  Microsoft signature. With network/update/telemetry egress blocked in the
  disposable QA account, run Entire-app automated checks and the FastPass
  tab-stops journey on stable shell/editor, error, high-contrast, and large-document
  states; save the `.a11ytest` artifacts and map every failure to the independent
  UIA/Narrator oracle. A missing/mismatched tool is explicitly unverified, and
  its screenshot or green scan cannot substitute for the behavioral clients.
- [ ] Drive text and navigation through real `SendInput` and clipboard paths in
  a disposable QA session/account; otherwise refuse clipboard/IME mutation until
  explicit consent. Prove capture/restoration where restoration is possible and
  never destroy delayed-render or unsupported user clipboard formats.
  Detect installed Windows TSF/IME profiles and run composition, commit, cancel,
  candidate movement, caret placement, and reconversion with a real non-Latin
  IME. Supplemental synthetic `WM_IME_*` tests do not count as A08. If no
  suitable installed IME exists, record A08 unverified and block admission.
- [ ] Measure input-to-mutation and displayed latency separately for the
  Scintilla child HWND. Fail on missing correlation, lost edits, queue growth,
  wrong final hash, or UIA deadlock.
- [ ] Run the shared final-pass protocol, then commit and push as
  `feat(editor): prove native text UIA and IME path`.

**Kill switch:** If a conformant STA-marshaled provider cannot expose the large
  document without blocking input or if real IME correctness remains dependent on
synthetic messages, Scintilla does not pass merely because Latin typing is fast;
execute the approved RichEdit challenger as a separate reversible plan.

## Task 5 (T0.2e): Prove authenticated IPC and isolated PDF rendering

**Prerequisite:** T0.2b has sealed the independently source-reconstructed PDFium
artifact after source/static-ABI closure, defined the public ABI table, and
proved that no PDFium DLL executed in Task 2. Task 5—not Task 2—owns runtime
known-answer comparison, community-DLL rejection at load time, the worker-only
dynamic-load boundary, and the single-engine-thread runtime contract under the
all-Zig ownership rule. A failed or unverified prerequisite blocks this task.

**Files:**

- Create `native/zig/src/ipc/frame.zig`
- Create `native/zig/src/ipc/pipe.zig`
- Create `native/zig/src/ipc/peer.zig`
- Create `native/zig/src/platform/windows/process.zig`
- Create `native/zig/src/pdf_main.zig`
- Create `native/zig/src/pdf/protocol.zig`
- Create `native/zig/src/pdf/client.zig`
- Create `native/zig/src/pdf/worker.zig`
- Create `native/zig/src/pdf/uia.zig`
- Modify `native/zig/src/pdf/pdfium.zig` to add the worker-only loader and lifecycle
- Create `native/zig/src/pdf/tile_handoff.zig`
- Create `native/zig/src/pdf/tile_cache.zig`
- Create `native/zig/fixtures/t0_2/pdf_corpus.zig`
- Create `native/zig/tests/ipc_property_test.zig`
- Create `native/zig/tests/lpac_boundary_test.zig`
- Create `native/zig/tests/pdf_geometry_test.zig`
- Create `native/zig/tests/pdf_isolation_test.zig`
- Create `native/zig/tests/pdf_resilience_test.zig`
- Create `native/zig/tests/pdf_tile_handoff_test.zig`
- Create `native/zig/tests/pdf_uia_test.zig`
- Create `native/zig/manifests/TExFlow.PdfWorker.exe.manifest`
- Create `native/zig/manifests/TExFlow.PdfWorker.rc`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `native/zig/src/main.zig`, `native/zig/src/app/lifecycle.zig`, `native/zig/src/app/strings.zig`, `native/zig/src/app/uia_shell.zig`, `native/zig/src/platform/windows/shell.zig`, `native/zig/src/platform/windows/presenter.zig`, `native/zig/qa/uia_client.zig`, `native/zig/qa/journey.zig`, `build.zig`, `.github/workflows/zig.yml`

**Acceptance rows:** A01, A03, A09, A10, A11, A14, A16, A17, A19.

- [ ] Specify PDF message types, state transitions, error taxonomy, exact caps,
  cancellation/version rules, and ownership before implementation. Add
  compile-time header layout assertions and encode/decode known answers.
- [ ] Property-test arbitrary fragmented/coalesced reads, every truncation
  boundary, maximum/minimum sizes, length/MAC/integer corruption, unknown
  flags/types/versions, duplicate/replayed/reordered channel sequences and
  replies, nonce mismatch, zero/wrong project, stale/future revision,
  expired/overflow/far-future deadline, queue saturation, cancellation races, peer exit, and
  timeout. Add live hostile-peer cases for pre-created pipe-name squatting,
  namespace enumeration/race, a same-logon non-AppContainer client that may open
  the transport through the required normal-side ACE but must fail retained-child
  identity/token/secret authentication before application data, wrong-role SID,
  either missing mirrored current-logon/package-SID ACE, a broad group SID,
  excess/unequal rights, generic-write/append/`FILE_CREATE_PIPE_INSTANCE`
  leakage, second-instance creation,
  remote-client rejection, wrong server/client PID,
  retained-handle creation-time mismatch (PID-reuse simulation), pipe-reported
  server PID versus inherited reduced-parent-handle mismatch, excessive
  parent-handle rights, missing/forged/late-closed parent handle,
  parent path/build-identity mismatch, any attempted worker open/hash of the UI image, bootstrap secret
  replay/second read, and every unexpected inheritable handle. Feed a
  deterministic mutation corpus to the parser in Debug and ReleaseSafe.
- [ ] Treat the authenticated PDF worker as an untrusted producer. Before any
  allocation or state mutation, have the UI-side decoder enforce the frame and
  per-type byte/count caps, then validate artifact hash,
  document/generation/page identity, UTF-8, monotonic in-range text offsets, finite checked
  transforms/rectangles, dimensions/stride, cross-field counts, and exact
  link/action/annotation allowlists. Reconstruct only owned immutable Zig data;
  never retain worker pointers, addresses, or mapped views. Fuzz valid-MAC
  hostile replies covering overflow, aliasing, overlap, NaN/infinity, negative
  dimensions, invalid UTF-8, offset disorder, count/length disagreement,
  stale/future generations, unknown enums, and cap boundaries. Any violation
  retains the last good artifact and quarantines/restarts the worker.
- [ ] Implement overlapped named-pipe I/O with bounded inbound/outbound byte and
  request counts. Implement the specified challenge transcript, HKDF-SHA-256,
  directional full HMAC-SHA-256, constant-time comparison, and non-wrapping
  sequence state; authenticate every post-handshake frame. Create the server
  first with `nMaxInstances=1`, `FILE_FLAG_FIRST_PIPE_INSTANCE`,
  `PIPE_REJECT_REMOTE_CLIENTS`, and the exact-SID/minimal-right protected DACL,
  then launch the child. Verify its canonical owner/DACL and prove that the
  already-held server handle—not a user reopen ACE—is how the UI retains access;
  verify
  server/client PID and the asymmetric peer contract: the UI proves the locked
  worker path/volume/file/SHA-256/token/module identity, while the worker proves
  inherited parent handle/PID/creation time/canonical process path/shared build
  identity without opening `TExFlow.exe`; also prove role, protocol, exact
  two-handle bootstrap list, timely worker-side closure of the
  reduced parent-query handle, exact 16-byte trial nonce propagation, and a
  first worker ETW/log event that echoes the nonce with PDF role, PID, creation
  time, and build identity. Reject a missing, mismatched, duplicated, or later
  nonce before application input; it is correlation only and never changes
  worker behavior or authority. Prove each later brokered-section state before
  accepting PDF work or committing a tile-slot generation.
- [ ] Launch the dedicated headless `TExFlow.PdfWorker.exe` using an
  imperatively created LPAC. Its PE/import graph must be distinct from
  `TExFlow.exe`, contain no UI/Scintilla/graphics imports, embed exact
  `ProductName=TExFlow`, `FileDescription=TExFlow PDF Worker`,
  `InternalName=TExFlow.PdfWorker`, and
  `OriginalFilename=TExFlow.PdfWorker.exe` resources plus the frozen common
  feasibility-version tuple, and reject every
  cross-role or unauthenticated internal-probe selector before role-specific
  initialization. Set `PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES` to the deterministic
  role package SID derived from exact LPAC moniker `texflow.pdfworker.v1` with
  `CapabilityCount=0`/`Capabilities=null`, set
  `PROC_THREAD_ATTRIBUTE_ALL_APPLICATION_PACKAGES_POLICY` to
  `PROCESS_CREATION_ALL_APPLICATION_PACKAGES_OPT_OUT`, grant no
  `registryRead`, `lpacCom`, network, or other named capability, and use an
  mirrored exact-current-logon-SID and exact-role-package-SID least-right client
  pipe ACEs, a kill-on-close Job Object,
  active-process/memory limits, child-process prohibition, the exact mandatory
  process-mitigation profile in the architecture contract, non-null canonical
  `lpApplicationName`, and the shared
  tested argv serializer. Fully configure the Job, then create the worker with
  `CREATE_SUSPENDED`, `PROC_THREAD_ATTRIBUTE_CHILD_PROCESS_POLICY` set to
  `PROCESS_CREATION_CHILD_PROCESS_RESTRICTED`, the AAP opt-out above, and no
  breakaway flag. Assign and query-verify the process in the intended nested-job
  chain; while it is still suspended, open its token read-only and require
  `TokenIsAppContainer=1`, `TokenIsLessPrivilegedAppContainer=1`, the exact
  `TokenAppContainerSid`, an empty `TokenCapabilities` set, Low integrity, and
  the requested child restriction. Only then call the sole `ResumeThread`; any
  earlier-step failure terminates it without executing worker code.
  Independently launch the same PDF worker in its authenticated no-engine
  `--sandbox-probe` internal mode as a regular-AppContainer control with the
  same empty capability list. Under one fresh parent granting
  every probe identity the same traverse/read-attribute access but no list or
  write, create three leaf canary objects that also grant the current logon SID
  but whose restricting-side grant is,
  respectively, `ALL APPLICATION PACKAGES`, `ALL RESTRICTED APPLICATION
  PACKAGES`, or one exact role package SID. The regular control must read the
  AAP canary; LPAC must be denied AAP and must read ARAP; record rather than
  assume the regular control's ARAP result. The intended LPAC must read its exact
  role canary and the wrong-role LPAC must be denied. The control receives no
  project, PDF, scientific, credential, or runtime-library bytes and is
  destroyed after the oracle; it is never a fallback. Use a deterministic role
  moniker/SID, but delete and recreate its profile storage before each
  generation and delete it after every clean/crash/timeout exit. Close all
  handles first; verify the recreated tree is empty, reparse-free, canonically
  ACLed, and used only as untrusted scratch. A partial or failed
  `DeleteAppContainerProfile` leaves the profile quarantined and blocks
  relaunch; planted DLL/config/input files must never be read or executed. Test
  absent/mismatched AAP policy, forged token expectations, unexpected
  capability/group SID, canary false-positive/false-negative, crash residue,
  open-handle deletion failure, reparse/ACL substitution, disk fill, bounded
  orphan discovery, parent-job conflict, assignment/resume failure, pre-resume
  side-effect absence, breakaway attempts, and eventual cleanup.
  Use the controller's retained `CreateProcessW` child-process handle with
  `PROCESS_QUERY_INFORMATION` to query every frozen mitigation policy while the
  thread remains suspended; do not confuse it with the inherited reduced parent
  handle used by the worker during peer authentication. Fail a supported
  missing or altered baseline field. Record a genuinely
  unavailable optional capability without pretending it applied. After loader
  initialization and before input admission, compare independent worker and
  controller module receipts, then repeat after PDFium load. Negative tests
  independently remove or relax every
  mandatory flag, opt into ATL thunk/dynamic-code downgrade, inject a UI or
  cross-role DLL, falsify Guard CF/CET metadata, and exercise supported versus
  unsupported CET. Each mutation must fail its specific oracle. Launch only from a
  sealed staged runtime whose
  ancestors inside the TExFlow-owned root grant each role only the tested
  `FILE_TRAVERSE|FILE_READ_ATTRIBUTES|SYNCHRONIZE` subset actually required,
  never list/create/delete/write. Record whether the token has enabled
  `SeChangeNotifyPrivilege`; do not rely on it to hide a missing ancestor ACE.
  Set and query-verify `SE_DACL_PROTECTED` on the controlled root and every
  descendant; never rewrite an ancestor outside the owned root, and record the
  actual token/external-prefix traverse result. Reject inherited/default/null DACLs and `Everyone`, `Users`, AAP,
  ARAP, generic-mask, or unenumerated ACEs. Grant each operation's exact rights
  on both the current-logon/owner side of the access check and the intended role
  package-SID side. Leaf-file ACLs grant the PDF SID only the required
  read/execute rights on `TExFlow.PdfWorker.exe`, grant the science SID only its
  separate worker image, deny both roles `TExFlow.exe`, Scintilla/UI/graphics,
  and the other role's image, and grant only the PDF SID read/map/load rights on
  the admitted source-reconstructed PDFium DLL. The science SID is denied DLL
  access, and neither role receives directory write/delete or anything on the
  repo/project.
  Assert the canonical ACL and live open/map/load denials from both roles.
  Explicitly reject the community-reference digest. Disable current-directory
  DLL search before the PDF worker loads any role dependency, lock each file against replacement
  while hashing/loading, load by canonical absolute path, and recheck the loaded
  module's path, file identity, and digest.
- [ ] Before any PDFium load, exercise the real PDF-worker bootstrap in a
  no-engine phase with a harmless Zig responder. Prove its LPAC token and AAP
  opt-out/canary, Job limits, peer identity, handle inheritance,
  sealed-runtime ACL, module search policy, and all targeted negative
  repo/private-registry/COM/network/write/spawn probes, then terminate
  it. Only a fresh worker launched after that test baseline may load the admitted
  source-reconstructed DLL. No task or QA mode may execute the community DLL.
- [ ] On both sealed physical OS lanes, capture loss-detecting kernel file,
  registry, image-load, process, and network evidence for the no-engine LPAC and
  the complete PDF/font corpus. Generate a canonical residual-access manifest
  for every successful operation outside the role profile and explicit product
  roots: requested/result operation, canonical path/object identity, frozen
  security descriptor and matching AAP/ARAP/role trustee ACEs, loaded-image
  signer/hash, and writable/executable/user-controlled status. Hash-bind the
  trace and manifest. Only controlled canaries attribute causality to one SID;
  the workload inventory explicitly is not a global Windows ACL map or runtime
  allowlist. Expected ARAP system reads are disclosed, not misclassified as
  brokered; any trace loss, unreadable required descriptor, unexplained
  success, project/private-user access, unexpected write, or user-writable
  executable/configuration load fails A10.
  Seed matching private-path and ARAP-readable decoys to prove the classifier
  detects both denied sensitive access and the residual surface.
- [ ] On the owning engine thread, run
  initialize/open/render/text/search/link/annotation/close/destroy known answers against independently generated
  semantic and pixel oracles in Debug, ReleaseSafe, and diagnostic ReleaseFast.
  Require exact pixels for simple vector and embedded-font fixtures on the same
  machine; for system-font-dependent fixtures, freeze font-file identities and
  a predeclared per-channel/geometry tolerance rather than choosing it after
  output is observed. Corrupt/truncated/password failures must return documented
  null/bool results and an immediately captured `FPDF_GetLastError`; the
  XFA-disabled compatibility stub must return false. Instrument the table so any
  call from a non-owner thread fails the probe.
- [ ] Use the pipe only for control. For each approved PDF <=128 MiB, create an
  exact-size anonymous pagefile section, hash its full contents, replace the UI
  handle with read-only access, close every writable view/write-capable handle,
  broker only section-map-read into the worker, and require the worker to rehash
  before parsing. Allow at most two outstanding input
  generations with <=128 MiB combined live bytes. For tiles, lazily create at
  most four live fresh unnamed one-MiB 512-pixel opaque BGRx sections with
  worker-map-write/UI-map-read rights. Never name, pool, or reuse a tile section
  object. Bind every handle value to its authenticated
  type/access/size/stride/slot/generation/SHA-256/state/close-ack record and enforce
  `created -> writing -> ready -> consuming -> retired` only. After `ready`,
  copy exactly 1 MiB into one of at most two UI-private staging buffers,
  recompute and compare the digest, close/unmap and retire the transfer object,
  and upload only from the private copy. Treat worker close acknowledgement as
  protocol evidence rather than write-authority revocation;
  reject duplicate, stale, aliased, wrong-access, oversized, non-section,
  unannounced, or numeric-handle-guess cases before mapping or GPU upload. Stress
  a late writer, a retained and self-duplicated worker handle/view, worker death
  at every state transition, digest mismatch, cancellation/reuse attempts, and
  timeout/reopen. The retired object must never reach another generation; any
  unexplained retained handle quarantines and replaces that worker generation.
  Compare a bounded overlapped-pipe copy into the same staging pool on the
  canonical tile trace; it is the only admitted fallback if one-shot section
  overhead misses the gate. Run negative probes from the worker for repo/project read, runtime
  write/delete, network connect, arbitrary write, undeclared handle use,
  DLL/path escape, `ALL APPLICATION PACKAGES`-only canary access, private
  registry read, undeclared COM activation, and child spawn. Every negative
  probe must be denied for the expected security reason; the ARAP canary is the
  explicit positive residual control and can never be counted as a denial.
  A regular-AppContainer or restricted-token fallback is isolation failure and
  blocks A10. Non-embedded-font and required data access must succeed only
  through the sealed hash-bound PDF-role resource closure; an LPAC compatibility
  failure blocks the PDF architecture rather than expanding capabilities after
  observing the corpus.
- [ ] Create, use, and destroy the PDFium library and every
  document/page/text/search/bitmap handle on one instrumented engine thread. No other worker thread
  and no UI thread may enter the function table. Feed that thread through a
  bounded priority queue: visible-page work preempts prefetch, and progressive
  rendering yields through `IFSDK_PAUSE` so stale generations cancel between
  continuations. Bound non-progressive open/parse/text calls with an external UI
  watchdog that terminates and replaces a wedged worker, preserves the previous
  valid artifact, and applies restart backoff; process death is containment, not
  an API error result.
- [ ] Make the UI own a lazy resident GPU LRU of verified private-copy
  512-pixel opaque BGRx tiles. Select its measured maximum from 32/48/64 MiB,
  never exceed 64 MiB, and key it by
  document/version/page/transform/tile/color mode. Use
  `FPDFBitmap_CreateEx(..., FPDFBitmap_BGRx, ...)`, initialize the full
  slot to paper white, assert returned format/stride/dimensions, and upload as
  `DXGI_FORMAT_B8G8R8A8_UNORM` with alpha ignored, from the verified UI-private
  copy only. Clip every tile to the PDF content viewport and paint UI-owned
  chrome afterward. Golden red/blue/transparency
  fixtures must detect channel swaps, uninitialized edge pixels, inverted rows,
  and accidental straight/premultiplied-alpha treatment. Prioritize visible
  work, cancel stale versions, cap decode dimensions and execution time, and keep
  the previous valid artifact visible on any failure.
- [ ] Generate a neutral two-page geometry fixture equivalent to the legacy
  oracle: page 1 at 612x792 with cross-span text and marker; page 2 at 420x600,
  rotation 90, UserUnit 1.5, and marker. Assert page/canvas dimensions,
  transform round trips, selection/search/hit rectangles within 0.05 device
  pixel at tested scales, and stale-document cancellation.
- [ ] Expose the current PDF artifact as a read-only UIA document/text surface
  backed only by the UI broker's independently validated, privately rebuilt
  immutable text/quad/link snapshot; the raw worker reply is never the provider
  backing store.
  A separate-process client must read pages, move ranges, find text, inspect
  links, observe current page/selection, and match bounding rectangles across
  zoom/rotation/UserUnit without causing PDFium calls on the UI thread. Stale or
  failed artifacts remain clearly labeled and never masquerade as current. An
  image-only page or page/document that crosses an extraction cap remains a
  navigable page element whose name/status says exact text is unavailable and
  that OCR has not been run; T0.2 contains no OCR and may not expose invented
  text. Verify these states through the separate UIA client and Narrator.
- [ ] Extend the corpus with Latin/CJK/Arabic, an image-only scanned page,
  non-embedded and embedded fonts,
  crop/media boxes, rotations, transparency, large pages, malformed xref/object
  streams, recursive/deep structures, oversized metadata/images, truncation,
  randomized mutations, deliberate timeout, worker crash, and rapid reopen.
  Active content and disabled handlers must never run. Assert that form fill,
  JavaScript, XFA, URI launch, upload/download, attachment launch, and machine
  time remain disabled or inert even when a hostile PDF requests them.
- [ ] Generate and hash the standard 30-page performance PDF in Zig with mixed
  text density, vector figures, raster figures, transparency, links, page sizes,
  rotations, and fonts representative of a scientific manuscript. Freeze its
  visible journey and expected page/tile/search hashes before benchmarking.
- [ ] Integrate the visible PDF surface and edit-version invalidation into the
  representative shell. Demonstrate latest-version tile replacement without
  claiming that T0.2 compiles LaTeX. Feed the versioned live-render scheduler
  deterministic synthetic job times and prove 220-750 ms adaptation, 75 ms
  supersession grace, and zero stale-current artifact through the real worker
  protocol.
- [ ] Measure aggregate UI+worker memory, CPU, handles, GPU bytes, cancellation
  latency, crash recovery, and tile-cache hard bounds. Repeated worker crashes
  must back off instead of creating a restart storm.
- [ ] Extend the single lifecycle with PDF client/worker, mapping, UIA snapshot,
  tile-cache, engine-thread, Job, and LPAC-profile ownership. Pause or
  crash at every shutdown barrier, race a late reply/callback/duplicate close,
  and prove no worker call, mapping, UIA access, or GPU upload survives its owner.
- [ ] Run the shared final-pass protocol, then commit and push as
  `feat(pdf): isolate bounded native preview worker`.

**Kill switch:** Any ambient project/network/write/child access, reusable or
unresolved LPAC-profile residue, failed/false LPAC token or AAP canary,
wrong/shared worker image, UI/Scintilla/graphics or cross-role import/module,
missing supported mandatory mitigation, module-receipt disagreement,
cross-thread PDFium entry, unbounded
allocation/queue, security fallback, active-content
execution, direct GPU upload from shared worker-writable bytes, tile-section
reuse, stale tile replacing a newer version, unexplained worker hang, or
serial-engine latency breach blocks the PDF choice and T1. Do not hide the breach
with unbounded worker processes or by relaxing the all-Zig boundary.

## Task 6 (T0.2f): Prove canonical ledger and disposable search durability

**Files:**

- Create `native/zig/src/science_main.zig`
- Create `native/zig/src/data/sqlite.zig`
- Create `native/zig/src/data/ledger.zig`
- Create `native/zig/src/data/search.zig`
- Create `native/zig/src/app/search_view.zig`
- Create `native/zig/fixtures/t0_2/ledger_events.zig`
- Create `native/zig/tests/ledger_model_test.zig`
- Create `native/zig/tests/sqlite_vfs_fault_test.zig`
- Create `native/zig/tests/ledger_process_kill_test.zig`
- Create `native/zig/tests/search_worker_kill_test.zig`
- Create `native/zig/tests/search_rebuild_test.zig`
- Create `native/zig/tests/search_protocol_test.zig`
- Create `native/zig/tests/search_ui_test.zig`
- Create `native/zig/tests/search_performance_test.zig`
- Create `native/zig/fixtures/t0_2/search_corpus.zig`
- Create `native/zig/manifests/TExFlow.ScienceWorker.exe.manifest`
- Create `native/zig/manifests/TExFlow.ScienceWorker.rc`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `native/zig/src/main.zig`, `native/zig/src/app/lifecycle.zig`, `native/zig/src/app/strings.zig`, `native/zig/src/app/layout.zig`, `native/zig/src/app/uia_shell.zig`, `native/zig/src/platform/windows/presenter.zig`, `native/zig/src/ipc/frame.zig`, `native/zig/src/ipc/pipe.zig`, `native/zig/src/ipc/peer.zig`, `native/zig/src/platform/windows/process.zig`, `native/zig/qa/uia_client.zig`, `native/zig/qa/journey.zig`, `build.zig`, `.github/workflows/zig.yml`

**Acceptance rows:** A01, A03, A09, A10, A12, A13, A14-A15 instrumentation
subsets, A16 search-result subset, and A17. Task 7 preregisters and runs the
authoritative integrated A14-A16 evidence.

### T0.2 SQLite resource contract

These are T0.2 admission limits, not undocumented tuning hints. The exact
compile options above and every connection value below are asserted after open;
an unsupported, silently clamped, or different value fails startup for that
database. T3 may tighten them or raise a proven domain-size limit through a
reviewed design delta and new boundary/performance evidence; production code
must not silently relax them.

| Boundary | Frozen value and behavior |
| --- | --- |
| Per-connection SQL limits | Ledger and backup connections use `SQLITE_LIMIT_LENGTH=2,097,152`; no ledger row contains a complete multi-field entity. Each <=1-MiB canonical field is stored once as ordered <=256-KiB content-chunk rows, while events and projections store only typed null/length/hash references. Each disposable-search connection uses `SQLITE_LIMIT_LENGTH=5,242,880`, below the six-MiB compile ceiling but with checked record-encoding headroom above four one-MiB fields. Every connection uses `SQLITE_LIMIT_SQL_LENGTH=100,000`, `SQLITE_LIMIT_COLUMN=100`, `SQLITE_LIMIT_EXPR_DEPTH=10`, `SQLITE_LIMIT_PARSER_DEPTH=100`, `SQLITE_LIMIT_COMPOUND_SELECT=3`, `SQLITE_LIMIT_VDBE_OP=25,000`, `SQLITE_LIMIT_FUNCTION_ARG=8`, `SQLITE_LIMIT_ATTACHED=0`, `SQLITE_LIMIT_LIKE_PATTERN_LENGTH=256`, `SQLITE_LIMIT_VARIABLE_NUMBER=64`, `SQLITE_LIMIT_TRIGGER_DEPTH=10`, and `SQLITE_LIMIT_WORKER_THREADS=0`. All content is bound, never embedded in SQL text. Boundary tests insert/read/verify exact 256-KiB ledger chunks and reconstruct the exact four-MiB canonical entity without any ledger row reaching the two-MiB limit; separately insert/update the four-MiB aggregate contentless-delete row, prove its encoded search row stays below the search limit, and reject any field/aggregate overflow before SQLite. |
| Connection hardening | Open only an absolute broker-approved path with `SQLITE_OPEN_FULLMUTEX` and extended result codes; never URI/PATH discovery. Immediately enable `SQLITE_DBCONFIG_DEFENSIVE`, disable trusted schema and legacy DQS, disable triggers/views and attach create/write, and assert extension loading is absent. Set `foreign_keys=ON`, `recursive_triggers=OFF`, `cell_size_check=ON`, `mmap_size=0`, and `temp_store=MEMORY`. A fixed authorizer allowlists the application-owned statement surface after transactional schema creation/migration; no user, worker, provider, or model text becomes SQL. |
| SQLite memory | Keep SQLite memory accounting and its default allocator/page cache active. In `TExFlow.exe`, set process-wide SQLite soft/hard heap limits to 24/32 MiB; in `TExFlow.ScienceWorker.exe`, use 48/64 MiB. Use a 512-byte x 128-slot lookaside pool per connection, a four-MiB writer page-cache target, a two-MiB query-only presentation cache, a one-MiB backup-destination cache, and at most 16 MiB of aggregate active-plus-staging search page cache. `SQLITE_NOMEM` is typed, rolls back the current operation, and preserves the last commit. Record `sqlite3_memory_highwater()` plus per-connection cache/lookaside high-water values; never claim the Job limit is SQLite's heap limit. |
| Database files | Set 4,096-byte pages before entering WAL. Runtime `max_page_count` is 65,536 pages (256 MiB) for ledger/verified backup and 131,072 pages (512 MiB) for each disposable search connection, with the stricter complete-root quota enforced before writes. The complete `W6-search` canonical ledger—including DB/WAL/SHM/journal/temp, 128 MiB of single-copy content chunks, event/reference metadata, and projections—must remain within the 256-MiB ledger limit in both logical and allocated bytes; no compression, sparse allocation, or omitted sidecar can manufacture a pass. `SQLITE_FULL` leaves the ledger readable and enters a visible storage-full/export-or-recover state; search-full discards only the unactivated stage or quarantines/rebuilds the derived generation. Quiescent active search logical and allocated bytes are <=192 MiB, clean empty-root rebuild peak <=224 MiB, and one-active/one-staging complete-root bytes <=400 MiB. These ceilings are exercised both at real `W6-search` scale and at reduced test-VFS boundaries; sparse allocation cannot substitute for either. |
| Broker ownership/queue | The ledger writer connection and any short-lived Online-Backup destination connection live only on the dedicated writer thread. One separate trusted search-presentation lane owns one query-only ledger connection: it copies at most one <=4-MiB entity from a short snapshot, finalizes before tokenization/yield, and never writes or holds a WAL reader across a turn. The science worker has one authenticated control-I/O thread and one database thread; only the latter owns/calls its at-most-one-active plus one-staging SQLite connections, and at most one SQLite call executes at a time. The control thread owns framing and bounded inbound/outbound queues and only publishes generation/deadline/cancellation atomics. The UI-to-broker ring admits at most 128 requests and eight MiB of owned request bytes with one active writer operation; the presentation lane retains the separate <=16-ID/one-entity caps. Enqueue is nonblocking; a full queue rejects the not-yet-accepted action visibly and retryably, never drops/reorders it or presents canonical state before the commit acknowledgement. No read transaction or prepared statement survives an event-loop turn. |
| Time/cancel | Use one non-reentrant busy handler with a 50-ms accumulated ceiling and a progress handler every approximately 1,000 VDBE instructions. Ordinary statement CPU budget is 100 ms; a canonical append has a 250-ms warning and five-second hard wall deadline; integrity/migration/backup/rebuild work is cancellable in <=50-ms/64-page slices with a 30-second T0.2 campaign ceiling. The custom tokenizer additionally observes generation/deadline/cancel atomics after <=64 KiB input or <=2 ms CPU. The UI STA never waits synchronously. A progress/tokenizer callback only reads immutable/atomic state; it never calls the connection or UI. A non-faulting search/rebuild must acknowledge cancellation in <=50 ms; on a miss the broker invalidates all visible pending work and terminates/quarantines the worker rather than waiting or activating its stage. A blocking VFS call that returns after its wall deadline is recorded as a storage fault, the transaction result is resolved safely, and no retry occurs blindly. |
| WAL lifecycle | Set `wal_autocheckpoint=0`; the WAL hook only records frame count and always returns `SQLITE_OK` because a hook error can surface after commit. After the commit acknowledgement, schedule a `PASSIVE` checkpoint on the owner thread when its queue is empty at 1,024 frames (about four MiB). At 4,096 frames, end owned readers and schedule `RESTART` during an idle maintenance window. Before a new mutation at 8,192 frames (about 32 MiB), pause mutation admission, retain the committed WAL untouched, and surface maintenance-required; never delete/truncate a live WAL as recovery. `journal_size_limit=4,194,304` reclaims a successfully checkpointed file but is explicitly not treated as a growth cap. |

The SQLite choice passed a seven-angle decision check: application limits,
process memory, WAL starvation/commit latency, hostile-schema hardening,
temporary/disk behavior, rollback/WAL2 challengers, and thread/cancel failure
modes. Released WAL with `synchronous=FULL` remains the ledger leader; rollback
`EXTRA` loses read/write concurrency, experimental WAL2 requires a non-release
branch, and a custom journal would duplicate SQLite's hardest correctness work.
Correctness/durability outrank bounded resources, UI latency, footprint, and
implementation complexity; doubling the latency weight does not displace the
asynchronous broker because commit/checkpoint work never runs on the UI STA.

The dependent Unicode/search/storage choice passed the specification's thirty-four-round reset.
The final specialist-library round retained one generated Zig pipeline because
ICU/Windows cannot freeze the required small Unicode-17 profile and neither
utf8proc nor libgrapheme alone supplies normalization, full default case fold,
grapheme, and word segmentation. The storage rounds replaced default FTS
content duplication with contentless-delete plus a small UUID map and bounded
complete-entity transport. The final external-content/columnsize and custom-
index/cache rounds found no smaller coherent trust/rank design. Doubling latency
keeps `detail=full` as the provisional detail leader; doubling footprint makes
the smaller FTS detail modes worth the exact reversible spike below, not an
unreviewed implementation-time switch.

- [ ] Define the minimal T0.2 schema before code: project identity, strictly
  increasing per-project event sequence, event kind/version, canonical payload,
  UUIDv7 event ID, previous hash, SHA-256 event hash, one signed 64-bit
  recorded-UTC-millisecond field, a project-scoped immutable content table with ordered
  <=256-KiB chunks, one entity-projection metadata row, and exactly four typed
  field-reference rows. A reference binds field ID, null/non-null tag, exact
  UTF-8 byte length, and SHA-256; projection/history never duplicate the text
  bytes. Encode null as tag zero, zero length, 32 zero hash bytes, and no content
  record. Encode non-null as tag one: empty uses SHA-256
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`, one
  metadata record, and zero chunks; nonempty uses exactly
  `ceil(length / 262144)` zero-based chunks, every nonfinal chunk exactly
  262,144 bytes and the final chunk
  1..262,144 bytes. Hash concatenated raw UTF-8 with no normalization or
  delimiter. Implement full RFC 8785 over I-JSON: reject duplicate keys,
  invalid UTF-8/surrogates, non-finite or non-round-trippable numbers, and
  unsupported values; use required escaping, UTF-16 code-unit property ordering,
  and ECMAScript-compatible shortest number serialization. Scientific accepted
  quantities retain the author decimal token as text with unit/uncertainty
  metadata; binary floating point is never their sole canonical value. Test the
  RFC vectors plus independently reviewed boundary bytes/hashes.
- [ ] Generate UUIDv7 IDs from the recorded UTC millisecond plus Windows CSPRNG
  random fields with exact version/variant bits. Test clock rollback, equal-ms
  bursts, deterministic injected-random known answers, collision rejection, and
  malformed imported IDs; require the UUIDv7 48-bit time field to equal the
  in-range recorded UTC millisecond, while the per-project sequence—not UUID or
  clock—remains ordering authority. Sequence starts at one, the first event uses
  an all-zero 32-byte previous hash, and every later event uses the immediately
  preceding verified hash; reject zero/gap/duplicate/overflow sequence and a
  nonzero genesis predecessor.
- [ ] Freeze event-hash bytes as
  `SHA-256("texflow:event:v1\0" || project_uuid[16] || sequence_u64_le ||
  event_uuid[16] || kind_u16_le || schema_version_u16_le ||
  recorded_utc_ms_i64_le || previous_hash[32] || payload_length_u32_le ||
  canonical_payload)` and reject a
  canonical payload above 1 MiB before allocation. Large canonical field bytes
  are not embedded in that JCS object: its fixed typed references bind content
  stored in the same transaction. Each field remains <=1 MiB and an entity
  <=4 MiB; the immutable application snapshot supplied to the writer is counted
  against the eight-MiB broker queue. Migration/version
  rules preserve old hash domains; timestamp and UUID time cannot determine
  ordering. Every persisted semantic event value must be either a fixed-width
  envelope field, inline in the canonical payload, or immutable content whose
  typed hash/length/null reference is inside that payload; only
  storage-technical values with no behavioral meaning may remain unbound. Mutate every
  envelope field, payload byte/length, previous hash, content byte/order/length,
  and projection reference independently and require reopen validation to
  quarantine it.
  State explicitly that the hash chain detects accidental
  corruption/divergence but is not authorship, signature, or same-user malicious-process
  protection.
- [ ] Wrap the exact SQLite C API in Zig with typed connection/statement/transaction
  ownership, bound parameters, checked return codes, extended error logging
  without paper content, the frozen busy/progress/deadline behavior, and
  deterministic close/finalize. Apply and read back every frozen SQL,
  hardening, memory, cache, lookaside, page-count, and temporary-store value
  above before accepting work. Resource-limit failures are typed and leave the
  last committed ledger usable. Test exactly-at/one-over boundaries, failed
  allocation at the hard heap ceiling, authorizer denials, and compile/runtime
  option drift; no test may disable the production caps merely to pass.
- [ ] Insert any new project-scoped content chunks, the referencing event, and
  every changed entity/field projection reference in one transaction. Hash and
  validate the full UTF-8 value before insertion. Reuse an existing
  `(project_uuid, sha256, byte_length)` key only after byte-for-byte streaming
  comparison; a mismatch is an integrity failure. Reopen and backup validation
  reject missing, extra, reordered, cross-project, orphan-referenced,
  wrong-length, or wrong-hash chunks before serving the value. Inject failure/process
  death at every chunk/event/projection boundary and require the complete old or
  complete new reference graph—never a dangling or mixed revision. Keep
  unreferenced newly inserted content impossible by transaction rollback; an
  immutable historical event remains a valid reference and is never
  garbage-collected as if it were derived cache.
- [ ] Run `ledger.db` behind a narrow trusted broker on a dedicated database
  thread in the UI process; the UI STA and every worker are forbidden from
  opening it directly. Configure WAL/FULL and make append plus canonical
  projection update one single-writer transaction. Implement the exact
  bounded-ring admission and asynchronous accepted/committed/rejected state
  machine above; queue saturation, cancellation before acceptance, cancellation
  after BEGIN, slow sync, and late completion may neither lose an accepted
  action nor publish an uncommitted one. Reopen validates sequence, hash chain,
  schema version, projection watermark, and projection content before serving
  state; any integrity failure makes the ledger read-only/quarantined until
  verified repair or restore.
- [ ] Add exactly one separate trusted query-only presentation connection/lane.
  For each candidate it opens a short read snapshot at the requested current
  watermark, resolves the four projection references, streams their ordered
  chunks while rechecking declared length/SHA-256, copies at most one <=4-MiB
  canonical entity plus its revision into owned memory, finalizes/ends the read
  transaction, and only then tokenizes and
  builds presentation outside SQLite. It cannot write, call the writer
  connection, or retain a statement/read mark across a yield. Immediately before
  publishing a safe-title/snippet result, recheck that the canonical watermark
  and entity revision are unchanged; otherwise discard/cancel and request a new
  generation. Stress concurrent append/checkpoint/search so presentation never
  starves the writer or WAL reclamation and no old-revision row appears.
- [ ] Configure `search.db` independently in the science worker as WAL/NORMAL
  with a contentless-delete FTS5 table, provisional `detail=full`,
  `columnsize=1`, the Zig-registered `texflow17` tokenizer, and a committed
  ledger watermark. Enable and read back core `secure_delete=ON` plus FTS5
  `secure-delete=1`; state explicitly that these reduce obsolete local index
  residue but do not promise forensic SSD erasure. A small ordinary table maps
  integer FTS rowids to unique canonical 16-byte entity UUIDs and stores no
  canonical text. Neither indexed field values nor snippets are readable back
  from FTS. Freeze the exact query rank as
  `bm25(search_fts, 1.0, 1.0, 1.0, 1.0)` and reject `columnsize=0`.
- [ ] Feed search only authenticated immutable canonical projection records
  reconstructed and hash-verified from those content references after ledger
  commit, never SQL or worker-selected fields. One entity uses a
  begin record; four enum-ordered <=1-MiB field logical messages fragmented by
  the common 64-KiB frame layer; and a commit record binding project, entity,
  canonical entity revision, ledger sequence/hash/watermark, rebuild
  generation, per-field hashes, aggregate length, and aggregate hash. Every
  field carries an exact null/non-null tag and checked length. Freeze field IDs
  1..4 and compute
  `SHA-256("texflow:search-field:v1\0" || field_id_u8 || tag_u8 ||
  length_u32_le || bytes)`; null is tag zero/length zero/no bytes and non-null
  empty is tag one. Compute the commit aggregate as
  `SHA-256("texflow:search-entity:v1\0" || project_uuid[16] ||
  entity_uuid[16] || entity_revision_u64_le || ledger_sequence_u64_le ||
  ledger_hash[32] || watermark_u64_le || generation_u64_le ||
  aggregate_length_u32_le || field_digest[0] || ... || field_digest[3])`.
  Unknown tags, noncanonical widths/order, overflow, or any digest mismatch fail
  before SQLite so null and empty cannot alias. The
  worker holds at most one <=4-MiB assembly, rejects missing/duplicate/reordered
  fields or mixed revisions, and performs the all-column FTS insert/update plus
  rowid-map mutation in one transaction only after commit verification. Delete
  shares that transaction. Cancellation/disconnect/crash discards incomplete
  assembly; a replay is idempotent. Rebuild input is UUID-sorted for deterministic
  rowid/database manifests. The ledger broker revalidates every returned
  watermark and canonical entity ID before any further use.
- [ ] Build every replacement in one generation-unique staging directory and
  retain at most one compatible active generation. No cancelled, crashed,
  over-quota, corrupt, wrong-watermark, wrong-tokenizer, or partial stage is
  queryable. Full replay, FTS integrity/membership checks, a successful
  truncating WAL checkpoint, statement finalization, clean close/reopen, and a
  verified complete-root manifest precede the broker's generation-bound active
  pointer replacement. If the <=400-MiB root cannot hold active plus stage,
  remove the old disposable generation and show the separate
  unavailable/rebuilding state before starting; never exceed the quota. Delete, corrupt,
  truncate, version-skew, and stale-watermark cases rebuild idempotently from
  canonical projections; search failure cannot roll back or mutate the ledger.
- [ ] Freeze the representative T0.2 searchable projection before creating its
  FTS table: `field_id` 1=`title`, 2=`abstract`, 3=`claim_text`, and
  4=`evidence_text`, each nullable UTF-8 and capped at one MiB, with at most four
  MiB total per entity. The fixed FTS columns follow that numeric order; the
  trusted broker uses field IDs only inside its own schema and no field ID
  crosses worker IPC. The small derived rowid map contains only its integer FTS
  rowid and the canonical 16-byte entity UUID. Typed exact DOI/citekey/provider
  IDs remain in the canonical ledger and do not cross into the T0.2 worker,
  because this slice has no exact-ID candidate union; unknown field IDs, dynamic
  field names, extra FTS
  columns, and over-aggregate entities are rejected before indexing. A later
  production schema may change this enum only through a versioned migration and
  tokenizer/schema-fingerprint rebuild, never through worker input.
- [ ] Register the FTS5 v2 custom tokenizer `texflow17` directly from Zig and
  require `fts5_api.iVersion >= 3` before reading/calling
  `xCreateTokenizer_v2`, set and assert `fts5_tokenizer_v2.iVersion = 2`, and
  fail before schema creation on a null function pointer or smaller/unknown
  layout. The exact schema passes zero tokenizer constructor arguments and the
  constructor rejects any supplied argument. The exact T0.2 FTS schema does not enable FTS5 locale support: every
  callback must receive `pLocale=null,nLocale=0`; nonempty/inconsistent locale,
  `FTS5_TOKENIZE_PREFIX`, `FTS5_TOKENIZE_AUX`, unknown flags, or anything other
  than one exact QUERY or DOCUMENT mode
  combination returns a checked error rather than changing segmentation.
  Segment
  by untailored Unicode-17/UAX-29 default word rules, emit only segments that
  contain a Unicode Letter or Number, and index
  `NFD(full-default-case-fold(NFD(token)))` without removing accents. Emit
  exactly one callback with flags zero for each eligible segment; synonyms and
  `FTS5_TOKEN_COLOCATED` are forbidden. Document
  and query paths use the exact same implementation/profile/table hash, which is
  bound into the search schema, event batch, request, and reply. Differentially
  prove NFC/NFD equivalence, Vietnamese accent distinction,
  Greek/Cyrillic/CJK/new-Unicode-17 coverage, full case-fold expansions, combining/emoji/control
  boundaries, no marks-only token, and exact source-byte offsets. The built-in
  Unicode-6.1 `unicode61`, ICU, Windows NLS, and locale dictionaries are negative
  production-dependency tests. Exact DOI/citekey/provider-ID fields remain
  canonical ledger data and are absent from the T0.2 derived worker schema.
  T0.2 does not claim an exact-ID or context boost: it labels its result order
  lexical-feasibility only. T3.1 must freeze and benchmark the typed-ID candidate union,
  feature/fusion fingerprint, missing-feature behavior, explanation receipt,
  and stable tie-breaks before enabling the product's smart ranking.
  Unit tests substitute truncated/version-2 `fts5_api` tables, null v2 methods,
  wrong tokenizer versions, constructor arguments, locale bytes,
  prefix/AUX/unknown flags, and every
  supported QUERY/DOCUMENT call shape; no test reads beyond the advertised API
  version.
  Stream each <=1-MiB field with <=64-KiB scratch and observe the current
  generation/deadline/cancel atomics after <=64 KiB of input or <=2 ms CPU; cap a raw emitted segment at
  1,024 bytes, its normalized token at 256 bytes, and the field at 65,536 tokens.
  Crossing a cap aborts the complete entity transaction and causes the trusted
  broker—not the worker—to record a typed `lexical-unindexed`
  canonical-eligibility reason. The visible exact-watermark ratio is eligible canonical
  fields over total canonical fields and explicitly says it is not indexed
  completeness. Worker-reported coverage is never an audit input. No path
  splits a token, accepts a partial field/entity, or mutates the canonical
  ledger.
- [ ] Define and fuzz the science request/reply schema as an untrusted boundary.
  The T0.2 query surface accepts one at-most-4-KiB valid-UTF-8 user string and
  tokenizes it as a whole with `texflow17`. Ordinary Unicode whitespace and
  punctuation participate only in the tokenizer's boundary rules; embedded
  NUL, C0/C1 controls, Unicode
  directional-format controls, zero emitted tokens, more than 64 emitted tokens,
  an emitted token above 256 bytes, and checked-length overflow are rejected.
  Normalized duplicates collapse in first-occurrence order before zero-based
  query indexes are assigned. A Zig builder encodes each token as one
  double-quoted FTS5 string, doubles every embedded U+0022 byte, joins phrases with
  exact ASCII ` AND `, rejects encoded output above 65,536 bytes, and binds that
  one value to the only parameter of a fixed MATCH statement. Fuzz
  `AND`/`OR`/`NOT`/`NEAR`, Hebrew-letter/double-quote segments, parentheses, column
  syntax, carets, minus signs, asterisks, semicolons, and SQL-looking text and
  prove they have only tokenizer-defined literal/separator meaning, never FTS5
  operator or SQL authority. Return at most 100 hits. Read exact
  `bm25(search_fts, 1.0, 1.0, 1.0, 1.0)` as IEEE-754
  binary64, require `-1_000_000.0 <= rank <= 1_000_000.0`, reject NaN/infinity,
  normalize a computed negative zero to positive zero, and encode the canonical
  bits as `rank_f64_le`. Order numeric rank ascending and then the canonical
  16-byte entity UUID in unsigned binary order; test signed zero, subnormals,
  equal ranks, adjacent representable values, byte-swapped payloads, NaN payload
  classes, infinities, and both bounds. Bind the request to
  project/generation/watermark/deadline. Raw rank is never user-visible; it is
  only a derived-navigation ordering value and diagnostic fixture bit pattern.
- [ ] Keep the worker reply descriptor-free: after its common envelope, each of
  at most 100 results contains exactly `entity_uuid[16]` and canonical
  `rank_f64_le`, with no field selector, token/byte position, hit count,
  truncation value, snippet, display bytes, or extension tail. For each of at
  most eight visible result IDs requested in one presentation batch, the trusted
  query-only presentation lane copies all four canonical fields plus entity
  revision from one short ledger snapshot, finalizes it, and uses the shared Zig
  tokenizer outside SQLite to stream every normalized query-token occurrence.
  The union must contain every de-duplicated literal-AND query token or the
  worker candidate is rejected and its disposable index quarantined/rebuilt;
  no identity, title, rank, skeleton labeled as a result, or snippet becomes
  visible before this proof succeeds.
  Apply one exact streaming presentation transform before measuring display
  caps: collapse each Unicode-17 `White_Space` run (CRLF is one separator) to an
  ASCII space and trim edge spaces; then map every remaining C0/C1 scalar, DEL,
  U+061C, U+200E/U+200F, U+202A-U+202E and U+2066-U+2069 to uppercase ASCII
  `[U+XXXX]`, preserving every other valid scalar byte-for-byte. DirectWrite
  isolates direction at the layout boundary; no hidden isolate is inserted in
  the text. Select only a transformed window that fits <=64 source tokens and
  <=8 KiB including one literal U+2026 at each omitted edge, by maximum
  distinct-query-term coverage, then maximum match count, then minimum source-byte span,
  then ascending `(field_id, start_ordinal, end_ordinal)`. It derives hit
  truncation itself and emits prefix/suffix elision plus sorted,
  non-overlapping half-open UTF-8 match ranges over the final display bytes.
  At most sixteen IDs await presentation, one <=4-MiB entity is materialized at
  a time, and the non-UI broker observes cancellation/yields after each <=64-KiB
  chunk and <=2 ms of CPU; a new query/scroll invalidates stale batches. Transform
  the canonical `title` field with the same grammar. If empty, render exact
  `search.untitled`, ` — `, and the full lowercase hyphenated canonical UUID;
  never promote claim/evidence text into a title. Otherwise retain the largest
  complete transformed-grapheme prefix for which a trailing U+2026 fits, so the
  final title including the marker is <=256 extended grapheme clusters and
  <=2 KiB UTF-8; omit the marker when untruncated. After match proof and an unchanged
  canonical watermark/entity revision, the UI may show the canonical
  identity/safe-title row before its snippet; it validates all derived
  text/ranges, converts to UTF-16, renders isolated layouts, and labels the
  snippet derived—not a quotation or evidence excerpt.
- [ ] Treat result soundness and result completeness separately. Inject a
  correctly authenticated worker that omits known matches, returns an empty
  list despite known matches, permutes valid IDs, and assigns arbitrary valid
  bounded ranks. The broker must never invent a row or snippet, while the UI
  must render the exact `search.results.notice`, `search.empty`,
  `search.rebuilding`, and `search.unavailable` values frozen above. Raw BM25 is
  hidden. Never emit `no evidence`, `no
  citation`, `not found`, a confidence, or a completeness claim from
  rank/absence. The broker alone renders exact `search.eligibility` at the ledger
  watermark; reject every worker-supplied coverage percentage.
  Verify the exact whitespace/control transform, `[U+XXXX]` grammar, U+2026
  accounting, untitled UUID fallback, and absence of hidden directional bytes.
  Prove every later
  T0.2 claim/citation/preflight fixture that needs completeness reads the
  canonical ledger or a frozen reconciliation receipt, not this result list.
- [ ] Implement the T0.2 native search surface in `search_view.zig`: a labeled
  query edit, explicit submit/cancel, one coalesced status live region, and a
  virtualized keyboard-navigable result list whose visible rows alone request
  broker proof. Expose stable UIA List/ListItem/Text identities and
  selected/busy states without putting raw rank or hidden candidates in accessible text.
  Preserve focus/selection by canonical UUID across safe refreshes, clear it on
  generation invalidation, and make Enter/navigation inert until a row is
  proved. Exercise exact resource copy, safe-title/snippet ranges, 100-result
  cap, 0/1/8/100/>100 states, resize/DPI/theme/high-contrast, screen-reader
  reading order, new-query/scroll cancellation, worker crash/rebuild, and no
  stale or false-positive row through the separate Zig UIA/OS-input client.
- [ ] Generate `W6-search` before measuring: exactly 10,000 canonical entities,
  four fields, 128 MiB of valid UTF-8, fixed multilingual/normalization/control
  cases, fixed hit-cardinality/query classes, and one exact four-MiB adversarial
  entity. Build isolated contentless-delete `detail=full`, `detail=column`, and
  `detail=none` databases plus one default stored-content `detail=full`
  counterfactual from identical bytes with the exact pinned SQLite build,
  `columnsize=1`, secure-delete settings, tokenizer, UUID map, and entity-update
  protocol. Require identical update/delete/replay behavior, literal-AND
  membership, and byte-canonical BM25 rank/order. Record quiescent complete-root
  logical/allocated bytes, empty-root and active-plus-stage peaks, rebuild
  CPU/wall time, first-use/warm query latency, peak memory, and cancellation.
  Contentless-delete `detail=full` remains the admitted baseline. If it misses a
  mandatory gate while another contentless detail mode meets every gate, or if
  all meet the gates and another mode reduces quiescent complete-root bytes by
  at least 20 percent without worsening any p95 latency by more than five
  percent, stop Task 6 and land a reviewed spec/plan delta before adopting it;
  never choose a mode at runtime or after seeing only a favorable subset. If no
  mode closes every gate, the data architecture fails rather than selecting the
  least-bad result. Stored-content and
  `columnsize=0` are not adoption candidates unless a new review identifies a
  mandatory capability that the contentless contract cannot supply.
- [ ] Make the search benchmark controller assert every timing/memory/size
  endpoint against synthetic known answers, then run only a clearly labeled
  current-host diagnostic in Task 6. Task 7 must preregister and execute the
  authoritative 30-trial `W6-search` first-use,
  warm-query/presentation/cancellation, and clean-rebuild cells on each frozen machine/OS stratum. For
  each query derive `H=min(100, expected_match_count)` only from the independent
  oracle; prove the exact capped membership/order before accepting latency, and
  evaluate every cardinality/adversarial class separately. Enforce p95 <=400 ms
  for first use, <=75 ms warm, both to `min(8,H)` proven safe-title rows or the
  terminal empty state for `H=0`; <=200 ms to `min(8,H)` representative
  broker-built snippets; <=750 ms for the four-MiB adversarial entity; <=50 ms
  cancellation; <=4-ms UI-STA slices; <=110/135-MiB peak aggregate private
  working set/commit; <=192-MiB quiescent active generation, <=224-MiB
  empty-root rebuild peak, <=400-MiB whole derived root; and <=30-s clean rebuild.
  Recursively count every DB/WAL/SHM/journal/temp/manifest/pointer/stage/residue
  file in both logical and allocated bytes. Retain every raw sample and fail
  rather than pool strata, drop outliers, accept an incorrect/short reply, or
  substitute a smaller corpus.
- [ ] The UI decoder must reject valid-MAC replies with wrong
  project/generation/watermark/hash, unknown or duplicate entity IDs, count/byte overflow,
  any descriptor/field/position/truncation/presentation extension,
  NaN/infinite/out-of-bound/noncanonical-negative-zero rank values,
  byte-swapped rank/UUID payloads, unstable rank/entity-ID
  ordering, any presentation/markup/SQL/path/command field, trailing bytes, or
  stale cancellation state. Preserve the last valid search view on rejection
  and quarantine/restart the worker without touching the canonical ledger.
- [ ] Launch the dedicated headless `TExFlow.ScienceWorker.exe` in a distinct
  LPAC profile with the same mandatory AAP opt-out, zero named capabilities,
  complete frozen mitigation profile, suspended token/policy assertions,
  classic-control canary, independent import/live-module inventory, and
  no-silent-fallback oracle as the PDF role. Its profile moniker is exactly
  `texflow.scienceworker.v1` and its embedded resources are exactly
  `ProductName=TExFlow`, `FileDescription=TExFlow Science Worker`,
  `InternalName=TExFlow.ScienceWorker`, and
  `OriginalFilename=TExFlow.ScienceWorker.exe` plus the frozen common
  feasibility-version tuple, with no invented legal
  publisher fields. Its entry point rejects PDF or
  unauthenticated probe-role substitution before SQLite initialization. Grant
  the required exact-current-logon/exact-science-package-SID access pair only to
  its verified role image and SQLite closure, a separate disposable search/cache
  directory, and the
  authenticated pipe; its independently erase-before/after LPAC profile remains
  untrusted scratch and is never the search store. Inherit no project, PDF, or
  ledger handle and prove the
  science SID cannot enumerate, open, map, or load `TExFlow.PdfWorker.exe` or
  the staged PDFium DLL, while the PDF SID cannot open/map/load the science
  worker or search closure. Prove
  OS-enforced denial of project and canonical-ledger reads/writes,
  `ALL APPLICATION PACKAGES`-only resources, registry, COM, arbitrary writes,
  network, and child spawn alongside peer
  authentication, bounded IPC, clean cancellation, shutdown, crash recovery,
  ACL restoration, and aggregate resource accounting. Reuse the Task 5
  loss-detecting access tracer on both sealed OS lanes for the complete
  SQLite/FTS search/rebuild corpus, merge the science role's successful ARAP and
  exact-role accesses into the canonical residual-access manifest, and apply
  the same trace-loss, private-path, unexpected-write, and user-writable
  executable/configuration kill switches.
- [ ] Carry the exact 16-byte UI trial nonce only inside the authenticated
  science-worker bootstrap. Before SQLite initialization or application input,
  require the first worker ETW/log event to echo that nonce with the science
  role, PID, creation time, and build identity; reject missing, mismatched,
  duplicate, stale, or separately supplied values. The nonce is correlation
  only and never enables fixtures, test paths, policy changes, or extra access.
- [ ] Inside that image, run exactly one authenticated overlapped-pipe control
  thread and one database thread. The control thread must continue receiving
  cancel/shutdown frames while SQLite or `texflow17` is active, owns the bounded
  request/reply queues, and publishes only checked generation/deadline/cancel
  atomics. The database thread alone opens/closes/calls SQLite and owns every
  connection, statement, transaction, and tokenizer; its progress handler and
  tokenizer only read those atomics. Race cancellation against prepare, step,
  tokenization, FTS merge, checkpoint, stage activation, close, and worker death;
  no cross-thread connection call, use-after-close, stale acknowledgement, or
  cancelled-generation activation is permitted.
- [ ] Implement a Zig test VFS that wraps the default SQLite VFS and injects at
  deterministic I/O ordinals: short/failing write, failing sync, truncate,
  delete, dropped write, delayed/reordered buffered writes, sector/power-safe
  characteristic variants, and crash without clean close. Each case records its
  explicit storage model and must not exceed that model's claim. Split cases
  into (a) documented VFS-contract failures reported to SQLite and (b) a device
  that violates successful-write/sync guarantees.
- [ ] For every injection point around BEGIN, WAL writes/sync, commit marker,
  projection writes, checkpoint, and reopen, contract-compliant cases must
  recover exactly the old or new complete transaction, never a hybrid; sequence
  and hash chain are valid; projection matches its watermark; `integrity_check`
  succeeds; and the next append works. For contract-violating device cases, the
  allowed result is a complete old/new state or explicit corruption/quarantine;
  silently serving a hybrid/tampered ledger is always failure. `integrity_check`
  is supporting evidence, not the durability oracle.
- [ ] Run a separate controller/worker process-kill campaign at randomized but
  seeded protocol barriers and I/O acknowledgements. Clearly label this process
  crash evidence; it is not a physical power-loss test. The VFS fault campaign
  supplies the deterministic power-loss/storage-failure model.
- [ ] Test duplicate event, sequence gap, wrong previous hash, payload tamper,
  projection tamper, cross-project event, divergent imported history, migration
  interruption, disk full/read-only, concurrent readers, busy timeout, live
  backup through SQLite Online Backup API, and restore into staging before
  atomic activation. Never copy a live WAL database file as backup.
- [ ] Drive the WAL state machine through 1,024/4,096/8,192-frame thresholds
  using a reduced-scale test VFS, including a held-reader starvation probe,
  queue pressure during checkpoint, close/reopen with a live committed WAL,
  checkpoint busy/cancel/error, and post-checkpoint size reclamation. Prove the
  hook never checkpoints or returns an error; the 8,192-frame gate pauses before
  the next BEGIN without damaging already committed state; and
  `journal_size_limit` is never reported as a hard cap.
- [ ] Stress app-data ACLs, owner-only redacted logs, repeated open/close,
  process-wide heap high-water, per-connection cache/lookaside high-water,
  queue byte/count saturation, statement/wall deadlines, page-count limits, and
  disk-space exhaustion. No database, checkpoint, backup, or maintenance task
  may block the UI thread, run foreground QoS while idle, or retry indefinitely.
- [ ] Extend the single lifecycle with ledger-broker and disposable-search
  ownership. During closing, reject new admission, resolve every accepted
  canonical append to committed or explicit failure within the hard deadline,
  discard derived search safely, and test slow sync, busy/checkpoint, worker
  crash, forced process death, double close, and reopen at every barrier.
- [ ] Run the shared final-pass protocol, then commit and push as
  `feat(data): prove durable ledger and rebuildable search`.

**Kill switch:** Any outcome outside a complete old/new ledger transaction,
hash/projection/content-reference divergence accepted silently, a missing,
corrupt, cross-project, dangling, or mixed-revision chunk served, canonical text
duplicated into event and projection rows, a ledger row above the two-MiB limit,
the complete `W6-search` ledger root above 256 MiB, live-file backup, search-to-ledger
coupling, persistent science-profile residue, shared/wrong worker image,
cross-role import/module/access, missing supported mandatory mitigation, module-
receipt disagreement, Unicode table/profile drift, accent-destructive or
Unicode-6.1 tokenization, stored canonical fields in the admitted FTS table,
`columnsize=0`, a partial/cancelled stage activated, blocked cancel reception,
a worker candidate displayed before broker literal-AND validation, unsafe or
unbounded title/presentation bytes, worker-authored hit/coverage metadata, any
UI/audit claim that treats worker omission/rank/eligibility as negative or
complete scientific evidence, a missed `W6-search` first-use/validated-row/
memory/complete-root/rebuild/cancellation gate, an unreviewed FTS detail/content
mode switch, or process-kill result mislabeled as power loss blocks T1.

## T0.2g campaign preregistration and matrix contract

T0.1 deliberately deferred the physical performance baseline, so Task 7 owns
it before any measurement. Two privacy-safe reference profiles are frozen: an
exact physical 4-core/8-GiB/iGPU/SSD low-tier machine and an exact physical
6-8-core/16-GiB/iGPU-or-entry-dGPU/SSD mainstream machine. Each profile records
CPU/model/core topology and microcode, firmware/BIOS, memory population, storage
model/firmware/free-space floor, GPU/adapter LUID/driver/WDDM, display model and
link/modes, OS edition/build/servicing state, cooling/thermal-throttle state,
power policy, and AC/battery condition. Hostname, username, SID, MAC address,
device serials, license material, and raw EDID serial fields are never committed.
A replacement requires an ADR plus side-by-side calibration before the former
machine is retired; a faster machine cannot silently inherit its label.

The required physical strata are the full product of `{low-tier, mainstream}`
and `{Windows 10 22H2 build 19045 with active ESU servicing, Windows 11 25H2 at
the frozen serviced build}`. The current 32-GiB development host is a separately
labeled diagnostic stratum. WARP, a VM, affinity, memory caps, or throttling are
stress tools, never reference-hardware substitutes.

Each `{machine, OS}` stratum is a separately bootable installation on the named
physical machine, or a bit-for-bit restored physical-disk image, never a guest
VM. Before preregistration, freeze the installation/image digest or restoration
receipt; edition and servicing/ESU channel; build, LCU/SSU, pending-update and
pending-reboot state; boot volume and pagefile policy; installed startup items
and security software; device-driver package versions; and the clean versus
established QA-user-base and TExFlow/project-state fixture. The physical image
contains one already initialized, sealed post-first-logon local-QA account, so
Windows first-logon setup is never mistaken for app cost; that loaded Windows
profile is not deleted, cloned, or rewritten between samples. Instead, with all
TExFlow processes terminated, the Zig controller atomically replaces only a
manifest-allowlisted set of TExFlow-owned state/cache roots and the generated
workspace root from a same-volume sealed template, then verifies paths, ACLs,
entry inventory, bytes, and hashes with no extra product state elsewhere.
`clean` installs the empty TExFlow state/cache fixture. `established` installs
the pinned representative workspace, history, and cache corpus into those same
declared roots. A product write outside the declared roots invalidates the trial
and is a containment bug. Cold-state replacement happens before full shutdown;
warm-state replacement happens before the one unmeasured priming launch. Neither
profile is the operator's everyday account, and neither requires rewriting an
active Windows profile hive. No OS,
driver, firmware, startup-item, security-software, or fixture mutation is
allowed after preregistration or during the final closed pass; any such change
creates a new stratum, resets its streak, and requires a new preregistration and
a complete replacement campaign.

For every `P0-baseline` cold sample, Fast Startup/hiberboot must be ineligible:
the operator-provisioned frozen QA image runs `powercfg /hibernate off`, records
the successful command and `powercfg /a` output, and rejects a campaign if hibernation or Fast
Startup becomes available again. A persisted pre-boot queue requests a full
shutdown (`shutdown.exe /s /t 0`, without `/hybrid`) followed by physical power
on; a controlled `Restart` is an allowed full-kernel-boot fallback because Fast
Startup does not apply to Restart, but it is labeled separately and cannot be
pooled with power-off samples. The post-boot harness accepts exactly one sample
only after both `Win32_OperatingSystem.LastBootUpTime` and `GetTickCount64`
prove a new boot within the preregistered tolerance, and after confirming no
earlier TExFlow process/startup launch in that boot. The manifest also freezes
the login method, desktop-ready oracle, and one fixed post-logon launch offset;
background load and outliers at that valid offset are retained rather than
selectively waiting for a favorable sample. Any reused boot identity,
hybrid/hibernate/resume transition, ambiguous clock, or second launch invalidates
the entire named cell under the restart rule below.

Before a trial, a repository-owned Zig generator writes a canonical campaign
manifest containing factor definitions, constraints, every row, workload and
tool digests, required repetitions, order seeds, benchmark-cell names, capture
oracle, and empty reference-machine slots. A Zig verifier independently proves:

- every required machine/OS stratum exists;
- strength-three coverage for every three-factor projection of resolution
  `{1920x1080, 2560x1440, 3840x2160}`, refresh `{60, 120, 144}`, DPI
  `{100, 150, 200}`, and shell renderer `{hardware, WARP}` within each stratum;
- constrained pairwise coverage across profile `{clean, established}`, theme
  `{light, dark, high-contrast}`, editor renderer `{selected DirectWrite,
  DirectWriteDC fallback}`, reduced motion, power state, visibility state, and
  the core display/render factors;
- explicit edge rows for 4K/144-Hz/200%-hardware,
  4K/60-Hz/200%-WARP, 1080p/60-Hz/100%-high-contrast/reduced-motion, and
  1440p/120-Hz/150%-hardware, plus a controlled 1080p RDP row and a conditional
  Advanced-Color/HDR visual row on every capable reference output; and
- every constraint, row ID, seed, and expected journey is canonical and unique.

This mixed-strength array follows the NIST covering-array rationale while
retaining known high-risk triples and extremes. Each row receives the complete
functional/visual journey once per campaign. Repeated performance distributions
are separate predeclared cells, not pooled covering-array samples:

| Cell | Configuration | Repetitions and strata |
| --- | --- | --- |
| `P0-baseline` | 1080p, 60 Hz, 100% DPI, hardware, SDR, AC balanced | 30 warm trials for each machine/OS/profile stratum; 30 independent hiberboot-ineligible full-kernel-boot launches for each such stratum and profile, with one preregistered boot method and post-logon offset per cell |
| `P1-pixel-refresh` | 4K, 144 Hz, 200% DPI, hardware, SDR | 30 warm trials for each machine/OS/profile stratum |
| `P2-software` | 1080p, 60 Hz, 100% DPI, WARP shell + DirectWriteDC editor, SDR | 30 warm trials for each machine/OS/profile stratum |
| `P3-balanced` | 1440p, 120 Hz, 150% DPI, hardware, SDR | 30 warm trials for each machine/OS/profile stratum |
| `P4-rdp` | Controlled independent-client RDP at 1080p/60-Hz/100% | 30 warm trials for each machine/OS/profile stratum against the same-session native-text comparator |
| `P5-battery` | Native display, recommended DPI, hardware, battery saver | 30 warm trials per profile only on a frozen reference machine with a physical battery; otherwise this spec-designated conditional cell is reported `NOT-APPLICABLE`, not simulated |
| `P6-large-editor` | `W2-large-editor`, 1080p/60-Hz/100%, hardware shell and selected DirectWrite editor, SDR, AC balanced, established fixture | 30 warm trials for each machine/OS stratum; apply the large-editor open/memory/index/convergence/slice gates without pooling |
| `P7-search-query` | `W6-search`, 1080p/60-Hz/100%, hardware, SDR, AC balanced, established fixture | Separate 30-trial first-use and warm query/presentation/cancellation distributions for each machine/OS stratum. First-use begins with no science process/open connection; warm clears the selected query's app caches. Every fixed cardinality class and the four-MiB adversarial row is validated and reported independently rather than pooled. |
| `P8-search-rebuild` | Clean `W6-search` derived root, 1080p/60-Hz/100%, hardware, SDR, AC balanced | 30 clean full-index rebuilds for each machine/OS stratum; retain wall/CPU/disk/memory and recursive logical/allocated root-size samples, inject cancel before activation, and prove the UI remains responsive throughout. |
| `V0-hdr` | Native HDR/WCG mode, hardware renderer, established profile | One functional/visual journey in the final pass on every capable frozen reference output; absence of HDR hardware is a declared non-gating `NOT-APPLICABLE` because TExFlow's v1 output contract is SDR, never a claim of tested HDR fidelity |

A cell is judged independently; machine, OS, renderer, profile, power, and RDP
distributions are never pooled to pass. The first 30 scheduled samples are the
sample set. Any missing/corrupt/lost-correlation sample fails that cell and
requires a harness repair plus a completely new cell run and seed; it is not
replaced selectively. Warmup is never sampled and outliers are retained. The
manifest and both reference identities are reviewed, committed, and pushed as
the Task 7 preregistration before a closed measured campaign. A provisional
current-host campaign instead commits that host identity and explicit empty
reference slots before its first sample. Results cannot rewrite rows, workloads,
budgets, identities, or exclusion rules after observation.

## T0.2g visible-capture decision and contract

Seven distinct research angles compared DXGI Desktop Duplication, Windows
Graphics Capture (WGC), `PrintWindow`, screen-DC capture, an app-owned
framebuffer, and camera/instrument evidence: visible popup fidelity; OS/ABI
floor; compositor timestamps and frame lifetime; multi-output/RDP/device-loss
failure modes; HDR/WCG; blocking/self-render alternatives; and measurement
perturbation/calibration. `IDXGIOutput5::DuplicateOutput1` is the leader because
it captures the visible DWM-composed output, supports the Windows 10 floor,
exposes QPC/frame-loss/protected-content metadata, and can retain high-color
scan-out formats. The final two angles found no better challenger; doubling
implementation-complexity weight or HDR weight does not change the choice.

The independent Zig QA controller uses `DuplicateOutput1` on the target output,
falling back to plain `DuplicateOutput` only for a declared SDR row. It creates
the D3D11 device on that output's adapter, supplies BGRA8 plus supported
high-color scan-out formats, uses finite 50-ms `AcquireNextFrame` waits under a
5-second state deadline, releases every acquired frame, and recreates the
duplication object after display/desktop switch or `DXGI_ERROR_ACCESS_LOST`.
`ACCESS_DENIED`, `NOT_CURRENTLY_AVAILABLE`, `SESSION_DISCONNECTED`, protected
content, unsupported HDR format, rotation/crop ambiguity, or a missing output is
an explicit unverified/failed state, never a silent fallback.

Canonical capture starts before the journey mutation, drains older frames, then
accepts only a desktop frame whose QPC `LastPresentTime` is at or after the
correlated TExFlow displayed-state marker. It records output/adapter identity,
mode, rotation, color space/HDR state, QPC, accumulated frames, coalescing,
protected-content flag, cursor state, DPI, z-order, DWM visible frame bounds,
popup-union crop, and raw/encoded SHA-256. The target window is wholly on one
output for canonical screenshots; cross-monitor transitions are exercised but
captured per output without inventing synchronized pixels. The cursor is moved
to a declared neutral point in the disposable session. Visual trials run only
in a sealed disposable local-QA account with generated fixtures, a known blank
desktop, notifications/focus-assist surfaces and account/cloud sync disabled,
no unrelated app window, and a pre/post inventory of visible top-level windows.
The controller and a bounded metadata scanner reject a candidate that exposes
an unexpected window/title, notification, account identifier, or non-fixture
content before it can enter the evidence pack. Fix the environment and rerun
that trial; never redact such a frame and present it as canonical raw evidence.
Full-output raw evidence
is retained only after that gate; a crop uses physical `DWMWA_EXTENDED_FRAME_BOUNDS` plus the visible
owned-popup union and preserves its coordinates.

A known-pixel/rotation/crop fixture calibrates each output and format before the
campaign. SDR BGRA data is encoded with the built-in WIC PNG encoder and decoded
again to prove the encoded artifact. A high-color row retains the raw surface
and color metadata plus an explicitly versioned HDR-to-sRGB tone-mapped PNG; an
SDR conversion cannot be presented as full-gamut proof. This proves compositor
pixels, not physical-panel colorimetry.

Screenshots run in dedicated visual trials after the state oracle and outside
startup, latency, idle, energy, and memory measurement intervals. WGC may be a
diagnostic cross-oracle for a fully visible isolated window, but cannot close
Windows 10 popup/overlay or visible-desktop coverage. `PrintWindow`, BitBlt or
screen-DC copies, app-exported buffers, and browser screenshots are prohibited
as native acceptance evidence. A disagreement between capture paths blocks the
affected state until explained and protected by a regression fixture.

## Task 7 (T0.2g): Build measurement harness and run native black-box QA

**Files:**

- Create `native/zig/src/bench/events.zig`
- Create `native/zig/src/bench/runner.zig`
- Create `native/zig/src/bench/presentmon_csv.zig`
- Create `native/zig/src/bench/wpa_csv.zig`
- Create `native/zig/src/bench/machine.zig`
- Create `native/zig/src/bench/matrix.zig`
- Create `native/zig/src/bench/evidence_pack.zig`
- Modify `native/zig/qa/journey.zig`
- Modify `native/zig/qa/capture.zig`
- Modify `native/zig/qa/capture_dxgi.zig`
- Modify `native/zig/qa/capture_wic.zig`
- Create `native/zig/fixtures/t0_2/campaign_workloads.zig`
- Create `native/zig/qa/campaign/t0_2_campaign.json`
- Create `native/zig/qa/campaign/reference_machines.json`
- Create `native/zig/manifests/texflow.wprp`
- Create `native/zig/tests/bench_parser_test.zig`
- Create `native/zig/tests/bench_matrix_test.zig`
- Create `native/zig/tests/evidence_pack_test.zig`
- Modify `native/zig/tests/capture_test.zig`
- Create `native/zig/tests/qa_oracle_test.zig`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify `build.zig`, `.github/workflows/zig.yml`, `docs/development.md`

**Acceptance ownership:** As a direct-evidence owner, close A05, A14-A16, A19,
and Task 7's CI/artifact-scope portion of A17. As the integrated revalidation
overlay, rerun A04 and A06-A13 rather than borrowing their earlier task results.
No row may be omitted under an undefined "as applicable" label, and a Task 7
rerun cannot replace a missing direct-owner result.

- [ ] Generate hostile WPR/WPAExporter/PresentMon CSV fixtures in Zig: BOM,
  quoted delimiters/newlines, locale decimals, missing/duplicate/reordered
  columns, `NA`, infinities, overflow, mixed PID, timestamp discontinuity,
  dropped provider events, wrong adapter/trial, and truncated files. Strict
  parsers must reject ambiguous or incomplete trials. Freeze the nearest-rank
  percentile rule (`ceil(p*N)`, one-based sorted rank), units, rounding, warmup,
  outlier policy (report, never delete), and p50/p95/p99/worst/raw output before
  measuring the implementation.
- [ ] Implement the canonical content-addressed evidence manifest/copy verifier.
  Test missing/truncated/swapped files, digest/count/path collision, interrupted
  copy, same-volume aliases, two partitions/mount points or storage-pool extents
  that share a physical disk, unavailable/ambiguous disk-extents identity,
  restore corruption, secret/user-content scanner failure, and retention
  metadata. A summary cannot claim a raw
  artifact whose two authorized durable copies have not been rehashed.
- [ ] Pin/fetch PresentMon only into the QA cache; verify its digest and version.
  Detect the already installed `wpr.exe` and `wpaexporter.exe`, record versions,
  validate the WPR profile, and fail a metric closed when collection/export or
  privileges are unavailable. Do not self-elevate.
- [ ] Implement a Zig controller that restores the exact per-sample clean or
  established allowlisted TExFlow/project-state fixture against the sealed QA
  user base while no TExFlow process or mapped state handle remains, verifies
  its path/ACL/inventory/digest and absence of product writes elsewhere, creates unique run caches,
  starts/stops WPR, launches TExFlow with exact
  `--trace-trial=<32 lowercase hexadecimal digits>`, runs native journeys,
  runs PresentMon, exports tables, validates correlations, aggregates the entire
  TExFlow process tree, retains raw artifacts, and writes a machine-readable
  result plus human summary. Resolve every external tool by canonical absolute
  path plus identity/hash/version, pass typed argv without a shell, use a minimal
  environment and bounded stdout/stderr, and test each tool's actual option
  parser. External tools are orchestrated; no PowerShell/Python benchmark logic
  becomes the oracle.
- [ ] Implement and independently test the campaign generator/verifier and
  privacy-safe machine fingerprint. Materialize every row and named performance
  cell from the preregistration contract; mutation tests must catch a missing
  level/pair/triple/edge, duplicate or unsatisfiable row, changed workload,
  selective replacement, pooled stratum, hidden serial/SID/MAC/hostname, and a
  machine that does not match its frozen slot. It must also reject an unsealed
  or mutated physical OS image, undefined clean/established fixture, pending
  reboot/update, enabled hiberboot, mismatched full-boot method, unchanged or
  ambiguous boot identity, changed login/desktop-ready/launch-offset policy, and
  a second sampled launch in one boot. Review, commit, and push the immutable
  campaign plus exact reference profiles before a closed campaign;
  for a provisional campaign, commit the diagnostic host and explicit missing
  slots before its first sample. Use
  `test(native): preregister T0.2 feasibility campaign`.
- [ ] After that preregistration commit is pushed and its source-set digest is
  revalidated, run `t0-2-repro` to obtain two byte-identical complete
  ReleaseSafe install roots. Generate a canonical candidate receipt containing
  the complete `path/type/size/SHA-256` manifest digest, every role PE digest,
  and the shared build identity; select exactly one verified root for the
  campaign. Keep the root owner-only/read-only, rehash its complete inventory
  before every named cell, and after each launch match canonical process image
  path, volume/file ID, SHA-256, and the independent loaded-module receipt.
  A changed, extra, missing, or same-build-identity/different-binary image
  invalidates the whole cell. The generated receipt is retained as output
  evidence and cannot alter source, fixtures, thresholds, or verdict logic.
- [ ] Define interactive startup exactly: the first non-placeholder editor/shell
  frame is displayed, restored text/selection/commands shown are real, and a
  harness keystroke mutates the source model. Reject splash/blank swap chain,
  created-only HWND, painted/display-only fixture text, or background discovery being mistaken
  for interactive. A warm trial follows one unmeasured priming launch, full
  process-tree termination, and five seconds of quiescence with OS caches intact;
  a cold trial follows an independent full-kernel boot under the preregistered
  hiberboot-ineligible contract with no prior TExFlow launch.
- [ ] Use ETW process-start as time zero and displayed-frame evidence from
  PresentMon. Correlate input events, Scintilla mutation, dirty submit, present,
  and displayed frames by monotonic timestamp/trial/version. Report editor child
  HWND and composed shell/PDF lanes separately. Validate supported PresentMon
  `MsAllInputToPhotonLatency` results for both lanes against a timestamped visual
  toggle. If the field is `NA` or correlation fails, label the software metric
  `input-to-displayed-frame` and use WPR/DWM plus a calibrated high-speed camera
  or latency instrument; retain raw sensor/capture data and error bounds.
- [ ] Make `journey.zig` use independent process discovery, UIA, `SendInput`,
  clipboard, window-management APIs, and exact state assertions. Cover launch,
  focus/keyboard-only navigation, large-file open, jump/scroll/edit/undo,
  theme/DPI/resize, PDF open/search/select/zoom/rotate, rapid edits/cancellation,
  worker crash/recovery, occlusion/minimize/resume, device rebuild, and shutdown.
  Exclude destructive external actions and production/user data.
- [ ] Implement the visible-capture contract with Zig-owned
  `IDXGIOutput5::DuplicateOutput1` orchestration and WIC encoding. Unit/fixture
  tests must falsify channel order, stride, rotation, crop/DPI virtualization,
  stale-QPC acceptance, accumulated/lost frames, protected content, finite-wait
  cancellation, access-loss recreation, RDP disconnect, HDR-to-SDR labeling,
  PNG round-trip, and raw/encoded digest changes. Calibrate every active output,
  capture only outside timed trials in the sealed disposable visual account,
  assert the expected top-level-window/notification/account-state inventory,
  reject non-fixture exposure before retention, and attach complete state metadata. Review
  all confirmed visual states for overlap, clipping, focus, contrast, density,
  hierarchy, stale content, resize jitter, popup/caption behavior, and capture
  disagreement. If an HTML report is emitted, browser-test its routes, filters,
  missing-artifact states, console, network, keyboard, zoom, and screenshots;
  that browser pass is report QA only.
- [ ] Run deterministic 10,000-edit tests and 30-page PDF stress; fail on final
  hash mismatch, lost latest version, drop/coalescing above budget, queue growth,
  handle/thread/GPU leak, restart storm, or memory budget. Record steady-state
  after a declared settling interval without hiding transient peaks.
- [ ] Sample memory after five minutes of an unchanged visible state and through
  a ten-minute window. Sum private working set and private commit across every
  TExFlow process; separately report shared pages without double-counting the
  same section, live section committed/mapped bytes, peak system/private commit,
  handles, threads, and workers. Assert <=128 MiB combined live PDF-input
  sections, <=4 MiB live one-shot tile-transfer sections, <=2 MiB private tile
  staging, and the selected <=32/48/64 MiB resident GPU tile LRU; prove
  cancellation/crash retires transfer objects and returns all categories toward
  steady-state. Forbid working-set trimming and preload tricks.
  Account app-owned
  committed/resident GPU allocations per heap/resource and adapter (using
  D3DKMT/ETW or an equivalently validated OS source), with DWM/driver cost shown
  separately and `P`/`T` inputs derivable from the resource inventory.
- [ ] After declared quiescence, compute aggregate process CPU time divided by
  wall time as percent of one logical processor and analyze ETW timer/wakeup
  activity for at least the defined idle window. Inventory both TExFlow and
  child-control timer paths. Record a visible focused Scintilla system-caret
  blink separately; while minimized or fully occluded, verify after quiescence
  that no render, polling, caret, dwell, scroll, widen, or idle-styling timer
  wakes, no timer-resolution escalation or hidden worker churn remains, and no
  periodic present occurs. Record foreground versus EcoQoS transitions and
  battery/power state.
- [ ] Execute every preregistered mixed-strength row, every 30-trial `P0`-`P8`
  cell, and the conditional functional/visual `V0-hdr` row exactly as declared.
  Randomize only through the committed seed
  algorithm; persist actual order before each launch. Record adapter/output LUID,
  driver/WDDM, shell renderer, editor renderer, mode, power, thermal, and profile identity to prove the selected
  path. A 125%-DPI or variable-refresh diagnostic may be appended under a new
  non-gating ID, but it cannot replace or be pooled with a mandatory row.
- [ ] Run OS-level DPI, high-contrast, reduced-motion, IME, clipboard, and RDP mutations only
  in a disposable QA account/session or controlled physical campaign with a
  captured before-state and guaranteed restoration. App-only test overrides are
  useful deterministic coverage but cannot be labeled proof of Windows reaction.
- [ ] Run each `P0-baseline` cold distribution only through independent clean
  full-kernel boots with hibernation/Fast Startup disabled and verified, a
  persisted pre-boot queue, the frozen shutdown/login/desktop-ready/post-logon
  offset method, independently checked `LastBootUpTime`/`GetTickCount64`, and
  one sampled launch per boot. Preserve
  power-off and Restart-fallback cells separately. Hybrid shutdown, hibernate,
  resume, app restart, standby, cache deletion, VM snapshot/reset, affinity, or
  a second launch in that boot cannot be labeled cold evidence. A failed or
  invalid sample fails and restarts the whole named cell after repair.
- [ ] Run both supported OS images on both frozen physical reference machines.
  If either machine, OS image, display mode, or reference identity is absent,
  current-host diagnostics may finish but A15 and T1 admission remain
  `UNVERIFIED-HARDWARE`; no current-host, CI, WARP, VM, or artificial resource
  restriction substitutes for the missing stratum.
- [ ] For every controlled RDP cell, record host/client builds, independent
  client identity, RTT distribution, transport/codec, client refresh and
  resolution, session reconnects, and capture status. Require host input/state
  gates, zero polling/lost-current state, and no more than one additional refresh
  period of app-attributable latency versus a native text control in the same
  session rather than applying the local photon threshold.
- [ ] Run the built-in Windows Narrator on both OS lanes with a predeclared
  keyboard-only operator script covering orientation, pane/status announcements,
  editor caret/selection/range reading, diagnostics, PDF alternatives, focus
  order, errors, and recovery. Record expected-versus-observed utterances and
  navigation; the independent UIA client is corroboration, not substitution.
  Run one real installed non-Latin IME on each OS lane through composition,
  commit, cancel, reconversion, caret, undo, save, and restart. A second screen
  reader is optional only when already installed; Narrator, the real IME, and
  RDP are mandatory and an unavailable lane blocks closed coverage.
- [ ] On both OS lanes in the final closed pass, rerun the pinned, pre-provisioned
  Accessibility Insights Entire-app automated checks and FastPass tab-stops
  journey over every preregistered steady UI state. Keep the signed-tool identity
  and `.a11ytest` output in the raw evidence pack, reconcile every result with
  the independent Zig UIA client and Narrator, and treat a tool crash, forced
  update, missing state, or unexplained disagreement as unverified. Exclude the
  tool from all timed/resource trials and from TExFlow distribution inventory.
- [ ] When every required environment is available, run one closed-coverage full
  campaign after the last repair with fresh profiles/caches and a new committed
  order seed.
  Compare expected/actual row IDs, first-30 sample counts, raw hashes, invalid
  trials, and per-stratum verdicts. Any Medium+ finding resets the campaign
  streak to `0/1` and requires repair plus a new full campaign. If a required
  environment is unavailable, run one current-host harness campaign only as
  provisional implementation evidence; label final admission streak `0/1`
  rather than “clean”. Commit and push results as
  `test(native): record measured T0.2 feasibility campaign`.

**Kill switch:** Stopwatch-only startup, self-reported display timing, aggregate
memory that omits workers, PresentMon `NA` coerced to a number, simulated
low-tier proof, software display timing mislabeled as photon timing, destructive
mutation of the user's active Windows profile, post-result matrix edits,
selective sample replacement, cross-stratum pooling, missing raw samples,
`PrintWindow`/screen-DC/app-framebuffer screenshot proof, or native behavior
inferred from browser QA invalidates the campaign.

## Task 8 (T0.2h): Review, evidence, and architecture admission

**Files:**

- Create `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-native-feasibility.md`
- Create `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-artifacts.json`
- Modify `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`
- Modify this plan only for factual as-built deviations with an appended ADR;
  never rewrite failed criteria after seeing results. Complete every such edit
  before the candidate source-set freeze below. Any later non-evidence edit
  creates a new source identity, resets the final streak, and requires complete
  rebuild/QA/measurement; only `docs/superpowers/evidence/**` may change after
  freeze without changing the measured source set.

**Acceptance ownership:** Produce direct Task 8 evidence for A01, A03, A15,
A17, and A18, where the matrix names T0.2h (including `all`). Independently own
the final replay/admission overlay for A01-A19. This final review cannot replace
missing direct-owner or Task 7 integrated evidence and cannot convert an
unverified row into a pass.

- [ ] Freeze the canonical candidate source set, export exactly that set to a
  clean temporary source root, and verify every path/mode/blob entry so
  untracked files and later evidence edits cannot contaminate measurements.
  Run the Zig-owned canonical source-set verifier before the build, inject the
  exact source-set digest, rehash the canonical `tools/zig/native-deps.json` bytes,
  and require the UI plus every worker's first event to equal the independently
  recomputed common build identity before retaining any trial. After the
  eventual commit/push, recompute the same source set from that commit and
  require equality; do not rebuild a different candidate and inherit the prior
  verdict. Prove the build, packaging, native QA, and benchmark graphs cannot
  read from the excluded evidence namespace.
- [ ] Require the final reproducibility replay to produce two byte-identical
  complete payloads and a new candidate receipt. Bind the final evidence to its
  complete-payload manifest digest, every role PE digest, shared build identity,
  and per-cell root/process/module revalidation records. A build identity alone
  is not binary identity, and T0.2's unsigned feasibility images must never be
  described as signed-package evidence.
- [ ] Re-run dependency acquisition audit, all portable and Windows tests,
  Debug/ReleaseSafe/diagnostic ReleaseFast ABI probes, reproducible builds, PE
  audit, native runtime journeys, isolation negatives, PDF corpus, SQLite fault
  matrix, campaign-coverage/capture calibration tests, benchmark parsers,
  resource stress, mandatory Narrator/IME/RDP journeys, and affected legacy
  checks from fresh caches and profiles.
- [ ] Perform adversarial review across correctness, accessibility, Unicode/IME,
  security, durability, performance methodology, visual craft, CI, licensing,
  supply chain, error recovery, and scope. Map every finding to severity and an
  acceptance row. On any Medium+ finding, fix it in the working tree, reset the
  final streak, and restart the complete final pass before creating a corrective
  commit. Commit and push only the resulting `1/1` clean state; if required
  post-push CI fails, reopen the task, reset the streak, and repair/repeat rather
  than calling that commit green.
- [ ] Obtain one final full closed-coverage pass after the last repair with no
  new Medium+ gap. It cannot reuse mutable outputs, profiles, DBs, dependency
  extraction, process state, trial ordering, or verdicts from before the repair.
- [ ] Write the evidence manifest with: source commit/tree; evidence-parent and
  evidence commit relationship; source-set/build identity; complete-payload
  manifest and role-PE digests; dependency/tool locks; commands; CI run IDs;
  preregistration/matrix/coverage hashes; raw artifact hashes/counts; redacted
  frozen machine/adapter/driver/display/power identity; per-cell distributions
  and budgets; calibrated screenshot inventory and capture metadata;
  Narrator/IME/RDP operator evidence; crash/fault matrix; findings ledger;
  unverified/failed rows; quality-streak transitions; and exact T1 admission
  decision. Commit the bounded redacted canonical artifact inventory (logical
  IDs, sizes, hashes, copy-receipt hashes, and retention deadline; no secret
  paths or credentials). Reopen both raw-evidence copies, restore into a fresh ignored root,
  and rehash the complete canonical manifest before finalizing A18; record the
  non-secret storage identities and retention deadline, never credentials.
- [ ] Separate `architecture-admitted` from `release-qualified`. T0.2 may admit
  the native architecture only against its defined feasibility evidence; signed
  MSIX/portable distribution, signer, installer size, update, clean uninstall,
  release-machine reruns, and the protected PDFium shipping rebuild from the
  T0.2-verified graph plus ABI/corpus equivalence and Authenticode remain visibly
  open product gates for T5.2.
- [ ] Avoid the self-referential evidence trap: the document binds the tested
  source commit/tree and its own parent/commit relationship; it never claims its
  own precomputed blob/hash equals a later edited value.
- [ ] Count the final pass only when every mandatory row, matrix cell, physical
  machine/OS stratum, cold distribution, Narrator/IME/RDP journey, and capture
  oracle is closed. A provisional/current-host rerun never increments the final
  admission streak. If every mandatory row passes, commit and push as
  `docs(evidence): admit TExFlow T0.2 native architecture`. If physical low-tier,
  physical mainstream, either supported OS image, cold-boot, Narrator, real IME,
  RDP, or other mandatory evidence is unavailable, use `docs(evidence): record
  provisional TExFlow T0.2 results`, keep the final streak at `0/1`, set
  admission to `BLOCKED` with the precise `UNVERIFIED-*` reason, and do not begin
  T1.

## 10. Planned build-step contract

Names become public developer workflow and must stay stable after T0.2 unless
an ADR replaces them.

The existing T0.1 `test`, `abi`, `miscompile-corpus`, and `simd-corpus` steps
remain callable and green in every supported host/optimization lane, and the
former installed-console smoke becomes stable test-only `t0-1-smoke`. On an x64
Windows target, the default install graph emits exactly GUI-subsystem
`TExFlow.exe` plus headless `TExFlow.PdfWorker.exe` and
`TExFlow.ScienceWorker.exe` and their admitted runtime data/DLL closure; the
test-only ABI library is excluded. On non-Windows targets the install graph is
empty and named portable test steps build only cache/test artifacts. A step
whose contract is Windows-native rejects
a non-Windows target precisely rather than silently skipping, while
`t0-2-ci` selects and reports the explicit portable subset on Linux and the
native subset on Windows.

| Command | Contract |
| --- | --- |
| `zig build t0-1-smoke` | Portable test-only replacement for the retired console smoke; asserts exact `TExFlow toolchain ok` known answer and installs no executable. |
| `zig build t0-2-repro` | Zig-owned two-clean-build/offline controller over separate exact product-install and test-artifact manifests. It accepts only a sealed Windows detached-NIC or Linux network-none runner after interface/route/proxy/process preflight and a zero-byte negative fetch canary; it never mutates host networking. Windows compares the complete canonical install payload—including every PE, admitted DLL/data/font/resource and notice/license member—and separately compares cache-only `texflow_abi`; Linux requires an empty install graph, compares only the test artifact, and rejects product executables. Task 2's baseline-bound `t0.1-transition` phase is historical/non-admissible; Task 3 removes it from CI/default selection. |
| `zig build deps-test` | Portable lock/extractor unit/property/security tests; no network. |
| `zig build deps-fetch` | The only ordinary locked-archive network step; exact locks and atomic cache activation. |
| `zig build deps-audit` | Offline cache/source/license/inventory and pinned-bundle PDFium provenance verification. |
| `zig build unicode-audit` | Offline deterministic Unicode-17 table regeneration, <=512-KiB footprint check, runtime/table identity, official UAX-15/UAX-29 conformance vectors, and source/archive/member-hash receipt. |
| `zig build deps-reproduce-pdfium -Dphase=resolve\|reproduce -Dallow-network=true -Drepro-root=<absolute-ntfs-path>` | Exceptional no-secret network lane on a qualified >=100-GiB NTFS host. `resolve` emits a no-compile candidate closure; after review, `reproduce` starts in a fresh root, accepts only the tracked receipt hash before GN/compiler launch, and emits binary-equivalence evidence without mutating the lock. |
| `zig build t0-2-unit` | Portable pure-Zig model/protocol/parser/hash tests. |
| `zig build t0-2-native` | Windows native ABI/runtime tests with bounded controller timeouts. |
| `zig build t0-2-security` | IPC peer/ACL/handle/LPAC-token plus AAP-denial, ARAP-residual, exact-role canaries, dedicated-PE recursive-import/live-module closure, effective mitigation-policy queries and negative mutations, access-manifest checks, and the non-admissible regular-AppContainer control. |
| `zig build t0-2-editor-qa` | Separate-process UIA, Unicode, input and IME campaign. |
| `zig build t0-2-pdf-qa` | PDF geometry, corpus, cache, cancellation and worker resilience campaign. |
| `zig build t0-2-data-qa` | Ledger model, VFS fault/process-kill, contentless search protocol/rebuild/cancel, and native hostile-search UI campaign. |
| `zig build t0-2-campaign-verify` | Offline canonical preregistration, mixed-strength coverage, reference-machine privacy/identity, capture-fixture and immutable-cell checks. |
| `zig build t0-2-bench` | Validated WPR/WPAExporter/PresentMon measured campaign; committed campaign hash, cell ID, machine slot, OS/profile stratum, pass ID, and order seed are required. |
| `zig build t0-2-qa` | Closed current-host native journey and visual evidence; cannot imply low-tier/cold completion. |
| `zig build t0-2-ci` | Deterministic CI-safe aggregate excluding physical/manual/privileged lanes. |

Every step emits a stable machine-readable result with schema version, selected
target/mode, start/end status, executed case count, skipped/unverified cases and
reason, and artifact digests. Exit code zero means all required cases in that
step passed; an unverified required case returns nonzero in admission mode.

## 11. Decision and failure policy

T0.2 chooses a leader only after evidence. The following outcomes cause a
reversible architecture decision, not a relaxed oracle:

| Failure | Required response |
| --- | --- |
| Scintilla build/ABI/UIA/IME fails | Stop editor progression and plan the pinned RichEdit challenger against the same corpus and budgets. |
| Zig container styling cannot remain bounded/correct | Keep plain unstyled text usable, stop editor admission, and compare a separately sandboxed styling design or RichEdit challenger; never attach product Lexilla in the privileged UI as an undeclared shortcut. |
| PDFium digest/provenance/source-reconstruction/ABI/worker-only load gate fails | Reject the exact pin and reopen the PDF ADR; do not fall back to MuPDF while the all-Zig rule forbids the error bridge it requires. |
| Serial PDFium engine breaches correctness, latency, or size | Profile progressive scheduling and required font/data support, then compare challengers under identical isolation and geometry gates; do not conceal failure with unbounded worker processes. |
| Zero-named-capability LPAC or the AAP opt-out cannot be proved, the ARAP residual surface cannot be completely traced/classified, or the required PDF/font/search corpus needs unclassified or unsafe ambient access | Reject worker/PDF admission and reopen the isolation architecture; regular AppContainer, restricted token, Job-only containment, or the experimental Windows 11 sandbox API is diagnostic/challenger evidence only. |
| A dedicated worker PE maps UI/Scintilla/graphics or the other role's closure, lacks a supported mandatory mitigation, disagrees with the independent live-module receipt, or needs a post-result mitigation relaxation | Reject the worker architecture and reopen its dependency/isolation ADR; a shared UI/worker image, weaker flag set, or undocumented module exception is not a fallback. |
| One-shot tile handoff misses latency or memory budgets | Compare the already specified bounded overlapped-pipe copy into UI-private staging on identical traces; never restore shared-memory direct upload or reusable writable sections. |
| SQLite VFS model produces hybrid state | Treat as a durability design failure; do not hide behind `integrity_check` or retries. |
| Flip path misses budgets | Profile queueing, dirty regions, device path, and child/compositor split; composition swapchain is a measured Win11-only challenger, not an assumption. |
| Current host passes but either frozen reference machine/OS stratum is absent | Record provisional result with final streak `0/1` and block T1; do not substitute CI, WARP, VM, affinity, memory caps, or the 32-GiB host. |
| No sealed detached-NIC/network-none runner is available for the two-clean-build oracle | Record `UNVERIFIED-NETWORK-ISOLATION`, keep A01 and the final streak open, and block T1; a clean cache, proxy poisoning, source scan, or absence of observed downloads is supporting evidence only. |
| No qualified PDFium reconstruction host is available | Record A03 unverified and block Task 5/T1; a standard 14-GiB hosted runner, community DLL, or cross-run binary artifact is not a substitute. |

## 12. Authoritative references used by this plan

- Zig 0.16.0 release and downloads:
  <https://ziglang.org/download/0.16.0/release-notes.html>,
  <https://ziglang.org/download/>
- Git hash-function transition and SHA-256 collision-resistance rationale:
  <https://git-scm.com/docs/hash-function-transition>
- Git raw object/index plumbing and global isolation switches:
  <https://git-scm.com/docs/git-cat-file>,
  <https://git-scm.com/docs/git-ls-files>,
  <https://git-scm.com/docs/git>
- Windows VERSIONINFO resource and prerelease/private-build fields:
  <https://learn.microsoft.com/en-us/windows/win32/menurc/versioninfo-resource>
- Microsoft flip model and dirty rectangles:
  <https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model>,
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi/ne-dxgi-dxgi_swap_effect>,
  <https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-1-2-presentation-improvements>
- Frame-latency waitable object:
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_3/nf-dxgi1_3-idxgiswapchain2-getframelatencywaitableobject>
- Composition swapchain challenger:
  <https://learn.microsoft.com/en-us/windows/win32/comp_swapchain/comp-swapchain>
- UIA server/text providers:
  <https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-serversideprovider>,
  <https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-implementingtextandtextrange>,
  <https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-uiautomationtextunits>,
  <https://learn.microsoft.com/en-us/windows/win32/winauto/textedit-control-pattern>,
  <https://learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/ne-uiautomationcore-provideroptions>,
  <https://learn.microsoft.com/en-us/windows/win32/com/creating-the-global-interface-table>,
  <https://learn.microsoft.com/en-us/windows/win32/com/when-to-use-the-global-interface-table>,
  <https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-cowaitformultiplehandles>
- Accessibility Insights for Windows production cross-oracle:
  <https://github.com/microsoft/accessibility-insights-windows/releases/tag/v1.1.2924.01>,
  <https://accessibilityinsights.io/docs/windows/overview/>,
  <https://accessibilityinsights.io/docs/windows/getstarted/automatedchecks/>
- COM apartment/provider threading:
  <https://learn.microsoft.com/en-us/windows/win32/com/choosing-the-threading-model>,
  <https://learn.microsoft.com/en-us/previous-versions/aa359445(v=vs.85)>
- Scintilla/Lexilla releases and direct API:
  <https://www.scintilla.org/ScintillaDownload.html>,
  <https://www.scintilla.org/LexillaDownload.html>,
  <https://scintilla.org/ScintillaDoc.html>,
  <https://sourceforge.net/p/scintilla/bugs/2506/>,
  <https://sourceforge.net/projects/scintilla/files/scintilla/5.6.6/>,
  <https://scintilla.org/LexillaDoc.html>,
  <https://scintilla.org/LexillaHistory.html>
- PDFium source/build, public ABI, threading caveat, and selected binary:
  <https://pdfium.googlesource.com/pdfium/+/refs/heads/main/README.md>,
  <https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdfview.h>,
  <https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_text.h>,
  <https://pdfium.googlesource.com/pdfium/+/refs/heads/main/public/fpdf_progressive.h>,
  <https://pdfium.googlesource.com/pdfium/+/refs/heads/main/PRESUBMIT.py>,
  <https://github.com/bblanchon/pdfium-binaries/releases/tag/chromium/8035>,
  <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline>,
  <https://docs.github.com/en/rest/repos/attestations?apiVersion=2026-03-10>,
  <https://cli.github.com/manual/gh_attestation_verify>,
  <https://cli.github.com/manual/gh_attestation_trusted-root>,
  <https://github.com/cli/cli/releases/tag/v2.100.0>,
  <https://github.com/cli/cli/security/advisories/GHSA-mm27-mwq9-fr5g>,
  <https://github.com/sigstore/root-signing>
- Qualified PDFium/Chromium Windows build resources and GitHub runner capacity:
  <https://pdfium.googlesource.com/pdfium/>,
  <https://chromium.googlesource.com/chromium/tools/depot_tools/+/a0fd6e66af74304c9b4605665435f4e88849e046/README.md>,
  <https://chromium.googlesource.com/chromium/tools/depot_tools/+/a0fd6e66af74304c9b4605665435f4e88849e046/gclient.py>,
  <https://chromium.googlesource.com/chromium/src/+/master/docs/windows_build_instructions.md>,
  <https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job>,
  <https://docs.github.com/en/actions/reference/runners/larger-runners>
- Rejected MuPDF error-boundary challenger:
  <https://mupdf.readthedocs.io/en/latest/reference/c/overview.html>,
  <https://github.com/ArtifexSoftware/mupdf/blob/master/include/mupdf/fitz/context.h>
- Unicode data, segmentation, normalization, BiDi, security, and license:
  <https://www.unicode.org/versions/Unicode17.0.0/>,
  <https://www.unicode.org/Public/17.0.0/ucd/UCD.zip>,
  <https://www.unicode.org/reports/tr29/tr29-47.html>,
  <https://www.unicode.org/reports/tr15/tr15-57.html>,
  <https://www.unicode.org/reports/tr9/tr9-51.html>,
  <https://www.unicode.org/reports/tr39/tr39-32.html>,
  <https://www.unicode.org/license.txt>
- Rejected/runtime-only Unicode challengers:
  <https://unicode-org.github.io/icu/userguide/boundaryanalysis/>,
  <https://unicode-org.github.io/icu/userguide/icu_data/>,
  <https://unicode-org.github.io/icu/userguide/icu_data/buildtool.html>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winnls/nf-winnls-normalizestring>,
  <https://learn.microsoft.com/en-us/windows/win32/intl/displaying-text-with-uniscribe>,
  <https://github.com/JuliaStrings/utf8proc/blob/master/utf8proc.h>,
  <https://libs.suckless.org/libgrapheme/>
- SQLite release, limits, hardening, memory, WAL, backup, threading, and
  crash-testing background:
  <https://sqlite.org/changes.html>,
  <https://www.sqlite.org/fts5.html>,
  <https://www.sqlite.org/security.html>,
  <https://www.sqlite.org/limits.html>,
  <https://www.sqlite.org/compile.html>,
  <https://www.sqlite.org/c3ref/c_limit_attached.html>,
  <https://www.sqlite.org/c3ref/hard_heap_limit64.html>,
  <https://www.sqlite.org/c3ref/progress_handler.html>,
  <https://www.sqlite.org/c3ref/busy_handler.html>,
  <https://www.sqlite.org/threadsafe.html>,
  <https://www.sqlite.org/pragma.html#pragma_synchronous>,
  <https://www.sqlite.org/wal.html>,
  <https://sqlite.org/backup.html>, <https://sqlite.org/testing.html>
- LPAC/AppContainer, process attributes, and Job Objects:
  <https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer>,
  <https://learn.microsoft.com/en-us/windows/win32/secauthz/appcontainer-isolation>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-token_information_class>,
  <https://chromium.googlesource.com/chromium/src/+/HEAD/docs/design/sandbox.md#less-privileged-app-container-lpac>,
  <https://devblogs.microsoft.com/oldnewthing/20220502-00/?p=106550>,
  <https://learn.microsoft.com/en-us/windows/apps/develop/communication/sharing-named-objects>,
  <https://learn.microsoft.com/en-us/windows/win32/secauthz/createprocessinsandbox>,
  <https://learn.microsoft.com/en-us/windows/win32/fileio/file-access-rights-constants>,
  <https://learn.microsoft.com/en-us/windows/win32/fileio/file-security-and-access-rights>,
  <https://learn.microsoft.com/en-us/windows/win32/secauthz/security-descriptor-control>,
  <https://learn.microsoft.com/en-us/windows/win32/secauthz/automatic-propagation-of-inheritable-aces>,
  <https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-deleteappcontainerprofile>,
  <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute>,
  <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessmitigationpolicy>,
  <https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags>,
  <https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-assignprocesstojobobject>,
  <https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects>
- Process launch, DLL search, pipe identity, and CNG randomness:
  <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw>,
  <https://learn.microsoft.com/en-us/windows/win32/sysinfo/handle-inheritance>,
  <https://learn.microsoft.com/en-us/windows/win32/dlls/about-dynamic-link-libraries>,
  <https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-entry-point-function>,
  <https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-setdefaultdlldirectories>,
  <https://learn.microsoft.com/en-us/windows/win32/dlls/dynamic-link-library-security>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeserverprocessid>,
  <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessid>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew>,
  <https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes>,
  <https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights>,
  <https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptgenrandom>,
  <https://chromium.googlesource.com/chromium/src/+/main/docs/design/sandbox.md#process-mitigation-policies>
- Cryptographic/data canonicalization standards:
  <https://www.rfc-editor.org/rfc/rfc2104>,
  <https://www.rfc-editor.org/rfc/rfc5869>,
  <https://www.rfc-editor.org/rfc/rfc7493>,
  <https://www.rfc-editor.org/rfc/rfc8785>,
  <https://www.rfc-editor.org/rfc/rfc9562>
- File-mapping/handle lifetime, synchronization, pipe fallback, and private D3D upload:
  <https://learn.microsoft.com/en-us/windows/win32/memory/file-mapping-security-and-access-rights>,
  <https://learn.microsoft.com/en-us/windows/win32/memory/sharing-files-and-memory>,
  <https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-mapviewoffile>,
  <https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-unmapviewoffile>,
  <https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-duplicatehandle>,
  <https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-type-read-and-wait-modes>,
  <https://learn.microsoft.com/en-us/windows/win32/api/d3d11_1/nf-d3d11_1-id3d11devicecontext1-updatesubresource1>
- Durable local-copy failure-domain identity:
  <https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ni-winioctl-ioctl_volume_get_volume_disk_extents>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winioctl/ns-winioctl-volume_disk_extents>
- Native capture, frame metadata, color, crop, encoding, and rejected fallback:
  <https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api>,
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_5/nf-dxgi1_5-idxgioutput5-duplicateoutput1>,
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgioutputduplication-acquirenextframe>,
  <https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/ns-dxgi1_2-dxgi_outdupl_frame_info>,
  <https://learn.microsoft.com/en-us/windows/win32/direct3darticles/high-dynamic-range>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect>,
  <https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nf-wincodec-iwicimagingfactory-createencoder>,
  <https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/screen-capture>,
  <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-printwindow>
- Campaign design and mandatory built-in screen-reader evidence:
  <https://www.nist.gov/publications/combinatorial-testing>,
  <https://www.nist.gov/publications/combinatorial-t-way-testing-software-adaptation-design-experiments>,
  <https://learn.microsoft.com/en-us/windows/apps/develop/accessibility>,
  <https://support.microsoft.com/en-us/windows/complete-guide-to-narrator-e4397a0d-ef4f-b386-d8ae-c172f109bdb1>
- Supported Windows lanes and full-boot identity:
  <https://learn.microsoft.com/en-us/windows/release-health/release-information>,
  <https://learn.microsoft.com/en-us/windows/whats-new/extended-security-updates>,
  <https://learn.microsoft.com/en-us/lifecycle/products/windows-11-home-and-pro>,
  <https://learn.microsoft.com/en-us/windows/win32/power/system-power-states>,
  <https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/fast-startup-causes-system-hibernation-shutdown-fail>,
  <https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options>,
  <https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem>,
  <https://learn.microsoft.com/en-us/windows/win32/sysinfo/time-functions>
- ETW/WPR/WPAExporter and PresentMon:
  <https://learn.microsoft.com/en-us/windows/win32/etw/process>,
  <https://learn.microsoft.com/en-us/windows-hardware/test/wpt/wpr-command-line-options>,
  <https://learn.microsoft.com/en-us/windows-hardware/test/wpt/exporter>,
  <https://github.com/GameTechDev/PresentMon/blob/main/README-ConsoleApplication.md>
- Framework challengers:
  <https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/deploy-unpackaged-apps>,
  <https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/self-contained-deploy/deploy-self-contained-apps>,
  <https://doc.qt.io/qt-6/windows-deployment.html>,
  <https://doc.qt.io/qt-6/accessible.html>
