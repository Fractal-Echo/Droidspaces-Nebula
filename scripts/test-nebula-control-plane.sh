#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cli="$repo_root/nebula-core-module/bin/nebula-core"
tmp="$(mktemp -d)"
socket_pids=()
cleanup() {
  for pid in "${socket_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

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

write_policy_defaults() {
  local file="$1"
  local configured="${2:-true}"
  {
    printf '{\n'
    printf '  "cooling_policy": {\n'
    printf '    "configured": %s,\n' "$configured"
    printf '    "temperature_min_c": 0,\n'
    printf '    "temperature_max_c": 120,\n'
    printf '    "balanced_c": 38,\n'
    printf '    "hot_c": 42,\n'
    printf '    "critical_c": 46,\n'
    printf '    "hysteresis_c": 2,\n'
    printf '    "minimum_dwell_seconds": 30\n'
    printf '  }\n'
    printf '}\n'
  } > "$file"
}

make_policy_fixture() {
  local fixture="$1"
  local thermal_value="${2:-41000}"
  local fan="${3:-present}"
  local pump="${4:-present}"
  rm -rf "$fixture"
  mkdir -p "$fixture/sys/class/thermal/thermal_zone0"
  printf '%s' "$thermal_value" > "$fixture/sys/class/thermal/thermal_zone0/temp"
  if [[ "$fan" == "present" ]]; then
    mkdir -p "$fixture/sys/kernel/fan"
    printf 0 > "$fixture/sys/kernel/fan/fan_enable"
    printf 0 > "$fixture/sys/kernel/fan/fan_speed_count"
    printf 2 > "$fixture/sys/kernel/fan/fan_speed_level"
  fi
  if [[ "$pump" == "present" ]]; then
    mkdir -p "$fixture/proc/driver/micropump"
    printf 1 > "$fixture/proc/driver/micropump/enable"
    printf 4 > "$fixture/proc/driver/micropump/freq"
    printf 80 > "$fixture/proc/driver/micropump/speed"
  fi
}

policy_json_for() {
  local fixture="$1"
  local defaults="$2"
  NEBULA_SYSROOT="$fixture" \
  NEBULA_DEFAULTS_JSON="$defaults" \
  sh "$cli" cooling policy --json
}

assert_policy_state() {
  local json="$1"
  local state="$2"
  local fan_intent="$3"
  local pump_intent="$4"
  python3 - "$json" "$state" "$fan_intent" "$pump_intent" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "cooling policy"
assert obj["preview_only"] is True
assert obj["state"] == sys.argv[2], obj
assert obj["fan"]["intent"] == sys.argv[3], obj["fan"]
assert obj["pump"]["intent"] == sys.argv[4], obj["pump"]
assert obj["fan"]["applied"] is False
assert obj["pump"]["applied"] is False
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
    "cooling.policy",
    "snapshot.cooling",
    "legacy.modules",
    "nubia.toolkit.status",
    "runtime.waylandie.status",
    "runtime.waylandie.proton-smoke",
    "display.lanes",
    "display.lane.phone.preflight",
    "display.lane.anland.preflight",
    "display.lane.dock.preflight",
    "adb.wifi",
}
missing = sorted(required - ids)
if missing:
    raise SystemExit(f"missing capabilities: {missing}")
PY

package_dir="$tmp/packages"
modules_root="$tmp/modules"
mkdir -p "$package_dir/cn.nubia.gameassist" \
  "$package_dir/cn.nubia.gamelauncher" \
  "$modules_root/zygisk_vector"
{
  printf 'id=zygisk_vector\n'
  printf 'name=Vector\n'
  printf 'version=v2.0 (3021)\n'
  printf 'versionCode=3021\n'
} > "$modules_root/zygisk_vector/module.prop"
nubia_status="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_MODULES_ROOT="$modules_root" \
  sh "$cli" nubia toolkit status --json
)"
python3 - "$nubia_status" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "nubia toolkit status"
assert obj["integration"] == "ported_status_only"
assert obj["old_toolkit_required"] is False
assert obj["lsposed_required_for_hooks"] is True
assert obj["lsposed_hooks_active"] is False
framework = obj["hook_framework"]
assert framework["id"] == "zygisk_vector"
assert framework["installed"] is True
assert framework["enabled"] is True
assert framework["android_16_compatible"] is True
packages = obj["packages"]
assert packages["game_assist"]["visible"] is True
assert packages["game_launcher"]["visible"] is True
assert packages["toolkit_reference"]["visible"] is False
assert any(item["id"] == "super_resolution_unlock" for item in obj["features"])
PY

