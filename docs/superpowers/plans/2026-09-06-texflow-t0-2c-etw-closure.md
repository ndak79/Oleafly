# T0.2c ETW lifecycle and admission closure

## Goal

Close the review findings left by the first ETW runtime slice without turning
diagnostics into a startup dependency. The shell must make registration and
write failures observable, preserve a provider handle when unregister fails so
teardown can retry, reject the all-zero correlation sentinel before native
startup, and include the native ETW/shell suites in the T0.2c aggregate gate.

## Acceptance oracle

- A supplied all-zero `--trace-trial` is rejected before any backend call.
- A registration failure leaves the shell running but exposes a typed
  `registration_failed` state and provider error.
- A write failure exposes `write_failed`; a failed unregister leaves the handle
  registered and a later teardown retries it. Successful teardown clears the
  provider and returns the shell to `disabled`.
- The real Windows shell test registers one admitted trial, emits the hidden
  bootstrap snapshot and a later successful/occluded Present event, and
  verifies teardown. Native fault tests inject only the narrow ETW ABI table;
  production still links directly to advapi32.
- Aggregate `t0-2c-models-test/check` depends on both native ETW and shell
  artifacts. Linux remains compile-only.

## Implementation order

1. Add failing admission, lifecycle, and ABI-fault assertions.
2. Implement typed shell telemetry state/error, retryable provider teardown,
   sentinel rejection, and aggregate build dependencies.
3. Run Windows Debug/ReleaseSafe, explicit `flip_discard`, Linux compile,
   product PE/runtime, aggregate, formatter, and diff checks.
4. Perform a five-axis review and record direct evidence. Keep the broader
   T0.2c UIA, D2D/DirectWrite, capture, and physical-matrix work explicitly
   open rather than over-claiming completion.

## Non-claims

This closure does not provide loss-free WPR/WPA/PresentMon collection,
long-run energy/event-rate measurements, DWM-visible capture, UIA journey
proof, D2D/DirectWrite composition, or Task 7 physical-machine admission.
