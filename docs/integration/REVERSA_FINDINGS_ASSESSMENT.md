# Reversa Findings Assessment

Date: 2026-06-24

## Scope

This assessment treats Reversa output as a contradiction and lead finder, not as
authority by itself. A lead becomes actionable only when backed by a local
artifact, command log, hash, source path, or bounded test result.

No device action, compositor launch, DRM operation, install, reboot, or phone
mutation was performed for this assessment.

## Findings

### 1. Hub placeholder scan

Result: no active Nebula placeholder payload was found in the Hub by filename.

Evidence:

- `scripts/audit-placeholders.sh` is the only Hub file matched by the bounded
  placeholder-name check.
- Prior cleanup removed generated build residue and stale temporary phone probe
  files.

Decision: no patch required. Future imports still need the Reversa placeholder
classification gate before being trusted as runtime payloads.

### 2. Phone/App graphics contradiction

Result: actionable promotion candidate.

Canonical state remains Sidecar-11:

- endpoint: Xwayland launches;
- active blocker: RGB GLX visual/fbconfig exposure.

Later Sidecar-13 evidence is stronger than a chat lead but not yet promoted into
the canonical chain:

- final classification: `XWAYLAND_GLX_RENDER_PASS_FORCE_COMPOSITION`;
- working trick: launch Gamescope with `--force-composition`;
- supporting fixes: ARGB8888 output format and ready-without-sync-fd behavior;
- effect: Gamescope composites X11 content into a full-size AR24 parent xdg
  dmabuf instead of leaving only a 1x1 parent backing buffer;
- bridge evidence: zero-copy dmabuf-present, 1318 commits, 0 failures;
- child evidence: glxgears ran under Xwayland and printed FPS output.

Decision: expose Sidecar-13 as a `promotion_candidate`, not as solved default
behavior. The next exact action is a minimal Wine GUI smoke through the exact
force-composition sidecar. Do not launch Steam until that smoke is promoted.

### 3. Dock lease evidence

Result: separate lane, not a replacement for Phone/App Mode.

Bob Dilian's evidence describes external-display-only DRM leasing where Android
keeps the internal panel and compositor while Linux receives a lease for DP-1 via
an Android-side broker and `SCM_RIGHTS` fd handoff.

Decision: keep this in Dock Lease Mode. It remains operator-gated and must use
dynamic discovery, explicit stop/revoke, and rollback. It must not be mixed into
the Phone/App WayLandIE lane.

### 4. Android 16 / 39-bit kernel constraint

Result: first-class runtime constraint.

Operator-reported environment:

- device: RM11 Pro / NX809J;
- ROM: stock RedMagic ROM;
- kernel: OnePlus Wild kernel;
- kernel VA limitation: 39 bits.

Decision: Nebula must avoid assuming 45-bit userspace/runtime compatibility
until a bounded runtime probe proves it. This especially matters for Wine,
Proton, Box/FEX-style runtimes, GPU stacks, and any prebuilt binary expecting a
larger VA layout.

## Patch Decision

Implemented read-only metadata only:

- Phone/App display lane JSON now reports Sidecar-13 as an unpromoted
  `promotion_candidate`.
- The same JSON reports `kernel_va_bits_constraint=39`.
- The app display-lane card and doctor report render the lead and constraint.

No launch command, mutating command, arbitrary path, DRM ioctl, compositor start,
or backend start was added.

## Next Single Action

Run a bounded promotion pass for the Phone/App lane:

1. Reuse the exact Sidecar-13 force-composition harness.
2. Run minimal Wine GUI smoke first.
3. Confirm the 39-bit kernel constraint does not break the selected runtime.
4. Promote only if artifact evidence matches the Sidecar-13 result and rollback
   remains clean.
