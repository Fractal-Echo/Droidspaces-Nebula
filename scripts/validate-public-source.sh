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
  "docs/integration/STATUS_MODEL.md"
  "docs/integration/schemas/dock-lease-command.schema.json"
  "docs/integration/schemas/dock-lease-result.schema.json"
  "tests/fixtures/dock-lease/lease-discovery-command.json"
  "tests/fixtures/dock-lease/lease-discovery-result.json"
  "tests/fixtures/dock-lease/lease-test-only-command.json"
  "tests/fixtures/dock-lease/lease-test-only-result.json"
  "scripts/validate-dock-lease-schema.js"
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
grep -q 'fixed_active_first_nebula_core_cli' app/src/main/java/io/droidspaces/nebula/core/NebulaCoreClient.java
grep -q 'NEBULA_CORE_DEBUG_PENDING' app/src/main/java/io/droidspaces/nebula/core/NebulaCoreClient.java
grep -q 'pending module rejected by anti-regression guard' app/src/main/java/io/droidspaces/nebula/core/NebulaCoreClient.java
grep -q 'display method-profiles --json' app/src/main/java/io/droidspaces/nebula/core/NebulaCoreClient.java
grep -q 'display method-profiles --json' nebula-core-module/README.md
grep -q 'display method-profiles --json' docs/integration/UNIFIED_CONTROL_PLANE.md
grep -q 'dock-lease-command.schema.json' docs/integration/DRM_CONTROL_REFERENCE.md
grep -q 'dock-lease-result.schema.json' docs/integration/DRM_CONTROL_REFERENCE.md
grep -q 'NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS' nebula-core-module/bin/nebula-core
grep -q 'NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS' docs/integration/REVERSA_FINDINGS_ASSESSMENT.md
grep -q 'NONE_WAYLAND_DISPLAY' docs/integration/STATUS_MODEL.md

node scripts/validate-dock-lease-schema.js

python3 - <<'PY'
from pathlib import Path

client = Path("app/src/main/java/io/droidspaces/nebula/core/NebulaCoreClient.java").read_text()
active_first = r'if [ -x \"$NEBULA_CORE_ACTIVE\" ]; then'
pending_fallback = r'elif [ -x \"$NEBULA_CORE_PENDING\" ]; then NEBULA_CORE_CLI=\"$NEBULA_CORE_PENDING\";'
if active_first not in client or pending_fallback not in client:
    raise SystemExit("NebulaCoreClient missing active-first dispatch/fallback markers")
if client.index(active_first) > client.index(pending_fallback):
    raise SystemExit("NebulaCoreClient must check active module before pending fallback")
if "fixed_pending_or_active_nebula_core_cli" in client:
    raise SystemExit("NebulaCoreClient regressed to pending-first label")

for path in [
    "README.md",
    "docs/integration/UNIFIED_CONTROL_PLANE.md",
    "docs/integration/BASELINE_INTEGRATIONS.md",
    "docs/integration/CONTROL_PLANE_POLICY.md",
    "nebula-core-module/README.md",
    "app/src/main/java/io/droidspaces/nebula/MainActivity.java",
    "nebula-core-module/bin/nebula-core",
]:
    text = Path(path).read_text()
    forbidden = [
        "NEBULA_R6_EXPORT_A1_VULKAN_LOADER_PIN_CONFIRMED",
        "vkGetMemoryFdKHR failures and zero real-buffer commits",
        "vkGetMemoryFdKHR failures, 0 real-buffer commits",
        "prefers that pending CLI before",
        "prefers that fixed pending CLI before",
        "hardware GLX and real-buffer pass are not proven",
        "Current blocker: " + "Vulkan export / " + "real-buffer path",
        "loader-pin confirmed, not a full A1",
    ]
    for marker in forbidden:
        if marker in text:
            raise SystemExit(f"{path} still contains stale regression marker: {marker}")
PY

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
