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
| `integrations baseline --json` | Reports the one baseline APK/module contract across WayLandIE, DroidSpaces/Anland, Nubia Toolkit, RedMagic Control Center, and PowerDeck without enabling mutating behavior. |
| `nubia toolkit status --json` | Reports audited Nubia Toolkit/Vector readiness without enabling hooks. |
| `runtime waylandie status --json` | Reports fixed WayLandIE rootfs, Proton, proot, and linker readiness. |
| `runtime waylandie proton-smoke --json` | Safe-mode guarded fixed root-assisted proot Proton smoke command. |
| `display lanes --json` | Read-only multi-lane selector status for Phone/App, Dock Lease, Anland, Compatibility, and Recovery lanes. |
| `display lane phone preflight --json` | Read-only WayLandIE/Gamescope/Xwayland lane preflight and active blocker status. |
| `display lane anland preflight --json` | Read-only selected DroidSpaces container, Anland env/socket, and render-node preflight. |
| `display lane dock preflight --json` | Read-only Dock lease evidence and operator approval requirements. |

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
- Dock profile activation blocked until the broker/receiver start path exists.
- Dock Lease Mode is a proven external-display reference lane, surfaced read-only
  until Nebula has fixed start/stop/revoke commands.
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
- The baseline integration report is read-only. It can mark an integration ready,
  partial, missing, or deferred, but it does not activate LSPosed hooks, write
  RedMagic nodes, start DroidSpaces containers, or launch WayLandIE targets.
- Vector (`zygisk_vector`) is the Android 16 LSPosed-compatible framework lane. Nebula Core reports its module state, but hook scoping and mutating Nubia Toolkit behavior remain deferred.
- The WayLandIE Proton smoke command accepts no arbitrary path, package, or shell input and is blocked by Nebula safe mode.
- The DRM Control package and Bob Dilian evidence are treated as confirmed Dock
  references for external-display-only composer-fd DRM leasing, `SCM_RIGHTS`
  handoff, wlroots receiver startup, and explicit revoke/stop. This patch
  exposes read-only preflight/status only; it does not execute leases.

## Source Integration

Nubia Toolkit remains an LSPosed hook lane. Pass 01 does not enable hooks.

RedMagic Control Center source is permitted by user-supplied author approval evidence and remains attributed. Nebula does not merge the APK or copy its UI; it ports only bounded capability knowledge into documentation and non-mutating status surfaces.

RedMagic PowerDeck is a local archived source reference with no recovered origin URL. Its dry-run/snapshot design is reimplemented conceptually in Nebula Core, not copied as a third-party payload.

## Display Lane Strategy

Nebula should solve and expose multiple display/runtime lanes because hardware,
kernels, docks, monitors, and user goals differ. The app is the selector and
diagnostic hub; Nebula Core is the fixed privileged executor. No lane should
silently replace another working lane.

Initial lane model:

| Lane | Purpose | Current ownership | Current requirements |
| --- | --- | --- | --- |
| Phone/App Mode | Run through the proven WayLandIE/bridge path on the phone display. | WayLandIE -> Wayland -> Turnip/KGSL -> bridge -> Gamescope/Xwayland. | Current display proof is `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS` when the pinned local ICD/driver and exact Gamescope/Xwayland sidecars are staged. Steam/Proton remains unpromoted until a bounded game-client proof promotes it. |
| Dock Lease Mode | Give Linux direct external-display ownership without taking the internal panel. | Future Nebula Core DRM lease broker and rootfs receiver. | Proven reference, operator approval required; external-display-only; explicit stop/revoke; no boot auto-launch. |
| Anland Surface Mode | Use Anland/Android app surface path when users need compatibility or a non-lease display. | Existing Anland/Droidspaces ecosystem. | Select by explicit override or one live active PID file; reject stale PID files and rootfs paths outside the selected container; require `anland.env` plus `/data/local/tmp/display_daemon.sock` before display-ready; fixed commands only; no raw helper-script execution. |
| Compatibility Mode | Conservative fallback for devices without RM11 Pro hardware, modified kernel, or working dock lease. | App-guided setup and read-only diagnostics first. | Must stay blocked until exact behavior is implemented and reversible. |
| Recovery/Safe Mode | Preserve rollback, ADB visibility, module safe mode, and phone usability. | Nebula Core and protected old modules until replacement is proven. | Always available; blocks target launches and risky display mutation. |

The target experience is one app and one core module coordinating these lanes,
not one rendering path forced onto every user.

Runtime constraints:

- The RM11 Pro stock RedMagic ROM plus OnePlus Wild kernel lane is
  live-confirmed as a 39-bit kernel VA environment through `/proc/config.gz`.
  Nebula surfaces this in display-lane status and must avoid assuming 45-bit
  userspace/runtime behavior.
- R6 Wayland proof 03 promotes the Phone/App display lane: dmabuf-present,
  real-buffer commits greater than zero, zero `vkGetMemoryFdKHR` failures,
  Gamescope exit `0`, bridge exit `0`, and Xwayland ready.
- Steam, Proton, and Wine were not run in that proof. Treat the remaining blocker
  as a game-client runtime requirement under 39-bit VA, not as a Wayland/Gamescope
  display blocker.

See `AUTO_COOLING_POLICY.md` for the pass 04 policy schema, state machine, and safety rules.

See `LEGACY_MODULE_MIGRATION.md` for the protected module audit and migration guardrails.

See `DRM_CONTROL_REFERENCE.md` for the confirmed Dock-mode method that should be
promoted only in a separate operator-approved pass.

See `REVERSA_FINDINGS_ASSESSMENT.md` for the contradiction assessment and the
2026-06-26 update that promotes the R6 Wayland display proof.

See `OLD_SIDECAR_PROMOTION_AUDIT.md` for the preserved sidecar chain and the
ARM64EC/39-bit Wine GUI blocker audit.

See `REDMAGIC_GAMEHUB_CONTROL_DECK.md` for the Control Deck UI direction and the
private RM11/China-ROM asset-pack lane.

Online references checked for future work:

- [FrankBarretta/LSFG-Android](https://github.com/FrankBarretta/LSFG-Android): Android LSFG app. Future/reference only because it is a graphics lane.
- [PancakeTAS/lsfg-vk](https://github.com/PancakeTAS/lsfg-vk): GPL-3.0 Vulkan layer. Future/reference only because it touches Vulkan/graphics and may depend on user-provided Lossless Scaling assets.
- [KernelSU Encore Tweaks](https://github.com/KernelSU-Modules-Repo/encore): profile/tuning module reference. Future/reference only; no generic performance writes are imported in pass 01.
