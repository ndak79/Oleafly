# T0.2c native shell controls

## Goal

Bind the deterministic shell semantic contract to a small set of real Win32
child controls so keyboard/UIA clients can discover named actions without
depending on custom-painted pixels. Keep the D3D swap-chain HWND as the sole
renderer and create only compact toolbar/status/pane labels on top.

## Acceptance oracle

- The shell creates named `BUTTON` controls for Open Folder, render mode,
  Compile, Save, and recovery, plus named `STATIC` labels for Project, Source,
  PDF, and Status (with a separate Ready value label).
- All controls are owned by the UI thread, are destroyed with the parent, and
  are laid out from the shared DIP breakpoints without clipping or overlap in
  the supported 760/880/1180 boundaries.
- Buttons expose tab stops and Ctrl-based keyboard accelerators without
  stealing the editor's conventional Ctrl+C shortcut; the recovery button is
  hidden until an error state. Large D3D content remains unobscured except for
  compact labels.
- A separate-process Windows test enumerates child HWNDs and verifies exact
  names/classes, standard caption, PMv2, and clean WM_CLOSE. Linux remains a
  compile-only lane; browser QA is not applicable to this native HWND slice.

## Order

1. Add child enumeration test first (RED).
2. Add resource-literal helper and native control ownership/layout.
3. Run focused native/product Debug and ReleaseSafe, Linux compile, and
   aggregate product checks.
4. Review lifetime, error cleanup, DPI/layout arithmetic, and the rule that no
   feature prose is hardcoded outside the resource table. Record evidence and
   commit independently.

## Non-claims

This slice does not implement server-side COM UIA providers, Direct2D text
composition, Scintilla, or the final capture/accessibility campaign. Those
layers must consume the same names and geometry and still remain T0.2c gates.
