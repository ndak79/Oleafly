# TExFlow T0.2 Native Architecture Feasibility Evidence Report

| Field | Value |
| --- | --- |
| Status | `PROVISIONAL` (Local Feasibility Proved; Physical Strata Gated) |
| Final Quality Streak | `1/1` (Local Diagnostic Scope) |
| Shipped Product Identity | `TExFlow` |
| Date | `2026-09-08` |
| Plan Reference | `docs/superpowers/plans/2026-09-04-oleafly-t0-2-native-feasibility.md` |

## 1. Executive Summary

The T0.2 native feasibility implementation has established, with verified local
Windows and cross-compiled Linux evidence, that a dedicated Zig-owned desktop
writing architecture satisfies the core technical contracts for TExFlow:

1. **T0.2a (Source Locking & Acquisition)**: Cryptographically locked native
   dependency manifests with content-addressed SHA-256 digests and Authenticode
   auditing.
2. **T0.2b (Static Boundary & Reproducibility)**: Reconstructed PDFium C ABI,
   Lexilla C ABI, and Scintilla static build contracts with zero unauthorized DLL
   execution and clean pairwise-root independence.
3. **T0.2c (Native Shell & Waitable Presenter)**: Win32 DPI-aware lifecycle,
   COM STA initialization, D3D11 waitable flip presentation, D2D/DirectWrite
   composition, and robust fallback for headless/WARP environments.
4. **T0.2d (Editor, Lexer, UIA & IME)**: Sequence-stamped piece-table editor model,
   UAX-29 text unit mapping, LaTeX/BibTeX container lexer, Scintilla direct
   dispatch with occluded energy management, and dedicated STA UIA provider.
5. **T0.2e (Authenticated IPC & Isolated PDF)**: Zero-trust IPC control plane
   with HMAC-SHA-256 and HKDF key derivation, LPAC worker isolation, 1 MiB
   tile-transfer state machine, and dedicated `TExFlow.PdfWorker.exe`.
6. **T0.2f (Canonical Ledger & Disposable Search)**: Monotonic sequence event
   ledger with cryptographic hash chaining, chunked immutable content references,
   and disposable FTS5 search index with BM25 ranking and `TExFlow.ScienceWorker.exe`.
7. **T0.2g (Measurement Harness & Black-Box QA)**: Nearest-rank percentile oracle,
   privacy-safe machine profiling, preregistered campaign matrix (P0-P8), and WPR
   tracing profile.
8. **T0.2h (Review & Architecture Admission)**: Independent audit of evidence,
   verification of zero regressions, and transparent reporting of open external
   statuses.

## 2. Acceptance Matrix Status

| ID | Requirement | State | Verification Evidence |
| --- | --- | --- | --- |
| A01 | Native Process Architecture | `PROVED (Local)` | Dedicated UI (`TExFlow.exe`), PDF Worker (`TExFlow.PdfWorker.exe`), and Science Worker (`TExFlow.ScienceWorker.exe`). |
| A02 | Build Identity & Authenticode | `PROVED (Local)` | `attestation_verify.zig` gated on Windows; deterministic build options. |
| A03 | Source Identity & Two-Root Repro | `PROVED (Local)` | Pairwise root independence checked via `compare-both`. |
| A04 | Shell Presentation & Headless Fallback | `PROVED (Local)` | Exit code 5 graceful handling on headless runners lacking DXGI frame presentation. |
| A05 | Startup Latency Measurement | `GATED` | Preregistered in `t0_2_campaign.json`; awaits physical multi-strata execution. |
| A06 | Scintilla Container Lexer | `PROVED (Local)` | 6/6 tests pass in `lexer_test.zig`; LaTeX & BibTeX container states. |
| A07 | Editor UIA Text Provider | `PROVED (Local)` | 15/15 tests pass in `uia_provider_test.zig`; out-of-process client in `uia_client.zig`. |
| A08 | IME & Text Input Path | `PROVED (Local)` | UTF-8 non-lossy gate; UAX-29 text units (7/7 tests pass). |
| A09 | Isolated PDF Rendering (LPAC) | `PROVED (Local)` | Moniker `texflow.pdfworker.v1`, token audit predicate (3/3 pass in `lpac_boundary_test.zig`). |
| A10 | PDF Tile Handoff & Memory Budgets | `PROVED (Local)` | 512x512 1 MiB tiles, monotonic handoff (3/3 pass in `pdf_tile_handoff_test.zig`). |
| A11 | Accessible PDF Representation | `PROVED (Local)` | Pure Zig document/page tree (2/2 pass in `pdf_uia_test.zig`). |
| A12 | Canonical Event Ledger & Hash Chain | `PROVED (Local)` | Unbroken SHA-256 chain, <=256 KiB chunks (4/4 pass in `ledger_model_test.zig`). |
| A13 | Disposable FTS5 Search & BM25 | `PROVED (Local)` | Contentless-delete FTS5, BM25 rank, staging promotion (tests pass). |
| A14 | Input-to-Photon & Present Pacing | `GATED` | Preregistered in `t0_2_campaign.json`; WPR tracing profile in `texflow.wprp`. |
| A15 | Memory & Working Set Caps | `PROVED (Local)` | 24 MiB metadata cap, bounded tile and query caches enforced in code. |
| A16 | Quiescent Power & Energy Contract | `PROVED (Local)` | Scintilla ticker occlusion management in `scintilla.zig`. |
| A17 | Evidence Retention & Replay | `PROVED (Local)` | Content-addressed artifacts inventory in `2026-09-04-oleafly-t0-2-artifacts.json`. |
| A18 | Architecture Admission | `PROVISIONAL` | Local feasibility proved across all tasks; physical external matrix open. |
| A19 | Accessibility Tree Conformance | `PROVED (Local)` | Shell semantic tree and Document pattern confirmed. |

## 3. Explicitly Open External Statuses

In accordance with the fail-closed verification policy, the following items
remain explicitly open until executed on physical reference hardware:

1. `UNVERIFIED-REMOTE-CI-RUN-IDS`: Requires post-push remote GitHub Actions runs.
2. `UNVERIFIED-NETWORK-ISOLATION`: Requires qualified runner with detached NIC.
3. `UNVERIFIED-DURABLE-RETENTION`: Requires observation across physical storage pools.
4. `UNVERIFIED-PDFIUM-INDEPENDENT-RECONSTRUCTION`: Requires physical rebuild timing.

T1 authoring work may proceed only after formal owner review of this provisional
feasibility evidence pack.
