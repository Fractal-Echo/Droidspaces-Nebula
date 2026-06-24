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
| `cooling policy --json` | Read-only fan + pump policy preview from fixed telemetry and module defaults. |
| `snapshot cooling create --json` | Stores a module-state snapshot of current cooling telemetry; no hardware writes. |
| `snapshot cooling get --json` | Returns the stored cooling snapshot. |
| `snapshot cooling rollback --dry-run --json` | Returns a rollback plan with `applied=false`; no hardware writes. |
| `legacy modules --json` | Reports protected old Droidspaces module status from fixed module IDs. |
| `nubia toolkit status --json` | Reports audited Nubia Toolkit/Vector readiness without enabling hooks. |
| `runtime waylandie status --json` | Reports fixed WayLandIE rootfs, Proton, proot, and linker readiness. |
| `runtime waylandie proton-smoke --json` | Safe-mode guarded fixed root-assisted proot Proton smoke command. |

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
- The auto cooling policy is preview-only in pass 04: it returns fan/pump intents with `applied=false`, reads thresholds only from `nebula-core-module/config/defaults.json`, and performs no hardware writes.
- Pass 05 snapshot commands write only Nebula Core state, never device control nodes. Rollback remains dry-run.
- Pass 05 legacy module migration is staged only. Nebula Core does not disable, delete, replace, or launch the protected Droidspaces modules.
- Vector (`zygisk_vector`) is the Android 16 LSPosed-compatible framework lane. Nebula Core reports its module state, but hook scoping and mutating Nubia Toolkit behavior remain deferred.
- The WayLandIE Proton smoke command accepts no arbitrary path, package, or shell input and is blocked by Nebula safe mode.
- The DRM Control package is treated as a confirmed future Dock reference for composer-fd DRM leasing, SCM_RIGHTS handoff, wlroots receiver startup, and explicit revoke/stop. It is not executed from this control-plane patch.

## Source Integration

Nubia Toolkit remains an LSPosed hook lane. Pass 01 does not enable hooks.

RedMagic Control Center source is permitted by user-supplied author approval evidence and remains attributed. Nebula does not merge the APK or copy its UI; it ports only bounded capability knowledge into documentation and non-mutating status surfaces.

RedMagic PowerDeck is a local archived source reference with no recovered origin URL. Its dry-run/snapshot design is reimplemented conceptually in Nebula Core, not copied as a third-party payload.

See `AUTO_COOLING_POLICY.md` for the pass 04 policy schema, state machine, and safety rules.

See `LEGACY_MODULE_MIGRATION.md` for the protected module audit and migration guardrails.

See `DRM_CONTROL_REFERENCE.md` for the confirmed Dock-mode method that should be promoted only in a separate crash-gated pass.

Online references checked for future work:

- [FrankBarretta/LSFG-Android](https://github.com/FrankBarretta/LSFG-Android): Android LSFG app. Future/reference only because it is a graphics lane.
- [PancakeTAS/lsfg-vk](https://github.com/PancakeTAS/lsfg-vk): GPL-3.0 Vulkan layer. Future/reference only because it touches Vulkan/graphics and may depend on user-provided Lossless Scaling assets.
- [KernelSU Encore Tweaks](https://github.com/KernelSU-Modules-Repo/encore): profile/tuning module reference. Future/reference only; no generic performance writes are imported in pass 01.
