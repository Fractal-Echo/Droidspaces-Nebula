# RedMagic Pump Read-Only Node Map

Pass 03 scope:

- `NubiaToolkit` at `0a2ee1a234b7f03dc6c5b0077bff003c1ba7c128`
- `Redmagic-Control-Center` at `e94d36e8204c228c6e8781157dea22946cf715e3`
- current Nebula app/module source

Only fixed read-only telemetry is accepted. Pump controls, profile application, automatic services, preferences, UI preview actions, and any write path are rejected for this pass.

| Candidate | Source repository | Exact file/function | Source commit | Node/property/service name | Expected type | Units | Expected range | Read mechanism | Clearly non-mutating | Required privilege | NX809J confidence | Relation to fan | Fallback | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Pump enabled state | Redmagic-Control-Center | `app/src/main/java/com/elitedarkkaiser/redmagic/HardwareController.kt` `PUMP_ENABLE`, `readPumpEnabled`; `DashboardSnapshot.readPumpEnabled` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/proc/driver/micropump/enable` | integer boolean | boolean | `0` or `1` | read first line from fixed allowlisted path | yes | root likely on production builds | high if node exists on NX809J | separate liquid-cooling pump, not fan RPM | `enabled=null`, precise error | ACCEPT_READONLY |
| Pump frequency selector | Redmagic-Control-Center | `HardwareController.kt` `PUMP_FREQ`, `readPumpFreq`; `DashboardSnapshot.readPumpFreq` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/proc/driver/micropump/freq` | integer | vendor selector, physical unit unknown | source writes `4`; Nebula accepts `0..100` only as readable telemetry evidence | read first line from fixed allowlisted path | yes | root likely | medium-high if node exists; semantic unit not proven | separate from fan level | retained in `sources`; no public value field until unit is proven | REFERENCE_ONLY |
| Pump speed selector | Redmagic-Control-Center | `HardwareController.kt` `PUMP_SPEED`, `readPumpSpeed`; `DashboardSnapshot.readPumpSpeed` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/proc/driver/micropump/speed` | integer | vendor speed value, percent-like by UI profile writes | source writes `40`, `60`, `80`, `90`; Nebula accepts `0..100` | read first line from fixed allowlisted path | yes | root likely | high if node exists on NX809J | separate from fan RPM and fan level | `speed=null`, precise error | ACCEPT_READONLY |
| Pump mode presence | Redmagic-Control-Center | `DeviceCapabilityScanner.scan` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/proc/driver/micropump/mode` | existence only | unknown | unknown | fixed existence check only | yes for existence; read semantics not proven | root may be needed | candidate only | separate from fan | `present=true` only if found; no `mode` value | UNKNOWN |
| Pump enable write | Redmagic-Control-Center | `HardwareController.enablePump` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `echo 0/1 > /proc/driver/micropump/enable` | write | boolean | `0` or `1` | rejected write command | no | root | source-relevant but mutating | separate from fan | no write path in Nebula | REJECT_MUTATING |
| Pump profile write | Redmagic-Control-Center | `HardwareController.setPumpProfile` | `e94d36e8204c228c6e8781157dea22946cf715e3` | writes `enable`, `freq`, `speed` | write sequence | vendor profile | `slow`, `medium`, `quick`, `experimental`, `off` | rejected write command | no | root | source-relevant but mutating | separate from fan | no write path in Nebula | REJECT_MUTATING |
| Automatic pump service | Redmagic-Control-Center | `AutoPumpService.applyPumpRule` | `e94d36e8204c228c6e8781157dea22946cf715e3` | service calls `enablePump` and `setPumpProfile` | service behavior | profile | temperature-driven | rejected service mutation | no | app service + root write | source-relevant but mutating | separate from fan | no service in Nebula | REJECT_MUTATING |
| Pump UI preview/profile controls | Redmagic-Control-Center | `PumpDialogUi`, `CoolingTabUi`, `MainActivity.applyPumpProfile` | `e94d36e8204c228c6e8781157dea22946cf715e3` | UI callbacks into pump writes | UI/action | profile | app-defined | rejected UI/control flow | no | app + root write | source-relevant but mutating | separate from fan | read-only card only | REJECT_MUTATING |
| Pump saved preferences | Redmagic-Control-Center | `PumpStorage`, `MasterProfileStorage`, `GameModeService` preference reads | `e94d36e8204c228c6e8781157dea22946cf715e3` | app-private pump preference keys | preference | profile/boolean | app-defined | SharedPreferences | non-mutating read, but not live hardware state | app-private | low for live telemetry | can mirror fan prefs but not hardware | ignored for telemetry | REFERENCE_ONLY |
| Nubia Toolkit pump candidate | NubiaToolkit | scoped search for pump/water/liquid/coolant/cooling terms | `0a2ee1a234b7f03dc6c5b0077bff003c1ba7c128` | none found for pump telemetry | n/a | n/a | n/a | n/a | n/a | n/a | none | none | no Nebula implementation | UNKNOWN |

Pass 03 JSON ownership:

- `supported=true` only when at least one accepted pump telemetry node is readable and validates.
- `present=true` only when a fixed micropump driver node exists.
- `enabled`, `speed`, `rpm`, `level`, `flow_rate`, and `mode` remain `null` unless the corresponding value is proven by an accepted source.
- No pump control, speed write, profile write, service start, Binder call, LSPosed hook, property write, or settings write is implemented.

Pass 04 policy preview:

- The pump participates in `nebula-core cooling policy --json` only as a separate read-only channel.
- Policy intent values are `stock`, `off`, `low`, `medium`, `high`, `maximum`, or `unavailable`.
- `applied=false` is mandatory in pass 04.
- Missing pump telemetry produces pump intent `unavailable` while thermal/fan preview can still be computed.
- The rejected RedMagic Control Center automatic pump service remains rejected because it writes pump profile nodes; Nebula only reimplements the non-mutating decision preview.
