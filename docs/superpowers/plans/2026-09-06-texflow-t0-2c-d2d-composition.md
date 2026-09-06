# T0.2c Direct2D/DirectWrite composition

## Goal

Add a small native composition layer to the TExFlow shell. Direct2D and
DirectWrite must share the admitted D3D11/DXGI device path, render directly to
the current swap-chain surface, and keep all device-bound resources alive
across frames. The shell remains UI-thread owned and does not gain a worker,
timer, retained scene graph, or second window renderer.

## Acceptance oracle

- `D2D1CreateDevice` is initialized from the D3D11 device's `IDXGIDevice`, and
  one single-threaded `ID2D1DeviceContext` plus one shared `IDWriteFactory` and
  `IDWriteTextFormat` are reused for every frame.
- A frame wraps the acquired `ID3D11Resource` as an `IDXGISurface`, creates a
  target bitmap with BGRA8/premultiplied-alpha properties, draws the shell
  chrome and optional product mark, calls `EndDraw`, detaches the target, and
  releases the temporary surface/bitmap/brush references in all paths. Standard
  native child controls remain the authoritative visual/accessibility source for
  toolbar captions and Project/Source/PDF/Status/Ready labels.
- Composition errors are typed and non-presenting: a failed target creation or
  `EndDraw` cannot reach `Present1`; a device-loss result is surfaced so the
  existing shell rebuild path can retire D2D before D3D resources.
- Resize/rebuild/destroy release composition before the back buffer and D3D11
  device, and a failed initialization leaves no partially owned COM graph.
- Windows Debug and ReleaseSafe native/product tests exercise initialization,
  one real shell draw, teardown, resize/rebuild ordering, the separate-process
  native UIA client, and a deterministic unsupported-target contract. Linux
  remains compile-only; browser QA is N/A because this is a native HWND/D3D
  surface.

## Implementation order

1. Add portable contract tests (RED) for dimensions, target properties,
   draw-state transitions, and error mapping.
2. Add the curated API aliases and `composition_native.zig` implementation;
   cache D2D/DWrite resources and release them in reverse ownership order.
3. Wire composition into shell create/render/resize/rebuild/destroy and link
   only `d2d1.dll` and `dwrite.dll`; extend the product PE allowlist/import
   contract.
4. Run focused Windows Debug/ReleaseSafe, explicit `flip_discard`, Linux
   compile, product PE/runtime, aggregate T0.2c, formatter, and diff checks.
5. Perform lifetime/error/device-loss/privacy/performance review, record direct
   evidence, and commit/push independently.

## Non-claims

This slice does not provide a custom COM UIA provider (the product does expose
standard child controls, and a separate UIA client now verifies them),
DWM-visible capture, DXGI Desktop Duplication/WIC screen-oracle proof, physical
DPI/occlusion/device-loss matrices, WPR/WPA/PresentMon energy measurements, or
the final T0.2c admission. Those remain explicit gates after this composition
bridge.
