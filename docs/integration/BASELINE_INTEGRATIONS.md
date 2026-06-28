# Baseline Integrations

Date: 2026-06-26

## Goal

Nebula should be the single baseline APK/module users install first.

The baseline does not replace WayLandIE, DroidSpaces, Nubia Toolkit, RedMagic
Control Center, or PowerDeck source projects. It owns the coordination layer:

- detect which pieces are present;
- report which layer owns each capability;
- keep risky controls read-only until a fixed command is promoted;
- give testers one doctor report instead of scattered notes.

## Baseline Command

```sh
su -c /data/adb/modules/nebula_core/bin/nebula-core integrations baseline --json
```

The APK calls the same fixed command through `NebulaCoreClient`. No arbitrary
shell text is accepted.

For the one-APK/one-module ownership view, use:

```sh
su -c /data/adb/modules/nebula_core/bin/nebula-core integrations standalone --json
```

`integrations standalone` wraps the baseline state with bundled-vs-external
ownership, fixed-command policy, active-module-first dispatch, and promotion
guardrails. It is the noob-facing answer to "what do I install first and which
layer owns this?"

## Integration Ownership

| Integration | Baseline role | Current mutation state |
| --- | --- | --- |
| Nebula Core | Fixed privileged status contract | Fixed commands only |
| WayLandIE | Phone/App display bridge and future game runtime lane | Display status read-only; Proton smoke remains safe-mode guarded |
| DroidSpaces / Anland | Selected container and surface fallback lane | Preflight read-only |
| Nubia Toolkit | GameHub/GameAssist hook reference | Hook activation deferred to explicit ReZygisk provider plus Vector/LSPosed scope |
| RedMagic Control Center | Hardware node reference and optional standalone APK | Node writes disabled in baseline |
| PowerDeck | Dry-run profile automation model | Preview/snapshot only |

## Contributor Linux Native Artifact

The 2026-06-28 `linux native.zip` contributor archive is local evidence under:

```text
/home/richtofen/.android/repositories/nebula-assets/local/contributor-linux-native-2026-06-28
```

It contains Anland compositor work, DroidSpaces engine material, KDE rootfs
builder scripts, desktop helper scripts, screenshots, APK/module artifacts,
keystores, generated build directories, and compiled binaries. Nebula can
promote source-level requirements and fixed command shapes from it, but the
public repo must not ingest the binary/build/private-key payloads wholesale.

## Requirements For Testers

- Rooted RM11 Pro / NX809J or compatible RedMagic device.
- KernelSU or Magisk-compatible module support for `nebula_core`.
- Nebula APK installed as `io.droidspaces.nebula`.
- WayLandIE companion package installed for the Phone/App display lane.
- DroidSpaces/Anland runtime files only if testing the selected container or
  surface lane.
- ReZygisk v1.0.0-rc.9 only if intentionally testing standalone Zygisk provider plumbing for future Nubia hook lanes; the recorded artifact/hash is evidence only, not installed or hook-ready state. Magisk built-in Zygisk must be disabled for that module path.
- Vector/LSPosed only if intentionally testing future Nubia hook lanes.

## Container Method Matrix

The baseline reports method ownership separately from readiness. A runtime can
be ready while display is still blocked.

| Method id | Container ref | Container kind | Display status meaning | Current start posture |
| --- | --- | --- | --- | --- |
| `phone_app_bridge` | `waylandie_app_imagefs` | `app_proot` | Phone active module proves WayLandIE/Gamescope/Xwayland display with `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`, `NONE_WAYLAND_DISPLAY`, `vkGetMemoryFdKHR` failures `0`, and real-buffer commits `2`; game-client runtime proof is not promoted yet. | No start command; game-client runtime proof is the next bounded gate before Steam/Proton promotion. |
| `anland_surface` | dedicated `anland-ubuntu26-kde` DroidSpaces profile/container | `droidspaces` | Ready only when the Anland consumer/daemon, env, socket bind, and producer rootfs are present. | Read-only preflight plus copyable source-backed setup commands. |
| `droidspaces_rootfs_image` | `rootfs.img` | `droidspaces_rootfs_image` | Storage/startup method, not a display renderer by itself. | Use `--rootfs-img` or `--rootfs-arc ... create`. |
| `droidspaces_rootfs_directory` | `rootfs_directory` | `droidspaces_rootfs_directory` | Storage/startup method for unpacked rootfs testing. | Use `--rootfs`. |
| `droidspaces_termux_x11` | `droidspaces_container_enable_termux_x11` | `droidspaces_native_x11` | DroidSpaces-native X11 display path using Termux:X11. | Set `enable_termux_x11=1`; use injected `DISPLAY=:0` on the current RM11 Pro proof. |
| `droidspaces_virgl` | `droidspaces_container_enable_virgl` | `droidspaces_native_gpu` | DroidSpaces-native virpipe 3D path. | Set `enable_virgl=1`; use injected `GALLIUM_DRIVER=virpipe`. |
| `droidspaces_turnip_kgsl` | `droidspaces_container_enable_gpu_mode` | `droidspaces_native_gpu` | Native Qualcomm/Adreno GPU path. | Set `enable_gpu_mode=1` and `enable_hw_access=1`; keep device-specific KGSL env in that profile. |
| `droidspaces_llvmpipe` | `droidspaces_container_software_gl` | `droidspaces_native_software` | Software GL fallback path. | Keep GPU/VirGL disabled and optionally force software GL. |
| `droidspaces_pulseaudio` | `droidspaces_container_enable_pulseaudio` | `droidspaces_native_audio` | Audio support path, not a display renderer. | Set `enable_pulseaudio=1`; use injected `PULSE_SERVER=unix:/tmp/.pulse-socket`. |
| `dock_drm_lease_external` | `none` | `none` | Reference evidence only; paused/crash-gated until external-display discovery, lease handoff, stop, and revoke are wired. | Operator approval and safe-mode checks are required. |
| `compatibility_software` | future dedicated software container | `none` today | Not wired by design. | No start command. |
| `recovery_safe` | `none` | `none` | Safe status lane, not a display renderer. | Always available. |

