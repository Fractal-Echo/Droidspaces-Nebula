# RedMagic Read-Only Node Map

Pass 02 source scope:

- `NubiaToolkit` at `0a2ee1a234b7f03dc6c5b0077bff003c1ba7c128`
- `Redmagic-Control-Center` at `e94d36e8204c228c6e8781157dea22946cf715e3`
- current Nebula app/module source

No PowerDeck-only display or GPU paths are promoted here because pass 02 requires exact read-only evidence from the scoped implementation files or live discovery.

| Feature | Exact source repository/file/function | Source commit | Path/property/service | Expected data type | Read command or API | Privilege required | Confirmed read-only | NX809J confidence | Fallback behavior | Integration decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Device manufacturer | Redmagic-Control-Center `DeviceCapabilityScanner.scan`; Nebula schema | `e94d36e8204c228c6e8781157dea22946cf715e3` | `ro.product.manufacturer` | string | `getprop ro.product.manufacturer` | shell/root not required when readable | yes | medium; generic Android identity | `"unknown"` | PORT |
| Device model | Redmagic-Control-Center `DeviceCapabilityScanner.scan` reads `Build.MODEL` and falls back to `ro.product.model` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `ro.product.model` | string | `getprop ro.product.model` | shell/root not required when readable | yes | high for NX809J check | `"unknown"` | PORT |
| Product name | Redmagic-Control-Center `DeviceCapabilityScanner.scan`; Nebula schema | `e94d36e8204c228c6e8781157dea22946cf715e3` | `ro.product.product.name` | string | `getprop ro.product.product.name` | shell/root not required when readable | yes | medium | `"unknown"` | PORT |
| Device codename | Redmagic-Control-Center `DeviceCapabilityScanner.scan`; Nebula schema | `e94d36e8204c228c6e8781157dea22946cf715e3` | `ro.product.device` | string | `getprop ro.product.device` | shell/root not required when readable | yes | medium | `"unknown"` | PORT |
| Board platform | Nebula schema; chipset identity requested in pass 02 | current Hub | `ro.board.platform` | string | `getprop ro.board.platform` | shell/root not required when readable | yes | medium; schema required, not RedMagic-specific | `"unknown"` | PORT |
| Kernel release | Nebula schema | current Hub | kernel release | string | `uname -r` | shell/root not required | yes | generic | `"unknown"` | PORT |
| Fan presence | Redmagic-Control-Center `DeviceCapabilityScanner.scan` checks fan node existence | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/sys/kernel/fan/fan_enable`, `/sys/kernel/fan/fan_speed_level`, `/sys/kernel/fan/fan_speed_count` | boolean exists | `[ -e allowlisted_path ]` | root may be needed on production builds | yes | high; exact RM fan paths in source | `supported=false`, error `missing:/sys/kernel/fan` | PORT |
| Fan enabled | Redmagic-Control-Center `HardwareController.isFanEnabled` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/sys/kernel/fan/fan_enable` | `0` or `1` | read first line from allowlisted path | root may be needed | yes | high | `enabled=null`, permission error if denied | PORT |
| Fan RPM | Redmagic-Control-Center `HardwareController.readFanRpm` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/sys/kernel/fan/fan_speed_count` | integer RPM | read first line from allowlisted path | root may be needed | yes | high | `rpm=null`, permission error if denied | PORT |
| Fan level | Redmagic-Control-Center `HardwareController.readFanLevel` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/sys/kernel/fan/fan_speed_level` | integer 0-5 expected | read first line from allowlisted path | root may be needed | yes | high | `level=null`, permission error if denied | PORT |
| Current performance/game mode | NubiaToolkit `GlobalGameModeHook`; Redmagic-Control-Center `GameModeService` | scoped commits | no confirmed root-readable system state path | unknown | rejected | unknown | no | unknown | `supported=false`, `NO_CONFIRMED_READ_ONLY_SOURCE` | REJECT for pass 02 |
| Display refresh/current display state | none in scoped implementation files | n/a | no confirmed path | unknown | rejected | unknown | no | unknown | `supported=false`, `NO_CONFIRMED_READ_ONLY_SOURCE` | REJECT for pass 02 |
| Thermal zone 0-3 primary | Redmagic-Control-Center `HardwareController.readTemperatureC` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/sys/class/thermal/thermal_zone0/temp` through `/sys/class/thermal/thermal_zone3/temp` | integer C or millicelsius | read first line from allowlisted path | root may be needed | yes | medium; generic thermal paths used by source | omit missing zones; permission error if denied | PORT |
| Thermal zone 0-3 virtual | Redmagic-Control-Center `HardwareController.readTemperatureC` | `e94d36e8204c228c6e8781157dea22946cf715e3` | `/sys/devices/virtual/thermal/thermal_zone0/temp` through `/sys/devices/virtual/thermal/thermal_zone3/temp` | integer C or millicelsius | read first line from allowlisted path | root may be needed | yes | medium; generic thermal paths used by source | omit missing zones; permission error if denied | PORT |
| RedMagic button state | Redmagic-Control-Center trigger files from pass 01 audit | `e94d36e8204c228c6e8781157dea22946cf715e3` | SAR/input/settings paths | mixed | rejected in pass 02 | root/accessibility | not enabled | candidate only | `supported=false`, `disabled_in_pass_02` | DEFER |

Rejected candidates:

- RedMagic performance/game mode app-private preferences: not a current device performance state.
- NubiaToolkit hook settings: describes hook configuration, not verified current performance mode.
- Any display/refresh node not present in scoped implementation files.
- Any path requiring writes, `setprop`, `settings put`, service mutation, input injection, or vendor-service mutation.
