#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

required_files=(
  ".gitignore"
  "README.md"
  "settings.gradle.kts"
  "build.gradle.kts"
  "app/build.gradle.kts"
  "app/src/main/AndroidManifest.xml"
  "app/src/main/java/io/droidspaces/nebula/MainActivity.java"
  "docs/asset-policy.md"
  "docs/lanes.md"
  "docs/repo-map.md"
  "docs/workflow.md"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "missing required file: $file" >&2
    exit 1
  fi
done

grep -q 'rootProject.name = "DroidSpaces-Nebula"' settings.gradle.kts
grep -q 'namespace = "io.droidspaces.nebula"' app/build.gradle.kts
grep -q 'applicationId = "io.droidspaces.nebula"' app/build.gradle.kts
grep -q 'android:name=".MainActivity"' app/src/main/AndroidManifest.xml
grep -q 'android.intent.action.MAIN' app/src/main/AndroidManifest.xml
grep -q 'io.droidspaces.nebula.waylandie' app/src/main/AndroidManifest.xml
grep -q 'io.droidspaces.nebula.waylandie' app/src/main/java/io/droidspaces/nebula/MainActivity.java
grep -q '0.2.0-no-root-nebula13-rootfs-vulkan-smoke' app/src/main/java/io/droidspaces/nebula/MainActivity.java
grep -q 'WAYLANDIE_PACKAGE=io.droidspaces.nebula.waylandie' nebula-core-module/bin/nebula-core
grep -q 'NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS' nebula-core-module/bin/nebula-core
grep -q 'NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS' docs/integration/REVERSA_FINDINGS_ASSESSMENT.md

for pattern in \
  'out/' \
  '.repo/' \
  'recovery.img' \
  'boot.img' \
  'init_boot.img' \
  'vendor_boot.img' \
  'dtbo.img' \
  'vbmeta*.img' \
  'super.img' \
  'nebula-assets/'
do
  if ! grep -Fq "$pattern" .gitignore; then
    echo ".gitignore missing pattern: $pattern" >&2
    exit 1
  fi
done

forbidden_paths="$(
  find . \
    -path ./.git -prune -o \
    -path ./.gradle -prune -o \
    -path ./build -prune -o \
    -path ./app/build -prune -o \
    -path ./.github -type f -print -o \
    -type f \( \
      -name '*.img' -o \
      -name '*.bin' -o \
      -name '*.mbn' -o \
      -name '*.elf' -o \
      -name '*.apk' -o \
      -name '*.aab' -o \
      -name '*.apks' -o \
      -name '*.idsig' -o \
      -name '*.zip' -o \
      -name '*.tar' -o \
      -name '*.tar.*' -o \
      -name '*.zst' -o \
      -name '*.key' -o \
      -name '*.keystore' -o \
      -iname '*token*' -o \
      -iname '*secret*' \
    \) -print
)"

if [[ -n "$forbidden_paths" ]]; then
  echo "forbidden public-source artifact(s):" >&2
  echo "$forbidden_paths" >&2
  exit 1
fi

if find . \
    -path ./.git -prune -o \
    -path ./.gradle -prune -o \
    -path ./build -prune -o \
    -path ./app/build -prune -o \
    -type d \( \
    -name nebula-assets -o \
    -name Backups -o \
    -name EDL -o \
    -name dumps -o \
    -name payload-dumps \
  \) -print | grep -q .; then
  echo "forbidden private/bulky directory present in source tree" >&2
  exit 1
fi

git diff --check

echo "Nebula public source validation passed."