waylandie_data="$tmp/waylandie-data"
waylandie_lib="$tmp/waylandie-lib"
mkdir -p "$package_dir/io.droidspaces.nebula.waylandie" \
  "$waylandie_data/files/imagefs" \
  "$waylandie_data/files/contents/proton/active/files/lib/wine/aarch64-unix" \
  "$waylandie_lib"
: > "$waylandie_lib/libproot.so"
: > "$waylandie_lib/libld_glibc.so"
: > "$waylandie_data/files/contents/proton/active/files/lib/wine/aarch64-unix/wine"
waylandie_status="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_data" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  sh "$cli" runtime waylandie status --json
)"
python3 - "$waylandie_status" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "runtime waylandie status"
assert obj["package"] == "io.droidspaces.nebula.waylandie"
assert obj["method"] == "root_assisted_proot"
assert obj["installed"] is True
assert obj["imagefs_present"] is True
assert obj["proot_present"] is True
assert obj["glibc_loader_present"] is True
assert obj["proton_present"] is True
assert obj["wine_present"] is True
assert obj["ready"] is True
assert obj["errors"] == []
PY

missing_waylandie_status="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_WAYLANDIE_DATA_DIR="$tmp/missing-waylandie" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$tmp/missing-lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  sh "$cli" runtime waylandie status --json
)"
python3 - "$missing_waylandie_status" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "runtime waylandie status"
assert obj["ready"] is False
assert "missing:imagefs" in obj["errors"]
assert "missing:proton_active" in obj["errors"]
PY

safe_smoke_data="$tmp/safe-smoke"
mkdir -p "$safe_smoke_data"
touch "$safe_smoke_data/safe_mode"
set +e
safe_smoke="$(
  NEBULA_DATA_DIR="$safe_smoke_data" \
  NEBULA_TEST_WAYLANDIE_SMOKE_RESULT=pass \
  sh "$cli" runtime waylandie proton-smoke --json
)"
safe_smoke_code=$?
set -e
[[ "$safe_smoke_code" -ne 0 ]]
python3 - "$safe_smoke" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "runtime waylandie proton-smoke"
assert obj["ok"] is False
assert obj["safe_mode"] is True
assert obj["error"] == "SAFE_MODE_ACTIVE"
PY

smoke_pass="$(
  NEBULA_TEST_WAYLANDIE_SMOKE_RESULT=pass \
  sh "$cli" runtime waylandie proton-smoke --json
)"
python3 - "$smoke_pass" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "runtime waylandie proton-smoke"
assert obj["ok"] is True
assert obj["method"] == "root_assisted_proot"
assert obj["exit_code"] == 0
assert obj["errors"] == []
PY

device_root="$tmp/device-root"
mkdir -p "$device_root/data/local/Droidspaces/bin" \
  "$device_root/data/local/Droidspaces/Containers/ubuntu" \
  "$device_root/data/local/tmp" \
  "$device_root/dev/dri"
: > "$device_root/dev/dri/renderD128"
cat > "$device_root/data/local/Droidspaces/bin/droidspaces" <<'SH'
#!/system/bin/sh
exit 0
SH
chmod 755 "$device_root/data/local/Droidspaces/bin/droidspaces"
cat > "$device_root/data/local/Droidspaces/Containers/ubuntu/container.config" <<'EOF'
enable_termux_x11=0
enable_hw_access=1
enable_gpu_mode=1
env_file=/data/local/Droidspaces/Containers/ubuntu/anland.env
bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock
EOF
cat > "$device_root/data/local/Droidspaces/Containers/ubuntu/anland.env" <<'EOF'
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
WAYLAND_DISPLAY=wayland-0
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
EOF
python3 - "$device_root/data/local/tmp/display_daemon.sock" <<'PY' &
import os, socket, sys, time
path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX)
s.bind(path)
s.listen(1)
time.sleep(120)
PY
socket_pids+=("$!")
sleep 0.2

