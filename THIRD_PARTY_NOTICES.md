# Third-Party Notices

DroidSpaces Nebula is a coordination layer. It reports, launches, or documents
multiple external lanes, but it should not silently claim ownership of upstream
projects, ROM assets, or binary payloads.

## Current Source And Runtime References

| Project / asset | Role in Nebula | Local status | Release boundary |
| --- | --- | --- | --- |
| DroidSpaces / Droidspaces-OSS | Container runtime reference and method profile source | Local source under `nebula-assets/Repos/Droidspaces-OSS`; license file observed as GPLv3 | Preserve GPLv3 notices and source obligations if distributing derived binaries. |
| WayLandIE / Vower WayLandIE | App display/runtime, compatibility lead, no-root/GPU/DXVK/Turnip reference | Vower latest synced locally at `3ea02d5`; license file observed as GPLv3 | Compatibility candidate until bounded device proof exists; preserve GPLv3 notices. |
| Anland / Goldzxcbug + Fractal-Echo fork | Android Wayland consumer/daemon/producer lane | Local source under `nebula-assets/Repos/anland`; no top-level license file observed in this pass | Verify upstream license before redistribution; local proof artifacts are research inputs. |
| DroidSpaces-rootfs-KDE-builder | Ubuntu26/KDE rootfs builder for Anland method | Local builder and rootfs archive under `nebula-assets/Repos/Droidspaces-rootfs-KDE-builder`; no top-level license file observed | Rootfs archives contain many distro packages; preserve package license metadata and verify redistribution terms before release. |
| Mesa / Freedreno / Turnip | Vulkan/KGSL driver evidence and runtime reference | Referenced by pinned ICD/driver evidence | Do not vendor blindly; preserve upstream licenses if distributing binaries. |
| Gamescope / Xwayland / wlroots ecosystem | Sidecars and compositor/display experiments | Sidecar proof artifacts are local assets | Treat sidecars as reviewed release artifacts only after hashes, provenance, and license notices are attached. |
| Termux / Termux:X11 | Compatibility display lane | Referenced as an installed/runtime method | Do not bundle Termux payloads without upstream notices and redistribution review. |
| Proton / Wine / DXVK / VKD3D / box64 / FEX | Future game-client/runtime lanes | Not promoted by current proof | Do not ship proprietary game clients or runtime payloads in this source repo. |
| Nubia Toolkit / RedMagic Control Center | RedMagic hardware/status references | Referenced for future hook/control lanes | Attribution required; mutating behavior remains gated. |
| RedMagicPowerDeck | Dry-run automation model | Local archived/vendor import, origin/license incomplete | Reimplement conceptually unless ownership and license are clarified. |
| OrangeFox / TWRP / AOSP / Qualcomm/Nubia device trees | Recovery and device-tree context through Canoe/OrangeFox work | Referenced by release-hub docs | Keep notices with the recovery/device-tree project, not inside Nebula APK source. |

## Local Proof Folders

Current curated proof folders are local-only:

```text
/home/richtofen/.android/repositories/rm11mainassets/projects/droidspace-repos/validated-sidecars/2026-06-25-r6-wayland-working-real-buffer-pass
/home/richtofen/.android/repositories/rm11mainassets/projects/droidspace-repos/validated-methods/2026-06-26-anland-droidspaces-wayland-visible
/home/richtofen/.android/repositories/rm11mainassets/projects/droidspace-repos/compatibility-candidates/vower-waylandie-origin-main-20260626
```

These paths are evidence organization, not public redistribution approval.

## Non-Affiliation

Nebula is not affiliated with Nubia, RedMagic, Valve, CodeWeavers, Wine, DXVK,
Mesa, KDE, Termux, Gamescope, DroidSpaces, WayLandIE, Anland, OrangeFox, TWRP,
or any upstream project unless a separate upstream relationship is explicitly
documented.
