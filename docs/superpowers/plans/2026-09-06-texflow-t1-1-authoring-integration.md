# T1.1 Native Authoring Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement this plan task-by-task. Each task must receive a spec-compliance review and a code-quality review before its commit is pushed.

**Goal:** Make the existing T1.1 workspace inventory, revisioned editor buffer, and atomic-save primitives form one real Windows authoring journey: Open Folder → choose a main `.tex` → edit → Save → verified clean state, with safe external-change handling and a deterministic multi-file outline.

**Architecture:** A new `app/authoring_session.zig` owns only portable authoring state and commands. It consumes the existing `workspace.zig`, `editor_buffer.zig`, and `atomic_save.zig` boundaries; it never owns HWNDs or performs UI-thread blocking I/O. A Windows bridge translates native shell command IDs and Scintilla/watcher notifications into typed session events, while injectable picker/watcher interfaces make the journey testable without a browser or a fake filesystem. Workspace inventory becomes conservative: every source read is no-follow and identity-checked, failures are reported instead of silently dropping files, and root/outline decisions are explicit.

**Tech Stack:** Zig 0.16.0, `std.Io.Dir`/`std.Io.File`, SHA-256, the existing native Win32 shell and UIA boundary, Scintilla direct-call seam, deterministic Windows fixture tests, and compile-only Linux checks. No WebView, Rust, JavaScript, network provider, or lossy text conversion is introduced.

---

## Scope and non-goals

This is an internal decomposition of the approved T1.1 roadmap slice, not a new top-level train. It closes the authoring integration gap before T1.2. It includes root discovery, Open Folder command plumbing, selected-file attachment, edit/save sequencing, conservative external-change states, and a bounded multi-file outline. It does not implement TexLab, Tectonic, PDF preview, SyncTeX, research, AI, or a three-way merge UI; those belong to T1.2 and later tasks once this journey is real.

The user-owned untracked plan `docs/superpowers/plans/2026-09-05-texflow-t1-1c-atomic-save.md` is read-only and must not be staged or changed.

## Acceptance oracle

- The native Open Folder control and `Ctrl+O` produce one typed session event; a picker result is canonicalized and rejected if it is not a directory, traverses a reparse point, or is outside the caller-approved boundary.
- Root discovery checks explicit `.texflow/project.toml`/configured root, a bounded magic-root marker, then include relationships and `.tex` candidates. A tie is represented as `needs_main_choice` with deterministic candidates; no source is mutated to persist a choice.
- Inventory reads every admitted regular source with a no-follow handle and records path, identity, byte length, SHA-256, encoding, and an explicit error entry for every unreadable/oversized/invalid file. `catch continue` is not allowed for source inventory.
- The selected main file attaches to one `editor_buffer.Buffer`; all programmatic edits and native edit notifications carry a contiguous sequence. A missing sequence, invalid UTF-8, hash divergence, or foreign path marks the buffer conflicted and prevents save/compile publication.
- Save commands enforce the canonical workspace root and call `atomic_save.save`; only a matching verified receipt may call `Buffer.markSaved`. External bytes changed, target disappeared, or recovery-only status never becomes clean and never overwrites the external file.
- A watcher event is correlated by canonical path and file identity. Clean buffers reload only after a hash/identity check; dirty buffers become `conflicted`; deletion becomes `missing`; overflow triggers bounded rescan and never silently blesses a partial inventory.
- The outline parser follows bounded `\input`, `\include`, and `\subfile`-style references only inside the inventory, records cycles and unresolved/outside-root references, and returns stable depth-first entries sorted by canonical relative path. It never executes TeX or reads arbitrary paths.
- The native product graph imports the session and bridge. Contract tests prove that Open Folder, Save, Compile placeholder, and Recovery buttons no longer only call `requestFrame`; each command emits a typed event and updates observable session state. Browser QA is N/A for this native surface; native runtime/UIA evidence is required when the real product is launched.

## File map

