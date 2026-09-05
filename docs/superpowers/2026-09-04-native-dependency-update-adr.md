# ADR: TExFlow native dependency updates

- Status: Accepted for the T0.2 dependency lock
- Date: 2026-09-04
- Scope: `tools/zig/native-deps.json`, its committed provenance inputs, and
  their cache-only acquisition and audit commands

## Context

TExFlow builds against exact native source, data, binary-reference, and QA-tool
locks. A version number and checksum alone do not establish source identity,
license suitability, archive safety, binary closure, or publisher provenance.
Some upstream archives are unsigned. The PDFium reference archive has a GitHub
attestation from a community build workflow, but that attestation is not an
independent reconstruction from the official PDFium source commit.

Automatic or opportunistic dependency updates would invalidate the reviewed
archive shapes, extraction limits, build switches, imports, licenses, and
provenance assumptions. The dated GitHub/Sigstore trusted-root snapshot is
reproducibility input for its locked historical attestation, not a current
revocation service.

## Decision

Every native dependency update requires a new dated ADR and a reviewed lock
change. A newer patch release is never sufficient reason to float a lock. The
update owner must complete this procedure:

1. State the dependency, old and proposed identities, reason, affected product
   or QA role, rollback point, and whether it is source, build-only data,
   reference evidence, a QA tool, or a shipping input.
2. Review upstream release notes and security notices. Record the canonical
   source repository and exact immutable tag/commit, the allowlisted HTTPS
   scheme/host/path, redirect policy, and why the selected origin is
   authoritative.
3. Re-evaluate the license, SPDX identifier, upstream license text, notice
   obligations, redistribution terms, and whether the material may enter a
   product package. Update `LICENSE` or `NOTICE` when required.
4. Acquire candidate bytes only through a no-secret online lane. Record byte
   size, SHA-256 from an official publication when available, independently
   measured SHA-256, archive root, exact member inventory, retained members,
   per-member hashes, expanded size, compression limits, and canonical tree
   digest where transport bytes are nondeterministic. Do not use account-backed
   profiles, cookies, ambient tokens, or a mutable package-manager URL.
5. Re-run the hostile archive review for traversal, absolute/drive/device/ADS
   names, links and special files, duplicates, Windows case and Unicode
   collisions, ambiguous ZIP descriptors, unsupported metadata, excess ratios,
   truncation, digest mismatch, interrupted staging, and activation before full
   verification. Any necessary parser-policy expansion must be narrow to the
   new reviewed shape and covered by a rejecting counterexample.
6. Recheck build switches, target/CPU/optimization policy, source patches,
   binary architecture, imports and exports, runtime role closure, file and
   package size, cache-only versus shipping status, and every affected test.
   Reference or QA artifacts must not enter the product install manifest.
7. For unsigned inputs, write the precise provenance limitation and the
   compensating checks. Do not describe a digest lock as publisher
   authentication. Do not promote a community reference binary to an admitted
   runtime without a separately reviewed source-reconstruction and release
   qualification decision.
8. For a PDFium update, obtain a fresh digest-keyed SLSA bundle without ambient
   authentication, pin and review a supported GitHub CLI executable, and export
   the GitHub/Sigstore trusted root twice from independent empty profiles. The
   two root exports must be byte-identical. Lock the CLI version/file digest and
   signer, bundle digest and exact subject set, root digest and date, workflow
   identity, repository, ref, source and signer digests, hosted-runner identity,
   verified timestamp, and run invocation. The generic release attestation
   asset and an ambient `gh attestation download` are not substitutes.
9. Update the manifest, committed attestation inputs, build package paths,
   notices, developer documentation, and tests together. Remove the candidate
   cache, run `zig build deps-fetch --summary all`, then run `zig build
   deps-test --summary all`, `zig build unicode-audit --summary all`, and `zig
   build deps-audit --summary all`. Capture exit codes, exact summaries, cache
   identity, artifact digests, and any failure or retry in the T0.2 worklog.
10. Prove the network-free replay only on an authorized sealed disposable
    runner. Windows requires a VM with its virtual NIC detached; Linux requires
    a container or network namespace with network mode `none`. The runner must
    pass the interface/route/proxy/process preflight and a zero-byte negative
    fetch canary before using the prefilled owner-only cache. If this evidence
    is unavailable, record `UNVERIFIED-NETWORK-ISOLATION` and do not claim an
    offline pass.
11. Run affected regression and falsification cases, complete the required
    clean closed-coverage review, and obtain review before landing the new lock.
    Record the final source commit/tree, CI run IDs, durable evidence locations
    and digests, findings, fixes, and streak transitions. A retry does not erase
    a flake, and an interim local success is not a final streak pass.

`zig build deps-fetch` remains the sole ordinary dependency network-acquisition
command. The separately authorized PDFium source-reconstruction lane is an
exceptional reproducibility operation on a qualified disposable machine; it
does not weaken this rule or mutate the lock automatically. Normal build,
test, Unicode-audit, and dependency-audit steps remain cache-only.

## Consequences

Updates are deliberate and may take longer than changing a version string, but
each accepted lock has reviewable acquisition, license, archive-shape, build,
binary, and provenance evidence. Unsigned inputs remain explicitly labelled,
trusted-root freshness is re-established during updates and protected release
qualification, and ordinary developer builds never contact the network
implicitly.
