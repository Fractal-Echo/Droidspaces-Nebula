# DRM Control Reference

This file records the confirmed external-display Dock method described in the
user-provided Bob Dilian transcript and screenshots from 2026-06-22. It contains
no experiment code.

## Confirmed Mechanism

The working model is not full DRM-card takeover and does not stop
SurfaceFlinger.

- Android SurfaceFlinger/vendor composer remains alive.
- The Qualcomm composer owns `/dev/dri/card0`.
- The same card exposes the internal panel and external display:
  - `DSI-1`: phone panel, left under Android control.
  - `DP-1`: external monitor, leased to Linux.
- Most duplicated composer DRM fds are not lease-authoritative and return
  `EACCES` for lease creation.
- One composer fd was reported as lease-authoritative: fd `11` in that run.
- The broker asks the kernel to lease only the external-display objects.
- The leased fd is sent into the Linux container over a Unix socket with
  `SCM_RIGHTS`.
- Patched wlroots consumes the received lease fd as its DRM backend.
- `labwc` or `cage` can then render directly to the leased external monitor.

Observed successful path:

```text
Linux app
-> Wayland
-> labwc/cage/wlroots inside container
-> leased DRM/KMS fd for DP-1
-> external monitor
```

Old Android-surface path avoided by this method:

```text
Linux app
-> Wayland/Xwayland
-> Android display bridge/app surface
-> SurfaceFlinger
-> Qualcomm HWC/composer
-> DRM/KMS card0 DP-1
-> external monitor
```

## Reported Lease Object Set

These IDs are evidence from one confirmed RM11 Pro / modified 6.12 kernel run,
not permanent constants:

| Object | Reported value | Notes |
| --- | ---: | --- |
| External connector | `89` | `DP-1`, external display. |
| CRTC | `285` | Used by the successful lease. |
| Plane | `137` | Accepted in lease object set. |
| Plane | `145` | Reported primary plane in later evidence. |
| Encoder | `86` | Do not include; reported `EINVAL`. |
| Composer fd | `11` | Lease-authoritative in the observed process. |

The final implementation must discover these dynamically per boot/session.
Never hard-code these object IDs as production behavior.

## Decoded Media Evidence Update

Reversa Stage 07 decoded three local videos from the RM11 Pro / DroidSpaces /
Nebula evidence bucket and promoted them only as artifact-backed evidence.

Two videos independently show the Dock/Anland userspace path reaching:

- DRM lease mode
- connector `89`
- CRTC `285`
- mode `1920x1080@75`
- lease fd `fd3`
- `/dev/dri/card0`
- `/dev/dri/renderD128`
- scanout plane `133`
- Mesa KGSL render device
- renderer `gles2`
- Wayland socket `wayland-0`
- wlroots DRM backend
- labwc compositor
- graphical target reached

This does not replace the earlier reported object table. It sharpens the rule:
object IDs, fds, planes, modes, and connector names are observed evidence, not
constants. The older report mentioned `2560x1080@75` and planes `137` / `145`;
the decoded videos show `1920x1080@75` and plane `133`. A real implementation
must dynamically discover the current external-display object set each run.

## BD DRM Control Package Intake

The 2026-06-28 Drive/ZIP intake preserved BD's DRM Control package as
reference evidence, not as vendored runtime code.

- Supplied ZIP SHA-256:
  `d680e50c50c3f4081fc0319cf6130efbb955d3c7a91678b7f4599a340e939558`
- Local intake report:
  `/home/richtofen/.android/repositories/nebula-assets/local/2026-06-28-bd-drm-control-drive-01/result.md`
- The supplied ZIP matched the 175-entry Drive manifest.
- Reversa scans for Dock lease, policy, gateway, and frontier profiles reported
  zero contradictions and zero patch candidates.
- Static syntax checks passed for shell and C sources.
- Remaining package debt is ShellCheck cleanup in
  `adapters/droidspace/android/stop-lease.sh`; do not promote the package to an
  active Nebula runtime until that is reviewed and fixed upstream or ported
  cleanly.

Nebula may use the package to sharpen the source-level command model,
provenance, object-discovery requirements, broker/receiver sequencing, and
rollback checklist. Nebula must not import the APK, generated artifacts, or
prebuilt helpers into the public repo without a separate rebuild/provenance
pass.

## Qualcomm / Adreno Guidance Reference

Qualcomm's public documentation page
`https://docs.qualcomm.com/doc/80-78185-2/topic/mobile_best_practices.html`
was captured as local-only evidence on 2026-06-28. The topic payload resolved to
a PDF and was summarized without copying vendor text into this public source.

Nebula promotes only these high-level guardrails:

- Prefer Vulkan-first runtime proof on Adreno display/runtime lanes.
- Treat swapchain and presentation behavior as power/thermal policy, not only
  latency policy.
