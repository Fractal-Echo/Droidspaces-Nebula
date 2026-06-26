# RedMagic GameHub Control Deck

Date: 2026-06-24

## Goal

Nebula should feel like the RM11 Pro control deck: a gaming hub, desktop-mode
selector, PowerDeck policy surface, and runtime launcher in one app.

The main app remains Nebula-owned code. The RedMagic/GameHub direction is a UI
and workflow target, not a full foreign APK merge.

## Asset Policy

Two asset lanes are supported:

| Lane | Source | Distribution | Decision |
| --- | --- | --- | --- |
| Public Nebula skin | Generated Nebula art and original project assets. | Can ship in public APKs. | Default. |
| RM11 owner skin | Assets extracted locally from the user's own RM11/China ROM or installed GameHub packages. | Private/local only unless license permission is explicit. | Allowed for local owner builds. |

Do not commit proprietary RedMagic ROM assets, sounds, pages, package resources,
or APK payloads into the public Hub unless their license and redistribution
rights are proven.

## Implementation Shape

Nebula APK:

- owns the Control Deck UI;
- presents Home, Profiles, Runtime, Hardware, and Logs surfaces;
- displays module, thermal, fan, pump, display-lane, and runtime status;
- invokes only fixed Nebula Core commands;
- supports a future local asset-pack loader for RM11-owner builds;
- supports a future Nebula icon pack so runtime lanes, hardware controls,
  profiles, and desktop targets have a unified RedMagic/Nebula visual language.

Nebula Core:

- owns privileged read/apply/snapshot/rollback logic;
- owns future PowerDeck auto policy application;
- owns future RedMagic button integration;
- does not depend on proprietary GameHub APK code.

Private ROM/GameHub lane:

- extract assets from the user's own firmware dump or installed packages;
- map only static resources such as images, sounds, icons, and layout reference
  screenshots;
- keep extracted assets out of Git by default;
- generate a local-only asset pack that the app can prefer when present.

## RedMagic GameHub APK Handling

Do not use stock GameHub as the main Nebula base. It would couple Nebula to
vendor signatures, private framework assumptions, resource IDs, update drift,
and redistribution risk.

Use GameHub as reference material:

- inspect package names, intents, and visible flows;
- reimplement the useful control-deck flow in Nebula;
- keep hooks and mutating behavior behind Vector/LSPosed or Nebula Core gates;
- preserve stock behavior when safe mode, missing module, or hook failure occurs.

## Desktop Mode Direction

Desktop Mode becomes a first-class deck target with multiple lanes:

- Phone/App WayLandIE lane;
- Dock Lease external-display lane;
- Anland/Android surface compatibility lane;
- safe/recovery lane.

The China ROM/GameHub assets can supply local RM11 visual polish, but runtime
behavior remains driven by Nebula's own fixed protocols and rollback model.

## Icon Pack Direction

The launcher icon and in-app symbols should move away from generic placeholders
and toward a layered Nebula `N` deck emblem:

- public APK: generated/open Nebula icon pack;
- private RM11 build: optional owner-extracted RedMagic/GameHub icon references;
- themed icon: simple monochrome `N` fallback;
- no proprietary icon redistribution without explicit permission.

Future icon groups:

- display lanes;
- PowerDeck cooling states;
- fan, pump, triggers, refresh, and performance;
- Wine/Proton, WayLandIE, Dock Lease, Anland, and Recovery targets;
- RedMagic button actions.

## Next Single Action

Build the Control Deck shell in Nebula with public-safe assets first, then add a
local-only RM11 asset-pack importer once the target resource list is known.
