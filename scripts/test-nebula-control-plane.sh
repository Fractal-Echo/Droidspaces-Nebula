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
required = {
    "profile.safe",
    "profile.phone",
    "profile.dock",
    "profile.compatibility",
    "safe-mode",
    "logs.tail",
    "redmagic.probe",
    "redmagic.pump.probe",
}
missing = sorted(required - ids)
if missing:
    raise SystemExit(f"missing capabilities: {missing}")
PY

fixture="$tmp/fixture"
props="$tmp/props"
mkdir -p \
  "$fixture/sys/kernel/fan" \
  "$fixture/sys/class/thermal/thermal_zone0" \
  "$fixture/proc/driver/micropump" \
  "$props"
printf 1 > "$fixture/sys/kernel/fan/fan_enable"
printf 4200 > "$fixture/sys/kernel/fan/fan_speed_count"
printf 4 > "$fixture/sys/kernel/fan/fan_speed_level"
printf 41000 > "$fixture/sys/class/thermal/thermal_zone0/temp"
printf 1 > "$fixture/proc/driver/micropump/enable"
printf 4 > "$fixture/proc/driver/micropump/freq"
printf 80 > "$fixture/proc/driver/micropump/speed"
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
for key in ["protocol_version", "command", "device", "fan", "pump", "performance", "display", "thermal", "redmagic_button"]:
    if key not in obj:
        raise SystemExit(f"missing probe key: {key}")
assert obj["command"] == "redmagic probe"
assert obj["device"]["model"] == "NX809J"
assert obj["fan"]["supported"] is True
assert obj["fan"]["present"] is True
assert obj["fan"]["enabled"] is True
assert obj["fan"]["rpm"] == 4200
assert obj["fan"]["level"] == 4
assert obj["pump"]["supported"] is True
assert obj["pump"]["present"] is True
assert obj["pump"]["enabled"] is True
assert obj["pump"]["speed"] == 80
assert obj["pump"]["rpm"] is None
assert obj["pump"]["level"] is None
assert obj["pump"]["flow_rate"] is None
assert obj["pump"]["flow_rate_unit"] is None
assert obj["pump"]["mode"] is None
assert obj["pump"]["confidence"] == "confirmed"
assert "/proc/driver/micropump/speed" in obj["pump"]["sources"]
assert obj["performance"]["supported"] is False
assert obj["display"]["supported"] is False
assert obj["thermal"]["supported"] is True
assert obj["thermal"]["readings"][0]["temp_c"] == 41.0
assert obj["redmagic_button"]["reason"] == "disabled_in_pass_02"
PY

pump_probe="$(
  NEBULA_SYSROOT="$fixture" \
  sh "$cli" redmagic pump probe --json
)"
python3 - "$pump_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "redmagic pump probe"
pump = obj["pump"]
assert pump["supported"] is True
assert pump["present"] is True
assert pump["enabled"] is True
assert pump["speed"] == 80
assert pump["rpm"] is None
assert pump["level"] is None
assert pump["flow_rate"] is None
assert pump["flow_rate_unit"] is None
assert pump["mode"] is None
assert pump["confidence"] == "confirmed"
assert pump["errors"] == []
PY

missing_probe="$(NEBULA_SYSROOT="$tmp/missing" sh "$cli" redmagic probe --json)"
python3 - "$missing_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["fan"]["supported"] is False
assert obj["fan"]["present"] is False
assert obj["pump"]["supported"] is False
assert obj["pump"]["present"] is False
assert obj["thermal"]["supported"] is False
assert obj["fan"]["errors"]
assert "missing:/proc/driver/micropump" in obj["pump"]["errors"]
PY

missing_pump_probe="$(NEBULA_SYSROOT="$tmp/missing" sh "$cli" redmagic pump probe --json)"
python3 - "$missing_pump_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
pump = obj["pump"]
assert pump["supported"] is False
assert pump["present"] is False
assert pump["sources"] == []
assert "missing:/proc/driver/micropump" in pump["errors"]
PY

denied_probe="$(
  NEBULA_SYSROOT="$fixture" \
  NEBULA_TEST_DENY_PATHS="/sys/kernel/fan/fan_speed_count:/proc/driver/micropump/speed" \
  sh "$cli" redmagic probe --json
)"
python3 - "$denied_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["fan"]["supported"] is True
assert obj["fan"]["rpm"] is None
assert "permission_denied:/sys/kernel/fan/fan_speed_count" in obj["fan"]["errors"]
assert obj["pump"]["supported"] is True
assert obj["pump"]["speed"] is None
assert "permission_denied:/proc/driver/micropump/speed" in obj["pump"]["errors"]
PY

malformed_fixture="$tmp/malformed"
mkdir -p "$malformed_fixture/proc/driver/micropump"
printf 1 > "$malformed_fixture/proc/driver/micropump/enable"
printf 4 > "$malformed_fixture/proc/driver/micropump/freq"
printf fast > "$malformed_fixture/proc/driver/micropump/speed"
malformed_pump="$(
  NEBULA_SYSROOT="$malformed_fixture" \
  sh "$cli" redmagic pump probe --json
)"
python3 - "$malformed_pump" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
pump = obj["pump"]
assert pump["supported"] is True
assert pump["speed"] is None
assert "invalid_numeric:/proc/driver/micropump/speed:fast" in pump["errors"]
PY

range_fixture="$tmp/out-of-range"
mkdir -p "$range_fixture/proc/driver/micropump"
printf 1 > "$range_fixture/proc/driver/micropump/enable"
printf 4 > "$range_fixture/proc/driver/micropump/freq"
printf 500 > "$range_fixture/proc/driver/micropump/speed"
range_pump="$(
  NEBULA_SYSROOT="$range_fixture" \
  sh "$cli" redmagic pump probe --json
)"
python3 - "$range_pump" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
pump = obj["pump"]
assert pump["supported"] is True
assert pump["speed"] is None
assert "out_of_range:/proc/driver/micropump/speed:500" in pump["errors"]
PY

set +e
extra_arg="$(sh "$cli" redmagic probe --json /etc/passwd 2>/dev/null)"
extra_code=$?
pump_extra_arg="$(sh "$cli" redmagic pump probe --json /proc/driver/micropump/speed 2>/dev/null)"
pump_extra_code=$?
set -e
[[ "$extra_code" -ne 0 ]]
[[ "$pump_extra_code" -ne 0 ]]
[[ "$(json_field "$extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$pump_extra_arg" error)" == "USAGE" ]]

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
rg -n 'protocolMismatch|moduleVersionMismatch|Invalid module JSON|parseRedMagicProbe|redMagicPumpProbe' "$repo_root/app/src/main/java/io/droidspaces/nebula/core" >/dev/null

echo "Nebula control plane host tests passed."