display_lanes="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_data" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  sh "$cli" display lanes --json
)"
python3 - "$display_lanes" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display lanes"
assert obj["selector"] == "multi_lane"
lanes = {item["id"]: item for item in obj["lanes"]}
assert lanes["phone_app_bridge"]["status"] == "ready_for_glx_fix"
assert lanes["phone_app_bridge"]["mutating"] is False
assert lanes["phone_app_bridge"]["launch_command_available"] is False
assert lanes["phone_app_bridge"]["active_blocker"] == "RGB_GLX_VISUAL_FBCONFIG_EXPOSURE"
assert lanes["anland_surface"]["status"] == "preflight_ready"
assert lanes["anland_surface"]["repair_command_available"] is False
assert lanes["anland_surface"]["checks"]["display_daemon_socket"] is True
assert lanes["dock_drm_lease_external"]["status"] == "proven_reference_not_wired"
assert lanes["dock_drm_lease_external"]["evidence_captured"] is True
assert lanes["dock_drm_lease_external"]["operator_gated"] is True
assert lanes["dock_drm_lease_external"]["external_display_only"] is True
assert lanes["dock_drm_lease_external"]["start_command_available"] is False
assert lanes["dock_drm_lease_external"]["reported_objects"]["hardcoded_forbidden"] is True
assert "no_lane_silently_replaces_another" in obj["selection_rules"]
PY

phone_preflight="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_data" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  sh "$cli" display lane phone preflight --json
)"
python3 - "$phone_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display lane phone preflight"
assert obj["id"] == "phone_app_bridge"
assert obj["available"] is True
assert obj["mutating"] is False
assert obj["launch_command_available"] is False
PY

anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display lane anland preflight"
assert obj["id"] == "anland_surface"
assert obj["available"] is True
assert obj["mutating"] is False
assert obj["repair_command_available"] is False
assert obj["checks"]["droidspaces_binary"] is True
assert obj["checks"]["display_daemon_socket"] is True
assert obj["checks"]["env_kgsl"] is True
PY

dock_preflight="$(sh "$cli" display lane dock preflight --json)"
python3 - "$dock_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display lane dock preflight"
assert obj["id"] == "dock_drm_lease_external"
assert obj["status"] == "proven_reference_not_wired"
assert obj["available"] is False
assert obj["mutating"] is False
assert obj["start_command_available"] is False
assert obj["evidence_captured"] is True
assert obj["operator_gated"] is True
assert obj["external_display_only"] is True
assert obj["internal_panel_allowed"] is False
assert obj["whole_card_takeover"] is False
assert obj["reported_objects"]["connector"] == 89
assert obj["reported_objects"]["hardcoded_forbidden"] is True
PY

settings_dir="$tmp/settings"
mkdir -p "$settings_dir"
printf 0 > "$settings_dir/global_adb_enabled"
printf 0 > "$settings_dir/global_adb_wifi_enabled"
printf 0 > "$settings_dir/global_enable_wireless_switch"
printf 0 > "$settings_dir/adb_wireless_port"
printf '20:3a:0c:78:9a:c8\n' > "$settings_dir/current_bssid"
adb_wifi_status="$(
  NEBULA_SETTINGS_DIR="$settings_dir" \
  sh "$cli" adb-wifi status --json
)"
python3 - "$adb_wifi_status" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "adb-wifi status"
assert obj["adb_debugging"] is False
assert obj["wireless_debugging"] is False
assert obj["settings_wireless_debugging"] is False
assert obj["ui_wireless_switch"] is False
assert obj["wireless_port"] == 0
assert obj["manager_bssid_available"] is True
assert obj["settings_requested"] is False
assert obj["manual_toggle_required"] is False
assert obj["activation_state"] == "disabled"
assert obj["auto_enable"] is False
assert obj["errors"] == []
PY