- Modify `native/zig/src/app/workspace.zig`: no-follow per-file reads, file identity/error records, case-insensitive ignored directories, root discovery helpers, and conservative encoding classification.
- Create `native/zig/src/app/authoring_session.zig`: portable project/session state, main-file choice, buffer attachment, sequence validation, save command, and external-change transitions.
- Create `native/zig/src/app/outline.zig`: bounded include/reference parser and deterministic outline/cycle model.
- Create `native/zig/src/platform/windows/authoring_bridge.zig`: typed translation of native command IDs, picker/watcher notifications, and Scintilla edit callbacks; no direct filesystem/compiler work on the window procedure.
- Create `native/zig/src/platform/windows/workspace_picker.zig`: Win32 folder-picker facade plus a test-injectable result interface.
- Create `native/zig/src/platform/windows/workspace_watcher.zig`: Windows notification adapter facade and portable event model; overflow/rescan is explicit.
- Extend `native/zig/tests/workspace_test.zig`: identity, error, root-discovery, encoding, and ignored-directory cases.
- Create `native/zig/tests/authoring_session_test.zig`: Open Folder → main choice → edit → save, stale/external/deleted/overflow branches, allocator cleanup, and root escape cases.
- Create `native/zig/tests/outline_test.zig`: includes, cycles, unresolved/outside-root references, stable ordering, and bounds.
- Create `native/zig/tests/authoring_bridge_test.zig`: command IDs, event translation, sequence gaps, and no-side-effect window dispatch.
- Modify `build.zig`: register new modules/tests and add `t1-1-authoring-test/check` to the existing model aggregate; keep the product target Windows x64-only and Linux compile-only.
- Modify `docs/development.md` and append the evidence worklog with exact commands, skips, and native/browser QA decision.

### Task 1: Harden the workspace inventory and root decision

**Files:**

- Modify `native/zig/src/app/workspace.zig`.
- Extend `native/zig/tests/workspace_test.zig`.
- Modify `build.zig` imports only if new public types require them.

- [x] **Step 1: Add failing tests.** Cover a symlink/reparse source, a hard link, a case-variant ignored directory, unreadable/oversized files, invalid UTF-8, BOM/CRLF, duplicate canonical paths, explicit root marker, include-derived candidates, and deterministic ambiguous candidates. Assert an error record rather than dropped inventory.
- [x] **Step 2: Run RED.** `zig build t1-1a-workspace-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug --summary all` must fail on the new expectations.
- [x] **Step 3: Implement identity-safe reads.** Open each file with `follow_symlinks = false`, stat/hash through the same handle, reject non-regular/reparse/hard-link entries according to the source policy, and append a bounded `InventoryIssue` for a read failure. Fold ignored directory names with ASCII case-insensitivity on Windows; preserve original source bytes and do not normalize text.
- [x] **Step 4: Implement root discovery values.** Expose `RootDecision` (`selected`, `needs_main_choice`, `no_candidate`) with candidate indices and reasons; explicit metadata and bounded magic-root markers outrank include-derived candidates. Do not write `.texflow` or alter project source.
- [x] **Step 5: Run Debug/ReleaseSafe/ReleaseFast Windows tests and Linux compile-only check.** Record every capability skip explicitly.

### Task 2: Connect the buffer and save primitive through a portable session

**Files:**

- Create `native/zig/src/app/authoring_session.zig`.
- Create `native/zig/tests/authoring_session_test.zig`.
- Modify `build.zig` to register `authoring_session` and test imports.

- [x] **Step 1: Write failing journey tests.** Cover opening an unambiguous folder, selecting an ambiguous main, attaching a file with BOM/newline policy, contiguous edits, stale/missing sequence, root escape, save success with receipt/clean state, external-change refusal, and recovery-retained status.
- [x] **Step 2: Run RED.** The session module and event methods do not exist.
- [x] **Step 3: Implement typed session state.** Define `Session`, `SessionState`, `MainChoice`, `EditEvent`, `SaveOutcome`, `ExternalChange`, and `SessionEvent`. `openFolder` consumes an already validated workspace; `attachMain` owns one `Buffer`; `applyEdit` requires the next sequence; `save` calls `atomic_save` then `markSaved` only after matching hash/revision; all owned paths/results have `deinit`.
- [x] **Step 4: Add external-event transitions.** Implement `file_changed`, `file_deleted`, `watch_overflow`, and `rescan_complete`; clean buffers may reload only when identity/hash matches the observed event, dirty buffers become conflicted, and missing files remain missing until an explicit reattach.
- [x] **Step 5: Run focused Windows Debug/ReleaseSafe and Linux compile checks.** Assert no session method calls a native HWND or starts a process.

