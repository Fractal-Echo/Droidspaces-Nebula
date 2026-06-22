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

## Build

```bash
ANDROID_HOME=/home/richtofen/.android/sdk ANDROID_SDK_ROOT=/home/richtofen/.android/sdk \
  /home/richtofen/.android/repositories/rm11mainassets/projects/droidspace-repos/Droidspaces-OSS/Android/gradlew \
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
/home/richtofen/.android/repositories/rm11mainassets/worktrees/waylandie-vower-578b431
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

## Safety

This app does not request storage, root, notification, overlay, or shell permissions. It does not write device nodes or install APKs.

Public source must not contain private dumps, full EDL backups, private keys, serials, personal logs, token material, or proprietary Qualcomm blobs.