set +e
adb_wifi_enable="$(
  NEBULA_SETTINGS_DIR="$settings_dir" \
  sh "$cli" adb-wifi enable --json
)"
adb_wifi_enable_code=$?
set -e
[[ "$adb_wifi_enable_code" -ne 0 ]]
python3 - "$adb_wifi_enable" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "adb-wifi enable"
assert obj["ok"] is False
assert obj["applied"] is False
assert obj["requested"] is True
assert obj["manager_request_ok"] is True
assert obj["adb_debugging"] is True
assert obj["wireless_debugging"] is False
assert obj["settings_wireless_debugging"] is True
assert obj["ui_wireless_switch"] is True
assert obj["manager_bssid_available"] is True
assert obj["settings_requested"] is True
assert obj["manual_toggle_required"] is True
assert obj["activation_state"] == "manual_toggle_required"
assert obj["auto_enable"] is True
assert "manual_toggle_required:wireless_port_inactive" in obj["errors"]
PY
[[ "$(cat "$settings_dir/global_adb_enabled")" == "1" ]]
[[ "$(cat "$settings_dir/global_adb_wifi_enabled")" == "1" ]]
[[ "$(cat "$settings_dir/global_enable_wireless_switch")" == "1" ]]
[[ "$(cat "$settings_dir/manager_allow_bssid")" == "20:3a:0c:78:9a:c8" ]]
[[ -f "$NEBULA_DATA_DIR/state/adb_wifi_auto_enable" ]]
[[ -s "$NEBULA_DATA_DIR/state/adb_wifi.state" ]]

printf 4294967295 > "$settings_dir/adb_wireless_port"
adb_wifi_invalid_port="$(
  NEBULA_SETTINGS_DIR="$settings_dir" \
  sh "$cli" adb-wifi status --json
)"
python3 - "$adb_wifi_invalid_port" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "adb-wifi status"
assert obj["wireless_debugging"] is False
assert obj["wireless_port"] is None
assert obj["settings_requested"] is True
assert obj["manual_toggle_required"] is True
assert obj["activation_state"] == "manual_toggle_required"
assert "unreadable:adb_manager_wireless_port" in obj["errors"]
assert "manual_toggle_required:wireless_port_inactive" in obj["errors"]
PY

printf 33195 > "$settings_dir/adb_wireless_port"
adb_wifi_enable="$(
  NEBULA_SETTINGS_DIR="$settings_dir" \
  sh "$cli" adb-wifi enable --json
)"
python3 - "$adb_wifi_enable" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "adb-wifi enable"
assert obj["ok"] is True
assert obj["applied"] is True
assert obj["requested"] is True
assert obj["manager_request_ok"] is True
assert obj["adb_debugging"] is True
assert obj["wireless_debugging"] is True
assert obj["settings_wireless_debugging"] is True
assert obj["ui_wireless_switch"] is True
assert obj["settings_requested"] is True
assert obj["manual_toggle_required"] is False
assert obj["activation_state"] == "live"
assert obj["wireless_port"] == 33195
assert obj["manager_bssid_available"] is True
assert obj["auto_enable"] is True
assert obj["errors"] == []
PY

adb_wifi_auto_disable="$(
  NEBULA_SETTINGS_DIR="$settings_dir" \
  sh "$cli" adb-wifi auto-disable --json
)"
python3 - "$adb_wifi_auto_disable" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "adb-wifi auto-disable"
assert obj["ok"] is True
assert obj["current_session_changed"] is False
assert obj["adb_debugging"] is True
assert obj["wireless_debugging"] is True
assert obj["settings_wireless_debugging"] is True
assert obj["ui_wireless_switch"] is True
assert obj["manager_bssid_available"] is True
assert obj["settings_requested"] is True
assert obj["manual_toggle_required"] is False
assert obj["activation_state"] == "live"
assert obj["auto_enable"] is False
PY
[[ ! -f "$NEBULA_DATA_DIR/state/adb_wifi_auto_enable" ]]
[[ "$(cat "$settings_dir/global_adb_enabled")" == "1" ]]
[[ "$(cat "$settings_dir/global_adb_wifi_enabled")" == "1" ]]
[[ "$(cat "$settings_dir/global_enable_wireless_switch")" == "1" ]]

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
policy_defaults="$tmp/policy-defaults.json"
write_policy_defaults "$policy_defaults" true

