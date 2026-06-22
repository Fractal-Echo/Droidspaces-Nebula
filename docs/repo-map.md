# Nebula Repo Map

Primary hub:

| Repo | Role | Decision |
| --- | --- | --- |
| `Fractal-Echo/Droidspaces-Nebula` | Public source/release hub | Primary |
| local `nebula-assets` | APK/log/screenshot/package bucket | Local-only |

Core upstreams and forks:

| Repo | Role | Decision |
| --- | --- | --- |
| `Fractal-Echo/Droidspaces-OSS` | Android/Linux container runtime | Keep as primary runtime reference |
| `Fractal-Echo/anland` | Working Android Wayland stack reference | Keep as high-priority reference |
| `Goldzxcbug/anland` | Active upstream lead for Android Wayland runtime | Track, do not vendor blindly |
| `Fractal-Echo/WayLandIE` | Existing Fractal fork of WayLandIE | Keep as source reference |
| `Vower2993/WayLandIE` | No-root/Wayland lead | Track as active lead |
| `cakroni1580/WayLandIE` | AdrenoTools/Turnip bridge reference | Track as active lead |
| `Fractal-Echo/mesa-for-android-container-rm11pro` | KGSL/Turnip/Mesa source | Keep as driver staging reference |
| `Fractal-Echo/Droidspaces-rootfs-KDE-builder` | Rootfs builder reference | Keep for KDE/rootfs workflow |

Support and future lanes:

| Repo | Role | Decision |
| --- | --- | --- |
| `Fractal-Echo/termux-app` | Fallback terminal app | Park |
| `Fractal-Echo/termux-x11` | Fallback X11 display lane | Park |
| `Fractal-Echo/fdroidclient` | Distribution tooling | Park |
| `Fractal-Echo/fdroidserver` | Distribution tooling | Park |
| `Fractal-Echo/libhybris` | Bionic/glibc research | Park until Vulkan path needs it |
| `Fractal-Echo/RM11Plus_KernelSU_SUSFS` | Kernel/root lane | Post-Wayland only |

Cleanup rule: delete local comparison clones only when this map names the retained upstream or active worktree.
