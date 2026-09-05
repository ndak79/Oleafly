# T1.1b Editor Buffer Revision and Dirty-State Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or
> superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Add a portable editor-buffer model that tracks exact source identity,
contiguous revisions, dirty/conflicted/missing state, encoding/newline policy,
and an ordered edit journal without copying the whole document on every edit.

**Scope boundary:** This slice does not attach Scintilla, watch the filesystem,
write files, merge external changes, compile, or create `.texflow` metadata.
It provides the narrow Zig value that the later UI and save slices can consume.

**Architecture decision:** Use a piece-table source value: immutable original
bytes plus an append-only inserted-byte buffer and compact piece descriptors.
Edits split/reuse pieces and append inserted bytes; they do not flatten the
document or duplicate the full source. Current-content hashing is lazy and
invalidated by an edit, so normal typing stays off the full-document hash path.

Decision-quality review considered five challenger rounds:

1. Full `ArrayList(u8)` replacement is simplest but copies the document per
   edit and violates the source-model performance constraint.
2. Gap buffer is fast for local edits but becomes a second mutable editor state,
   conflicting with Scintilla as the sole mutable UI endpoint.
3. Piece table preserves the original bytes, makes inserted storage append-only,
   and keeps the Zig value derived and journalable; it is the current leader.
4. Rope/AVL chunks improve arbitrary large-document edits but add balancing,
   pointer/lifetime, and snapshot complexity before Scintilla integration exists.
5. Memory-map/COW storage complicates Windows file lifetime and cannot provide a
   safe portable edit journal. Two final sensitivity passes (latency-first and
   maintenance-first) keep the piece table as the best reversible choice.

The switch condition is explicit: if later real Scintilla traces show sustained
piece fragmentation above a bounded threshold or snapshot latency misses the
T1.2 budget, compact during bounded idle time or replace the descriptor store
behind this interface; callers must not depend on the representation.

**Spec:** `docs/superpowers/specs/2026-09-03-oleafly-zig-scientific-ai-ide-design.md`,
sections 8, 9, 23.1, and 24.

## Acceptance oracle

- Attach accepts valid UTF-8 source bytes, preserves a UTF-8 BOM, detects the
  newline policy, and starts at revision zero with equal saved/current hashes.
- Every accepted edit uses exactly `revision + 1`; stale or skipped sequences
  fail without mutating content, journal, hash, or state.
- Edit ranges are validated against the logical text excluding a BOM. Inserted
  bytes must be valid UTF-8; deleted bytes are represented by the journal.
- A successful edit increments revision, marks the buffer dirty, invalidates
  only the lazy current hash, and records exact sequence/range/length metadata.
- Edits made while the buffer is `conflicted` or `missing` remain editable for
  recovery, but preserve that state; no edit silently resolves an external
  conflict or recreates a missing file.
- Materialization reproduces exact bytes, including the original BOM and
  existing newline bytes; it is the explicit snapshot operation, not the edit
  hot path.
- `markSaved` accepts only a hash equal to the current materialized content;
  mismatches leave the buffer dirty. A matching hash makes a clean/dirty buffer
  clean and records the saved revision; conflicted/missing buffers reject the
  transition until a later merge/reload slice explicitly resolves them.
  Conflicted and missing states are explicit transitions.
- `deinit` releases every owned allocation; failed edits and failed saves do not
  leak or partially mutate the buffer.

## Task 1: TDD tests and portable module

**Files:**

- Create: `native/zig/src/app/editor_buffer.zig`
- Create: `native/zig/tests/editor_buffer_test.zig`
- Modify: `build.zig` to register `editor_buffer` and
  `t1-1b-editor-buffer-test/check` steps in the model aggregate
- Modify: `docs/superpowers/evidence/2026-09-04-oleafly-t0-2-worklog.md`

**Public interfaces:**

- `Buffer.attach(allocator, canonical_path, disk_bytes) !Buffer`
- `deinit`, `applyEdit(sequence, start, deleted_len, inserted)`
- `materialize(allocator) ![]u8`
- `currentHash() ![32]u8`, `savedHash() [32]u8`
- `markSaved(hash) !void`, `markConflicted()`, `markMissing()`
- `path()`, `revision()`, `savedRevision()`, `textLength()`, `state()`,
  `encoding()`, `newlinePolicy()`, `journal()`

### [x] Step 1 — Write failing tests

Cover BOM/CRLF detection, exact initial hashes, insert/delete materialization,
contiguous sequence enforcement, stale/skipped sequence rejection, invalid UTF-8
and range rejection, lazy hash refresh, save-hash mismatch/acceptance, sticky
conflicted/missing states, and allocator-clean teardown.

### [x] Step 2 — Verify RED

Run:

```text
zig build t1-1b-editor-buffer-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug
```

Expected failure: the `editor_buffer` module and public contract do not exist.

### [x] Step 3 — Implement the minimum piece-table model

Keep the original text and added bytes owned by `Buffer`; use compact descriptors
that merge adjacent pieces from the same source. Build replacement descriptors
before swapping them so allocation errors preserve the prior state. Keep path,
hash, encoding, newline, and state metadata independent from the piece storage.

### [x] Step 4 — Focused verification

Run:

```text
zig build t1-1b-editor-buffer-test -Dtarget=x86_64-windows-msvc -Doptimize=Debug
zig build t1-1b-editor-buffer-test -Dtarget=x86_64-windows-msvc -Doptimize=ReleaseSafe
zig build t1-1b-editor-buffer-check -Dtarget=x86_64-linux -Doptimize=Debug
```

Linux is compile-only on this Windows host. A Linux test binary is not claimed
as executed unless a Linux runner is available.

### [x] Step 5 — Impact checks and review

Run Windows `t0-2c-models-test`, Linux `t0-2c-models-check`, and Windows
`t0-2c-product-build` at the already admitted optimization levels. Run
`zig fmt --check` and `git diff --check`. Review piece-table range math,
sequence atomicity, BOM/newline round-trip, hash invalidation, and all error
cleanup. Browser QA is not applicable because this is a portable native model.

### [ ] Step 6 — Commit and push

Append evidence, commit as `feat(editor): add revisioned piece-table buffer`,
and push `origin/main` only after the review finds no Medium+ issue. Quality
streak remains `1/1`; any new Medium+ finding resets it.

## Plan review record

- Requirement trace: every T1.1b field in section 8 is mapped to a public
  getter or an explicit future-slice boundary; no filesystem write or UI handle
  leaks into this portable model.
- State-machine review: sequence gaps/stale edits, hash mismatch, and sticky
  conflicted/missing states are rejected or preserved without implicit recovery.
- Performance review: full-document materialization and hashing are explicit
  snapshot/audit operations; the edit path only appends inserted bytes and
  rebuilds compact descriptors.
- Failure review: allocation failure before commit keeps the prior pieces,
  journal, revision, state, and added-byte length unchanged.
- Test/QA review: BOM, newline variants, invalid UTF-8, range boundaries,
  repeated edits, save mismatch, and cross-platform compile evidence are all
  named; browser QA is explicitly not applicable.

After these rounds, no unresolved Medium+ plan gap remained. The only external
review attempt was a Luna max stream that ended with `adapter_eof`, so it is not
counted as a clean external review.
