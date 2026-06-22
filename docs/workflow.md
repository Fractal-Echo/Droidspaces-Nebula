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
/home/richtofen/.android/repositories/rm11mainassets/worktrees/waylandie-vower-578b431
```

Status:

- Nebula package installs.
- Android-side AdrenoTools bridge now reports ready.
- Rootfs must be restored/staged before re-running Vulkan/Wayland smoke tests.

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

## Vulkan Smoke Gate

2026-06-21 controlled `vkcube` A/B was blocked during preflight.

Do not run `vkcube`, Steam, Proton, DXVK, or gamescope unless `vulkaninfo --summary` first exits `0` from the same Nebula app-private rootfs and reports `Adreno (TM) 840`.

Current blocked checkpoint:

| Check | Result |
| --- | --- |
| Package | `io.droidspaces.nebula.waylandie` |
| Version | `0.2.0-no-root-nebula13-rootfs-vulkan-smoke` |
| Expected KGSL ICD | Missing at `/data/user/0/io.droidspaces.nebula.waylandie/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json` |
| Expected KGSL driver | Missing at `/data/user/0/io.droidspaces.nebula.waylandie/files/imagefs/usr/local/lib/libvulkan_freedreno.so` |
| Current ICD path | Present at `/data/user/0/io.droidspaces.nebula.waylandie/files/imagefs/usr/share/vulkan/icd.d/freedreno_icd.json` |
| Current driver path | Present at `/data/user/0/io.droidspaces.nebula.waylandie/files/imagefs/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so` |
| Current `/usr/local` ICD smoke | Exit `1`, no drivers |
| Current `/usr/share` ICD smoke | Exit `1`, physical-device enumeration failed |

Next single action: restore or stage the verified glibc KGSL/Turnip files into the expected `/usr/local` smoke path, then rerun only `vulkaninfo --summary`.
