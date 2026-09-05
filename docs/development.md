# Development

What you need to work on TExFlow. The native rewrite lives in `native/zig/` and
uses the root Zig build. The existing Oleafly [Tauri 2](https://tauri.app)
React, TypeScript, and Rust application remains a development oracle while the
rewrite is staged. Its retained names describe repository lineage and legacy
paths; the product and all new native identities are named TExFlow.

## Repo layout

```
TExFlow/
├── crates/
│   ├── oleafly-core/       shared Rust project, path, and build-directory policy
│   ├── oleafly-cli/        oleaflyc commands and native compiler adapter
│   └── oleafly-agent/      provider-neutral agent runtime
├── src/                    React app shell (stores, Tauri client, UI kit, port adapters)
│   ├── components/         ui (shadcn-style), layout, editor glue, preview panes, ai
│   ├── contributions/      registers rail tabs / commands / AI toolsets into the registry
│   ├── features/           compile, synctex, export
│   ├── lib/                tauri wrappers, github, spellcheck, utils, package shims
│   └── store/              zustand stores
├── packages/               @oleafly/* engine packages (consumed as TS source)
│   ├── latex/  ai-core/  registry/  preflight/
│   └── editor/  preview/  diagram/  ai-tools/  templates/
├── src-tauri/
│   ├── src/                rust: commands, DocumentEngine, config, git, paths, project, synctex
│   ├── binaries/           target-suffixed compiler sidecars
│   ├── resources/          templates, licenses, and pinned runtime archives
│   └── tauri.conf.json
├── scripts/fetch-tectonic.sh
├── scripts/fetch-biber.sh
├── scripts/fetch-typst.sh
├── scripts/fetch-language-servers.mjs
└── docs/
```

The frontend is a pnpm workspace: feature engines live in `packages/*` behind
injected ports, and the app shell wires them together. Read
[Architecture](architecture.md) before touching `packages/`: it
covers the port pattern, the contribution registry, and the alias wiring.

## Prerequisites

- Node.js 22.13+ and pnpm 11.9+ (the exact pnpm version is declared in
  `package.json`)
- Rust (stable) via [rustup](https://rustup.rs)
- [Tauri 2 system dependencies](https://v2.tauri.app/start/prerequisites/) for your OS
- Optional during setup: [pandoc](https://pandoc.org/installing.html) for Markdown PDF compilation and document export (the app can install its pinned build on demand)

## TExFlow Zig walking skeleton (T0.1)

The rewrite starts in native/zig/ while the existing Tauri/React/Rust tree
remains a development oracle. The root build.zig and build.zig.zon are the
future build entry points; no legacy runtime is wrapped or packaged by this
slice.

Download the exact archive listed in tools/zig/toolchain.json from
ziglang.org, verify its byte size and SHA-256 before extraction, and put the
matching directory on PATH. CI performs the same checks on fresh Windows and
Linux runners.

```
zig version
zig fmt --check build.zig build.zig.zon native/zig tools/zig
zig build --fetch=all
zig build -Doptimize=Debug test --summary all
zig build --release=safe test --summary all
zig build --release=safe abi --summary all
zig build --release=fast abi --summary all
zig build --release=safe miscompile-corpus --summary all
zig build --release=safe simd-corpus --summary all
zig build --release=fast simd-corpus --summary all
zig build --release=safe run --summary all
```

The last command runs the native `texflow` executable and prints
`texflow toolchain ok`, preserving the T0.1 smoke check under the product's
current executable identity. ReleaseSafe is the shipping
default; ReleaseFast is used only to expose optimizer-dependent ABI, FNV, or
SIMD known-answer regressions. The full application, native Windows UI, editor,
compiler workers, research ledger, and publishing pipeline remain future
bounded slices.

## Native dependency workflow (T0.2a)

The T0.2a dependency lock is `tools/zig/native-deps.json`. These are the stable
operator commands:

```text
zig build deps-fetch --summary all
zig build deps-test --summary all
zig build unicode-audit --summary all
zig build deps-audit --summary all
```

`deps-fetch` is the sole ordinary command allowed to acquire native dependency
bytes from the network. It first acquires the locked Unicode input needed for
path-collision checks, then acquires the remaining ordinary artifacts. It does
not install the operator-provisioned Accessibility Insights package. A future
PDFium source-reconstruction command is a separately authorized, disposable
machine lane and is not an alternative routine fetch path. `zig build
--fetch=all` concerns Zig package dependencies only and must not be used as a
substitute for `deps-fetch`.

The other three commands are cache-only:

- `deps-test` runs the portable manifest, downloader, archive, attestation, and
  hostile-input tests without initializing the acquisition path.
- `unicode-audit` regenerates the locked Unicode 17 tables twice, compares
  exact bytes, checks the table-size bound and official conformance data, and
  writes only Zig build-cache outputs.
- `deps-audit` revalidates every locked cache entry and the Unicode inputs, then
  performs the Windows PDFium provenance check using the exact cached
  `github-cli` executable plus the committed attestation bundle and trusted
  root. The full attestation lane is Windows-native.

Treat `tools/zig/.cache/native-deps/` as one opaque cache root. New acquisitions
are immutable generations below
`.v2/<artifact-id>/generations/g-<24-lowercase-hex>/`; the artifact's strict
`current` selector names the active generation. Each generation contains the
locked `archive.bin`, extracted `payload/`, and `.complete.json` receipt. The
fetcher may read a valid legacy `<artifact-id>/` entry when no V2 store exists
for that artifact, but it never creates or silently migrates a legacy entry;
once an artifact has a V2 store, V2 is authoritative. Never copy an individual
generation, rewrite `current`, or hand-edit this layout. Generated Unicode
modules, test executables, and audit executables live in the Zig cache selected
by `--cache-dir` (the repository default is `.zig-cache/`). None of these
commands installs a product or writes a dependency artifact to `zig-out/`.
These cache and raw-evidence locations are ignored and must remain uncommitted.
The fetcher protects the dependency cache, every retained generation, and each
staging directory with an owner-only ACL on Windows; on POSIX hosts it creates
private directories and files with modes `0700` and `0600`.

Exclusive repair preserves a corrupted sealed generation in the artifact's
`quarantine/` directory instead of recursively deleting immutable descendants.
Only ordinary, reparse-free trees with exact read/execute OWNER RIGHTS ACLs and
valid original receipt metadata qualify. Each `g-<24-lowercase-hex>` directory
has an immutable JSON sidecar recording artifact/version/generation identity
and the actual archive, payload, and original-receipt hashes and sizes.
Quarantine never participates in selection, rollback, or export. Audit checks
its complete structure, exact ACLs, and evidence hashes; it rejects unknown
entries, missing/malformed evidence, changed content, and more than 64 items.
After interruption between directory rename and evidence publication, audit
fails closed; the next exclusive fetch verifies the orphan tree and completes
its evidence without downloading again. Known partial sidecar stages are
removed only after ordinary-file and owner-only ACL checks. A malformed original
receipt or unsafe tree remains an error. No command deletes sealed quarantine
content or silently rewrites an existing evidence record.

Publication keeps the stage root and all descendants at exact read/execute
OWNER RIGHTS ACLs while Windows child handles close for the native rename.
The held root handle supplies its previously granted rename permission; the
published tree and content are checked before selector activation. An exclusive
fetch also moves a complete frozen interrupted root stage into quarantine,
preserving its ACLs and evidence. Audit leaves that interrupted stage untouched
and reports failure. Unicode bootstrap uses the same reconciliation rules
before schema validation and after replacing a stale selection, so the later
cache-only Unicode export sees a fully reconciled cache.
A stage interrupted partway through freezing has mixed ACLs; both audit and
fetch reject it without deleting or altering its children.
Earlier mutable stages remain recoverable: the root must have its protected
full-control ACL, and every descendant must have exactly one current-owner
OWNER RIGHTS full-control grant, either protected or inherited from creation.
Fetch verifies the whole ordinary tree before deletion and never rewrites ACLs
to make a failed cleanup pass. Audit always leaves interrupted stages untouched.

An audit never repairs a missing or tampered artifact from the network. Treat
that result as a fail-closed cache miss. On a host explicitly authorized for
ordinary acquisition, run `zig build deps-fetch --summary all`, preserve the
owner-only boundary, and then rerun the three cache-only commands. On an
offline or read-only runner, report the failure and move the entire separately
prefilled and verified opaque cache root as one unit; do not omit an inactive
generation or selector, broaden an ACL, make the cache writable, or hand-edit a
receipt merely to obtain a passing result. The receiving host must preserve the
owner-only boundary and rerun `deps-audit`. A cold cache without an authorized
acquisition lane is expected to remain unavailable.

The external GitHub attestation check does not trust `PATH`, an ambient GitHub
login, or the user's GitHub CLI cache. It invokes the cached `gh.exe` 2.100.0
whose SHA-256 is
`2ae2b350c227a618f2d8965b1900aeee13446ff42e17ef0bd5a0b6405c593cfb`,
passes the committed
`tools/zig/attestations/pdfium-chromium-8035-win-x64.jsonl` bundle (SHA-256
`1f84f3d920a8c3ad5dc480899631eef877c43f99d1e85b634af55570f51e2ee6`),
and passes the committed dated trusted root (SHA-256
`db07310827da2ae2798ec7eefc5daf8432506ce458d5bc30cd2feba03708d239`).
The verifier checks all three locked inputs before use, runs `gh attestation
verify` with an empty scrubbed profile, explicit bundle/root/repository and
workflow identity arguments, and rechecks the inputs afterward. It parses the
bounded JSON result and requires exactly one matching PDFium subject among the
45 attested subjects. It never downloads an attestation or trusted root during
the audit.

Digest, inventory, and provenance checks do not make every upstream archive
publisher-authenticated. Several locked archives are unsigned. In particular,
the PDFium attestation binds the archive digest to the named community workflow
and builder commit, but it does not prove an independent rebuild from the
official PDFium source commit. The community DLL remains reference evidence and
is not an admitted or shipping runtime. Follow the
[native dependency update ADR](superpowers/2026-09-04-native-dependency-update-adr.md)
for every lock change; dependencies never float to a newer release.

A scrubbed profile and fail-fast loopback proxy settings are defense in depth,
not proof that the host had no network route. Admission-grade offline evidence
requires an authorized sealed disposable runner: a Windows VM with its virtual
NIC detached, or a Linux container/network namespace with network mode `none`,
plus the isolation preflight and a zero-byte negative-fetch canary. Do not
disable a developer workstation's adapter or firewall to manufacture this
evidence. When no qualifying runner and receipt are available, record the exact
status `UNVERIFIED-NETWORK-ISOLATION`; a successful local audit must not be
reported as an offline pass.

## First run

```bash
pnpm install
host_target="$(rustc -vV | sed -n 's/^host: //p')"
./scripts/fetch-tectonic.sh "$host_target"
./scripts/fetch-biber.sh "$host_target" # pinned Biber 2.17
./scripts/fetch-typst.sh "$host_target"
pnpm tauri dev
```

The sidecar scripts fetch only the current host for day-to-day development.
Pass `all` only when preparing every supported target for CI or release work.

TexLab and Tinymist use the separate checksum-pinned language-server fetcher.
Run `pnpm language-servers:fetch` when you need that optional editor
intelligence. Its default installs TexLab under the current user's app-data directory as an
explicit development setup action and stages Tinymist's exact upstream archive
as a Tauri resource. Neither language server is an `externalBin`: TexLab's
GPL object-distribution checklist awaits a
separate maintainer decision, and normal Tauri release builds neither require
nor package it. The app's first-run path must display the pinned license/source
and wait for user consent before downloading. See
[Language-server toolchain](language-server-toolchain.md). `pnpm build` does
not fetch or require any sidecar.

## Day-to-day

```bash
pnpm tauri dev          # run the app with hot reload (frontend) + cargo incremental (backend)
pnpm build              # typecheck + build the frontend (tsc -b && vite build)
pnpm tauri build        # produce a distributable bundle
```

The command-line adapter is source-only for now. Run it from the workspace:

```bash
cargo run -p oleafly-cli --bin oleaflyc -- --help
cargo run -p oleafly-cli --bin oleaflyc -- init
cargo run -p oleafly-cli --bin oleaflyc -- build
cargo run -p oleafly-cli --bin oleaflyc -- project info --json
```

`oleaflyc` works on the current directory unless you pass `-C <path>`. It also
has `watch`, `clean`, and `doctor`. Output is human-readable by default.
`--json` switches to structured output, and watch mode prints newline-delimited
JSON events. Build and watch kill a compiler after 300 seconds unless you pass
`--timeout <seconds>`. The CLI never turns on TeX shell escape. Only the
desktop can, and only through its device-local trust prompt for the system TeX
engine.

### Checks before opening a PR

Make sure both pass:

```bash
pnpm build                                # frontend typecheck (noUnusedLocals/Parameters on)
pnpm test                                 # vitest across src/ and packages/
pnpm language-servers:test                # manifest, checksum, target, URL, and license policy
pnpm audit --prod --audit-level high      # registry-backed npm advisory check
cargo check --workspace                   # all Rust crates compile
cargo test -p oleafly-core -p oleafly-cli --all-targets  # shared core and CLI
cargo deny --workspace --all-features --config src-tauri/deny.toml check  # Rust advisories, licenses, and sources
```

The two audit commands require registry/network access. CI records their
current results on every code change. An offline local run cannot certify that
the dependency graph is advisory-free.

For user-facing changes, also run the end-to-end suite (real app and real
compiles, see [e2e/README.md](../e2e/README.md)):

```bash
pnpm test:e2e:app                         # builds + launches the app, runs Playwright, tears down
```

## How a compile works

1. The frontend loads the backend `project_engine` descriptor and its capability flags, then calls `compileProject(projectId, mainDoc, offline)` through Tauri IPC.
2. `oleafly-core` validates the workspace, resolves the source inside the project root, and prepares the isolated build directory.
3. The desktop adapter dispatches through `DocumentEngine`. UI code must not infer engine behavior from a filename. The `oleaflyc` adapter invokes its native compiler runner through the same shared workspace policy.
4. The desktop LaTeX adapter writes `_oleafly_entry.tex` and invokes Tectonic with `--synctex --keep-logs --print` and, when requested, `--only-cached`. The CLI invokes the selected source directly and normalizes its PDF output to `_oleafly_entry.pdf`.
5. Typst invokes the pinned Typst CLI directly against the selected `.typ` main document with short diagnostics and an explicit PDF output path.
6. Markdown invokes Pandoc directly against `.md`/`.markdown`, with an explicit
   output path and `--pdf-engine=<absolute bundled Tectonic path>`. Pandoc's
   manual explicitly supports a full PDF-engine path. Do not replace this with
   an implicit system `pdflatex`, since packaged Oleafly must not depend on an
   undeclared TeX installation. The process runs with the project root as its
   working directory so relative images, bibliography files, and CSL files work
   for both root and nested main documents.

Tauri's [sidecar documentation](https://v2.tauri.app/develop/sidecar/) defines
`bundle.externalBin` inputs with target-triple suffixes and exposes the packaged
sidecar under its unsuffixed name at runtime. Oleafly's Pandoc adapter resolves
that packaged Tectonic executable beside the application executable, matching
Tauri's desktop bundle layout. Unit tests cover macOS app-bundle and Cargo
debug/release candidates, while the release workflow inspects the staged
unsuffixed sibling on every target.

Tectonic 0.16.9 release archives are checksum-pinned from the official GitHub
Releases API `digest` fields. `scripts/fetch-tectonic.sh` verifies SHA256 before
extracting exactly the root `tectonic`/`tectonic.exe` regular-file member. The
same script is used by CI and every release target, including Windows.

TexLab 5.26.0 and Tinymist 0.15.2 have a separate machine-readable manifest,
secure Node fetcher, and distribution policy. Neither language server is a
Tauri `externalBin`. TexLab resolves from its consent-gated, checksum-pinned
app-local-data installation. Tinymist's target-specific upstream archive is a
Tauri resource. Rust verifies and extracts it atomically into the same
versioned app-local-data layout on first use. Keeping the archive immutable is
important because macOS and Windows signing may modify executable bytes. See
[Language-server toolchain](language-server-toolchain.md) for the target
matrix, integrity checks, CLI modes, and license obligations.
7. All engines stream normalized log/error events. Rust returns compile metadata through JSON IPC. The PDF itself is fetched separately as raw binary IPC rather than embedded as base64 in the result.
8. The frontend renders PDF bytes with pdf.js and publishes normalized diagnostics to CodeMirror.

Engine descriptors model compilation policy plus formatting/source-preflight
profiles and feature/export/template-kind sets. Frontend consumers use the
fail-closed files-store descriptor rather than guessing from extensions. See
the [document engine matrix](document-engines.md).

Typst currently reports `supports_synctex=false`, `supports_offline=false`, and
`supports_isolated_compile=false`. Consequently reverse/forward search, the
offline compiler toggle, and LaTeX/TikZ figure generation are hidden or
normalized off for Typst projects. Add such behavior only after the backend
engine capability becomes truthful. Do not add extension-based UI exceptions.

## Where state lives

Oleafly stores app-managed state beneath the user's `~/.oleafly/` directory.
The application keeps preferences separate from owner-only encrypted
credentials. Do not copy, publish, or commit files from this directory. The
directory also contains project folders (each with its own `.git` repository)
and the application log. Exact credential filenames and key material are
intentionally omitted from public documentation.

## Key extension points

- Add an AI provider → `crates/oleafly-agent/src/provider.rs` (`CATALOG` + `wire_for`), and mirror the display entry in `packages/ai-core/src/providers.ts` (`PROVIDERS`). OpenAI-compatible providers just need a `base_url`, since routing collapses to three wire formats.
- Add a Tauri command → declare in `src-tauri/src/*.rs`, register in `src-tauri/src/lib.rs`, wrap in `src/lib/tauri.ts`.
- Add a document engine → implement `DocumentEngine` in `src-tauri/src/document_engine.rs`, expose truthful capabilities, add a checksum-pinned sidecar fetch/smoke path, then consume the descriptor in UI controls.
- Add a project template → drop a folder with a `template.json` manifest into `src-tauri/resources/templates/` (engine-general template metadata remains planned work).
- Add a tool for the AI → `packages/ai-tools/src/tools.ts`. App services it needs go through `AiToolsHost` (adapter in `src/lib/ai-tools.ts`).
- Add a rail tab / palette or omnibar command / AI toolset → register it in `src/contributions/` (see [Architecture](architecture.md#the-contribution-registry)).

## Sync and GitHub internals

OAuth device flow runs server-side in Rust (`src-tauri/src/github.rs`) because the OAuth endpoints aren't CORS-enabled. The API calls (api.github.com) happen from the frontend.

## Coding style

- TypeScript: follow what's already there. No comments unless asked. Respect `noUnusedLocals`/`noUnusedParameters`.
- Rust: idiomatic, small commands, friendly error strings.
- UI: Tailwind v4 + Geist tokens. Reuse the `Button`/`Tooltip`/`Select` primitives.
- User-facing copy: prefer short sentences. Do not use em dashes or semicolons
  in labels, status text, errors, accessibility text, tool descriptions, or AI
  prompts. Syntax examples and source-language snippets are exempt.

## Releasing

Packaging targets macOS Apple Silicon, Windows x64, Linux x64, and Linux ARM64.
Each target gets matching Tectonic, Biber, Typst, and language-server resources
that are fetched and smoke-tested in CI. A tag produces a complete draft.
Publishing is a separate manual workflow run and is blocked until the live
Anthropic and Google real-app contracts pass. See [Auto-updates](updates.md)
for required secrets, optional model variables, signing, and publication.
