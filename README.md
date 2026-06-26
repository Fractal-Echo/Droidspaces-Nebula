# DroidSpaces Nebula

DroidSpaces Nebula is the public release hub for the RM11 Pro DroidSpaces, Wayland, Steam/Proton, and PowerDeck experiments.

This repo is the reviewable source and workflow layer. Large APKs, screenshots, logs, Mesa packages, rootfs images, and private device evidence stay in the local `nebula-assets` folder or in explicit GitHub Release assets after review.

Nebula is not a replacement for DroidSpaces, Termux:X11, WayLandIE, Nubia Toolkit, or RedMagic Control Center. It is the coordination layer:

- show which lanes are installed
- verify versions and signer hashes
- launch the existing apps or their Android app-info screens
- generate a copyable diagnostic report
- keep risky root/module work out of the first app cut

Current status: WIP. Do not describe Nebula as stable, production ready, or safe for general users yet.

## Package

```text
io.droidspaces.nebula
```

## What To Install First

Start with the Nebula baseline:

1. Install the Nebula APK.
2. Install the Nebula Core KernelSU/Magisk-style module.
3. Open Nebula and press **Refresh**.
4. Copy the doctor report if you are filing a test result.

Nebula then reports the status of the other lanes from one place:

- WayLandIE display/runtime;
- DroidSpaces / Anland container fallback;
- Nubia Toolkit / Vector hook readiness;
- RedMagic Control Center hardware references;
- PowerDeck dry-run automation readiness.

## Requirements

- Rooted Android device for the Nebula Core module.
- RM11 Pro / NX809J for RedMagic fan, pump, LED, trigger, and GameHub-specific checks.
- WayLandIE companion APK for the Phone/App display lane.
- DroidSpaces/Anland files only when testing the container surface lane.
- Vector/LSPosed only when intentionally testing future Nubia hook lanes.
- ADB access for logs, APK install, module install, and recovery.

Baseline status is read-only. It does not enable LSPosed hooks, write hardware
nodes, start game clients, replace DroidSpaces, or launch Proton/Wine/Steam.

## Method Containers

Nebula reports each display method with its own `container_ref`,
`container_kind`, `container_status`, `display_status`, `runtime_status`, and
`missing_requirements` fields. This keeps a working lane from being confused
with a different incomplete lane.

For the full source-backed map, run:

```sh
su -c '/data/adb/modules/nebula_core/bin/nebula-core display method-containers --json'
```

For concrete DroidSpaces profile templates, run:

```sh
su -c '/data/adb/modules/nebula_core/bin/nebula-core display method-profiles --json'
```

`method-profiles` is read-only. It emits config/env lines, config paths, and
copyable `create`/`start` commands. Safe config-only materialization is direct
atomic file creation: write `container.config.tmp`, move it to
`container.config`, chmod `0644`, then start later with
`droidspaces --config=<container.config> start`. DroidSpaces `create` only
creates a rootfs image; `start` persists or mirrors `container.config`. Use one
writable rootfs image or directory per profile, because multiple active profiles
must not share the same writable `rootfs.img`.

| Method | Container ref | Current requirements |
| --- | --- | --- |
| Phone/App Mode | `waylandie_app_imagefs` | Display proven by `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`; game-client runtime proof is not promoted yet. |
| Anland Surface Mode | dedicated DroidSpaces Anland container, recommended `anland-ubuntu26-kde` | Needs the Anland Android consumer APK, `virtual-drm-daemon` module, Ubuntu26 KDE rootfs with `anland_kde`, `anland.env`, socket bind, and `startanland-kde.sh`. |
| DroidSpaces rootfs image | `rootfs.img` | Use `--rootfs-img` or import `--rootfs-arc` into a sparse image for stable Android container storage. |
| DroidSpaces rootfs directory | `rootfs_directory` | Use `--rootfs` for simple unpacked rootfs testing. |
| DroidSpaces Termux:X11 | `droidspaces_container_enable_termux_x11` | Set `enable_termux_x11=1`; DroidSpaces injects `DISPLAY=:0` through `/run/droidspaces.env` on the current RM11 Pro proof. |
| DroidSpaces VirGL | `droidspaces_container_enable_virgl` | Set `enable_virgl=1`; DroidSpaces injects `GALLIUM_DRIVER=virpipe` and uses `/tmp/.virgl_test`. |
| DroidSpaces Turnip/KGSL | `droidspaces_container_enable_gpu_mode` | Set `enable_gpu_mode=1` and `enable_hw_access=1`; device-specific Turnip/KGSL env still belongs to that container. |
| DroidSpaces llvmpipe | `droidspaces_container_software_gl` | Keep GPU/VirGL disabled and optionally force software GL for compatibility checks. |
| DroidSpaces PulseAudio | `droidspaces_container_enable_pulseaudio` | Set `enable_pulseaudio=1`; DroidSpaces injects `PULSE_SERVER=unix:/tmp/.pulse-socket`. |
| Dock Lease Mode | `none` until a lease receiver is implemented | External-display discovery and operator approval are still required. |
| Compatibility Mode | future dedicated compatibility/software container | Not wired by design. |
| Recovery/Safe Mode | `none` | Always available, blocks risky starts. |

