# Nebula Lanes

## Safe Desktop

Uses Termux and Termux:X11. This is the least risky lane for XFCE/KDE desktop testing because it uses known Android app boundaries.

## Zero-Copy Display

Uses the existing WayLandIE proof app and bridge tests. Vower WayLandIE remains a reference until signer/package/auth/storage risks are resolved.

## DroidSpaces Container

Uses DroidSpaces as the container runtime. Nebula should not fork container lifecycle logic until the app can prove a real gap.

## Native Compositor

Uses wlroots-style Android bridge references for Activity-per-surface, Binder/AIDL, AHardwareBuffer, and SurfaceControl ideas. This stays a reference lane until RedMagic/Adreno proof exists.

## PowerDeck

Uses the dry-run-first RedMagic PowerDeck module. Nebula can later become the UI/control surface, but the module remains the guarded writer.

## Steam/Proton

Parked until the display path is repeatable. WCP, Proton, WinNative, and PulseAudio leads stay as references.
