# Nebula Unified Control Plane

Pass 01 splits Droidspaces: Nebula into one Android APK and one KernelSU module.
`CONTROL_PLANE_POLICY.md` is the current policy authority for docs/UI wording
around read-only probes, preview-only status, runtime-lane separation, hook-lane
separation, and source/asset rules.

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
| `nubia toolkit status --json` | Reports audited Nubia Toolkit, ReZygisk provider, and Vector readiness without enabling hooks. |
| `runtime waylandie status --json` | Reports fixed WayLandIE rootfs, Proton, proot, live package/native/linker paths, selected local Freedreno ICD/driver, and the `VK_ICD_FILENAMES` / `VK_DRIVER_FILES` loader pin. |
| `runtime waylandie proton-smoke --json` | Safe-mode guarded fixed root-assisted proot Proton smoke command. |
| `display lanes --json` | Read-only multi-lane selector status for Phone/App, Dock Lease, Anland, Compatibility, and Recovery lanes. |
| `display method-containers --json` | Read-only display method ownership map for WayLandIE, DroidSpaces/Anland, native DroidSpaces methods, Dock reference, compatibility, and recovery lanes. |
| `display method-profiles --json` | Read-only DroidSpaces/Anland profile templates for separate rootfs image, rootfs directory, Termux:X11, VirGL, Turnip/KGSL, llvmpipe, and PulseAudio methods. |
| `display lane phone preflight --json` | Read-only WayLandIE/Gamescope/Xwayland lane preflight, active blocker status, and reinstall-safe live `package_path` / `native_lib_dir` / `glibc_loader` evidence. |
| `display lane anland preflight --json` | Read-only selected DroidSpaces container, Anland env/socket, and render-node preflight. |
| `display lane dock preflight --json` | Read-only Dock lease evidence and operator approval requirements. |

Blocked pass 01 activations:

- `profile set dock` returns `BLOCKED_NOT_READY`.
- `profile set compatibility` returns `BLOCKED_NOT_READY`.

No command accepts arbitrary shell text. The APK client exposes typed methods only.
The APK dispatches to the active Nebula Core module first:
`/data/adb/modules/nebula_core/bin/nebula-core`. A pending
`/data/adb/modules_update/nebula_core/bin/nebula-core` is only a fallback when
the active module is missing, or an explicit debug/probe override after the
anti-regression guard rejects stale pending output. This prevents a staged
module from masking the phone-proven active baseline.

WayLandIE package paths are resolved live from Android package state. Archived
proof paths under `/data/app/...` are evidence only; they must not be reused as
fixed launch paths after reinstall because Android rotates the install-instance
directory while keeping the stable app data directory and sidecar paths intact.

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
- app Git revision identifier when Gradle can read it;
- reported module version/protocol/revision identifier from `status --json`.

Git revision metadata here is project provenance only. It does not permit adding
proprietary RedMagic ROM, GameHub, vendor APK, sound, icon, layout, or binary
assets into the public Hub.

A module version or protocol mismatch is visible in the Nebula Core card and doctor report.

## Safety

Pass 01 defaults:

- Safe profile first.
- Safe mode available and explicit.
- Dock profile activation blocked until the broker/receiver start path exists.
- Dock Lease Mode is a proven external-display reference lane, surfaced read-only
  and paused/crash-gated until Nebula has fixed start/stop/revoke commands.
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
- ReZygisk (`rezygisk`) is the selected standalone Zygisk provider candidate for
  hook-lane testing when the normal provider path fails. Local artifact:
  `/mnt/d/Downloads/ReZygisk-v1.0.0-rc.9-release.zip`, SHA-256
  `5da9308aca2f1233e1b74744a86b39ab55749db352a829c7578743df6af16f4f`, module
  version `v1.0.0 (513-faccedf-release)`, author `The PerformanC Organization`.
  Recording this artifact does not mean it is installed, enabled, scoped, or
  hook-ready. Its module scripts exit when Magisk built-in Zygisk is enabled, so
  disable Magisk built-in Zygisk before using this provider in a separate hook
  test pass.
- Vector (`zygisk_vector`) is the Android 16 LSPosed-compatible framework lane.
  Nebula Core reports its module state, but hook scoping and mutating Nubia
  Toolkit behavior remain deferred.