probe="$(
  NEBULA_SYSROOT="$fixture" \
  NEBULA_TEST_PROP_DIR="$props" \
  NEBULA_TEST_KERNEL="host-test" \
  NEBULA_DEFAULTS_JSON="$policy_defaults" \
  sh "$cli" redmagic probe --json
)"
python3 - "$probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
for key in ["protocol_version", "command", "device", "fan", "pump", "performance", "display", "thermal", "cooling_policy", "redmagic_button"]:
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
policy = obj["cooling_policy"]
assert policy["preview_only"] is True
assert policy["configured"] is True
assert policy["state"] == "BALANCED"
assert policy["controlling_sensor"]["temperature_c"] == 41.0
assert policy["fan"]["intent"] == "medium"
assert policy["fan"]["applied"] is False
assert policy["pump"]["intent"] == "low"
assert policy["pump"]["applied"] is False
assert policy["policy"]["threshold_source"] == "defaults.json"
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

mkdir -p "$modules_root/droidspaces" "$modules_root/rm11-droidspace-bridge-fd"
{
  printf 'id=droidspaces\n'
  printf 'name=Droidspaces: Daemon & Init\n'
  printf 'version=v6.3.0\n'
  printf 'versionCode=6300\n'
  printf 'description=Daemon: Running (PID 1559) | Containers: 1 started, 0 failed\n'
} > "$modules_root/droidspaces/module.prop"
{
  printf 'id=rm11-droidspace-bridge-fd\n'
  printf 'name=RM11 Droidspaces Bridge FD Policy\n'
  printf 'version=2026.06.19\n'
  printf 'versionCode=20260619\n'
  printf 'description=Persists bridge fd-use SELinux rule and /dev/shm setup\n'
} > "$modules_root/rm11-droidspace-bridge-fd/module.prop"
legacy_probe="$(
  NEBULA_MODULES_ROOT="$modules_root" \
  sh "$cli" legacy modules --json
)"
python3 - "$legacy_probe" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "legacy modules"
assert obj["migration_enabled"] is False
modules = {item["id"]: item for item in obj["modules"]}
assert modules["droidspaces"]["protected"] is True
assert modules["droidspaces"]["installed"] is True
assert modules["droidspaces"]["version"] == "v6.3.0"
assert modules["rm11-droidspace-bridge-fd"]["protected"] is True
assert modules["rm11-droidspace-bridge-fd"]["installed"] is True
assert modules["rm11-droidspace-bridge-fd"]["nebula_import"] == "staged_audit_only"
assert "do_not_disable_both" in obj["guardrails"]
PY

snapshot_create="$(
  NEBULA_SYSROOT="$fixture" \
  sh "$cli" snapshot cooling create --json
)"
python3 - "$snapshot_create" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "snapshot cooling create"
assert obj["ok"] is True
snap = obj["snapshot"]
assert snap["scope"] == "cooling"
assert snap["fan"]["enabled"] is True
assert snap["fan"]["rpm"] == 4200
assert snap["fan"]["level"] == 4
assert snap["pump"]["enabled"] is True
assert snap["pump"]["speed"] == 80
assert snap["pump"]["freq"] == 4
assert snap["apply_supported"] is False
assert snap["rollback_supported"] is True
PY

snapshot_get="$(sh "$cli" snapshot cooling get --json)"
python3 - "$snapshot_get" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "snapshot cooling get"
assert obj["present"] is True
assert obj["snapshot"]["scope"] == "cooling"
PY

rollback_dry_run="$(
  NEBULA_SYSROOT="$fixture" \
  sh "$cli" snapshot cooling rollback --dry-run --json
)"
python3 - "$rollback_dry_run" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "snapshot cooling rollback"
assert obj["ok"] is True
assert obj["dry_run"] is True
assert obj["applied"] is False
assert obj["writes_enabled"] is False
assert obj["snapshot"]["scope"] == "cooling"
assert obj["current"]["scope"] == "cooling"
PY

cool_fixture="$tmp/policy-cool"
make_policy_fixture "$cool_fixture" 37000 present present
cool_policy="$(policy_json_for "$cool_fixture" "$policy_defaults")"
assert_policy_state "$cool_policy" COOL off off

balanced_fixture="$tmp/policy-balanced"
make_policy_fixture "$balanced_fixture" 41000 present present
balanced_policy="$(policy_json_for "$balanced_fixture" "$policy_defaults")"
assert_policy_state "$balanced_policy" BALANCED medium low

