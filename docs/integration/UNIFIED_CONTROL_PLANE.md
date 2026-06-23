# Nebula Unified Control Plane

Pass 01 splits Droidspaces: Nebula into one Android APK and one KernelSU module.

## Roles

APK:

- UI and profiles.
- Capability display.
- Module/version/protocol status.
- Fixed command invocation only.
- Logs and diagnostics.
- No unrestricted root execution.
- No target launch in pass 01.

KSU module:

- Fixed root CLI.
- SELinux policy file, with no speculative rules in pass 01.
- Future vendor/device access owner.
- Future target supervision owner.
- Future RedMagic button event integration owner.
- Safe mode and crash counter owner.
- No target auto-launch during boot.

## Protocol

`NEBULA_CORE_PROTOCOL_VERSION=1`

Allowed fixed commands:

| Command | Result |
| --- | --- |
| `status --json` | Module, protocol, version, safe mode, profile, daemon state. |
| `capabilities --json` | Fixed advertised module capabilities. |
| `profile get --json` | Current stored profile. |
| `profile set safe` | Stores safe profile and enables safe mode. |
| `profile set phone` | Stores phone profile and clears safe mode. Starts no target. |
| `safe-mode get --json` | Safe-mode state. |
| `safe-mode enable` | Enables safe mode and stores safe profile. |
| `logs tail --lines N` | Returns the last 1-500 module log lines as JSON. |
| `redmagic probe --json` | Read-only aggregate RM11 Pro RedMagic telemetry. |
| `redmagic pump probe --json` | Read-only liquid-cooling pump telemetry from fixed micropump nodes. |

Blocked pass 01 activations:

- `profile set dock` returns `BLOCKED_NOT_READY`.
- `profile set compatibility` returns `BLOCKED_NOT_READY`.

No command accepts arbitrary shell text. The APK client exposes typed methods only.

## Version Lock

The shared project version is defined in `gradle.properties`:

- `nebulaVersion`
- `nebulaVersionCode`
- `nebulaCoreProtocolVersion`

The APK exports these through `BuildConfig`. The module ZIP builder reads the same properties and rewrites staged `module.prop` before packaging.

The APK displays:

- app version;
- expected module version;
- protocol version;
- app Git commit when Gradle can read it;
- reported module version/protocol/Git commit from `status --json`.

A module version or protocol mismatch is visible in the Nebula Core card and doctor report.

## Safety

Pass 01 defaults:

- Safe profile first.
- Safe mode available and explicit.
- Dock Mode blocked.
- Compatibility Mode blocked.
- No phone/device action during build or tests.
- No boot-time target start.
- No compositor/display/backend start.
- No unrestricted shell console in the APK.
- Mutating Nubia/RedMagic controls are represented as audited status only.
- The RedMagic pump probe reads only fixed source-derived `/proc/driver/micropump` nodes and never exposes pump enable, disable, speed, mode, or profile setters.

## Source Integration

Nubia Toolkit remains an LSPosed hook lane. Pass 01 does not enable hooks.

RedMagic Control Center source is permitted by user-supplied author approval evidence and remains attributed. Nebula does not merge the APK or copy its UI; it ports only bounded capability knowledge into documentation and non-mutating status surfaces.

RedMagic PowerDeck is a local archived source reference with no recovered origin URL. Its dry-run/snapshot design is reimplemented conceptually in Nebula Core, not copied as a third-party payload.

Online references checked for future work:

- [FrankBarretta/LSFG-Android](https://github.com/FrankBarretta/LSFG-Android): Android LSFG app. Future/reference only because it is a graphics lane.
- [PancakeTAS/lsfg-vk](https://github.com/PancakeTAS/lsfg-vk): GPL-3.0 Vulkan layer. Future/reference only because it touches Vulkan/graphics and may depend on user-provided Lossless Scaling assets.
- [KernelSU Encore Tweaks](https://github.com/KernelSU-Modules-Repo/encore): profile/tuning module reference. Future/reference only; no generic performance writes are imported in pass 01.
