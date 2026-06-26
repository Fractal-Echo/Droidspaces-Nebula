#!/usr/bin/env bash
set -euo pipefail

ADB="${ADB:-/mnt/c/platform-tools/adb.exe}"
MODEL="${NEBULA_ADB_MODEL:-NX809J}"
prefer_wireless=0
print_env=0

usage() {
  cat <<'EOF'
Usage: resolve-rm11-adb-serial.sh [--prefer-wireless] [--env]

Resolves the RM11Pro ADB target. By default this preserves the historic
behavior: any already-connected device matching NEBULA_ADB_MODEL wins, then
mDNS wireless endpoints are tried.

Options:
  --prefer-wireless  Refresh mDNS and prefer the live _adb-tls-connect endpoint.
  --env              Print shell env lines instead of only the serial:
                     ADB=..., MODEL=..., PHONE=..., ADB_SERIAL=...
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --prefer-wireless|--wireless)
      prefer_wireless=1
      ;;
    --env|--print-env)
      print_env=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

adb_cmd() {
  "$ADB" "$@" < /dev/null
}

device_for_model() {
  adb_cmd devices -l 2>/dev/null \
    | awk -v model="$MODEL" '$2 == "device" && index($0, "model:" model) { print $1; exit }'
}

emit_result() {
  local serial="$1"
  local phone="${2:-}"
  if [[ "$print_env" == "1" ]]; then
    printf 'ADB=%s\n' "$ADB"
    printf 'MODEL=%s\n' "$MODEL"
    if [[ -n "$phone" ]]; then
      printf 'PHONE=%s\n' "$phone"
    fi
    printf 'ADB_SERIAL=%s\n' "$serial"
  else
    printf '%s\n' "$serial"
  fi
}

mapfile -t endpoints < <(adb_cmd mdns services 2>/dev/null \
  | tr -d '\r' \
  | awk '$2 == "_adb-tls-connect._tcp" && $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ { print $3 }')

try_wireless() {
  local endpoint serial state model
  for endpoint in "${endpoints[@]}"; do
    adb_cmd connect "$endpoint" >/dev/null 2>&1 || true
    state="$(adb_cmd -s "$endpoint" get-state 2>/dev/null | tr -d '\r' || true)"
    model="$(adb_cmd -s "$endpoint" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
    if [[ "$state" == "device" && "$model" == "$MODEL" ]]; then
      emit_result "$endpoint" "$endpoint"
      return 0
    fi
  done

  serial="$(device_for_model)"
  if [[ -n "$serial" ]]; then
    for endpoint in "${endpoints[@]}"; do
      case "$serial" in
        "$endpoint"|adb-*)
          emit_result "$serial" "$endpoint"
          return 0
          ;;
      esac
    done
  fi

  if [[ "${#endpoints[@]}" -eq 1 ]]; then
    emit_result "${endpoints[0]}" "${endpoints[0]}"
    return 0
  fi

  return 1
}

if [[ "$prefer_wireless" == "1" ]]; then
  if try_wireless; then
    exit 0
  fi
fi

serial="$(device_for_model)"
if [[ -n "$serial" ]]; then
  emit_result "$serial"
  exit 0
fi

if [[ "${#endpoints[@]}" -eq 0 ]]; then
  echo "no wireless ADB endpoint found via adb devices or adb mdns services" >&2
  exit 1
fi

if try_wireless; then
  exit 0
fi

echo "multiple wireless ADB endpoints found, but none verified as model:$MODEL:" >&2
printf '  %s\n' "${endpoints[@]}" >&2
exit 1
