# Nebula Status Model

This document is the status contract for Nebula Core and the Android app. It
keeps static evidence snapshots separate from live runtime checks so the UI does
not promote a lane past what the logs prove.

## Current Evidence Snapshot

The current Phone/App lane truth is:

```json
{
  "source": "evidence_snapshot",
  "real_buffer_pass": true,
  "hardware_glx_pass": false,
  "software_glx_reproduced": true,
  "active_blocker": "NONE_WAYLAND_DISPLAY",
  "vk_get_memory_fd_failures": 0,
  "real_buffer_commits": 2,
  "runtime_blocker": "GAME_CLIENT_RUNTIME_NOT_PROMOTED_39BIT_VA"
}
```

These values are pinned to the bounded R6 Wayland proof 03 artifact. Do not
replace them with older loader-pin or blocked-export labels unless new local
evidence explicitly proves a regression.

## Lane Meanings

| Lane | Current state | Meaning |
| --- | --- | --- |
| Phone/App Mode | `wayland_display_pass` | WayLandIE, pinned local Turnip/Freedreno loader state, Gamescope, Xwayland, dmabuf-present, and real-buffer commits are proven for display readiness. Game-client runtime remains unpromoted under the 39-bit VA constraint. |
| Dock Lease Mode | `proven_reference_not_wired` | DRM lease evidence is captured as an external-display reference lane, but no mutating start path is wired. |
| Anland Surface Mode | `preflight_only` | DroidSpaces/Anland files can satisfy a preflight, but this lane is not a silent substitute for Phone/App real-buffer proof. |
| Compatibility Mode | `not_wired` | Compatibility fallback remains a declared method lane, not an implemented runtime. |
| ReZygisk Provider | `documented_not_installed` | ReZygisk is a provider lane, not proof that hooks are active. |
| Cooling Policy | `preview_only` | Cooling output must keep `applied=false`; status reads must not write fan or pump nodes. |

## Required Negative Claims

Nebula Core and the app must keep these claims constrained until new evidence
proves otherwise:

- `hardware_glx_pass`
- Game-client runtime ready/Steam-ready
- Dock Mode startable
- ReZygisk installed or hook-ready by documentation alone
- Cooling policy applied

## Next Proof Gate

The next runtime proof is a bounded game-client run before Steam promotion. It
must preserve the proven Wayland display state while testing only whether a
client runtime can survive the live-confirmed 39-bit VA environment.