Phone/App Mode exposes `selected_icd`, `selected_vulkan_driver`, and
`loader_pin` in read-only status output. For the current R6 proof path,
`VK_ICD_FILENAMES` and `VK_DRIVER_FILES` both point to the pinned local
Freedreno ICD manifest inside the WayLandIE imagefs; that ICD then points to
the local `libvulkan_freedreno.so`.

DroidSpaces-native rootfs, display, GPU, software rendering, and audio methods
come from the DroidSpaces repos and remain separate rows. Anland must not
silently rewrite a general Termux:X11, VirGL, or Turnip test container in place.
Its mode flips display ownership to the Anland daemon socket and Wayland/KGSL
env, so the safer target is a dedicated Anland profile/container.

The command contract is:

```sh
su -c /data/adb/modules/nebula_core/bin/nebula-core display method-containers --json
su -c /data/adb/modules/nebula_core/bin/nebula-core display method-profiles --json
```

`method-profiles` is read-only. It emits per-method DroidSpaces profile
templates for Anland, Termux:X11, VirGL, Turnip/KGSL, llvmpipe, and PulseAudio.
Safe config-only materialization is direct atomic file creation of
`container.config`, followed later by:

```sh
droidspaces --config=<container.config> start
```

DroidSpaces `create` creates a rootfs image, while `start` persists or mirrors
the active `container.config`. Use one writable rootfs image or directory per
profile; do not run multiple active profiles against the same writable
`rootfs.img`.

Known Anland requirements from source/runtime evidence:

```ini
enable_termux_x11=0
enable_hw_access=1
enable_gpu_mode=1
env_file=/data/local/Droidspaces/Containers/<container>/anland.env
bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock
```

```ini
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
WAYLAND_DISPLAY=wayland-0
XDG_SESSION_TYPE=wayland
QT_QPA_PLATFORM=wayland
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
TU_DEBUG=noconform
```

The Android-side daemon creates `/data/local/tmp/display_daemon.sock`. The
container sees that socket as `/run/display.sock`. The socket must be
app-writable, normally `srw-rw-rw-`; otherwise the producer connects but the
Android consumer cannot deposit buffers. The producer rootfs comes from
`Droidspaces-rootfs-KDE-builder` with Ubuntu26, KDE auto-start, and `anland_kde`
enabled. That builder emits a `.tar.xz`; import it with `droidspaces
--rootfs-arc=... --rootfs-img=... create`, then start `anland-ubuntu26-kde` from
the resulting `rootfs.img`. Inside the running container, launch
`startanland-kde.sh`.

## Guardrails

- Baseline status never enables LSPosed hooks.
- Baseline status never writes fan, pump, LED, trigger, display, GPU, or thermal
  nodes.
- Baseline status never disables legacy DroidSpaces modules.
- Baseline status never starts Proton, Wine, Steam, DXVK, or game clients.
- WayLandIE display proof can be ready while game-client runtime proof is not
  promoted yet.
- Preview-only policy rows must keep `applied=false`; read-only status must not
  be treated as applied automation.
- Reversa reports, generated artifacts, and local zips are advisory evidence
  until classified against source paths, hashes, logs, or bounded test output.

## Promotion Rule

An integration can move from status-only to an apply/start command only after it
has:

- a fixed command name;
- a bounded input schema;
- a dry-run or snapshot path when hardware state can change;
- a host test fixture;
- a live phone proof log;
- rollback or explicit stop behavior when applicable.
