#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_root/nebula-core-module/bin/nebula-core"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export NEBULA_DATA_DIR="$tmp/data"
export NEBULA_MODULE_DIR="$repo_root/nebula-core-module"
export NEBULA_MODULE_PROP="$repo_root/nebula-core-module/module.prop"
export NEBULA_GIT_COMMIT="host-test"

json_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
print(obj.get(sys.argv[2], ""))
PY
}

status="$(sh "$cli" status --json)"
[[ "$(json_field "$status" protocol_version)" == "1" ]]
[[ "$(json_field "$status" profile)" == "safe" ]]

safe="$(sh "$cli" safe-mode get --json)"
[[ "$(json_field "$safe" safe_mode)" == "False" ]]

sh "$cli" safe-mode enable >/dev/null
safe="$(sh "$cli" safe-mode get --json)"
[[ "$(json_field "$safe" safe_mode)" == "True" ]]
[[ -f "$NEBULA_DATA_DIR/safe_mode" ]]

sh "$cli" profile set phone >/dev/null
profile="$(sh "$cli" profile get --json)"
[[ "$(json_field "$profile" profile)" == "phone" ]]
[[ "$(json_field "$profile" safe_mode)" == "False" ]]

set +e
dock_out="$(sh "$cli" profile set dock 2>/dev/null)"
dock_code=$?
compat_out="$(sh "$cli" profile set compatibility 2>/dev/null)"
compat_code=$?
set -e
[[ "$dock_code" -ne 0 ]]
[[ "$compat_code" -ne 0 ]]
[[ "$(json_field "$dock_out" error)" == "BLOCKED_NOT_READY" ]]
[[ "$(json_field "$compat_out" error)" == "BLOCKED_NOT_READY" ]]

caps="$(sh "$cli" capabilities --json)"
python3 - "$caps" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
ids = {item["id"] for item in obj["capabilities"]}
required = {"profile.safe", "profile.phone", "profile.dock", "profile.compatibility", "safe-mode", "logs.tail", "redmagic.probe"}
missing = sorted(required - ids)
if missing:
    raise SystemExit(f"missing capabilities: {missing}")
PY

fixture="$tmp/fixture"
props="$tmp/props"
mkdir -p "$fixture/sys/kernel/fan" "$fixture/sys/class/thermal/thermal_zone0" "$props"
printf 1 > "$fixture/sys/kernel/fan/fan_enable"
printf 4200 > "$fixture/sys/kernel/fan/fan_speed_count"
printf 4 > "$fixture/sys/kernel/fan/fan_speed_level"
printf 41000 > "$fixture/sys/class/thermal/thermal_zone0/temp"
printf nubia > "$props/ro.product.manufacturer"
printf NX809J > "$props/ro.product.model"
printf NX809J > "$props/ro.product.product.name"
printf NX809J > "$props/ro.product.device"
printf pineapple > "$props/ro.board.platform"

probe="$(
  NEBULA_SYSROOT="$fixture" \
  NEBULA_TEST_PROP_DIR="$props" \
  NEBULA_TEST_KERNEL="host-test" \
  sh "$cli" redmagic probe --json
)"
python3 - "$probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
for key in ["protocol_version", "command", "device", "fan", "performance", "display", "thermal", "redmagic_button"]:
    if key not in obj:
        raise SystemExit(f"missing probe key: {key}")
assert obj["command"] == "redmagic probe"
assert obj["device"]["model"] == "NX809J"
assert obj["fan"]["supported"] is True
assert obj["fan"]["present"] is True
assert obj["fan"]["enabled"] is True
assert obj["fan"]["rpm"] == 4200
assert obj["fan"]["level"] == 4
assert obj["performance"]["supported"] is False
assert obj["display"]["supported"] is False
assert obj["thermal"]["supported"] is True
assert obj["thermal"]["readings"][0]["temp_c"] == 41.0
assert obj["redmagic_button"]["reason"] == "disabled_in_pass_02"
PY

missing_probe="$(NEBULA_SYSROOT="$tmp/missing" sh "$cli" redmagic probe --json)"
python3 - "$missing_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["fan"]["supported"] is False
assert obj["fan"]["present"] is False
assert obj["thermal"]["supported"] is False
assert obj["fan"]["errors"]
PY

denied_probe="$(
  NEBULA_SYSROOT="$fixture" \
  NEBULA_TEST_DENY_PATHS="/sys/kernel/fan/fan_speed_count" \
  sh "$cli" redmagic probe --json
)"
python3 - "$denied_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["fan"]["supported"] is True
assert obj["fan"]["rpm"] is None
assert "permission_denied:/sys/kernel/fan/fan_speed_count" in obj["fan"]["errors"]
PY

set +e
extra_arg="$(sh "$cli" redmagic probe --json /etc/passwd 2>/dev/null)"
extra_code=$?
set -e
[[ "$extra_code" -ne 0 ]]
[[ "$(json_field "$extra_arg" error)" == "USAGE" ]]

logs="$(sh "$cli" logs tail --lines 10)"
python3 - "$logs" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
if not isinstance(obj.get("lines"), list):
    raise SystemExit("logs.lines is not a list")
PY

if rg -n 'WayLandIE|Wayland|Gamescope|Xwayland|DRM|compositor|linux|am start|monkey' "$repo_root/nebula-core-module/service.sh"; then
  echo "service.sh contains forbidden backend launch strings" >&2
  exit 1
fi

if rg -n 'setprop|settings put|service (start|stop|restart)|am start|cmd activity|input tap' "$repo_root/nebula-core-module/bin/nebula-core"; then
  echo "nebula-core contains forbidden mutation command strings" >&2
  exit 1
fi

if rg -n 'cat "?[$][{]?[A-Za-z0-9_]+|/etc/passwd|/proc/kmsg' "$repo_root/nebula-core-module/bin/nebula-core"; then
  echo "nebula-core appears to expose arbitrary path reads" >&2
  exit 1
fi

rg -n 'NEBULA_CORE_PROTOCOL_VERSION = 1|NEBULA_CORE_PROTOCOL_VERSION=1' "$repo_root/app/src/main/java/io/droidspaces/nebula/core/NebulaCoreProtocol.java" >/dev/null
rg -n 'protocolMismatch|moduleVersionMismatch|Invalid module JSON|parseRedMagicProbe' "$repo_root/app/src/main/java/io/droidspaces/nebula/core" >/dev/null

echo "Nebula control plane host tests passed."