DroidSpaces already owns rootfs image/directory startup, Termux:X11, VirGL,
Turnip/KGSL, llvmpipe, and PulseAudio wiring. Nebula reports them separately so
we can try each method without mixing socket, GPU, audio, and rootfs assumptions
into one confused profile.

Anland is not a generic toggle for the same daily container. It flips display
ownership to the Anland daemon socket and a patched Wayland/KWin producer. The
repo-backed producer path is the DroidSpaces rootfs KDE builder with Ubuntu26,
KDE auto-start, and `anland_kde` enabled. A dedicated Anland profile/container
should own:

```ini
env_file=/data/local/Droidspaces/Containers/<container>/anland.env
bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock
```

The host socket must be app-writable, normally `srw-rw-rw-`. If it exists as
root-only or owner-writable only, the producer can connect but the Android
consumer cannot deposit buffers, which presents as a black Anland screen.

and `anland.env` must set at least:

```ini
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
```

The Ubuntu26/KDE builder emits a `.tar.xz` rootfs archive. Stage it on the
phone as `/sdcard/Download/anland-ubuntu26-kde.tar.xz`, then let DroidSpaces
create the sparse rootfs image:

```sh
/data/local/Droidspaces/bin/droidspaces \
  --rootfs-arc=/sdcard/Download/anland-ubuntu26-kde.tar.xz \
  --rootfs-img=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img \
  --size=32G \
  create
```

Then start or restart the container through DroidSpaces, not by raw-writing the
container config:

```sh
/data/local/Droidspaces/bin/droidspaces \
  --name=anland-ubuntu26-kde \
  --rootfs-img=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img \
  --net=host \
  --hw-access \
  --gpu \
  --selinux-permissive \
  --privileged=nocaps,noseccomp \
  --env=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/anland.env \
  --bind=/data/local/tmp/display_daemon.sock:/run/display.sock \
  start
```

Inside that rootfs, the producer command is `startanland-kde.sh`.

For sparse-image containers, verify and launch it through DroidSpaces:

```sh
/data/local/Droidspaces/bin/droidspaces --name=anland-ubuntu26-kde \
  run sh -lc 'test -x /usr/local/bin/startanland-kde.sh'

/data/local/Droidspaces/bin/droidspaces --name=anland-ubuntu26-kde \
  run sh -lc 'nohup /usr/local/bin/startanland-kde.sh >/tmp/anland-kde.log 2>&1 &'
```

## Build

```bash
ANDROID_HOME=/home/richtofen/.android/sdk ANDROID_SDK_ROOT=/home/richtofen/.android/sdk \
  /home/richtofen/.android/repositories/nebula-assets/Repos/Droidspaces-OSS/Android/gradlew \
  --project-dir /home/richtofen/.android/repositories/Droidspaces-Nebula \
  --no-daemon :app:assembleDebug
```

Verified locally on 2026-06-21 after moving the repo to the top-level
`/home/richtofen/.android/repositories/Droidspaces-Nebula` path.

## GitHub Validation

The CI workflow in `.github/workflows/nebula-android.yml` runs source hygiene
checks first, then builds the debug APK on GitHub Actions. It uploads only the
generated debug APK and SHA256 file from CI.

## Repo Layout

```text
app/        Android selector/doctor app
docs/       workflow, lane, upstream, and safety notes
scripts/    validation helpers for CI and local review
```

The current WayLandIE bridge experiments are still promoted selectively from the local WIP worktree:

```text
/home/richtofen/.android/repositories/nebula-assets/Repos/waylandie-vower-578b431
```

Do not vendor that whole worktree until the active diffs are reviewed and trimmed.

## Current Lanes

- Safe desktop: Termux, Termux:API, Termux:X11
- Zero-copy display: WayLandIE proof lane
- DroidSpaces container: DroidSpaces app lane
- Native compositor: wlroots/AHardwareBuffer reference lane
- Steam/Proton: WinNative/GameNative/Proton/Wine reference lane
- PowerDeck: dry-run module lane
- RedMagic controls: RedMagic Control Center and Nubia Toolkit reference lane
- Vower reference: build-pass lead, not a drop-in install target

See:

- [Asset Policy](docs/asset-policy.md)
- [Repo Map](docs/repo-map.md)
- [Workflow](docs/workflow.md)
- [Baseline Integrations](docs/integration/BASELINE_INTEGRATIONS.md)

## Safety

This app does not request storage, root, notification, overlay, or shell permissions. It does not write device nodes or install APKs.

Public source must not contain private dumps, full EDL backups, private keys, serials, personal logs, token material, or proprietary Qualcomm blobs.
