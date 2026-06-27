# Nebula Workflow

## Source Of Truth

Use `Fractal-Echo/Droidspaces-Nebula` for source, docs, and release notes.

Use local `nebula-assets` for bulky artifacts and evidence. Do not turn `nebula-assets` into a public source repo.

## Promotion Flow

1. Prove a feature in a local worktree or upstream fork.
2. Record the exact repo, branch, commit, APK hash, and test result in `nebula-assets`.
3. Copy only reviewed source changes into this repo.
4. Keep assets out of git unless they are tiny text manifests.
5. Build locally.
6. Publish only after review, with SHA256 hashes and rollback notes.

## Current Active Worktree

```text
/home/richtofen/.android/repositories/nebula-assets/Repos/waylandie-vower-578b431
```

Status:

- Nebula package installs.
- Android-side AdrenoTools bridge reports ready.
- R6 Wayland proof 03 passed with the local pinned Freedreno ICD/driver,
  Gamescope sidecar, Xwayland sidecar, dmabuf-present, real-buffer commits, and
  zero `vkGetMemoryFdKHR` failures.
- Steam/Proton/Wine remains a separate game-client proof gate.

## Verified Hub Build

2026-06-21:

- Source path: `/home/richtofen/.android/repositories/Droidspaces-Nebula`
- Command: `:app:assembleDebug`
- Result: build-pass
- APK SHA256: `e08366401971e27cbea108c17cc35f19457ce19c76538d39fa4336dee02cb815`
- Artifact policy: keep generated APKs in local `nebula-assets`, not in public source.

## CI Gate

`.github/workflows/nebula-android.yml` runs:

1. `scripts/validate-public-source.sh`
2. Android debug APK build
3. SHA256 generation for the CI artifact

The workflow is intended for `main`, `build/**`, `ci/**`, pull requests, and
manual dispatch.

## Cleanup Flow

1. Keep one active worktree per lane.
2. Keep one upstream clone per useful reference.
3. Delete generated build caches.
4. Delete duplicate non-git comparison trees after their retained copy is documented.
5. Do not delete private backups, OrangeFox rollback evidence, or kernel evidence during Nebula cleanup.

## Wayland / Vulkan Gate

2026-06-25 R6 evidence now treats WayLandIE as an export-blocked baseline, not
a real-buffer display pass.

Do not run Steam, Proton, DXVK, or game targets until the bounded game-client gate
is staged. Display preflight must first confirm the same requirements used by the
proof:

| Check | Required state |
| --- | --- |
| Package | `io.droidspaces.nebula.waylandie` |
| Version | `0.2.0-no-root-nebula13-rootfs-vulkan-smoke` |
| Local KGSL ICD | Present at `/data/user/0/io.droidspaces.nebula.waylandie/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json` |
| Local KGSL driver | Present at `/data/user/0/io.droidspaces.nebula.waylandie/files/imagefs/usr/local/lib/libvulkan_freedreno.so` |
| Gamescope sidecar | `xwayland-gamescope-14-exportable-fence-guard-a4-473ba531` |
| Xwayland sidecar | `xwayland-gamescope-06-xwayland-9f1a3d62` |
| Loader-pin result | `NEBULA_R6_EXPORT_A1_VULKAN_LOADER_PIN_CONFIRMED` |
| Software GLX result | `NEBULA_R6_SOFTWARE_GLX_REPRODUCED` with `llvmpipe` |
| Active blocker | `vulkan_export_real_buffer`: `vkGetMemoryFdKHR` failures, 0 real-buffer commits, 8 no-buffer commits |

Next single action: rerun only the bounded A1 export/runtime proof after ADB is
live and the staged runner path is verified.
