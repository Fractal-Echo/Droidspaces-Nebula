# DRM Control Reference

This file records the confirmed external-display Dock method described in the
user-provided Bob Dilian transcript and screenshots from 2026-06-22. It is a
reference artifact only; no code is imported from the experiment here.

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

Future Dock mode should port the pattern as a separate crash-gated lane:

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

## Risk Gates

Do not promote this into an active Nebula command until these are true:

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

Reference only. No DRM fd probing, composer fd probing, `CREATE_LEASE`,
wlroots DRM backend launch, display mutation, SurfaceFlinger stop, or compositor
launch is executed by this documentation pass.
