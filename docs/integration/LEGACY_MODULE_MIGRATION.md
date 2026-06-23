# Legacy Module Migration

Pass 05 begins moving old Droidspaces module responsibilities into Nebula Core without disabling the protected modules.

## Protected Modules

Do not delete or disable these yet:

- `droidspaces` / Droidspaces: Daemon & Init
- `rm11-droidspace-bridge-fd` / RM11 Droidspaces Bridge FD Policy

They may still support the known-good Wayland/bridge baseline. They can be disabled only one at a time, after Nebula Core contains equivalent behavior and after reboot verification passes.

## Read-Only Audit

Captured protected module evidence is stored under:

`/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-22-nebula-core-unification-snapshot-05/`

Audited functions:

| Module | Function | Nebula Core status |
| --- | --- | --- |
| `droidspaces` | post-fs-data dmesg logger | staged audit only |
| `droidspaces` | `.daemon_mode` marker handling | staged audit only |
| `droidspaces` | `/vendor/bin/droidspaces` native-init detection | staged audit only |
| `droidspaces` | `droidspacesd_exec` relabel before daemon launch | staged audit only |
| `droidspaces` | rootfs image `vold_data_file` relabel | staged audit only |
| `droidspaces` | boot-completed wait and network wait | staged audit only |
| `droidspaces` | `run_at_boot=1` container scan/start | staged audit only |
| `droidspaces` | module.prop daemon/container status update | staged audit only |
| `rm11-droidspace-bridge-fd` | `allow untrusted_app droidspacesd fd use` | staged policy evidence |
| `rm11-droidspace-bridge-fd` | KernelSU sepolicy check/patch flow | staged audit only |
| `rm11-droidspace-bridge-fd` | container `/dev/shm` create and `1777` chmod | staged audit only |

## Nebula Core Additions

New fixed command:

`nebula-core legacy modules --json`

This reports the protected modules from fixed IDs only. It accepts no module name or path argument.

New staged files:

- `nebula-core-module/config/legacy-modules.json`
- `nebula-core-module/sepolicy.d/droidspaces-staged.rule`

The staged sepolicy file is packaged evidence only. It is not active KernelSU policy because Nebula Core must coexist with the old modules during the first install/test step.

## Snapshot / Rollback Infrastructure

New fixed commands:

- `nebula-core snapshot cooling create --json`
- `nebula-core snapshot cooling get --json`
- `nebula-core snapshot cooling rollback --dry-run --json`

Snapshot creation stores current fan and pump telemetry under Nebula Core state. Rollback is dry-run only and returns `applied=false`.

No fan write, pump write, profile write, service mutation, or boot-time target launch is introduced in pass 05.

## Migration Order

1. Install/test the APK by itself.
2. Install Nebula Core while retaining `droidspaces` and `rm11-droidspace-bridge-fd`.
3. Verify `status --json`, `legacy modules --json`, `cooling policy --json`, and snapshot dry-run output.
4. Activate one imported function at a time inside Nebula Core.
5. Disable only one old module.
6. Reboot and verify the known-good baseline.
7. Keep rollback evidence.
8. Delete an old module only after the replacement survives migration testing.

## Hard Stops

- Do not disable both protected modules together.
- Do not remove protected modules yet.
- Do not add automatic cooling writes.
- Do not add boot-time target launch.
- Do not run graphics, DRM lease, or compositor validation from this pass.
