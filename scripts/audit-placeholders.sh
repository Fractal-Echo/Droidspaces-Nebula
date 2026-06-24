#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
asset_root="/home/richtofen/.android/repositories/nebula-assets"
repos_root="$asset_root/Repos"
vendor_root="$asset_root/vendor-imports"
staging_root="$asset_root/staging"

out="${1:-$asset_root/logs/placeholder-audit.tsv}"
mkdir -p "$(dirname "$out")"

emit() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$out"
}

scan_root() {
  local label="$1"
  local root="$2"
  [[ -e "$root" ]] || return 0

  find "$root" \
    \( -name .git -o -name .gradle -o -name build -o -name app-build -o \
       -name node_modules -o -name .cxx -o -name meson-private -o \
       -name __pycache__ \) -prune -o \
    -type f -print0 |
    while IFS= read -r -d '' file; do
      rel="${file#$root/}"
      if [[ "$file" == "$repo_root/scripts/audit-placeholders.sh" ]]; then
        continue
      fi
      if [[ ! -s "$file" ]]; then
        emit review zero_byte "$file" "$label"
        continue
      fi
      case "$rel" in
        *.png|*.jpg|*.jpeg|*.webp|*.mp4|*.gif|*.apk|*.zip|*.deb|*.so|*.a|*.o|*.jar|*.class)
          continue
          ;;
      esac
      case "$(basename "$file")" in
        *placeholder*|*PLACEHOLDER*|*placebo*|*PLACEBO*|*dummy*|*DUMMY*|*stub*|*STUB*|*.placeholder)
          emit review suspect_name "$file" "$label"
          ;;
      esac
      if grep -Iq . "$file"; then
        if grep -InE 'PLACEHOLDER|PLACEBO|TODO placeholder|TODO: placeholder|dummy implementation|fake implementation|stub implementation' "$file" >/tmp/nebula-placeholder-grep.$$ 2>/dev/null; then
          while IFS= read -r match; do
            emit review suspect_text "$file" "$label:$match"
          done < /tmp/nebula-placeholder-grep.$$
          rm -f /tmp/nebula-placeholder-grep.$$
        fi
      fi
    done
}

printf 'severity\tkind\tpath\tdetail\n' > "$out"

scan_root hub "$repo_root"
scan_root Droidspaces-OSS "$repos_root/Droidspaces-OSS"
scan_root WayLandIE "$repos_root/waylandie-vower-578b431"
scan_root gamescope "$repos_root/gamescope"
scan_root anland "$repos_root/anland"
scan_root Droidspaces-rootfs-KDE-builder "$repos_root/Droidspaces-rootfs-KDE-builder"
scan_root box64 "$repos_root/box64"
scan_root dxvk "$repos_root/dxvk"
scan_root mesa-rm11pro "$repos_root/mesa-for-android-container-rm11pro"
scan_root FEX "$repos_root/FEX"
scan_root Proton "$repos_root/Proton"
scan_root NubiaToolkit "$vendor_root/NubiaToolkit"
scan_root Redmagic-Control-Center "$vendor_root/Redmagic-Control-Center"
scan_root gamescope-sidecar "$staging_root/nebula-xwayland-gamescope-sidecar-05/gamescope-wayland-backend"

if [[ "$(wc -l < "$out")" -eq 1 ]]; then
  emit info clean "-" "no obvious placeholder/placebo files found"
fi

echo "Placeholder audit written to $out"
