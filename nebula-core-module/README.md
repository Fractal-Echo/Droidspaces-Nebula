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

`profile set dock` and `profile set compatibility` return `BLOCKED_NOT_READY`.
The service creates `/data/adb/nebula/logs` and `/data/adb/nebula/state` after boot completion and does not start any target.

Safe mode is represented by `/data/adb/nebula/safe_mode`. The module action toggles that file and updates the stored profile.
