# Nebula R6 Child-Libpath Frontier

Date: 2026-06-25

Purpose: pin the current R6 graphics frontier so future passes do not reopen solved stages.

## Current Policy Note: 2026-06-27

This file preserves the 2026-06-25 child-libpath frontier. It is historical
evidence now, not the active Nebula control-plane blocker.

Current live control-plane status:

- app/native bridge solved;
- local ICD/driver loader pin confirmed;
- later software GLX evidence is treated as reproduced;
- do not reopen full GLX visual/fbconfig inventory or run `glxgears` for this
  docs cleanup;
- active display blocker is clear:
  `NONE_WAYLAND_DISPLAY`;
- remaining promotion blocker:
  `GAME_CLIENT_RUNTIME_NOT_PROMOTED_39BIT_VA`.

Current classification:

```text
NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS
```

## Preserved 2026-06-25 Frontier

Android abstract bridge:

- solved
- `/proc/net/unix` contains `@waylandie.nebula.bridge.v1`

Native Linux Wayland bridge:

- solved/restored
- `server=ready`
- `socket=wayland-0`
- stderr empty
- cleanup exit `143`

Gamescope:

- launches from promoted r6 sidecar
- selects `Adreno (TM) 840`
- reaches `Xserver is ready`
- exits `0` after child shutdown

Xwayland:

- runner invoked
- `xkbcomp` invoked
- Xserver ready
- exits `1` after child SIGBUS / broken pipe

Preserved failure at that time:

- first decisive failure line: `Bus error`
- child command: `glxgears`
- child exit: `135` (`SIGBUS`)
- bridge real buffer commits: `0`
- GLX inventory was not captured
- software GLX was requested but not reproduced yet

Preserved classification at that time:

```text
NEBULA_R6_HARNESS_REGRESSION
```

## Do Not Reopen

Do not treat the current state as any of these:

- app bridge failure
- native bridge failure
- XKB failure
- Xauthority/XWM failure
- parent Wayland registry failure
- DRM lease work
- Proton/Wine/Steam readiness

The next failure is post-Xserver child runtime/library-path behavior.

## Required Libpath Model

`BRIDGE_LIBPATH`:

- use the restored working bridge path only
- exclude r6 private libc, loader, Wayland, wlroots-era private libs

`GAMESCOPE_LIBPATH`:

- r6 Gamescope runtime first
- then Xwayland/rootfs/system libs

`CHILD_LIBPATH`:

- Xwayland sidecar `extra-lib`
- Xwayland sidecar `usr/lib/aarch64-linux-gnu`
- imagefs `usr/local/lib`
- imagefs `usr/lib`
- imagefs `usr/lib/aarch64-linux-gnu`
- imagefs `lib/aarch64-linux-gnu`
- `/system/lib64`

Do not include r6 private libc/loader/Wayland libs in `CHILD_LIBPATH` unless a controlled A/B proves they are required.

## Next Single Action

Split `CHILD_LIBPATH` from `GAMESCOPE_LIBPATH`.

Run in this order:

1. `glxinfo -B`
2. full `glxinfo` visual/fbconfig inventory
3. bounded `glxgears -info` only after `glxinfo` succeeds

Do not run `glxgears` first.

## Required Classification Rules

```text
NEBULA_R6_REGRESSED_BRIDGE_UNEXPECTED
NEBULA_R6_GAMESCOPE_OR_XWAYLAND_REGRESSION
NEBULA_R6_CHILD_LIBPATH_SIGBUS
NEBULA_R6_GLX_NO_RGB_VISUAL_OR_FBCONFIG
NEBULA_R6_SOFTWARE_GLX_REPRODUCED
NEBULA_R6_HARDWARE_GLX_PASS
```

Do not call software GLX a hardware pass. Do not proceed to Wine, DXVK, FEX, Proton, or Steam after software GLX alone.

## Local Evidence

Parity report:

```text
/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-25-nebula-r6-harness-parity-01/result.md
```

Key files:

```text
/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-25-nebula-r6-harness-parity-01/historical-vs-r6.tsv
/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-25-nebula-r6-harness-parity-01/bridge-environment.diff
/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-25-nebula-r6-harness-parity-01/exact-historical-command.txt
/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-25-nebula-r6-harness-parity-01/exact-r6-command.txt
```

Artifact hashes:

```text
2f98ace78c3b4ec7807193f49859a49d9fa3b0d68536659899c02dcebee31a11  result.md
8a41fccbc1a1780e70d57ea7501fb9b9241cde1df05d3903cb982333a4cc97f3  exact-r6-command.txt
9f8de4863f965fc74f762770c5fc343f6c4bf96f424e2707605ac50ae5702b85  bridge-environment.diff
adf28199b749c0409246a4b8e90895042cbcc607c0b2bed8cfd0c9db4f51f04d  exact-historical-command.txt
c326a747dc1ce33ee3c6de890c07b162ff06af5799be6c98d05b4f9d46c708e3  historical-vs-r6.tsv
```
