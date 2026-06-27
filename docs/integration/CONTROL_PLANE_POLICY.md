# Nebula Control-Plane Policy

Date: 2026-06-27

This policy is the source-of-truth wording for the Nebula documentation and UI
control-plane contract. It does not promote a runtime feature by itself.

## Baseline Shape

Nebula is one public APK plus one Nebula Core module.

- The APK owns status presentation, profile intent, typed buttons, doctor output,
  and user-readable diagnostics.
- Nebula Core owns privileged fixed commands, state files, safe mode, snapshots,
  rollback plans, and future apply/start operations.
- The APK must not expose unrestricted shell execution.
- Reversa findings, generated reports, screenshots, and chat notes are advisory
  until classified against local artifacts, source paths, hashes, logs, or bounded
  test output.
- Generated artifacts cannot override checked source, hash, or log evidence.

## Mutation Rules

Read-only probes must not mutate device state.

Preview-only policies must report `applied=false`. Cooling policy preview,
baseline integration status, and lane preflights can describe intent or missing
requirements, but they must not write hardware nodes, settings, properties,
vendor services, display state, or hook scope.

Any future mutating operation requires all of these before promotion:

- an explicit fixed command;
- a bounded input schema;
- a before-state snapshot when hardware or Android state can change;
- rollback or explicit stop/revoke behavior;
- safe-mode blocking;
- result logging;
- a host test fixture;
- a live proof log for the exact device/runtime lane.

## Runtime Lane Separation

Runtime lanes are separate. A proof in one lane does not silently promote another.

| Lane | Owner | Current policy |
| --- | --- | --- |
| Phone/App Mode | WayLandIE plus Nebula status/preflight | App/native bridge is solved and the pinned local ICD/driver loader path is confirmed. The active blocker is Vulkan export/real-buffer runtime evidence: `vkGetMemoryFdKHR` failures and `0` real-buffer commits keep full runtime success unpromoted. |
| Dock Lease Mode | Future Nebula Core lease broker plus receiver | Advisory and paused/crash-gated. No active DRM lease, composer-fd probing, `CREATE_LEASE`, wlroots DRM backend launch, or display mutation is implied. |
| Anland Surface Mode | DroidSpaces/Anland profile/container | Preflight-only until the selected container, `anland.env`, `/data/local/tmp/display_daemon.sock`, render node, and rootfs ownership are present together. |
| Compatibility Mode | Future conservative fallback | Blocked until implemented with reversible fixed commands. It is not Steam, Proton, Wine, DXVK, or game-client ready. |
| Recovery/Safe Mode | Nebula Core | Always available and blocks risky launch/apply/display paths. |

## Hook Lane Separation

ReZygisk and Vector/LSPosed are different layers.

- ReZygisk is the standalone Zygisk provider candidate when the normal provider
  path fails. The local artifact hash can be recorded as evidence, but that does
  not mean the module is installed, enabled, scoped, or hook-ready.
- Vector/LSPosed is the hook framework lane. Framework presence does not enable
  Nubia Toolkit hooks or mutating GameHub behavior.
- Hook readiness requires explicit provider state, framework state, scope state,
  rollback plan, and safe-mode behavior in a separate pass.

## Source And Asset Rules

Evidence-only materials are not copied into Nebula unless license, authorship,
and redistribution rights are proven.

Git revision identifiers in the app/module mean project provenance only. They do
not authorize adding proprietary ROM, GameHub, vendor APK, sound, icon, layout,
or binary assets to the public Hub.

Public Nebula builds must use generated/open assets or project-owned assets.
Owner-extracted RM11/GameHub assets belong in a local-only asset pack unless
explicit redistribution permission exists.
