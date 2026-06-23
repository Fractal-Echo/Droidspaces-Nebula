#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-/mnt/c/platform-tools/adb.exe}"
MODEL="${NEBULA_ADB_MODEL:-NX809J}"

device_for_model() {
  "$ADB" devices -l 2>/dev/null \
    | awk -v model="$MODEL" '$2 == "device" && index($0, "model:" model) { print $1; exit }'
}

serial="$(device_for_model)"
if [[ -n "$serial" ]]; then
  printf '%s\n' "$serial"
  exit 0
fi

mapfile -t endpoints < <("$ADB" mdns services 2>/dev/null \
  | awk '$2 == "_adb-tls-connect._tcp" && $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ { print $3 }')

if [[ "${#endpoints[@]}" -eq 0 ]]; then
  echo "no wireless ADB endpoint found via adb devices or adb mdns services" >&2
  exit 1
fi

for endpoint in "${endpoints[@]}"; do
  "$ADB" connect "$endpoint" >/dev/null 2>&1 || true
  serial="$(device_for_model)"
  if [[ -n "$serial" ]]; then
    printf '%s\n' "$serial"
    exit 0
  fi
done

if [[ "${#endpoints[@]}" -eq 1 ]]; then
  printf '%s\n' "${endpoints[0]}"
  exit 0
fi

echo "multiple wireless ADB endpoints found, but none verified as model:$MODEL:" >&2
printf '  %s\n' "${endpoints[@]}" >&2
exit 1
