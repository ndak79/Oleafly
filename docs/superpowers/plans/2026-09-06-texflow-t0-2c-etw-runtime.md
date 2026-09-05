# T0.2c ETW runtime provider

## Goal

Turn the existing fixed-width render telemetry model into a real, optional
Windows ETW provider without adding a runtime shim or any user/content fields.
The provider must be cheap when disabled, explicit about registration failure,
and owned by the UI thread for the lifetime of the native shell.

## Acceptance oracle

- A stable provider GUID and one binary `EVENT_DESCRIPTOR` write exactly the
  64-byte `windows_telemetry.Event` payload.
- Registration, write, and unregister use the narrow `advapi32` ETW ABI; no
  manifest, source text, paths, paper contents, or secrets enter the payload.
- The shell binds the admitted 128-bit trial ID, emits only after a successful
  or occluded Present, and releases the provider during teardown. ETW failure
  never blocks first-frame startup because tracing is diagnostic-only.
- A native Windows test registers/writes/unregisters; Linux is compile-only.
  The product PE oracle requires the exact ETW imports and allows only the
  existing system DLL set plus `advapi32.dll`.

## Order

1. Add the native provider test first (RED when the provider is absent).
2. Implement the ABI-neutral ETW provider and wire optional shell lifecycle
   plus post-Present emission.
3. Run focused Windows Debug/ReleaseSafe, Linux compile, product PE/runtime,
   aggregate model, formatter, and diff checks.
4. Review payload privacy, handle/lifetime/error behavior, disabled-provider
   cost, and frame outcome ordering; record evidence and commit/push.

## Non-claims

This slice does not claim loss-free WPR/WPA collection, PresentMon correlation,
30-trial measurement, causal security attribution, or Task 7's physical
machine/occlusion campaign. Those remain later T0.2c/T0.2g gates.
