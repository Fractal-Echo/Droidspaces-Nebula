# Auto Cooling Policy Preview

Pass 04 adds a read-only, module-owned cooling policy preview for RM11 Pro / NX809J.

The policy does not enable, disable, tune, or write the fan or liquid-cooling pump. It only combines already allowlisted telemetry into an intent preview so the app can show what Nebula Core would request after a future snapshot/rollback-controlled write pass.

## Command

`nebula-core cooling policy --json`

The aggregate `nebula-core redmagic probe --json` also includes the same object as `cooling_policy`.

The command accepts no path, shell text, target name, profile, or setter argument.

## Authority

Thresholds and dwell/hysteresis defaults live only in:

`nebula-core-module/config/defaults.json`

The APK renders the returned state and intents. It does not duplicate temperature thresholds.

## States

| State | Meaning |
| --- | --- |
| `UNAVAILABLE` | Policy cannot make a preview decision because calibration is missing or no valid thermal sensor was readable. |
| `SAFE_MODE` | Safe mode is active; future cooling writes must preserve stock behavior. |
| `COOL` | Valid thermal telemetry is below the first response band. |
| `BALANCED` | Valid telemetry entered the balanced response band. |
| `HOT` | Valid telemetry entered the high response band. |
| `CRITICAL` | Valid telemetry entered the maximum response band. |

## Intents

Fan and pump are modeled as separate channels.

Allowed intent vocabulary:

- `stock`
- `off`
- `low`
- `medium`
- `high`
- `maximum`
- `unavailable`

Pass 04 always returns `applied=false` for both channels.

UI and status surfaces must preserve that meaning. A preview result can describe
future fan/pump intent, but it must not be rendered as applied automation.

## JSON Shape

```json
{
  "protocol_version": 1,
  "command": "cooling policy",
  "preview_only": true,
  "configured": true,
  "safe_mode": false,
  "state": "BALANCED",
  "controlling_sensor": {
    "name": "/sys/class/thermal/thermal_zone0/temp",
    "source": "Redmagic-Control-Center HardwareController.kt:275-288@e94d36e8204c228c6e8781157dea22946cf715e3",
    "temperature_c": 41.0
  },
  "thermal": {
    "maximum_c": 41.0,
    "valid_sensor_count": 1,
    "rejected_sensor_count": 0
  },
  "fan": {
    "supported": true,
    "present": true,
    "current": {
      "enabled": false,
      "rpm": 0,
      "level": 2
    },
    "intent": "medium",
    "applied": false
  },
  "pump": {
    "supported": true,
    "present": true,
    "current": {
      "enabled": true,
      "speed": 80,
      "freq": 4
    },
    "intent": "low",
    "applied": false
  },
  "policy": {
    "threshold_source": "defaults.json",
    "hysteresis_c": 2.0,
    "minimum_dwell_seconds": 30
  },
  "reason": [],
  "errors": []
}
```

## Safety

- No sysfs/procfs writes.
- No property writes.
- No settings writes.
- No vendor-service mutation.
- No LSPosed hook.
- No target launch.
- No arbitrary file path argument.
- Safe mode returns `SAFE_MODE` and `stock` intents.
- Missing fan or pump telemetry makes only that channel `unavailable`; it does not block a thermal-only policy preview.

## Deferred

Future mutation work requires exact write provenance, prior-value snapshotting, rollback, dwell enforcement across real state storage, and a safe fallback that preserves stock RedMagic behavior on module failure.
