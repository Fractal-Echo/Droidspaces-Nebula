# Reversa Findings Assessment

Date: 2026-06-24

## Scope

This assessment treats Reversa output as a contradiction and lead finder, not as
authority by itself. A lead becomes actionable only when backed by a local
artifact, command log, hash, source path, or bounded test result.

No device action, compositor launch, DRM operation, install, reboot, or phone
mutation was performed for this assessment.

## Current Update: 2026-06-26

R6 Wayland proof 03 supersedes the old Phone/App display classification as the
current default state:

- final classification: `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`;
- proof result:
  `/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-25-nebula-r6-wayland-working-03/result.md`;
- display evidence: `SUMMARY_COMMITS=7189`, `SUMMARY_FAILURES=0`,
  `SUMMARY_ZERO_COPY=dmabuf-present`, `VKGETMEMORYFD_FAILURE_COUNT=0`,
  `REAL_COMMIT_COUNT=2`, `XWAYLAND_READY=yes`, `GAMESCOPE_EXIT=0`, and
  `BRIDGE_EXIT=0`;
- app presenter evidence: `DMABUF_PRESENT_STATUS=pass`,
  `DMABUF_PRESENT_NATIVE=surfacecontrol-vulkan-native`,
  `DMABUF_PRESENT_ZERO_COPY=gpu`, and
  `DMABUF_PRESENT_SYNC=surfacecontrol-acquire-fence`;
- required runtime assets: pinned local
  `/usr/local/etc/vulkan/icd.d/freedreno_icd.json`, local
  `/usr/local/lib/libvulkan_freedreno.so`,
  `xwayland-gamescope-14-exportable-fence-guard-a4-473ba531`, and
  `xwayland-gamescope-06-xwayland-9f1a3d62`.

Decision: the Wayland/Gamescope/Xwayland display gate is promoted when those
exact prerequisites are staged. Steam, Proton, Wine, and game clients remain a
separate bounded runtime proof gate under the 39-bit VA constraint.

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

Decision: the next Wine path is not another blind display rerun. It is a bounded
ARM64EC Wine runtime investigation for 39-bit VA behavior, PE unwind/exception
metadata, and `winex11.drv` attach.

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

Run a bounded promotion pass for the Phone/App lane:

1. Reuse the exact Sidecar-13 force-composition harness.
2. Run minimal Wine GUI smoke first.
3. Patch or swap the ARM64EC Wine runtime path so `winex11.drv` attach survives
   under 39-bit VA.
4. Promote only if artifact evidence matches the Sidecar-13 result and rollback
   remains clean.
