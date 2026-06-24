# Old Sidecar Promotion Audit

Date: 2026-06-24

## Scope

This is a bounded read-only audit of the existing WayLandIE/Gamescope/Xwayland
sidecar chain. It uses only the current Hub docs and the preserved sidecar logs
under `nebula-assets/logs`.

No device action, graphics launch, DRM operation, install, reboot, or source
mutation was performed for this audit.

## Sidecar Chain

| Sidecar | Classification | What it proves | Current decision |
| --- | --- | --- | --- |
| 05 | `GAMESCOPE_PROCESS_LIVE_PASS_XWAYLAND_KEYMAP_BLOCKED` | Gamescope starts and stays alive with the bridge; blocker moved to XKB. | Historical setup proof. |
| 06 | `XWAYLAND_XKB_PATH_PASS_XWM_AUTH_BLOCKED` | `XWAYLAND_XKBCOMP` wrapper fixes the Android `/usr/bin/xkbcomp` path assumption. | Keep the XKB wrapper requirement. |
| 07 | `GAMESCOPE_PARENT_WAYLAND_PRESENTATION_CHECK_STALLED_BEFORE_XWAYLAND` | Xauthority handoff was corrected; a suspected parent-Wayland stall appeared. | Superseded by sidecar-11. |
| 08 | `NOT_PARENT_WAYLAND_BLOCKED` | Parent Wayland registry and presentation callbacks returned; first failure moved to GLX. | Supporting evidence only. |
| 09 | `SUPERSEDED_PARENT_REGISTRY_BLOCK` | Parent-registry blocker hypothesis. | Superseded by sidecar-11. |
| 10 | `WAYLAND_REGISTRY_PASS` | Raw Wayland client received 11 bridge globals including `wl_compositor`, `xdg_wm_base`, `wp_presentation`, `zwp_linux_dmabuf_v1`, and `wl_shm`. | Proven bridge registry baseline. |
| 11 | `PARENT_DISPATCH_NOT_REPRODUCED_XWAYLAND_LAUNCHES_GLX_BLOCKED` | Gamescope receives registry globals, Xwayland launches, blocker becomes RGB GLX visual/fbconfig exposure. | Canonical source-of-truth endpoint. |
| 12 | `XWAYLAND_GLX_EXTENSION_MISSING` | Xwayland had no GLX extension, no RGB GLX visuals, and no FBConfigs; plain X11 RGB visuals existed. | Supporting GLX blocker evidence. |
| 13 | `XWAYLAND_GLX_RENDER_PASS_FORCE_COMPOSITION` | `--force-composition` plus ARGB8888/ready-without-sync-fd produces full-size parent xdg dmabufs and glxgears renders through Xwayland. | Promotion candidate, not default until runtime smoke passes. |

## Display Promotion Finding

Sidecar-13 is the strongest Phone/App display artifact:

- command includes `gamescope --force-composition --expose-wayland -W 800 -H 600 -w 800 -h 600`;
- bridge summary reports zero-copy `dmabuf-present`, 1318 commits, and 0 failures;
- full-size parent attaches are `2688x1216`;
- Xwayland and glxgears remain alive at the final sample;
- glxgears reports about 2696-2718 FPS.

The display fix is not a Wine fix. It proves X11 software GLX presentation
through the bridge when Gamescope is forced to composite into a full-size parent
xdg buffer.

## Wine Runtime Finding

The post-sidecar-13 Wine GUI attempts move the blocker into ARM64EC Wine runtime
startup:

- r28 keeps Gamescope, bridge, Xwayland, Xauthority, and XKB alive;
- `winex11.drv` maps and begins `PROCESS_ATTACH`;
- the child exits with `CHILD_EXIT=1`;
- bridge real-buffer commits remain `0`;
- pattern counts include `invalid frame=14244447`, `c0000005=1`,
  `winex11.drv=25`, `CANNOT LINK=0`, `dlopen=0`, and `libX11=0`.

Proton 11 console smoke is not blocked the same way:

- `WINE_VERSION_EXIT=0`;
- `CMD_VER_EXIT=0`;
- `CMD_ECHO_EXIT=0`.

That separates basic Wine loader availability from GUI driver attach.

## 39-Bit VA Evidence

The RM11 Pro test kernel is live-confirmed as a 39-bit VA environment through
`/proc/config.gz`:

- `CONFIG_ARM64_VA_BITS_39=y`;
- `CONFIG_ARM64_VA_BITS=39`;
- `CONFIG_ARM64_4K_PAGES=y`;
- `CONFIG_ARM64_PA_BITS=48`;
- compat support is enabled.

The Wine driver metadata reinforces the runtime suspicion:

- `ntdll.dll` and `winex11.drv` are `COFF-ARM64X`;
- both are `IMAGE_FILE_LARGE_ADDRESS_AWARE`;
- both have `IMAGE_DLL_CHARACTERISTICS_HIGH_ENTROPY_VA`;
- both use image base `0x180000000`;
- both carry exception/unwind metadata through `.pdata`;
- both carry ARM64X metadata through `.a64xrm`.

## Rejected Interpretations

- Do not treat sidecar-13 as proof that Steam is ready. Steam is downstream of
  Wine GUI attach and must wait.
- Do not treat Wine GUI failure as a Gamescope force-composition regression.
  Xwayland and Gamescope are already alive in the decisive Wine run.
- Do not merge Dock Lease evidence into Phone/App Mode. Dock Lease is an
  external-display-only broker/SCM_RIGHTS lane.
- Do not rerun old parent-registry or XKB probes unless a new artifact
  contradicts sidecar-10/11.

## Next Patch Target

Patch or swap the ARM64EC Wine runtime path, not the display path:

1. Inspect the exact Proton/Wine source for `PROTON_LIMIT_ADDRESS_SPACE`,
   `WINE_LARGE_ADDRESS_AWARE`, ARM64EC view allocation, ARM64X metadata,
   `.pdata` unwind lookup, and SEH frame validation.
2. Prefer a reversible runtime experiment that constrains PE image placement or
   disables high-entropy VA behavior for the minimal GUI smoke.
3. Reuse the exact sidecar-13 force-composition harness.
4. Promote the Phone/App lane only when a minimal Wine GUI child produces real
   bridge buffer commits.

Classification:

`SIDECAR13_DISPLAY_PROMOTION_CANDIDATE_ARM64EC_39BIT_RUNTIME_BLOCKED`
