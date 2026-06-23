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

Pass 05 stages protected legacy Droidspaces module migration evidence. The staged SELinux policy under `sepolicy.d/` is not active module policy yet; keep the old `droidspaces` and `rm11-droidspace-bridge-fd` modules enabled until one-at-a-time migration and reboot verification pass.
