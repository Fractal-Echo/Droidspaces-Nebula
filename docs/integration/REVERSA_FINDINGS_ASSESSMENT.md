# Reversa Findings Assessment

Date: 2026-06-24

## Scope

This assessment treats Reversa output as a contradiction and lead finder, not as
authority by itself. A lead becomes actionable only when backed by a local
artifact, command log, hash, source path, or bounded test result.

No device action, compositor launch, DRM operation, install, reboot, or phone
mutation was performed for this assessment.

## Current Update: 2026-06-27

This documentation cleanup corrects the stale loader-pin rollback that crept
back into local source. The current confirmed display state is the R6 Wayland
real-buffer pass, not the older A1 loader-pin-only proof:

- final current classification:
  `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`;
- proven: pinned local Freedreno ICD and driver, dmabuf-present path,
  Gamescope/Xwayland readiness, `vkGetMemoryFdKHR` failures at `0`, bridge exit
  `0`, and real-buffer commits greater than `0`;
- not proven: Steam, Proton, Wine, DXVK, FEX, or a game client running through
  the display path under the live 39-bit VA constraint;
- active blocker:
  `GAME_CLIENT_RUNTIME_NOT_PROMOTED_39BIT_VA`.

Decision: the local control-plane source must not regress to loader-pin-only or
blocked-export labels. The next runtime gate is a bounded game-client proof under
the live-confirmed 39-bit VA constraint.

## Findings

### 1. Hub placeholder scan

Result: no active Nebula placeholder payload was found in the Hub by filename.

Evidence:

- `scripts/audit-placeholders.sh` was a self-match from the audit script's own
  sentinel strings, not an unresolved runtime payload.
- The audit script now builds those sentinel strings at runtime so Reversa does
  not report the audit tool itself as source uncertainty.
- Prior cleanup removed generated build residue and stale temporary phone probe
  files.

Decision: no runtime patch required. Future imports still need the Reversa
placeholder classification gate before being trusted as runtime payloads.

### 2. Phone/App graphics contradiction

Result: historical evidence, superseded as the live control-plane blocker by the
2026-06-27 loader-pin/export classification above.

Earlier canonical state was Sidecar-11:

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

Decision: preserve Sidecar-13 as historical promotion evidence, not as solved
default behavior. Do not launch Steam, Proton, Wine, DXVK, FEX, or game clients
from this historical lane. Phone/App display proof is promoted by the later R6
Wayland working 03 sidecar-14/sidecar-06 real-buffer evidence; game-client
runtime still needs a separate bounded proof.

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

Live-confirmed environment:

- device: RM11 Pro / NX809J;
- ROM: stock RedMagic ROM;
- kernel: OnePlus Wild kernel;
- kernel VA limitation: `CONFIG_ARM64_VA_BITS=39`;
- page size: `CONFIG_ARM64_4K_PAGES=y`;
- physical address width: `CONFIG_ARM64_PA_BITS=48`;
- compat support: enabled.

Decision: Nebula must avoid assuming 45-bit userspace/runtime compatibility
until a bounded runtime probe proves it. This especially matters for Wine,
Proton, Box/FEX-style runtimes, GPU stacks, and any prebuilt binary expecting a
larger VA layout.

### 5. Wine GUI runtime blocker

Result: actionable runtime blocker, separate from force-composition display.

Sidecar-13 proves X11 GLX presentation through Gamescope force-composition for
software GLX content. The later Wine/Proton notepad attempts do not promote the
Wine GUI lane: Xwayland starts and `winex11.drv` loads, then the ARM64EC Wine
runtime fails during `winex11.drv` process attach with SEH `invalid frame` and
`c0000005` evidence. Bridge real-buffer commits remain zero for those Wine GUI
attempts.

Decision: this remains historical runtime evidence. The next live gate is not a
Wine rerun and not another display-proof promotion; it is bounded game-client
runtime proof under the live-confirmed 39-bit VA constraint.

See `OLD_SIDECAR_PROMOTION_AUDIT.md` for the sidecar-by-sidecar evidence chain
and rejected interpretations.

## Patch Decision

Implemented read-only metadata only:

- Phone/App display lane JSON now reports Sidecar-13 as an unpromoted
  `promotion_candidate`.
- The same JSON reports `kernel_va_bits_constraint=39`.
- The same JSON reports the current Wine GUI runtime blocker:
  `ARM64EC_WINE_WINEX11_SEH_INVALID_FRAME_39BIT_VA`.
- The app display-lane card and doctor report render the lead and constraint.

No launch command, mutating command, arbitrary path, DRM ioctl, compositor start,
or backend start was added.

## Next Single Action

Run the bounded A1 export/runtime proof only after the readiness checklist is
true. Promote only if it reduces `vkGetMemoryFdKHR` failures, produces bridge
real-buffer commits greater than `0`, preserves Gamescope/Xwayland readiness,
and preserves child software GLX survival. Do not run Steam, Proton, Wine, DXVK,
FEX, or game clients for this gate.