- The WayLandIE Proton smoke command accepts no arbitrary path, package, or shell input and is blocked by Nebula safe mode.
- The DRM Control package and Bob Dilian evidence are treated as confirmed Dock
  references for external-display-only composer-fd DRM leasing, `SCM_RIGHTS`
  handoff, wlroots receiver startup, and explicit revoke/stop. This patch
  exposes read-only preflight/status only; it does not execute leases and does
  not imply an active Dock lease.

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
| Phone/App Mode | Run through the WayLandIE/bridge path on the phone display. | WayLandIE -> Wayland -> Turnip/KGSL -> bridge -> Gamescope/Xwayland. | Phone active module proves `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`, `NONE_WAYLAND_DISPLAY`, `vkGetMemoryFdKHR` failures `0`, and real-buffer commits `2`. Steam/Proton remains unpromoted until a bounded game-client proof promotes it. |
| Dock Lease Mode | Give Linux direct external-display ownership without taking the internal panel. | Future Nebula Core DRM lease broker and rootfs receiver. | Proven advisory evidence, paused/crash-gated, operator approval required; external-display-only; explicit stop/revoke; no boot auto-launch. |
| Anland Surface Mode | Use Anland/Android app surface path when users need compatibility or a non-lease display. | Existing Anland/Droidspaces ecosystem. | Select by explicit override or one live active PID file; reject stale PID files and rootfs paths outside the selected container; require `anland.env` plus `/data/local/tmp/display_daemon.sock` before display-ready; fixed commands only; no raw helper-script execution. |
| Compatibility Mode | Conservative fallback for devices without RM11 Pro hardware, modified kernel, or working dock lease. | App-guided setup and read-only diagnostics first. | Must stay blocked until exact behavior is implemented and reversible. |
| Recovery/Safe Mode | Preserve rollback, ADB visibility, module safe mode, and phone usability. | Nebula Core and protected old modules until replacement is proven. | Always available; blocks target launches and risky display mutation. |

Dock Lease Stage 08 is host-only. The command/result schemas under
`docs/integration/schemas/` and fixtures under `tests/fixtures/dock-lease/`
exist to prove the authority boundary before runtime work. They do not add an
APK allowlist command, module command, DRM lease start path, compositor launch,
or device mutation. `scripts/dock-lease-command-plan-report.js` turns those
fixtures into a generated review report only; it does not unlock Dock runtime
execution.

The target experience is one app and one core module coordinating these lanes,
not one rendering path forced onto every user.

Runtime constraints:

- The RM11 Pro stock RedMagic ROM plus OnePlus Wild kernel lane is
  live-confirmed as a 39-bit kernel VA environment through `/proc/config.gz`.
  Nebula surfaces this in display-lane status and must avoid assuming 45-bit
  userspace/runtime behavior.
- Current Phone/App control-plane status is phone-proof aligned:
  `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`, `NONE_WAYLAND_DISPLAY`,
  `vkGetMemoryFdKHR` failures `0`, and bridge real-buffer commits `2`.
  The remaining blocker is game-client runtime promotion under the
  live-confirmed 39-bit VA constraint.
- App/native bridge readiness and child software GLX reproduction should not
  reopen the older full GLX visual/fbconfig inventory. Steam, Proton, Wine, DXVK,
  FEX, and game clients remain unpromoted until a bounded game-client proof
  passes under the live-confirmed 39-bit VA constraint.

See `AUTO_COOLING_POLICY.md` for the pass 04 policy schema, state machine, and safety rules.

See `LEGACY_MODULE_MIGRATION.md` for the protected module audit and migration guardrails.

See `DRM_CONTROL_REFERENCE.md` for the confirmed Dock-mode method that should be
promoted only in a separate operator-approved pass.

See `CONTROL_PLANE_POLICY.md` for the current control-plane policy split.

See `REVERSA_FINDINGS_ASSESSMENT.md` for the contradiction assessment and the
2026-06-27 update that demotes stale real-buffer-pass wording to historical
evidence while preserving the R6 Wayland working 03 real-buffer display proof.
The next gate is bounded game-client runtime proof under the live 39-bit VA
constraint.

See `OLD_SIDECAR_PROMOTION_AUDIT.md` for the preserved sidecar chain and the
ARM64EC/39-bit Wine GUI blocker audit.

See `REDMAGIC_GAMEHUB_CONTROL_DECK.md` for the Control Deck UI direction and the
private RM11/China-ROM asset-pack lane.

Online references checked for future work:

- [FrankBarretta/LSFG-Android](https://github.com/FrankBarretta/LSFG-Android): Android LSFG app. Future advisory only because it is a graphics lane.
- [PancakeTAS/lsfg-vk](https://github.com/PancakeTAS/lsfg-vk): GPL-3.0 Vulkan layer. Future advisory only because it touches Vulkan/graphics and may depend on user-provided Lossless Scaling assets.
- [KernelSU Encore Tweaks](https://github.com/KernelSU-Modules-Repo/encore): profile/tuning module evidence. Future advisory only; no generic performance writes are added in pass 01.
