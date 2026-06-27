# Nebula Status Model

This document is the status contract for Nebula Core and the Android app. It
keeps static evidence snapshots separate from live runtime checks so the UI does
not promote a lane past what the logs prove.

## Current Evidence Snapshot

The current Phone/App lane truth is:

```json
{
  "source": "evidence_snapshot",
  "real_buffer_pass": false,
  "hardware_glx_pass": false,
  "software_glx_reproduced": true,
  "gl_renderer": "llvmpipe",
  "active_blocker": "vulkan_export_real_buffer",
  "vk_get_memory_fd_failures": 1199,
  "real_buffer_commits": 0,
  "no_buffer_commits": 8,
  "a1_fasttest_env_status": "staged_not_run_adb_offline"
}
```

Do not replace these values with optimistic labels unless a new bounded evidence
run proves the replacement.

## Lane Meanings

| Lane | Current state | Meaning |
| --- | --- | --- |
| Phone/App Mode | `blocked_export` | WayLandIE app/native bridge and local Turnip/Freedreno loader pin are proven, and software GLX is reproduced through `llvmpipe`; Vulkan export has not produced real-buffer commits. |
| Dock Lease Mode | `paused_crash_gated` | DRM lease work remains reference/status-only until the crash-gated resume requirements are satisfied. |
| Anland Surface Mode | `preflight_only` | DroidSpaces/Anland files can satisfy a preflight, but this lane is not a silent substitute for Phone/App real-buffer proof. |
| Compatibility Mode | `blocked_real_buffer` | Compatibility fallback is visible as a lane, but it cannot claim hardware GLX or real-buffer pass. |
| ReZygisk Provider | `documented_not_installed` | ReZygisk is a provider lane, not proof that hooks are active. |
| Cooling Policy | `preview_only` | Cooling output must keep `applied=false`; status reads must not write fan or pump nodes. |

## Required Negative Claims

Nebula Core and the app must keep these claims false until new evidence proves
otherwise:

- `real_buffer_pass`
- `hardware_glx_pass`
- Dock Mode ready/startable
- ReZygisk installed or hook-ready by documentation alone
- Cooling policy applied

## Next Proof Gate

The next runtime proof is the bounded A1 export/runtime run after ADB is live
and the staged runner path is verified. It should answer only whether the
Fasttest-02-style KGSL/Turnip export environment reduces `vkGetMemoryFdKHR`
failures, produces bridge real-buffer commits greater than 0, preserves
Gamescope/Xwayland readiness, and keeps child software GLX alive.
