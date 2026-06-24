# DRM Control Reference

The attached DRM Control README describes a confirmed external-display Dock
method, not an unproven guess.

## Model

- Android keeps ownership of the external display through the vendor composer.
- A broker uses the live composer DRM fd to create a lease for discovered
  connector, CRTC, and scanout plane objects.
- The lease fd is sent into the Linux rootfs with `SCM_RIGHTS`.
- A rootfs receiver verifies the fd, maps it to the wlroots DRM backend, and
  starts labwc.
- Stop/revoke explicitly clears stale scanout state and returns display control
  to Android.

## Nebula Integration Target

Future Dock mode should port the pattern as:

- Nebula Core fixed commands only.
- Receiver-only preflight before any CREATE_LEASE operation.
- No hard-coded connector, CRTC, or plane IDs.
- Explicit stop/revoke command with evidence capture.
- Crash counter and safe-mode block.
- No boot-time Dock auto-launch.

## Current Status

Reference only in this patch. No DRM fd probing, composer fd probing,
CREATE_LEASE, wlroots DRM backend launch, or display mutation is executed here.