hot_fixture="$tmp/policy-hot"
make_policy_fixture "$hot_fixture" 43000 present present
hot_policy="$(policy_json_for "$hot_fixture" "$policy_defaults")"
assert_policy_state "$hot_policy" HOT high high

critical_fixture="$tmp/policy-critical"
make_policy_fixture "$critical_fixture" 47000 present present
critical_policy="$(policy_json_for "$critical_fixture" "$policy_defaults")"
assert_policy_state "$critical_policy" CRITICAL maximum maximum

boundary_fixture="$tmp/policy-boundary"
make_policy_fixture "$boundary_fixture" 38000 present present
boundary_policy="$(policy_json_for "$boundary_fixture" "$policy_defaults")"
assert_policy_state "$boundary_policy" BALANCED medium low
make_policy_fixture "$boundary_fixture" 42000 present present
boundary_hot_policy="$(policy_json_for "$boundary_fixture" "$policy_defaults")"
assert_policy_state "$boundary_hot_policy" HOT high high
make_policy_fixture "$boundary_fixture" 46000 present present
boundary_critical_policy="$(policy_json_for "$boundary_fixture" "$policy_defaults")"
assert_policy_state "$boundary_critical_policy" CRITICAL maximum maximum

hysteresis_fixture="$tmp/policy-hysteresis"
make_policy_fixture "$hysteresis_fixture" 41000 present present
hysteresis_policy="$(
  NEBULA_SYSROOT="$hysteresis_fixture" \
  NEBULA_DEFAULTS_JSON="$policy_defaults" \
  NEBULA_POLICY_PREVIOUS_STATE=HOT \
  NEBULA_POLICY_PREVIOUS_STATE_AGE_SECONDS=999 \
  sh "$cli" cooling policy --json
)"
assert_policy_state "$hysteresis_policy" HOT high high
python3 - "$hysteresis_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert "hysteresis_hold" in obj["reason"]
PY

dwell_fixture="$tmp/policy-dwell"
make_policy_fixture "$dwell_fixture" 37000 present present
dwell_policy="$(
  NEBULA_SYSROOT="$dwell_fixture" \
  NEBULA_DEFAULTS_JSON="$policy_defaults" \
  NEBULA_POLICY_PREVIOUS_STATE=CRITICAL \
  NEBULA_POLICY_PREVIOUS_STATE_AGE_SECONDS=10 \
  sh "$cli" cooling policy --json
)"
assert_policy_state "$dwell_policy" CRITICAL maximum maximum
python3 - "$dwell_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert "minimum_dwell_active" in obj["reason"]
PY

malformed_temp_fixture="$tmp/policy-malformed"
make_policy_fixture "$malformed_temp_fixture" fast present present
malformed_policy="$(policy_json_for "$malformed_temp_fixture" "$policy_defaults")"
assert_policy_state "$malformed_policy" UNAVAILABLE stock stock
python3 - "$malformed_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["thermal"]["valid_sensor_count"] == 0
assert obj["thermal"]["rejected_sensor_count"] == 1
assert any(item.startswith("rejected_thermal:") for item in obj["reason"])
assert "no_valid_thermal" in obj["reason"]
PY

out_of_range_temp_fixture="$tmp/policy-out-of-range"
make_policy_fixture "$out_of_range_temp_fixture" 250000 present present
out_of_range_policy="$(policy_json_for "$out_of_range_temp_fixture" "$policy_defaults")"
assert_policy_state "$out_of_range_policy" UNAVAILABLE stock stock
python3 - "$out_of_range_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["thermal"]["valid_sensor_count"] == 0
assert obj["thermal"]["rejected_sensor_count"] == 1
PY