- Preserve tile-rendering, UBWC, GMEM, and optimal image-layout assumptions
  when designing sidecars, wrappers, or native display paths.
- Avoid CPU/GPU readback and linear/mutable/sparse image paths unless a bounded
  runtime proof justifies them.
- Key Adreno workarounds from runtime driver/version evidence instead of
  generic assumptions.
- Require profiler or direct runtime evidence before promoting performance
  claims.

The Qualcomm PDFs/text extraction remain local-only under
`nebula-assets/local/qualcomm-mobile-best-practices-2026-06-28`. Do not commit
vendor PDF/text payloads or proprietary blobs.

## Reported Validation

Reported evidence from the experiment:

- External DP is real KMS: `DP-1`, connector `89`, `2560x1080@75`.
- Internal phone panel remains alive as `DSI-1`.
- Android composer continues running and still owns `/dev/dri/card0`.
- `pidfd_getfd` can duplicate composer card fds.
- Android-native atomic `TEST_ONLY` passed for the leased DP output.
- A real three-second KMS solid-color commit succeeded.
- `WLR_DRM_LEASE_FD=3` passed the lease fd to wlroots through `SCM_RIGHTS`.
- `wayland-info` saw `DP-1` at `2560x1080@74.991`.
- `WLR_RENDERER=pixman` worked with `XRGB8888` and no modifiers.
- `glmark2-wayland` later ran under the leased GLES2 compositor with
  `GL_VENDOR: freedreno` and `GL_RENDERER: Adreno (TM) 840`, scoring about
  `7716` at `640x480` before timeout.

Expected side effects:

- Android and scrcpy no longer see/render the leased external display path.
- Anything that requires SurfaceFlinger presentation will not work on the
  leased output.
- Android desktop mode may disappear from the external display while Linux owns
  the lease.

## Nebula Integration Target

Future Dock mode should port the pattern as a separate operator-gated lane:

- Nebula Core fixed commands only.
- External-display-only preflight before any lease attempt.
- Dynamic discovery of the current composer pid, usable composer fd, connector,
  CRTC, and plane set.
- Explicit rejection of internal-panel `DSI-*` leasing.
- Explicit rejection of whole-card DRM master takeover.
- Receiver-only smoke test before any real lease command.
- Atomic `TEST_ONLY` before real commit.
- `SCM_RIGHTS` handoff into the rootfs; no inherited-fd dependency.
- Patched wlroots/labwc/cage backend consumes the received fd.
- Explicit stop/revoke command with evidence capture.
- Crash counter and Nebula safe-mode block.
- No boot-time Dock auto-launch.

Candidate future command shape:

```text
dock lease status --json
dock lease preflight --json
dock lease start external --json
dock lease stop --json
```

All commands must reject arbitrary paths, raw shell text, connector IDs, CRTC
IDs, plane IDs, and fd numbers from the app.

Stage 08 adds host-only command/result schemas and fixtures, not executable
runtime commands:

- `docs/integration/schemas/dock-lease-command.schema.json`
- `docs/integration/schemas/dock-lease-result.schema.json`
- `tests/fixtures/dock-lease/`
- `scripts/validate-dock-lease-schema.js`
- `scripts/dock-lease-command-plan-report.js`

Those fixtures intentionally keep `execute=false`,
`mutation_allowed_by_policy=false`, dynamic discovery required, external display
only, internal panel blocked, whole-card takeover blocked, `TEST_ONLY` required,
`SCM_RIGHTS` recorded, stop/revoke required, rollback required, and crash
auto-retry disabled.

The generated command-plan report is also host-only. It records the future step
order and guard state while keeping `profile set dock` blocked and leaving the
APK/module runtime allowlists unchanged.

## Risk Gates

Do not promote this into an active start command until these are true:

- Exact source/code from the working broker is reviewed and licensed for use.
- The object discovery code proves `DP-1` or another external connector is
  connected and active.
- The phone panel remains Android-controlled during preflight.
- ADB rollback is available before start.
- Stop/revoke restores Android display ownership.
- Failure increments a crash counter and blocks auto-retry.
- Safe mode blocks all Dock lease commands.
- The old WayLandIE/Gamescope lane remains available as fallback.

## Current Status

Advisory status. No DRM fd probing, composer fd probing, `CREATE_LEASE`,
wlroots DRM backend launch, display mutation, SurfaceFlinger stop, or compositor
launch is executed by this documentation pass.

Dock Lease Mode is paused/crash-gated. Nebula may display the reference and
preflight requirements, but no active DRM lease or display ownership transfer is
implied until a separate operator-approved runtime pass wires start, stop,
revoke, snapshot, safe-mode, and result logging.
