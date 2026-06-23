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

`profile set dock` and `profile set compatibility` return `BLOCKED_NOT_READY`.
The service creates `/data/adb/nebula/logs` and `/data/adb/nebula/state` after boot completion and does not start any target.

Safe mode is represented by `/data/adb/nebula/safe_mode`. The module action toggles that file and updates the stored profile.

ADB Wi-Fi recovery is opt-in. `adb-wifi enable --json` writes only
`Settings.Global adb_enabled=1` and `adb_wifi_enabled=1`, snapshots the prior
values, and creates `/data/adb/nebula/state/adb_wifi_auto_enable`. On later
boots, the service re-applies only those two settings when that flag is present.
`adb-wifi auto-disable --json` removes the boot flag without turning off the
current debugging session.

Pass 05 stages protected legacy Droidspaces module migration evidence. The staged SELinux policy under `sepolicy.d/` is not active module policy yet; keep the old `droidspaces` and `rm11-droidspace-bridge-fd` modules enabled until one-at-a-time migration and reboot verification pass.
