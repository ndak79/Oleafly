# T1.1a Source Workspace Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a portable, read-only Open Folder workspace inventory that canonicalizes the approved folder, discovers LaTeX source files, and identifies deterministic main-document candidates without writing project metadata.

**Architecture:** `app/workspace.zig` owns only canonical workspace identity and a sorted source inventory. It reads a user-approved folder through Zig's `std.Io.Dir`, excludes derived/control directories, classifies source extensions, and detects main candidates from bounded UTF-8 text markers. It does not edit, save, watch, compile, or create `.texflow` files; later T1.1 slices consume its immutable inventory.

**Tech Stack:** Zig 0.16 standard library, `std.Io.Dir`, SHA-256 for content identity, portable unit/integration tests using `std.testing.tmpDir`.

**Spec:** `docs/superpowers/specs/2026-09-03-oleafly-zig-scientific-ai-ide-design.md`, sections 8, 23.1 (T1.1 Source workspace), and 24.

## Global Constraints

- `.tex` remains the source of truth; this slice never rewrites user files.
- Open Folder accepts a normal folder without import or copy and does not write metadata during inspection.
- All paths are canonical absolute paths for identity and slash-normalized relative paths for display.
- Source inventory is deterministic: sorted by UTF-8 relative path, with no duplicate path entries.
- Derived/control directories `.git`, `.texflow`, `build`, `out`, and `target` are excluded from recursive inventory.
- Binary/undecodable files are ignored by source classification, never coerced with replacement characters.
- This is a portable model lane; Windows runtime evidence is required, Linux is compile/test portability evidence.

---

### Task 1: Open Folder and deterministic source inventory

**Files:**
- Create: `native/zig/src/app/workspace.zig`
- Create: `native/zig/tests/workspace_test.zig`
- Modify: `build.zig` to register the module and T1.1a tests in the model test/check aggregate
- Modify: `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`

**Interfaces:**
- Produces `workspace.Workspace.open(allocator, io, absolute_or_relative_path) !Workspace`.
- Produces `workspace.Workspace.deinit()` and `workspace.Workspace.rescan()`.
- Produces `workspace.Workspace.rootPath() []const u8`, `files() []const SourceFile`, and `mainCandidates() []const usize`.
- `SourceFile` contains canonical relative path, `Kind` (`tex`, `bib`, `style`, `class`, `tikz`), byte length, and SHA-256 bytes.
- Later editor slices may use the inventory as a read-only snapshot; no editor pointers or platform handles cross this boundary.

- [x] **Step 1: Write the failing tests**

Create a real temporary folder containing nested `.tex`, `.bib`, `.sty`, `.cls`, `.tikz`, an excluded `.git` file, a binary file, and one deterministic candidate main file. Assert canonical root, sorted slash-normalized inventory, exact kinds/hash/length, excluded directories, deterministic main-candidate ordering, and no `.texflow` file after `open`.

- [x] **Step 2: Run the focused test to verify RED**

Run: `zig build t1-1a-workspace-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug`

Expected: compile/test failure because `workspace` and its `Workspace.open` contract do not exist.

- [x] **Step 3: Implement the minimal workspace module**

Use `std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator)` for canonical root identity, open it with `std.Io.Dir.openDirAbsolute(io, absolute_root, .{ .iterate = true, .follow_symlinks = false })`, recurse with `Dir.walk(allocator)`, skip only the allowlisted derived/control directory names, read bounded source bytes, reject invalid UTF-8 for source classification, compute SHA-256, and sort owned `SourceFile` values by relative path. Detect a main candidate when a UTF-8 `.tex` file contains `\\documentclass` or `\\begin{document}`; never choose a candidate implicitly when the list is empty or ambiguous.

- [x] **Step 4: Run focused Windows tests and Linux compile/test**

Run:

```text
zig build t1-1a-workspace-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug
zig build t1-1a-workspace-test -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe
zig build t1-1a-workspace-check -Dtarget=x86_64-linux -Doptimize=Debug
```

Expected: all focused tests pass; Linux remains a portable filesystem-model lane.

- [x] **Step 5: Run impacted model/product checks**

Run `zig build t0-2c-models-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug`, `zig build t0-2c-models-check -Dtarget=x86_64-linux -Doptimize=Debug`, and `zig build t0-2c-product-build -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe`.

- [x] **Step 6: Review and commit**

Review path traversal, symlink/reparse handling, invalid UTF-8, allocation cleanup, deterministic ordering, and the no-write guarantee. Run `git diff --check`; append evidence with Browser QA marked not applicable for this portable filesystem model; commit as `feat(workspace): add read-only source inventory` and push `origin/main`.
