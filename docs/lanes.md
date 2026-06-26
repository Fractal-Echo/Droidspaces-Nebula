# Nebula Lanes

`display lanes --json` is the source of truth for lane names. Each lane reports
its method id, container reference, runtime status, display status, and current
missing requirements.

| Lane id | Method id | Container ref | Status |
| --- | --- | --- | --- |
| `phone_app_bridge` | `phone_app_bridge` | `waylandie_app_imagefs` | WayLandIE display proof lane. Display is proven; game-client runtime proof is not promoted yet. |
| `anland_surface` | `anland_surface` | dedicated DroidSpaces Anland container, recommended `anland-ubuntu26-kde` | Container runtime fallback. Display requires the Anland consumer/daemon, `anland.env`, the socket bind, and an Anland producer rootfs. |
| `dock_drm_lease_external` | `dock_drm_lease_external` | `none` | External display lease reference. Not wired as a startable path. |
| `compatibility` | `compatibility_software` | future dedicated software container | Not wired by design. |
| `recovery_safe` | `recovery_safe` | `none` | Safe status lane, not a renderer. |

`display method-containers --json` also exposes DroidSpaces-native method
containers that are not separate Nebula display lanes yet: rootfs image,
rootfs directory, Termux:X11, VirGL, Turnip/KGSL, llvmpipe, and PulseAudio.
Those rows come from the DroidSpaces repos and keep each available container
method visible instead of folding everything into Anland.

`display method-profiles --json` turns that map into read-only DroidSpaces
profile templates. It does not start containers. It records the config/env lines
and source-backed `create`/`start` commands for Anland, Termux:X11, VirGL,
Turnip/KGSL, llvmpipe, and PulseAudio profiles. Each profile gets its own
rootfs path; do not run multiple writable profiles against the same `rootfs.img`.
Safe config-only materialization is direct atomic file creation of
`container.config`, followed later by:

```sh
droidspaces --config=<container.config> start
```

## Anland Surface

Anland uses DroidSpaces as the container runtime, but it is not the same method
as a Termux:X11 or VirGL desktop. It expects the Android display daemon socket:

```text
/data/local/tmp/display_daemon.sock
```

bound inside the selected container as:

```text
/run/display.sock
```

The host socket must be writable by the Android consumer app. `srw-rw-rw-` is
the expected mode; `srwxr-xr-x` is not enough and leaves KWin waiting in
fallback with a black consumer surface.

The selected container must also own an `anland.env` file that sets
`ANLAND_SOCKET=/run/display.sock`, `ANLAND_DRM_DEVICE=/dev/dri/renderD128`, and
the KGSL/Turnip environment. Nebula reports this as runtime-ready only when the
container is selected, the rootfs is inside the selected container directory, and
the render node exists. It reports display-ready only when the daemon socket is
present, app-writable, and the rootfs contains an Anland producer such as
`startanland-kde.sh`.

Use a dedicated Anland profile/container for this lane. Do not rewrite a general
Termux:X11, VirGL, or daily Turnip test container in place.

Source-backed setup is exposed by:

```sh
su -c '/data/adb/modules/nebula_core/bin/nebula-core display method-containers --json'
```

The expected producer rootfs is built from `Droidspaces-rootfs-KDE-builder` with
Ubuntu26, KDE auto-start, and `anland_kde` enabled. The builder emits a
`.tar.xz`; import it with DroidSpaces `create` to produce the dedicated
`anland-ubuntu26-kde/rootfs.img`, then start that container with the socket
bind. After it is running, verify and launch `startanland-kde.sh` through
`droidspaces --name=anland-ubuntu26-kde run ...`.

## Steam/Proton

Parked until the display path is repeatable. WCP, Proton, WinNative, and
PulseAudio leads stay as references.