no_sensor_fixture="$tmp/policy-no-sensor"
rm -rf "$no_sensor_fixture"
mkdir -p "$no_sensor_fixture/sys/kernel/fan" "$no_sensor_fixture/proc/driver/micropump"
printf 0 > "$no_sensor_fixture/sys/kernel/fan/fan_enable"
printf 0 > "$no_sensor_fixture/sys/kernel/fan/fan_speed_count"
printf 2 > "$no_sensor_fixture/sys/kernel/fan/fan_speed_level"
printf 1 > "$no_sensor_fixture/proc/driver/micropump/enable"
printf 4 > "$no_sensor_fixture/proc/driver/micropump/freq"
printf 80 > "$no_sensor_fixture/proc/driver/micropump/speed"
no_sensor_policy="$(policy_json_for "$no_sensor_fixture" "$policy_defaults")"
assert_policy_state "$no_sensor_policy" UNAVAILABLE stock stock
python3 - "$no_sensor_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert "no_valid_thermal" in obj["reason"]
PY

fan_missing_fixture="$tmp/policy-fan-missing"
make_policy_fixture "$fan_missing_fixture" 41000 missing present
fan_missing_policy="$(policy_json_for "$fan_missing_fixture" "$policy_defaults")"
assert_policy_state "$fan_missing_policy" BALANCED unavailable low

pump_missing_fixture="$tmp/policy-pump-missing"
make_policy_fixture "$pump_missing_fixture" 41000 present missing
pump_missing_policy="$(policy_json_for "$pump_missing_fixture" "$policy_defaults")"
assert_policy_state "$pump_missing_policy" BALANCED medium unavailable

both_missing_fixture="$tmp/policy-both-missing"
make_policy_fixture "$both_missing_fixture" 41000 missing missing
both_missing_policy="$(policy_json_for "$both_missing_fixture" "$policy_defaults")"
assert_policy_state "$both_missing_policy" BALANCED unavailable unavailable

safe_policy_data="$tmp/policy-safe-data"
mkdir -p "$safe_policy_data"
touch "$safe_policy_data/safe_mode"
safe_policy="$(
  NEBULA_SYSROOT="$balanced_fixture" \
  NEBULA_DEFAULTS_JSON="$policy_defaults" \
  NEBULA_DATA_DIR="$safe_policy_data" \
  sh "$cli" cooling policy --json
)"
assert_policy_state "$safe_policy" SAFE_MODE stock stock

unconfigured_defaults="$tmp/policy-unconfigured.json"
write_policy_defaults "$unconfigured_defaults" false
unconfigured_policy="$(policy_json_for "$balanced_fixture" "$unconfigured_defaults")"
assert_policy_state "$unconfigured_policy" UNAVAILABLE stock stock
python3 - "$unconfigured_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["configured"] is False
assert "CALIBRATION_REQUIRED" in obj["errors"]
PY

denied_policy="$(
  NEBULA_SYSROOT="$balanced_fixture" \
  NEBULA_DEFAULTS_JSON="$policy_defaults" \
  NEBULA_TEST_DENY_PATHS="/sys/class/thermal/thermal_zone0/temp" \
  sh "$cli" cooling policy --json
)"
assert_policy_state "$denied_policy" UNAVAILABLE stock stock
python3 - "$denied_policy" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert "permission_denied:/sys/class/thermal/thermal_zone0/temp" in obj["errors"]
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
cooling_extra_arg="$(sh "$cli" cooling policy --json /sys/class/thermal/thermal_zone0/temp 2>/dev/null)"
cooling_extra_code=$?
legacy_extra_arg="$(sh "$cli" legacy modules --json droidspaces 2>/dev/null)"
legacy_extra_code=$?
snapshot_extra_arg="$(sh "$cli" snapshot cooling rollback --dry-run --json apply 2>/dev/null)"
snapshot_extra_code=$?
adb_wifi_extra_arg="$(sh "$cli" adb-wifi enable --json /tmp/path 2>/dev/null)"
adb_wifi_extra_code=$?
nubia_extra_arg="$(sh "$cli" nubia toolkit status --json /tmp/path 2>/dev/null)"
nubia_extra_code=$?
runtime_status_extra_arg="$(sh "$cli" runtime waylandie status --json /tmp/path 2>/dev/null)"
runtime_status_extra_code=$?
runtime_smoke_extra_arg="$(sh "$cli" runtime waylandie proton-smoke --json /tmp/path 2>/dev/null)"
runtime_smoke_extra_code=$?
display_lanes_extra_arg="$(sh "$cli" display lanes --json /tmp/path 2>/dev/null)"
display_lanes_extra_code=$?
display_phone_extra_arg="$(sh "$cli" display lane phone preflight --json /tmp/path 2>/dev/null)"
display_phone_extra_code=$?
display_anland_extra_arg="$(sh "$cli" display lane anland preflight --json /tmp/path 2>/dev/null)"
display_anland_extra_code=$?
display_dock_extra_arg="$(sh "$cli" display lane dock preflight --json /tmp/path 2>/dev/null)"
display_dock_extra_code=$?
set -e
[[ "$extra_code" -ne 0 ]]
[[ "$pump_extra_code" -ne 0 ]]
[[ "$cooling_extra_code" -ne 0 ]]
[[ "$legacy_extra_code" -ne 0 ]]
[[ "$snapshot_extra_code" -ne 0 ]]
[[ "$adb_wifi_extra_code" -ne 0 ]]
[[ "$nubia_extra_code" -ne 0 ]]
[[ "$runtime_status_extra_code" -ne 0 ]]
[[ "$runtime_smoke_extra_code" -ne 0 ]]
[[ "$display_lanes_extra_code" -ne 0 ]]
[[ "$display_phone_extra_code" -ne 0 ]]
[[ "$display_anland_extra_code" -ne 0 ]]
[[ "$display_dock_extra_code" -ne 0 ]]
[[ "$(json_field "$extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$pump_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$cooling_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$legacy_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$snapshot_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$adb_wifi_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$nubia_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$runtime_status_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$runtime_smoke_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_lanes_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_phone_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_anland_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_dock_extra_arg" error)" == "USAGE" ]]

