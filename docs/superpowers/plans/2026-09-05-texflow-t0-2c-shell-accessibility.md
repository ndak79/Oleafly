# T0.2c shell accessibility and telemetry contract

## Scope

Close the remaining portable contract gap in T0.2c for the shell UIA tree and
render telemetry without claiming the later COM/UIA runtime or capture campaign.
The slice must remain allocation-free at runtime, deterministic across Windows
and Linux compile lanes, and consume the existing layout, theme, and resource
contracts rather than duplicating shell prose or geometry rules.

## Acceptance oracle

- A fixed revisioned shell snapshot contains one deterministic root tree with
  Project, Source, PDF, status, splitter, mode, compile, save, and recovery
  nodes; parent links are acyclic and every visible interactive node has a name,
  control type, bounds, state, and appropriate pattern bits.
- Layout reductions follow `app/layout.zig`; no visible interactive bounds are
  smaller than 24 DIP, touch mode uses at least 44 DIP, and unsupported narrow
  windows expose a deterministic recovery/status path instead of clipped panes.
- Names resolve through the versioned English resource table. Missing resources
  fail closed and no module embeds shell prose.
- Telemetry records carry only the locked fields (trial id, PID/TID, QPC,
  adapter LUID, render path, dimensions, dirty pixels, version); serialization
  is fixed-width/deterministic and rejects non-hex trial ids or source-bearing
  values.
- Windows Debug/ReleaseSafe focused tests, Linux compile checks, aggregate
  T0.2c model/product checks, `zig fmt --check`, and `git diff --check` pass.

## Implementation order

1. Write `uia_shell_test.zig` and `telemetry_test.zig` first (RED).
2. Implement `app/uia_shell.zig` and `platform/windows/telemetry.zig` with
   fixed-capacity data and pure validation/serialization.
3. Wire build steps and aggregate edges; run focused and regression lanes.
4. Review the diff for allocator/lifetime, accessibility geometry, resource
   ownership, and privacy leaks; record bounded evidence. Do not mark the full
   T0.2c admission complete until native UIA/capture/ETW campaign evidence also
   exists.

## Explicit non-claims

This slice does not implement a COM UIA provider, native shell child controls,
screen capture, ETW registration, or Task 7's physical-matrix measurements. It
provides the deterministic contract those later runtime layers must consume.
