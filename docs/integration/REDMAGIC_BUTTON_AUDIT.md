# RedMagic Button Audit

Pass 01 searched only preserved patches, consolidation manifests, restored Nubia/RedMagic sources, and current Hub source.

## Evidence

Redmagic-Control-Center restored source:

- `HardwareController.enableTriggers()` writes `1` to `/sys/class/leds/sar0/mode_operation` and `/sys/class/leds/sar1/mode_operation`.
- `HardwareController.disableTriggers()` writes `0` to the same nodes.
- `TriggerAccessibilityService.onKeyEvent()` handles `KeyEvent.KEYCODE_F7` and `KeyEvent.KEYCODE_F8`.
- `TriggerRootService.findTriggerEvent()` searches `/sys/class/input/event*/device/name` for `nubia_tgk_aw_sar0_ch0` and `nubia_tgk_aw_sar1_ch0`.
- `TriggerRootService.startReader()` runs `getevent -l /dev/input/eventN` through root and classifies down/up lines.
- `MagicKeyActions` and `HardwareController` use settings keys `fourth_physical_key_function_value`, `physical_key_function_app_value`, and `zte_keypad_slide_on_or_off` for the slider/Magic Key lane.

No preserved source proved a complete safe stock fallback for remapping the RedMagic button into Nebula.

## Assessment

| Item | Result |
| --- | --- |
| Event source | Candidate sources are accessibility `KEYCODE_F7/F8` and root `getevent` from `nubia_tgk_aw_sar0_ch0` / `nubia_tgk_aw_sar1_ch0`. |
| Vendor intent/service/input event/hook | Input event reader and accessibility key handling are proven in restored source. Slider/Magic Key settings are proven as Settings provider writes. |
| Privilege requirement | Root is required for SAR sysfs and `/dev/input` event reading. Accessibility service is required for the F7/F8 app path. |
| Stock behavior | Not fully proven in source. Control Center can assign stock slider modes: camera, Game Space, sound mode, flashlight, voice recorder, launch app, or disabled. |
| Conflict risk | Medium-high: custom readers may consume/duplicate input behavior; settings writes can override stock Magic Key behavior. |
| Safe fallback | Required: if safe mode is enabled, module missing, or reader fails, preserve stock behavior and do not disable system handling. |
| LSPosed required | Not required for the restored Control Center trigger paths. LSPosed may still be useful for future Game Space integration, but not for pass 01 button handling. |
| Single KSU module viability | Viable for future event reader and fixed actions, provided it has explicit start/stop commands, safe mode checks, crash counters, and restores stock settings. |

## Recommendation

Do not enable the hook or reader in pass 01.

Future design:

- Short press opens Nebula target selector.
- Long press launches the last successful target.
- Safe mode or module failure preserves stock RedMagic behavior.
- KSU module owns the root event reader.
- APK owns UI configuration and status display.
- No arbitrary action strings; only fixed actions are accepted.

Integration recommendation: `REIMPLEMENT` inside Nebula Core after a device-side proof pass captures exact event behavior and stock fallback state. Until then the UI reports `disabled_pass_01`.