logs="$(sh "$cli" logs tail --lines 10)"
python3 - "$logs" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
if not isinstance(obj.get("lines"), list):
    raise SystemExit("logs.lines is not a list")
PY

if grep -RInE 'WayLandIE|Wayland|Gamescope|Xwayland|DRM|compositor|linux|am start|monkey' "$repo_root/nebula-core-module/service.sh"; then
  echo "service.sh contains forbidden backend launch strings" >&2
  exit 1
fi

if grep -RInE 'setprop|service (start|stop|restart)|am start|cmd activity|input tap' "$repo_root/nebula-core-module/bin/nebula-core"; then
  echo "nebula-core contains forbidden mutation command strings" >&2
  exit 1
fi

if grep -RInE 'settings put' "$repo_root/nebula-core-module/bin/nebula-core" | grep -Ev 'settings put global (adb_enabled|adb_wifi_enabled|enable_wireless_switch) 1'; then
  echo "nebula-core contains forbidden non-ADB settings mutation strings" >&2
  exit 1
fi

if grep -RInE 'service call' "$repo_root/nebula-core-module" | grep -Ev 'service call adb (4|10)'; then
  echo "nebula-core module contains forbidden non-ADB-manager Binder calls" >&2
  exit 1
fi

if grep -RInE 'pump (enable|disable|speed|mode|auto)|fan (enable|level|speed)|cooling (apply|set)|applyPump|enablePump|setPump|applied":true' "$repo_root/nebula-core-module/bin/nebula-core"; then
  echo "nebula-core contains forbidden cooling mutation strings" >&2
  exit 1
fi

if grep -RInE 'cat "?[$][{]?[A-Za-z0-9_]+|/etc/passwd|/proc/kmsg' "$repo_root/nebula-core-module/bin/nebula-core"; then
  echo "nebula-core appears to expose arbitrary path reads" >&2
  exit 1
fi

if grep -RInE 'balanced_c|hot_c|critical_c|temperature_min_c|temperature_max_c|46[.]0|42[.]0|38[.]0' "$repo_root/app/src/main/java"; then
  echo "app contains duplicated cooling threshold source" >&2
  exit 1
fi

grep -RInE 'NEBULA_CORE_PROTOCOL_VERSION = 1|NEBULA_CORE_PROTOCOL_VERSION=1' "$repo_root/app/src/main/java/io/droidspaces/nebula/core/NebulaCoreProtocol.java" >/dev/null
grep -RInE 'protocolMismatch|moduleVersionMismatch|Invalid module JSON|parseRedMagicProbe|redMagicPumpProbe|coolingPolicy' "$repo_root/app/src/main/java/io/droidspaces/nebula/core" >/dev/null

echo "Nebula control plane host tests passed."
