# Nubia / RedMagic Feature Matrix

Source restoration:

| Source | Origin | Commit | Local unique patch | License result |
| --- | --- | --- | --- | --- |
| NubiaToolkit | `https://github.com/KhanhNguyen9872/NubiaToolkit.git` | `0a2ee1a234b7f03dc6c5b0077bff003c1ba7c128` | Preserved `gradlew` diff reapplied from consolidation. | Apache-2.0 in `LICENSE`. |
| Redmagic-Control-Center | `https://github.com/austineyoung2000/Redmagic-Control-Center.git` | `e94d36e8204c228c6e8781157dea22946cf715e3` | Preserved `gradlew` diff reapplied from consolidation. | No repo license file; user supplied author permission screenshot saying "Do as you please". Attribution required; no wholesale UI/code merge. |
| RedMagicPowerDeck | Local archive `nebula-assets__Repos__RedMagicPowerDeck.tar.zst` | `SOURCE_ORIGIN_MISSING` | Local archived source only. | No recovered origin/license; reference only unless ownership/license is clarified. |
| gpp-enable-module.zip | Local zip `rm11mainassets/modules/gpp-enable-module.zip` | Not a git source. | None. | No license; reference only. |

## Matrix

| Feature | Source project | Source file/function | License | Purpose | Mode | Privilege | Method | NX809J relevance | Rollback | Boot risk | Owner | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Nebula Core status | Nebula | `nebula-core-module/bin/nebula-core status_json` | Project source | Show module/protocol/version/safe state. | Read-only | KSU root for module CLI | module script | Project-owned | None | Low | Module + app | PORT |
| Safe profile | Nebula | `profile_set safe`, `safe_mode_enable` | Project source | Disable future target launch paths. | Mutating state file only | KSU root | module script | Project-owned | `profile set phone` or action toggle | Low | Module | PORT |
| Phone profile | Nebula | `profile_set phone` | Project source | Select App/Phone mode without launch. | Mutating state file only | KSU root | module script | Project-owned | `profile set safe` | Low | Module | PORT |
| Dock profile | Nebula | `profile_set dock` | Project source | Future external/dock target. | Blocked | KSU root later | module script later | Locked blocked state | Returns `BLOCKED_NOT_READY` | None in pass 01 | Module | REJECT for pass 01 |
| Compatibility profile | Nebula | `profile_set compatibility` | Project source | Future compatibility target. | Blocked | KSU root later | module script later | Locked blocked state | Returns `BLOCKED_NOT_READY` | None in pass 01 | Module | REJECT for pass 01 |
| No-kill Game Assist hook | NubiaToolkit | `NoKillHook.hookCleanAnimationController`, `hookMindSyncManager`, `hookOneMoreThingManager` | Apache-2.0 | Prevent Game Assist cleanup of background apps. | Mutating behavior | LSPosed/root | LSPosed hook | RedMagic relevant, NX809J not live-confirmed in pass 01 | Disable LSPosed module/feature | Medium boot/session risk | Future app + hook lane | UNKNOWN |
| Global Game Mode | NubiaToolkit | `GlobalGameModeHook.hookGameCheck*` | Apache-2.0 | Treat apps as Game Space apps. | Mutating behavior | LSPosed/root | LSPosed hook | RedMagic relevant, NX809J not live-confirmed | Disable hook | Medium | Future hook lane | UNKNOWN |
| Hide Energy Cube | NubiaToolkit | `HideEnergyCubeHook.hookGameAssistLaunchTips` | Apache-2.0 | Suppress Game Assist tip/overlay. | Mutating behavior | LSPosed/root | LSPosed hook | RedMagic relevant, NX809J not live-confirmed | Disable hook | Low-medium | Future hook lane | UNKNOWN |
| Small window bypass | NubiaToolkit | `SmallWindowHook.hookSmallWindow` | Apache-2.0 | Allow more apps in small-window mode. | Mutating behavior | LSPosed/root | LSPosed hook | RedMagic relevant, NX809J not live-confirmed | Disable hook | Medium | Future hook lane | UNKNOWN |
| Super resolution unlock | NubiaToolkit | `SuperResolutionHook.hookPluginUtils`, `hookSuperResolutionHelper` | Apache-2.0 | Expose/support Superior Pic Quality gates. | Mutating behavior | LSPosed/root | LSPosed hook, Settings provider, system property path by analysis | RedMagic relevant; exact NX809J render effect unconfirmed | Disable hook; clear related settings/properties if later used | Medium-high because vendor behavior is unclear | Future app + hook/module | REFERENCE_ONLY |
| Watermark length | NubiaToolkit | `WatermarkLengthHook.hookWaterMarkWatcher` | Apache-2.0 | Increase Game Launcher watermark text limit. | Mutating UI behavior | LSPosed/root | LSPosed hook | RedMagic relevant, NX809J not live-confirmed | Disable hook | Low | Future hook lane | UNKNOWN |
| Fan enable/level/PWM/RPM | Redmagic-Control-Center | `HardwareController.enableFan`, `setFanLevel`, `setFanPwm`, `readFanRpm` | Author permission, attribution required | Cooling fan control/status. | Mutating/read-only | Root | sysfs | NX809J candidate from Control Center and PowerDeck node map; not live-tested | Snapshot prior values, write previous enable/level/PWM | Medium | Module | REIMPLEMENT later; status only in pass 01 |
| Micropump read-only telemetry | Redmagic-Control-Center | `HardwareController.readPumpEnabled`, `readPumpFreq`, `readPumpSpeed`; `DashboardSnapshot.readPumpEnabled/readPumpFreq/readPumpSpeed`; `DeviceCapabilityScanner.scan` | Author permission, attribution required | Liquid-cooling pump support, presence, enabled state, and vendor speed telemetry. | Read-only | Root likely | procfs | NX809J candidate from Control Center; live support must be reported from exact nodes only | None | Low | Module + app | PORT in pass 03 |
| Auto cooling policy preview | Nebula reimplementation from Redmagic-Control-Center telemetry evidence | `nebula-core cooling policy --json`; `defaults.json` | Project source with RedMagic attribution | Combine thermal, internal fan, and liquid pump telemetry into read-only fan/pump intents. | Read-only preview | Root likely for telemetry reads | fixed CLI + sysfs/procfs reads | NX809J relevant when fan/pump/thermal nodes are readable | No rollback needed in pass 04 because no writes; future apply requires snapshot/rollback | Low in pass 04 | Module owns policy; app renders state | PORT in pass 04 |
| Micropump control/profile writes | Redmagic-Control-Center | `HardwareController.enablePump`, `setPumpProfile`; `AutoPumpService.applyPumpRule`; `PumpDialogUi` | Author permission, attribution required | Liquid-cooling pump enable/profile control. | Mutating | Root | procfs writes/service/UI callbacks | NX809J candidate from Control Center and PowerDeck | Snapshot enable/freq/speed, restore previous values if ever enabled | Medium | Future module | REJECT_MUTATING for pass 03 |
| RGB LEDs | Redmagic-Control-Center | `setFanLedEnabled`, `setLogoLedEffect`, `setShoulderLedEffect` | Author permission, attribution required | Fan/logo/shoulder lighting. | Mutating | Root | sysfs | NX809J candidate; not live-tested | Snapshot LED effect/cfg, restore/off | Low-medium | Module + app UI | REIMPLEMENT later; status only in pass 01 |
| Shoulder triggers | Redmagic-Control-Center | `enableTriggers`, `disableTriggers`, `TriggerRootService` | Author permission, attribution required | Enable/handle shoulder trigger input. | Mutating | Root/accessibility | sysfs, input event, shell command | NX809J candidate via `nubia_tgk_aw_sar*` event names; not live-tested | Disable custom service, restore SAR mode, stock fallback | Medium-high | Module later | REIMPLEMENT later; disabled in pass 01 |
| Magic Key / slider | Redmagic-Control-Center | `setSliderStockFunction`, `setSliderLaunchApp`, `readSliderState`, `MagicKeyActions` | Author permission, attribution required | Map physical slider/Magic Key actions. | Mutating/read-only | Root | Settings provider, system setting, global setting | NX809J candidate; setting names proven in source only | Restore previous `fourth_physical_key_function_value` and app value | Medium | Module later | REIMPLEMENT later; disabled in pass 01 |
| Haptics | Redmagic-Control-Center | `vibrate` | Author permission, attribution required | Trigger vibration feedback. | Mutating | Root | sysfs | NX809J candidate; not live-tested | Stop activation/write safe values | Low | Module later | REFERENCE_ONLY |
| Thermal telemetry | Redmagic-Control-Center | `readTemperatureC/F` | Author permission, attribution required | Read thermal zones. | Read-only | Root preferred | sysfs | Generic Android + RM11 candidate | None | Low | Module | REIMPLEMENT later |
| Device capability scan | Redmagic-Control-Center | `DeviceCapabilityScanner.scan` | Author permission, attribution required | Detect fan/pump/LED/trigger/slider/haptics. | Read-only | Root in source; app pass 01 uses package/build checks only | sysfs/getprop in source; Android Build/package checks in Nebula | NX809J check in source uses model `NX809J` | None | Low | App + module later | REIMPLEMENT |
| Master profiles | Redmagic-Control-Center | `MasterProfileStorage`, `MasterProfileActions` | Author permission, attribution required | Save/apply hardware profiles. | Mutating | Root | app prefs + root writes | RM11 profile concept relevant | Snapshot/restore full profile | Medium | App + module | REIMPLEMENT later |
| PowerDeck dry-run/snapshot | RedMagicPowerDeck | `README.md`, `module/rm-powerdeck-apply.sh`, `docs/node-map.md` | SOURCE_ORIGIN_MISSING | Safe profile automation model. | Mutating later | Root | module script | Explicit REDMAGIC 11 Pro/NX809J in README | Snapshot/restore design | Low while dry-run | Module | REIMPLEMENT conceptually |
| GPP all-game property | gpp-enable-module.zip | `service.sh: setprop vendor.gpp.allgame.enable 1` | No license | Enable vendor GPP all-game flag at boot. | Mutating | Root | system property | RM11 relevance unknown; not live-tested | `setprop vendor.gpp.allgame.enable 0` if proven later | Medium due boot property mutation | Module later | REFERENCE_ONLY |
| LSFG Android | Online fork | [FrankBarretta/LSFG-Android](https://github.com/FrankBarretta/LSFG-Android) | See upstream license | Android Lossless Scaling frame generation app. | Mutating graphics path | App/overlay/media capture | MediaProjection/overlay/Vulkan by upstream description | Reddit/source claims RM11 Pro works, not local proof | Disable app/overlay | High for this pass due graphics lane lock | Future graphics lane | REFERENCE_ONLY |
| lsfg-vk | Online fork | [PancakeTAS/lsfg-vk](https://github.com/PancakeTAS/lsfg-vk) | GPL-3.0 | Vulkan frame generation layer. | Mutating graphics path | User runtime | Vulkan layer | Not Android/NX809J-specific | Remove layer/config | High due graphics lane lock and asset/license constraints | Future graphics lane | REFERENCE_ONLY |
| Encore Tweaks | Online KSU module | [KernelSU-Modules-Repo/encore](https://github.com/KernelSU-Modules-Repo/encore) | See upstream | Dynamic performance profiles. | Mutating | Root | module scripts | Generic, not NX809J-specific | Disable module | Medium-high if blindly ported | Reference only | REFERENCE_ONLY |

## Pass 01 Selected Work

Selected for port/reimplementation now:

- Nebula Core fixed JSON CLI.
- Safe/phone profile state.
- Blocked dock/compatibility responses.
- Module status/version/protocol display.
- Nubia/RedMagic capability discovery cards.
- RedMagic button audit card, disabled.
- RedMagic liquid-cooling pump read-only probe in pass 03.
- Read-only automatic cooling policy preview in pass 04.

Deferred or rejected:

- Any LSPosed hook activation.
- Any fan/pump/LED/trigger/slider/haptic write.
- Pump `freq` and `mode` value semantics until units/meaning are proven.
- Any automatic fan/pump apply action; pass 04 exposes preview intents only.
- GPP property auto-set at boot.
- Lossless Scaling/Vulkan/frame-generation integration.
- Generic performance tuning modules.
- Arbitrary root-shell execution.
