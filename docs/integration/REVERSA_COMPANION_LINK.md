# Reversa Companion Link

Reversa-Matrix may query Nebula read-only status over ADB. Nebula remains the
phone-side control deck; Reversa remains the host evidence and patch-intelligence
engine.

The first companion link is read-only only.

## Read-Only Scope

Allowed active-module queries:

```text
/data/adb/modules/nebula_core/bin/nebula-core status --json
/data/adb/modules/nebula_core/bin/nebula-core display lanes --json
/data/adb/modules/nebula_core/bin/nebula-core display method-profiles --json
/data/adb/modules/nebula_core/bin/nebula-core display method-containers --json
/data/adb/modules/nebula_core/bin/nebula-core integrations baseline --json
/data/adb/modules/nebula_core/bin/nebula-core cooling policy --json
```

Allowed package/path queries:

```text
pm path io.droidspaces.nebula
pm path io.droidspaces.nebula.waylandie
cmd package list packages -U | grep -E "droidspaces|nebula|waylandie"
```

Pending module may be queried only for explicit guarded dry-check:

```text
/data/adb/modules_update/nebula_core/bin/nebula-core status --json
/data/adb/modules_update/nebula_core/bin/nebula-core display lanes --json
```

## Authority Rule

The active module is the normal authority:

```text
/data/adb/modules/nebula_core/bin/nebula-core
```

The pending module is not the normal UI source:

```text
/data/adb/modules_update/nebula_core/bin/nebula-core
```

Pending output must be rejected if it falls below the active known-good frontier.

## Guarded Actions

Install, stage, reboot, graphics launch, DRM lease, ReZygisk install, and module
mutation require later explicit approval. This document does not approve any of
those actions.

Known-good frontier evidence beats recency. A newer failed lane does not replace
older raw proof.
