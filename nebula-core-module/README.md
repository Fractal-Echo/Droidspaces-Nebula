# Droidspaces: Nebula Core

Nebula Core is the privileged execution plane for Droidspaces: Nebula.

Pass 01 exposes only a fixed JSON command protocol:

- `status --json`
- `capabilities --json`
- `profile get --json`
- `profile set safe`
- `profile set phone`
- `profile set dock`
- `profile set compatibility`
- `safe-mode get --json`
- `safe-mode enable`
- `adb-wifi status --json`
- `adb-wifi enable --json`
- `adb-wifi auto-disable --json`
- `logs tail --lines N`
- `redmagic probe --json`
- `redmagic pump probe --json`
- `cooling policy --json`
- `snapshot cooling create --json`
- `snapshot cooling get --json`
- `snapshot cooling rollback --dry-run --json`
- `legacy modules --json`
- `nubia toolkit status --json`
- `runtime waylandie status --json`
- `runtime waylandie proton-smoke --json`
- `display lanes --json`
- `display lane phone preflight --json`
- `display lane anland preflight --json`
- `display lane dock preflight --json`

`profile set dock` and `profile set compatibility` return `BLOCKED_NOT_READY`.
The service creates `/data/adb/nebula/logs` and `/data/adb/nebula/state` after boot completion and does not start any target.

Safe mode is represented by `/data/adb/nebula/safe_mode`. The module action toggles that file and updates the stored profile.

ADB Wi-Fi recovery is opt-in. `adb-wifi enable --json` writes only
`Settings.Global adb_enabled=1`, `adb_wifi_enabled=1`, and the observed
RedMagic/Nubia UI switch candidate `enable_wireless_switch=1`, snapshots the
prior values, calls Android's fixed `IAdbManager.allowWirelessDebugging`
transaction for the current validated Wi-Fi BSSID, and creates
`/data/adb/nebula/state/adb_wifi_auto_enable`. On later boots, an early bounded
`post-fs-data` worker and the later service re-apply only those three fixed ADB
Wi-Fi settings and the same fixed ADB manager transaction when that flag is
present. `wireless_debugging=true` and `applied=true` are reported only when
Android's ADB manager exposes a positive wireless debugging port. If the settings
are requested but the port remains inactive, JSON reports
`manual_toggle_required=true` and `activation_state=manual_toggle_required`
instead of pretending the session is live. `adb-wifi auto-disable --json`
removes the boot flag without turning off the current debugging session. If
Android already reports the UI switch candidate or `adb_wifi_enabled=1` at
service time, the service also preserves that existing developer-option choice
by re-applying only those same ADB Wi-Fi settings and the fixed ADB manager
transaction.

Pass 05 stages protected legacy Droidspaces module migration evidence. The staged SELinux policy under `sepolicy.d/` is not active module policy yet; keep the old `droidspaces` and `rm11-droidspace-bridge-fd` modules enabled until one-at-a-time migration and reboot verification pass.

`nubia toolkit status --json` reports the audited Nubia Toolkit hook lane, the
ReZygisk standalone Zygisk provider state, and the Android 16-compatible
Vector/LSPosed module state. It does not enable hooks, scope packages,
force-stop vendor apps, or require the old standalone Nubia Toolkit APK for
status display.

`runtime waylandie status --json` checks fixed WayLandIE app/runtime paths only.
`runtime waylandie proton-smoke --json` is safe-mode guarded and runs only the
fixed root-assisted proot Proton smoke command. It accepts no path, package, or
shell argument and is never launched during boot.

`display lanes --json` reports the multi-lane display selector state. The lane
preflight commands are read-only:

- Phone/App Mode reports the WayLandIE R6 Wayland proof state. A pass requires
  the bridge binary, pinned local Freedreno ICD, local Vulkan driver, and the
  exact Gamescope/Xwayland sidecars used by
  `NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS`. Steam/Proton remains unpromoted
  until a separate game-client proof passes under the live-confirmed 39-bit
  kernel VA constraint.
- Anland Surface Mode selects an explicit or single live active DroidSpaces
  container, then checks config, Anland env, display socket presence, rootfs
  ownership, and render-node visibility. Stale PID files, unsafe `rootfs_path`
  values outside the selected container, and invalid overrides fail closed.
- Dock Lease Mode reports the proven external-display DRM lease reference and
  required operator-approved start conditions. It does not probe composer fds,
  create leases, run wlroots, or mutate display state.

Each display lane also reports `container_ref`, `container_kind`,
`container_status`, `display_status`, `runtime_status`,
`requirement_status`, and `missing_requirements` so runtime readiness and
display readiness cannot be confused.