### Task 3: Build deterministic multi-file outline

**Files:**

- Create `native/zig/src/app/outline.zig`.
- Create `native/zig/tests/outline_test.zig`.
- Modify `build.zig` module/test wiring.

- [x] **Step 1: Write failing fixtures.** Include nested `\\input`/`\\include`, quoted paths, comments, cycles, missing references, outside-root traversal, malformed UTF-8, duplicate edges, and a file-count/byte/depth limit.
- [x] **Step 2: Run RED.** The parser and outline types are absent.
- [x] **Step 3: Implement a bounded lexical reference parser.** Scan UTF-8 source bytes without executing macros; ignore comments and escaped delimiters; resolve only inventory-relative paths with approved `.tex`/`.bib`/`.sty`/`.cls`/`.tikz` kinds. Return `unresolved`/`outside_root`/`cycle` issue values instead of silently dropping edges.
- [x] **Step 4: Implement stable traversal.** Produce `OutlineEntry` records with parent index, path, label, and depth; use deterministic path ordering and a visited set keyed by file identity. Keep the graph immutable after construction.
- [x] **Step 5: Run all outline negative fixtures and compile-only cross-target checks.**

### Task 4: Wire native commands, picker, and watcher events

**Files:**

- Create `native/zig/src/platform/windows/authoring_bridge.zig`.
- Create `native/zig/src/platform/windows/workspace_picker.zig`.
- Create `native/zig/src/platform/windows/workspace_watcher.zig`.
- Create `native/zig/tests/authoring_bridge_test.zig`.
- Modify `native/zig/src/platform/windows/shell_native.zig` only at the command dispatch seam and product state ownership.
- Modify `build.zig` module/product wiring.

- [x] **Step 1: Write failing bridge tests.** Assert control IDs/keyboard accelerators map to `open_folder`, `save`, `compile_request`, `show_recovery`, and `mode_change`; invalid IDs/notifications are ignored; event translation does not open files or call `requestFrame` as a substitute for behavior.
- [x] **Step 2: Run RED.** The bridge and picker/watcher facades are absent.
- [x] **Step 3: Implement injected interfaces.** `WorkspacePicker.pick()` returns a validated path/result; `WorkspaceWatcher` emits typed path/identity/overflow events; the bridge posts events to the UI-owned session queue and schedules a frame only after state changes. The window procedure remains non-blocking and forwards unrelated messages to `DefWindowProcW`.
- [x] **Step 4: Add native folder-picker implementation.** Use the existing Win32 COM boundary and an explicit folder-only dialog; convert UTF-16 to validated UTF-8, reject cancellation as a no-op, and never persist a choice without the session’s explicit command.
- [x] **Step 5: Add watcher adapter contract.** Use a bounded overlapped `ReadDirectoryChangesW` facade on Windows, retain directory/file identity, treat buffer overflow as `watch_overflow`, and close handles on every shutdown path. Non-Windows exposes compile-only stubs.
- [x] **Step 6: Run Windows native bridge tests and product build; run Linux compile-only.**

### Task 5: Integrate the product graph and prove the real journey

**Files:**

- Modify `native/zig/src/main.zig`/`native/zig/src/platform/windows/shell_native.zig` to construct and own the session/bridge without moving filesystem work into the window procedure.
- Extend `native/zig/tests/windows_product_test.zig` or create `native/zig/tests/authoring_product_test.zig` for command/state contracts.
- Modify `build.zig` to import the session/bridge into the product executable and test target.

