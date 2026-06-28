# Contributor Linux Native Artifact

Date: 2026-06-28

## Source

Local artifact:

```text
/mnt/d/Downloads/linux native.zip
sha256=848bab354f6f1a46f842cc32536d558518d21e0280e299f814a9a1fbaf73e4ec
```

Local evidence extraction:

```text
/home/richtofen/.android/repositories/nebula-assets/local/contributor-linux-native-2026-06-28
```

The archive has 7,813 entries, no path-traversal entries, and about 431 MB of
uncompressed material.

## Contents Observed

- Anland compositor source and Android daemon/consumer material.
- DroidSpaces engine source, docs, patches, and generated outputs.
- DroidSpaces KDE rootfs builder material.
- Desktop helper scripts for container start, Anland consumer launch, Steam
  install, audio fix, screenshots, terminal, and status checks.
- APKs, module zips, keystores, Gradle/CMake build directories, compiled
  objects, native binaries, screenshots, and generated logs.

## Integration Rule

This artifact is useful, but it is not a source drop to commit wholesale.

Allowed:

- Extract source-level requirements and command shapes.
- Compare Anland socket, daemon, producer, rootfs, and DroidSpaces profile
  behavior against Nebula Core status.
- Promote fixed, bounded commands only after tests and live proof.
- Keep hashes, inventories, and scan results under local evidence.

Not allowed:

- Commit APKs, module zips, private keys, keystores, generated build trees, or
  compiled binaries from this archive into the public repo.
- Replace the active phone-proven WayLandIE lane with this archive.
- Start containers, launch Steam, launch games, or write device nodes from this
  artifact review pass.

## Nebula Mapping

`integrations standalone --json` records this policy as an ownership split:

- Nebula APK: UI and doctor report.
- Nebula Core module: fixed privileged status and guarded commands.
- WayLandIE: external app/imagefs display lane.
- DroidSpaces/Anland: external container assets and preflight lane.
- ReZygisk/Vector: external hook provider/scope lane.
- RedMagic hardware: device-firmware node evidence, read-only in baseline.
- PowerDeck: preview/snapshot policy lane.

`display anland recipes --json` records the source-level desktop flow without
turning it into an executor. The manifest keeps these recipe families visible:

- verify/install Anland Consumer APK and daemon module artifacts;
- create the Anland Ubuntu/KDE DroidSpaces rootfs image;
- materialize `container.config` and `anland.env`;
- restart the display daemon and socket;
- start/stop/restart the selected container;
- launch the KDE/Anland producer;
- run status checks or capture screenshot evidence;
- defer shell entry, audio mutation, browser installs, and Steam installs.

The command also records the important drift: the contributor proof used
`Ubuntu`/`ubuntu` scripts, an observed 16G rootfs-create path, and both
`anland-daemon` and `virtual-drm-daemon` module naming. Nebula normalizes the
future clean profile to `anland-ubuntu26-kde`, 32G sparse image, and explicit
preflight before any mutating recipe can graduate.

Final promotion requires a reproducible source build, bounded command schema,
Reversa scan, host tests, and live proof before any new mutating command is
exposed.

`display anland status-check --json` is the first promoted read-only
recipe-adjacent status surface. It does not run the contributor status script.
Instead, it projects the selected Anland/DroidSpaces path from fixed checks:
binary/config/env/rootfs/socket/render-node/producer presence, selected
container source, and active pidfile state. It does not invoke DroidSpaces
runtime commands, process inventory, daemon log tailing, recipe commands,
container lifecycle, KDE launch, package installation, or game runtime commands.
For active image rootfs cases, producer verification remains unknown until a
separate bounded verify pass explicitly allows that runtime probe.
