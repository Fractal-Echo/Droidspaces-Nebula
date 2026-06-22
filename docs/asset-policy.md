# Nebula Asset Policy

`nebula-assets` is local-only by default.

Keep in `nebula-assets`:

- debug APK ladders
- screenshots
- UI XML captures
- logcat and shell logs
- Mesa/Turnip staging packages
- rootfs staging tarballs
- comparison output

Keep in this source repo:

- Android source
- build scripts
- docs
- small text manifests
- CI definitions
- release notes

Never commit:

- private dumps or full EDL backups
- raw partition backups
- `boot.img`, `init_boot.img`, `vendor_boot.img`, `dtbo.img`, `vbmeta*.img`, `super.img`, or `recovery.img`
- proprietary Qualcomm drivers
- private keys, keystores, tokens, serials, or personal logs

Release rule: publish only reviewed artifacts through GitHub Releases, with SHA256 hashes and a note saying whether the artifact is `proof`, `debug`, `rollback`, or `release-candidate`.