- [x] **Step 1: Write failing product-contract tests.** Prove Open Folder creates a session, main selection exposes an editor target, edit updates dirty state, Save calls the verified boundary, and stale external bytes keep the buffer conflicted. Prove the product graph—not only isolated tests—contains the session module.
- [x] **Step 2: Run RED.** Existing controls currently only invalidate a frame; the product contract must fail until the real bridge is wired.
- [x] **Step 3: Implement product ownership.** Keep the session behind a narrow event sink owned by the native UI backend; use a worker/IO queue for scans and saves; publish immutable state snapshots to layout/UIA; never hold UI locks across I/O.
- [x] **Step 4: Run a native Windows black-box smoke fixture.** Launch the product with a disposable fixture project, Open Folder, choose main, edit through the editor seam, Save, inspect exact bytes/hash/state, inject an external edit, and verify the next save refuses overwrite. Capture logs and the final session state.
- [x] **Step 5: Run aggregate/product/Linux gates and inspect the PE import graph.** Confirm workspace/session code is in the UI image only and no worker dependency edge is introduced.

### Task 6: Review, evidence, commit, and push

**Files:**

- Modify `docs/development.md` with the native authoring commands and explicit unsupported/fixture boundaries.
- Append `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md` with test counts, black-box evidence, skips, review streak, and remaining external statuses.
- Do not change `docs/superpowers/plans/2026-09-05-texflow-t1-1c-atomic-save.md`.

- [x] **Step 1: Run formatter and focused matrix.** `zig fmt --check` all changed Zig; Windows Debug/ReleaseSafe/ReleaseFast; Linux/aarch64 compile checks; `git diff --check`.
- [x] **Step 2: Run aggregate/product gates.** `t0-2c-models-test`, `t0-2c-product-build`, and `t0-2c-models-check` with `--summary all -j1`.
- [x] **Step 3: Perform two fresh review passes after the last repair.** Pass A checks path/device identity, sequence/dirty/save races, watcher overflow, outline traversal, UI-thread ownership, and allocator cleanup. Pass B checks fidelity to all T1.1 requirements and verifies the product graph really owns the session. Any Medium+ finding resets the slice streak to `0/1`; no commit occurs until one clean pass is recorded.
- [x] **Step 4: Native QA decision.** Browser QA is N/A; native black-box/UIA evidence is mandatory for the real product smoke fixture. Record unverified hardware/remote/PDFium/network statuses without promotion.
- [x] **Step 5: Commit coherent slices and push.** Implementation commits use `feat(editor): integrate native authoring session` (or smaller task-specific messages); evidence/docs is a separate commit; push `origin/main` only after review and gates.

## Plan review record

### Review pass 1 — roadmap and requirement coverage

- T1.1 is treated as an end-to-end slice, not three disconnected primitives: Tasks 1–5 connect inventory, buffer, save, commands, watcher, outline, and the product graph.
- The plan explicitly fixes the audit’s current gaps: no silent `catch continue`, no-follow identity reads, Windows case-folded ignored directories, non-lossy encoding policy, and real `WM_COMMAND` behavior.
- T1.2 is intentionally not started until the product authoring journey is observable; this preserves the approved sequencing without redefining the roadmap.

### Review pass 2 — adversarial and security coverage

- Rejected: reparse/hard-link/root escapes, case/NFD aliases, outside-root includes, sequence gaps, stale external writes, watcher overflow, partial scans, lost notifications, and UI-thread blocking I/O.
- Required falsification: mutate the file after snapshot/preflight, inject a dropped edit event, overflow the watcher buffer, add a symlink/junction, and force allocation failure; each must produce conflict/error/recovery state rather than a green save.
- Native dialog/picker and watcher are interfaces with deterministic fake implementations, so tests do not need credentials, network, browser automation, or destructive host changes.

### Review pass 3 — performance, UX, and evidence honesty

- Inventory, save, and watcher reads run off the UI thread; the UI receives immutable state snapshots and one frame invalidation per observable change.
- All counts, bytes, depth, watcher payload, and queue sizes are bounded; a dirty/conflicted buffer never silently reloads or disappears.
- The plan requires native smoke evidence for Open Folder/edit/save and explicitly labels Linux as compile-only and browser QA as N/A.
- No plan step claims T1.2, PDFium, TexLab, remote CI, network isolation, or full release admission.

No unresolved Medium+ plan gap remains for this T1.1 authoring-integration scope. The later watcher/merge and T1.2 plans remain separate work only after this journey is green.
