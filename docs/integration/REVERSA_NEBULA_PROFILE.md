# Reversa Nebula Profile

Reversa local tool:

- Path: `/home/richtofen/.android/repositories/tool-repos/reversa-fractal-echo`
- Version checked: `1.2.44`
- Role in Nebula: reverse-engineering agent framework and prompt source.
- Install policy: do not run `reversa install` in the Hub unless explicitly
  requested for a dedicated Reversa pass. The installer creates project
  scaffolding; normal Nebula passes should stay artifact-first and bounded.

## Nebula Operating Rules

Every Nebula-tuned Reversa agent must obey:

- Read the locked evidence rules before reasoning.
- Search only the explicitly named trees for the pass.
- Separate evidence from inference.
- Treat screenshots, chats, and external claims as leads until backed by an
  artifact, source path, command log, or hash.
- Never run ADB, DRM ioctls, compositor launches, module installs, APK installs,
  reboots, or root/device mutations unless the pass explicitly authorizes them.
- Classify every result with one target, one artifact set, and one final
  classification.

## Agent Pack

### `reversa-nebula-scout`

Purpose: produce a bounded map of the relevant source trees for one pass.

Inputs:

- `CURRENT_STATE.md`
- `LOG_CATALOG.tsv`
- the pass request
- exact allowed source paths

Outputs:

- allowed tree list
- files inspected
- evidence gaps
- no implementation changes

Hard stop:

- any need for broad `/home`, all-repo, or device search.

### `reversa-nebula-graphics-archaeologist`

Purpose: reason about the three display lanes without mixing their evidence.

Lane taxonomy:

- Phone/App: WayLandIE -> Wayland -> Turnip/KGSL -> bridge -> Gamescope -> Xwayland.
- Anland: Droidspaces app/surface fallback path.
- Dock Lease: external-display DRM/KMS lease reference path.

Required distinctions:

- sidecar-11 evidence versus later unpromoted evidence
- Xwayland launch versus GLX visual/fbconfig exposure
- external-display lease versus whole-card DRM master takeover
- proven reference versus Nebula-wired command

Output decisions:

- `READY_FOR_FIX`
- `PROMOTION_CANDIDATE`
- `REFERENCE_ONLY`
- `OPERATOR_GATED`
- `NOT_WIRED`
- `REJECT`

Promotion candidate rule:

- A later sidecar may be surfaced as `PROMOTION_CANDIDATE` only when it has
  artifact evidence and a bounded next test. It must not replace the canonical
  blocker until that promotion pass succeeds.

Runtime constraint rule:

- Record operator-provided kernel/runtime constraints, such as the RM11 Pro
  OnePlus Wild 39-bit VA limit, as constraints until independently probed.

### `reversa-nebula-module-auditor`

Purpose: audit Nebula Core KSU module behavior.

Checks:

- no boot auto-launch of Linux, Wayland, Gamescope, Xwayland, DRM lease, or
  compositor targets
- fixed CLI allowlist only
- no arbitrary shell or path arguments
- safe mode blocks future mutating launches
- crash counter and rollback paths exist before enabling mutations
- SELinux policy is evidence-backed and minimal

Outputs:

- pass/fail table
- exact file/function references
- boot risk classification
- rollback requirement

### `reversa-nebula-placeholder-audit`

Purpose: classify placeholder-looking files without breaking real upstream code.

Evidence classes:

- `ACTIVE_PAYLOAD`: used by Nebula runtime/module/build and must be real.
- `GENERATED_OUTPUT`: build/cache artifact; exclude from public-source checks.
- `UPSTREAM_BENIGN`: real upstream test, framework, CI, stub, or marker file.
- `LOCAL_PAYLOAD_UNPROVEN`: local binary/module payload with unclear provenance.
- `MISSING_ARTIFACT`: path is required by a script/build but absent or empty.
- `UNKNOWN`: not enough evidence.

Rules:

- Do not replace by filename alone.
- Prove import/use before declaring a placeholder dangerous.
- Record hashes for binary payloads before any decision.
- If a neighbor file suggests a pattern, treat it as evidence, not permission to
  synthesize replacement content.

### `reversa-nebula-test-captain`

Purpose: turn an engineering pass into reproducible validation.

Outputs:

- exact commands
- expected artifacts and SHA256 targets
- allowed device actions
- forbidden mutation list
- result.md outline
- final classification rule

## Usage

Use this profile to brief Reversa-style agents for Nebula work. Do not use it
as permission to scan `tool-repos` or unrelated repositories. If a pass needs a
tool from `tool-repos`, name the exact tool path and the exact question first.
