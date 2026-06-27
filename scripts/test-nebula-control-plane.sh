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
assert obj["cooling_policy_state"] == "preview_only"
assert obj["preview_only"] is True
assert obj["applied"] is False
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
python3 - "$status" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
model = obj["status_model"]
assert model["source"] == "evidence_snapshot"
phone = model["phone_app"]
assert phone["real_buffer_pass"] is False
assert phone["hardware_glx_pass"] is False
assert phone["software_glx_reproduced"] is True
assert phone["gl_renderer"] == "llvmpipe"
assert phone["active_blocker"] == "vulkan_export_real_buffer"
assert phone["vk_get_memory_fd_failures"] == 1199
assert phone["real_buffer_commits"] == 0
assert phone["no_buffer_commits"] == 8
assert phone["a1_fasttest_env_status"] == "staged_not_run_adb_offline"
assert model["dock"]["dock_lease_state"] == "paused_crash_gated"
assert model["hook_lane"]["rezygisk_provider_state"] == "documented_not_installed"
assert model["hook_lane"]["hook_ready"] is False
assert model["cooling"]["cooling_policy_state"] == "preview_only"
assert model["cooling"]["applied"] is False
PY

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
    "integrations.baseline",
    "nubia.toolkit.status",
    "runtime.waylandie.status",
    "runtime.waylandie.proton-smoke",
    "display.lanes",
    "display.method-containers",
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
  "$modules_root/zygisk_vector" \
  "$modules_root/rezygisk"
{
  printf 'id=zygisk_vector\n'
  printf 'name=Vector\n'
  printf 'version=v2.0 (3021)\n'
  printf 'versionCode=3021\n'
} > "$modules_root/zygisk_vector/module.prop"
{
  printf 'id=rezygisk\n'
  printf 'name=ReZygisk\n'
  printf 'version=v1.0.0 (513-faccedf-release)\n'
  printf 'versionCode=513\n'
  printf 'author=The PerformanC Organization\n'
  printf 'description=Standalone implementation of Zygisk.\n'
} > "$modules_root/rezygisk/module.prop"
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
provider = obj["zygisk_provider"]
assert provider["id"] == "rezygisk"
assert provider["name"] == "ReZygisk"
assert provider["role"] == "standalone_zygisk_provider"
assert provider["installed"] is True
assert provider["enabled"] is True
assert provider["version"] == "v1.0.0 (513-faccedf-release)"
assert provider["version_code"] == 513
assert provider["artifact_sha256"] == "5da9308aca2f1233e1b74744a86b39ab55749db352a829c7578743df6af16f4f"
assert provider["requires_magisk_builtin_zygisk_disabled"] is True
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
  "$waylandie_data/files/imagefs/usr/local/bin" \
  "$waylandie_data/files/imagefs/usr/local/etc/vulkan/icd.d" \
  "$waylandie_data/files/imagefs/usr/local/lib" \
  "$waylandie_data/files/contents/proton/active/files/lib/wine/aarch64-unix" \
  "$waylandie_data/files/sidecars/xwayland-gamescope-14-exportable-fence-guard-a4-473ba531/usr/local/bin" \
  "$waylandie_data/files/sidecars/xwayland-gamescope-06-xwayland-9f1a3d62/usr/bin" \
  "$waylandie_lib"
: > "$waylandie_lib/libproot.so"
: > "$waylandie_lib/libld_glibc.so"
: > "$waylandie_data/files/imagefs/usr/local/bin/waylandie-wayland-bridge"
: > "$waylandie_data/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json"
: > "$waylandie_data/files/imagefs/usr/local/lib/libvulkan_freedreno.so"
: > "$waylandie_data/files/sidecars/xwayland-gamescope-14-exportable-fence-guard-a4-473ba531/usr/local/bin/gamescope"
: > "$waylandie_data/files/sidecars/xwayland-gamescope-06-xwayland-9f1a3d62/usr/bin/Xwayland"
: > "$waylandie_data/files/contents/proton/active/files/lib/wine/aarch64-unix/wine"
chmod +x "$waylandie_data/files/imagefs/usr/local/bin/waylandie-wayland-bridge" \
  "$waylandie_data/files/sidecars/xwayland-gamescope-14-exportable-fence-guard-a4-473ba531/usr/local/bin/gamescope" \
  "$waylandie_data/files/sidecars/xwayland-gamescope-06-xwayland-9f1a3d62/usr/bin/Xwayland"
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
assert obj["display_ready"] is True
assert obj["bridge_present"] is True
assert obj["local_icd_present"] is True
assert obj["local_vulkan_driver_present"] is True
assert obj["selected_icd"].endswith("/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json")
assert obj["selected_vulkan_driver"].endswith("/files/imagefs/usr/local/lib/libvulkan_freedreno.so")
assert obj["loader_pin"]["VK_ICD_FILENAMES"] == obj["selected_icd"]
assert obj["loader_pin"]["VK_DRIVER_FILES"] == obj["selected_icd"]
assert obj["gamescope_sidecar_present"] is True
assert obj["xwayland_sidecar_present"] is True
assert obj["errors"] == []
assert obj["display_errors"] == []
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
assert obj["display_ready"] is False
assert "missing:imagefs" in obj["errors"]
assert "missing:proton_active" in obj["errors"]
assert "missing:imagefs" in obj["display_errors"]
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
  "$device_root/data/local/Droidspaces/Containers/ubuntu/rootfs" \
  "$device_root/data/local/Droidspaces/Containers/ubuntu/rootfs/usr/local/bin" \
  "$device_root/data/local/tmp" \
  "$device_root/dev/dri"
: > "$device_root/dev/dri/renderD128"
: > "$device_root/data/local/Droidspaces/Containers/ubuntu/rootfs/usr/local/bin/startanland-kde.sh"
chmod 755 "$device_root/data/local/Droidspaces/Containers/ubuntu/rootfs/usr/local/bin/startanland-kde.sh"
cat > "$device_root/data/local/Droidspaces/bin/droidspaces" <<'SH'
#!/bin/sh
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
os.chmod(path, 0o666)
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
assert lanes["phone_app_bridge"]["status"] == "blocked_export"
assert lanes["phone_app_bridge"]["state"] == "blocked_export"
assert lanes["phone_app_bridge"]["method_id"] == "phone_app_bridge"
assert lanes["phone_app_bridge"]["available"] is False
assert lanes["phone_app_bridge"]["container_ref"] == "waylandie_app_imagefs"
assert lanes["phone_app_bridge"]["container_kind"] == "app_proot"
assert lanes["phone_app_bridge"]["container_status"] == "ready"
assert lanes["phone_app_bridge"]["display_status"] == "export_blocked"
assert lanes["phone_app_bridge"]["runtime_status"] == "runtime_export_blocked"
assert lanes["phone_app_bridge"]["requirement_status"] == "blocked_export"
assert "vulkan_export_real_buffer" in lanes["phone_app_bridge"]["missing_requirements"]
assert "a1_fasttest_env_not_run_adb_offline" in lanes["phone_app_bridge"]["missing_requirements"]
assert "game_client_runtime_proof_not_promoted_39bit_va" in lanes["phone_app_bridge"]["missing_requirements"]
assert lanes["phone_app_bridge"]["mutating"] is False
assert lanes["phone_app_bridge"]["launch_command_available"] is False
assert lanes["phone_app_bridge"]["active_blocker"] == "vulkan_export_real_buffer"
assert lanes["phone_app_bridge"]["canonical_blocker"] == "vulkan_export_real_buffer"
assert lanes["phone_app_bridge"]["proof_classification"] == "NEBULA_R6_EXPORT_A1_VULKAN_LOADER_PIN_CONFIRMED"
assert lanes["phone_app_bridge"]["proof_metrics"]["summary_failures"] == 1199
assert lanes["phone_app_bridge"]["proof_metrics"]["vkGetMemoryFdKHR_failures"] == 1199
assert lanes["phone_app_bridge"]["proof_metrics"]["vk_get_memory_fd_failures"] == 1199
assert lanes["phone_app_bridge"]["proof_metrics"]["real_buffer_commits"] == 0
assert lanes["phone_app_bridge"]["proof_metrics"]["no_buffer_commits"] == 8
assert lanes["phone_app_bridge"]["lead_status"] == "blocked_export"
assert lanes["phone_app_bridge"]["next_reversa_action"] == "bounded_a1_export_runtime_after_adb_live"
assert lanes["phone_app_bridge"]["steam_allowed"] is False
assert lanes["phone_app_bridge"]["proton_ready"] is False
assert lanes["phone_app_bridge"]["steam_ready"] is False
assert lanes["phone_app_bridge"]["wine_ready"] is False
assert lanes["phone_app_bridge"]["kernel_va_bits_constraint"] == 39
assert lanes["phone_app_bridge"]["kernel_va_bits_evidence"] == "live_proc_config_gz"
assert lanes["phone_app_bridge"]["runtime_blocker"] == "vulkan_export_real_buffer"
assert lanes["phone_app_bridge"]["real_buffer_pass"] is False
assert lanes["phone_app_bridge"]["hardware_glx_pass"] is False
assert lanes["phone_app_bridge"]["software_glx_reproduced"] is True
assert lanes["phone_app_bridge"]["gl_renderer"] == "llvmpipe"
assert lanes["phone_app_bridge"]["vk_get_memory_fd_failures"] == 1199
assert lanes["phone_app_bridge"]["real_buffer_commits"] == 0
assert lanes["phone_app_bridge"]["no_buffer_commits"] == 8
assert lanes["phone_app_bridge"]["a1_fasttest_env_status"] == "staged_not_run_adb_offline"
assert lanes["phone_app_bridge"]["selected_icd"].endswith("/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json")
assert lanes["phone_app_bridge"]["selected_vulkan_driver"].endswith("/files/imagefs/usr/local/lib/libvulkan_freedreno.so")
assert lanes["phone_app_bridge"]["loader_pin"]["VK_ICD_FILENAMES"] == lanes["phone_app_bridge"]["selected_icd"]
assert lanes["phone_app_bridge"]["loader_pin"]["VK_DRIVER_FILES"] == lanes["phone_app_bridge"]["selected_icd"]
assert lanes["phone_app_bridge"]["checks"]["display_ready"] is True
assert lanes["phone_app_bridge"]["checks"]["runtime_ready"] is True
assert lanes["phone_app_bridge"]["checks"]["local_icd_present"] is True
assert lanes["phone_app_bridge"]["checks"]["local_vulkan_driver_present"] is True
assert lanes["phone_app_bridge"]["checks"]["gamescope_sidecar_present"] is True
assert lanes["phone_app_bridge"]["checks"]["xwayland_sidecar_present"] is True
assert lanes["anland_surface"]["status"] == "preflight_ready"
assert lanes["anland_surface"]["state"] == "preflight_only"
assert lanes["anland_surface"]["method_id"] == "anland_surface"
assert lanes["anland_surface"]["container_ref"] == "ubuntu"
assert lanes["anland_surface"]["container_kind"] == "droidspaces"
assert lanes["anland_surface"]["container_status"] == "ready"
assert lanes["anland_surface"]["display_status"] == "display_ready"
assert lanes["anland_surface"]["runtime_status"] == "runtime_ready"
assert lanes["anland_surface"]["requirement_status"] == "complete"
assert lanes["anland_surface"]["missing_requirements"] == []
assert lanes["anland_surface"]["selected_container"] == "ubuntu"
assert lanes["anland_surface"]["container_selection_source"] == "default_fallback"
assert lanes["anland_surface"]["container_active"] is False
assert lanes["anland_surface"]["container_pid"] is None
assert lanes["anland_surface"]["repair_command_available"] is False
assert lanes["anland_surface"]["checks"]["active_container_pidfile"] is False
assert lanes["anland_surface"]["checks"]["display_daemon_socket"] is True
assert lanes["anland_surface"]["checks"]["display_daemon_socket_writable"] is True
assert lanes["anland_surface"]["checks"]["anland_producer"] is True
assert lanes["anland_surface"]["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
assert lanes["dock_drm_lease_external"]["status"] == "paused_crash_gated"
assert lanes["dock_drm_lease_external"]["state"] == "paused_crash_gated"
assert lanes["dock_drm_lease_external"]["dock_lease_state"] == "paused_crash_gated"
assert lanes["dock_drm_lease_external"]["method_id"] == "dock_drm_lease_external"
assert lanes["dock_drm_lease_external"]["container_ref"] == "none"
assert lanes["dock_drm_lease_external"]["container_kind"] == "none"
assert lanes["dock_drm_lease_external"]["display_status"] == "paused_crash_gated"
assert lanes["dock_drm_lease_external"]["runtime_status"] == "not_required"
assert lanes["dock_drm_lease_external"]["requirement_status"] == "crashdump_gated_resume_required"
assert "crashdump_gated_resume_required" in lanes["dock_drm_lease_external"]["missing_requirements"]
assert "external_display_discovery_required" in lanes["dock_drm_lease_external"]["missing_requirements"]
assert lanes["dock_drm_lease_external"]["evidence_captured"] is True
assert lanes["dock_drm_lease_external"]["operator_required"] is True
assert lanes["dock_drm_lease_external"]["external_display_only"] is True
assert lanes["dock_drm_lease_external"]["start_command_available"] is False
assert lanes["dock_drm_lease_external"]["reported_objects"]["hardcoded_forbidden"] is True
assert lanes["compatibility"]["method_id"] == "compatibility_software"
assert lanes["compatibility"]["status"] == "blocked_real_buffer"
assert lanes["compatibility"]["state"] == "blocked_real_buffer"
assert lanes["compatibility"]["requirement_status"] == "blocked_real_buffer"
assert "real_buffer_commits_missing" in lanes["compatibility"]["missing_requirements"]
assert lanes["compatibility"]["real_buffer_pass"] is False
assert lanes["compatibility"]["hardware_glx_pass"] is False
assert lanes["compatibility"]["software_glx_reproduced"] is True
assert lanes["compatibility"]["gl_renderer"] == "llvmpipe"
assert lanes["recovery_safe"]["method_id"] == "recovery_safe"
assert lanes["recovery_safe"]["requirement_status"] == "complete"
assert "no_lane_silently_replaces_another" in obj["selection_rules"]
PY

method_containers="$(
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  sh "$cli" display method-containers --json
)"
python3 - "$method_containers" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display method-containers"
containers = {item["method_id"]: item for item in obj["containers"]}
assert containers["phone_app_bridge"]["container_ref"] == "waylandie_app_imagefs"
assert containers["phone_app_bridge"]["container_kind"] == "app_proot"
assert containers["phone_app_bridge"]["status"] == "blocked_export"
assert containers["phone_app_bridge"]["state"] == "blocked_export"
assert containers["phone_app_bridge"]["current_limit"] == "vulkan_export_real_buffer"
assert containers["phone_app_bridge"]["real_buffer_pass"] is False
assert containers["phone_app_bridge"]["hardware_glx_pass"] is False
assert containers["phone_app_bridge"]["software_glx_reproduced"] is True
assert containers["phone_app_bridge"]["gl_renderer"] == "llvmpipe"
assert containers["phone_app_bridge"]["vk_get_memory_fd_failures"] == 1199
assert containers["phone_app_bridge"]["real_buffer_commits"] == 0
assert containers["phone_app_bridge"]["no_buffer_commits"] == 8
anland = containers["anland_surface"]
assert anland["container_kind"] == "droidspaces"
assert anland["container_ref"] == "ubuntu"
assert anland["recommended_container"] == "anland-ubuntu26-kde"
assert anland["selected_is_recommended"] is False
assert "bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock" in anland["required_config"]
assert "ANLAND_SOCKET=/run/display.sock" in anland["required_env"]
assert "MESA_LOADER_DRIVER_OVERRIDE=kgsl" in anland["required_env"]
assert anland["setup_commands"]["consumer_apk_package"] == "com.anland.consumer"
assert "ksud module install" in anland["setup_commands"]["daemon_module_install"]
assert anland["setup_commands"]["recommended_rootfs_archive"] == "/sdcard/Download/anland-ubuntu26-kde.tar.xz"
assert anland["setup_commands"]["recommended_rootfs_img"] == "/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img"
assert anland["setup_commands"]["recommended_rootfs_size"] == "32G"
assert "--rootfs-arc=/sdcard/Download/anland-ubuntu26-kde.tar.xz" in anland["setup_commands"]["droidspaces_create_rootfs_img"]
assert "--rootfs-img=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img" in anland["setup_commands"]["droidspaces_create_rootfs_img"]
assert "--name=anland-ubuntu26-kde" in anland["setup_commands"]["droidspaces_start_recommended"]
assert "--bind=/data/local/tmp/display_daemon.sock:/run/display.sock" in anland["setup_commands"]["droidspaces_start_recommended"]
assert anland["setup_commands"]["producer_start_command"] == "startanland-kde.sh"
assert "test -x /usr/local/bin/startanland-kde.sh" in anland["setup_commands"]["producer_verify_command"]
assert "nohup /usr/local/bin/startanland-kde.sh" in anland["setup_commands"]["producer_run_command"]
assert anland["checks"]["anland_producer"] is True
assert anland["checks"]["rootfs_image"] is False
assert anland["selected_paths"]["rootfs_mode"] == "directory"
assert containers["droidspaces_rootfs_image"]["container_kind"] == "droidspaces_rootfs_image"
assert "--rootfs-img=<path>" in containers["droidspaces_rootfs_image"]["requirements"]
assert "create_from_archive" in containers["droidspaces_rootfs_image"]["setup_commands"]
assert containers["droidspaces_rootfs_directory"]["container_kind"] == "droidspaces_rootfs_directory"
assert "--rootfs=<path>" in containers["droidspaces_rootfs_directory"]["requirements"]
assert containers["droidspaces_termux_x11"]["container_kind"] == "droidspaces_native_x11"
assert "enable_termux_x11=1" in containers["droidspaces_termux_x11"]["required_config"]
assert "DISPLAY=:0" in containers["droidspaces_termux_x11"]["required_env"]
assert containers["droidspaces_virgl"]["container_kind"] == "droidspaces_native_gpu"
assert "enable_virgl=1" in containers["droidspaces_virgl"]["required_config"]
assert "GALLIUM_DRIVER=virpipe" in containers["droidspaces_virgl"]["required_env"]
assert containers["droidspaces_turnip_kgsl"]["container_kind"] == "droidspaces_native_gpu"
assert "enable_gpu_mode=1" in containers["droidspaces_turnip_kgsl"]["required_config"]
assert "enable_hw_access=1" in containers["droidspaces_turnip_kgsl"]["required_config"]
assert containers["droidspaces_llvmpipe"]["container_kind"] == "droidspaces_native_software"
assert "enable_gpu_mode=0" in containers["droidspaces_llvmpipe"]["required_config"]
assert containers["droidspaces_pulseaudio"]["container_kind"] == "droidspaces_native_audio"
assert "PULSE_SERVER=unix:/tmp/.pulse-socket" in containers["droidspaces_pulseaudio"]["required_env"]
assert containers["dock_drm_lease_external"]["container_ref"] == "none"
assert containers["compatibility_software"]["container_ref"] == "compatibility-software"
assert containers["recovery_safe"]["status"] == "always_available"
assert "DroidSpaces native X11, VirGL, Turnip/KGSL" in obj["rule"]
assert "dedicated Ubuntu26/KDE/anland_kde producer rootfs" in obj["rule"]
PY

method_profiles="$(
  sh "$cli" display method-profiles --json
)"
python3 - "$method_profiles" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display method-profiles"
assert obj["mutating"] is False
assert "do not start multiple active writable profiles against the same rootfs.img" in obj["rootfs_policy"]
assert "write /data/local/Droidspaces/Containers/<name>/container.config atomically" in obj["config_materialization"]
profiles = {item["profile_id"]: item for item in obj["profiles"]}
assert profiles["anland_wayland_kde"]["method_id"] == "anland_surface"
assert profiles["anland_wayland_kde"]["container_name"] == "anland-ubuntu26-kde"
assert profiles["anland_wayland_kde"]["config_path"] == "/data/local/Droidspaces/Containers/anland-ubuntu26-kde/container.config"
assert "hostname=anland-ubuntu26-kde" in profiles["anland_wayland_kde"]["config_lines"]
assert "bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock" in profiles["anland_wayland_kde"]["config_lines"]
assert "ANLAND_SOCKET=/run/display.sock" in profiles["anland_wayland_kde"]["env_lines"]
assert "startanland-kde.sh" in profiles["anland_wayland_kde"]["commands"]["producer_start"]
assert profiles["termux_x11_desktop"]["method_id"] == "droidspaces_termux_x11"
assert profiles["termux_x11_desktop"]["config_path"] == "/data/local/Droidspaces/Containers/rm11-termux-x11/container.config"
assert "enable_termux_x11=1" in profiles["termux_x11_desktop"]["config_lines"]
assert "run_at_boot=0" in profiles["termux_x11_desktop"]["config_lines"]
assert "use_sparse_image=1" in profiles["termux_x11_desktop"]["config_lines"]
assert "DISPLAY=:0" in profiles["termux_x11_desktop"]["expected_env"]
assert profiles["virgl_desktop"]["method_id"] == "droidspaces_virgl"
assert "enable_virgl=1" in profiles["virgl_desktop"]["config_lines"]
assert "GALLIUM_DRIVER=virpipe" in profiles["virgl_desktop"]["expected_env"]
assert profiles["turnip_kgsl_desktop"]["method_id"] == "droidspaces_turnip_kgsl"
assert "enable_gpu_mode=1" in profiles["turnip_kgsl_desktop"]["config_lines"]
assert "MESA_LOADER_DRIVER_OVERRIDE=kgsl" in profiles["turnip_kgsl_desktop"]["env_lines"]
assert profiles["llvmpipe_software"]["method_id"] == "droidspaces_llvmpipe"
assert "enable_gpu_mode=0" in profiles["llvmpipe_software"]["config_lines"]
assert "LIBGL_ALWAYS_SOFTWARE=1" in profiles["llvmpipe_software"]["env_lines"]
assert profiles["pulse_audio"]["method_id"] == "droidspaces_pulseaudio"
assert "enable_pulseaudio=1" in profiles["pulse_audio"]["config_lines"]
rules = " ".join(obj["materialization_rules"])
assert "direct atomic file creation" in rules
assert "chmod 0644" in rules
assert "droidspaces --config=<container.config> start" in rules
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
assert obj["status"] == "blocked_export"
assert obj["state"] == "blocked_export"
assert obj["available"] is False
assert obj["mutating"] is False
assert obj["launch_command_available"] is False
assert obj["active_blocker"] == "vulkan_export_real_buffer"
assert obj["proof_classification"] == "NEBULA_R6_EXPORT_A1_VULKAN_LOADER_PIN_CONFIRMED"
assert obj["lead_status"] == "blocked_export"
assert obj["next_reversa_action"] == "bounded_a1_export_runtime_after_adb_live"
assert obj["steam_allowed"] is False
assert obj["proton_ready"] is False
assert obj["steam_ready"] is False
assert obj["wine_ready"] is False
assert obj["kernel_va_bits_constraint"] == 39
assert obj["kernel_va_bits_evidence"] == "live_proc_config_gz"
assert obj["runtime_blocker"] == "vulkan_export_real_buffer"
assert obj["real_buffer_pass"] is False
assert obj["hardware_glx_pass"] is False
assert obj["software_glx_reproduced"] is True
assert obj["gl_renderer"] == "llvmpipe"
assert obj["vk_get_memory_fd_failures"] == 1199
assert obj["real_buffer_commits"] == 0
assert obj["no_buffer_commits"] == 8
assert obj["a1_fasttest_env_status"] == "staged_not_run_adb_offline"
assert obj["checks"]["display_ready"] is True
assert obj["checks"]["runtime_ready"] is True
assert obj["checks"]["gamescope_sidecar_present"] is True
assert obj["checks"]["xwayland_sidecar_present"] is True
PY

waylandie_no_sidecar="$tmp/waylandie-no-sidecar"
mkdir -p "$waylandie_no_sidecar/files/imagefs/usr/local/bin" \
  "$waylandie_no_sidecar/files/imagefs/usr/local/etc/vulkan/icd.d" \
  "$waylandie_no_sidecar/files/imagefs/usr/local/lib" \
  "$waylandie_no_sidecar/files/contents/proton/active/files/lib/wine/aarch64-unix"
: > "$waylandie_no_sidecar/files/imagefs/usr/local/bin/waylandie-wayland-bridge"
: > "$waylandie_no_sidecar/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json"
: > "$waylandie_no_sidecar/files/imagefs/usr/local/lib/libvulkan_freedreno.so"
: > "$waylandie_no_sidecar/files/contents/proton/active/files/lib/wine/aarch64-unix/wine"
chmod +x "$waylandie_no_sidecar/files/imagefs/usr/local/bin/waylandie-wayland-bridge"
phone_preflight_no_sidecar="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_no_sidecar" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  sh "$cli" display lane phone preflight --json
)"
python3 - "$phone_preflight_no_sidecar" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "partial"
assert obj["available"] is False
assert obj["active_blocker"] == "WAYLAND_DISPLAY_PREFLIGHT_INCOMPLETE"
assert obj["checks"]["runtime_ready"] is True
assert obj["checks"]["display_ready"] is False
assert obj["checks"]["local_icd_present"] is True
assert obj["checks"]["local_vulkan_driver_present"] is True
assert obj["checks"]["gamescope_sidecar_present"] is False
assert obj["checks"]["xwayland_sidecar_present"] is False
assert "missing:gamescope_sidecar" in obj["errors"]
assert "missing:xwayland_sidecar" in obj["errors"]
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
assert obj["selected_container"] == "ubuntu"
assert obj["container_selection_source"] == "default_fallback"
assert obj["container_active"] is False
assert obj["container_pid"] is None
assert obj["mutating"] is False
assert obj["repair_command_available"] is False
assert obj["checks"]["droidspaces_binary"] is True
assert obj["checks"]["container_selected"] is True
assert obj["checks"]["active_container_pidfile"] is False
assert obj["checks"]["rootfs_path"] is True
assert obj["checks"]["rootfs_image"] is False
assert obj["checks"]["display_daemon_socket"] is True
assert obj["checks"]["display_daemon_socket_writable"] is True
assert obj["checks"]["env_kgsl"] is True
assert "ANLAND_SOCKET=/run/display.sock" in obj["required_env"]
assert obj["setup_commands"]["recommended_container"] == "anland-ubuntu26-kde"
assert "--rootfs-arc=/sdcard/Download/anland-ubuntu26-kde.tar.xz" in obj["setup_commands"]["droidspaces_create_rootfs_img"]
assert "--bind=/data/local/tmp/display_daemon.sock:/run/display.sock" in obj["setup_commands"]["droidspaces_start_recommended"]
assert obj["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
assert obj["selected_paths"]["rootfs_mode"] == "directory"
PY

chmod 755 "$device_root/data/local/tmp/display_daemon.sock"
locked_socket_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$locked_socket_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "container_runtime_ready", obj
assert obj["available"] is False
assert obj["runtime_ready"] is True
assert obj["checks"]["display_daemon_socket"] is True
assert obj["checks"]["display_daemon_socket_writable"] is False
assert "blocked:display_daemon_socket_not_app_writable" in obj["errors"]
PY
chmod 666 "$device_root/data/local/tmp/display_daemon.sock"

invalid_override_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  NEBULA_ANLAND_CONTAINER="../bad" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$invalid_override_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "partial", obj
assert obj["available"] is False
assert obj["runtime_ready"] is False
assert obj["selected_container"] == ""
assert obj["container_selection_source"] == "invalid_env_override"
assert obj["requirement_status"] == "invalid_selection"
assert obj["checks"]["container_selected"] is False
assert "invalid:env_override_container" in obj["errors"]
PY

unsafe_root="$tmp/device-root-unsafe-root"
mkdir -p "$unsafe_root/data/local/Droidspaces/bin" \
  "$unsafe_root/data/local/Droidspaces/Containers/unsafe" \
  "$unsafe_root/data/local/tmp" \
  "$unsafe_root/dev/dri"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$unsafe_root/data/local/Droidspaces/bin/droidspaces"
: > "$unsafe_root/dev/dri/renderD128"
cat > "$unsafe_root/data/local/Droidspaces/Containers/unsafe/container.config" <<'EOF'
name=unsafe
rootfs_path=/data/local/tmp
enable_hw_access=1
enable_gpu_mode=1
EOF
unsafe_root_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$unsafe_root" \
  NEBULA_ANLAND_CONTAINER=unsafe \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$unsafe_root_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "partial", obj
assert obj["available"] is False
assert obj["runtime_ready"] is False
assert obj["selected_container"] == "unsafe"
assert obj["container_selection_source"] == "env_override"
assert obj["checks"]["rootfs_path"] is False
assert obj["requirement_status"] == "invalid_rootfs_path"
assert "invalid:rootfs_path_outside_container" in obj["errors"]
PY

image_root="$tmp/device-root-image"
mkdir -p "$image_root/data/local/Droidspaces/bin" \
  "$image_root/data/local/Droidspaces/Containers/anland-ubuntu26-kde" \
  "$image_root/data/local/tmp" \
  "$image_root/dev/dri"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$image_root/data/local/Droidspaces/bin/droidspaces"
: > "$image_root/dev/dri/renderD128"
: > "$image_root/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img"
cat > "$image_root/data/local/Droidspaces/Containers/anland-ubuntu26-kde/container.config" <<'EOF'
name=anland-ubuntu26-kde
rootfs_path=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img
enable_termux_x11=0
enable_hw_access=1
enable_gpu_mode=1
selinux_permissive=1
privileged=nocaps,noseccomp
env_file=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/anland.env
bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock
EOF
cat > "$image_root/data/local/Droidspaces/Containers/anland-ubuntu26-kde/anland.env" <<'EOF'
ANLAND=1
ANLAND_SOCKET=/run/display.sock
ANLAND_DRM_DEVICE=/dev/dri/renderD128
WAYLAND_DISPLAY=wayland-0
MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1
EOF
python3 - "$image_root/data/local/tmp/display_daemon.sock" <<'PY' &
import os, socket, sys, time
path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
os.chmod(path, 0o666)
s.listen(1)
time.sleep(30)
PY
socket_pids+=("$!")
sleep 0.2
image_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$image_root" \
  NEBULA_ANLAND_CONTAINER=anland-ubuntu26-kde \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$image_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "container_runtime_ready", obj
assert obj["available"] is False
assert obj["runtime_ready"] is True
assert obj["selected_container"] == "anland-ubuntu26-kde"
assert obj["container_selection_source"] == "env_override"
assert obj["checks"]["rootfs_path"] is True
assert obj["checks"]["rootfs_image"] is True
assert obj["checks"]["anland_env"] is True
assert obj["checks"]["display_daemon_socket"] is True
assert obj["checks"]["display_daemon_socket_writable"] is True
assert obj["checks"]["anland_producer"] is False
assert obj["selected_paths"]["rootfs_path"] == "/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img"
assert obj["selected_paths"]["rootfs_mode"] == "image"
assert "unknown:anland_producer_inside_rootfs_image_run_verify_required" in obj["errors"]
assert "test -x /usr/local/bin/startanland-kde.sh" in obj["setup_commands"]["producer_verify_command"]
PY

mkdir -p "$image_root/data/local/Droidspaces/Pids" "$image_root/proc/4343"
printf 4343 > "$image_root/data/local/Droidspaces/Pids/anland-ubuntu26-kde.pid"
active_image_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$image_root" \
  NEBULA_ANLAND_CONTAINER=anland-ubuntu26-kde \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$active_image_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "preflight_ready", obj
assert obj["available"] is True
assert obj["runtime_ready"] is True
assert obj["container_active"] is True
assert obj["container_pid"] == 4343
assert obj["checks"]["rootfs_image"] is True
assert obj["checks"]["display_daemon_socket_writable"] is True
assert obj["checks"]["anland_producer"] is True
assert obj["errors"] == []
PY
rm -f "$image_root/data/local/Droidspaces/Pids/anland-ubuntu26-kde.pid"

active_root="$tmp/device-root-active"
mkdir -p "$active_root/data/local/Droidspaces/bin" \
  "$active_root/data/local/Droidspaces/Pids" \
  "$active_root/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/rootfs" \
  "$active_root/data/local/tmp" \
  "$active_root/dev/dri" \
  "$active_root/proc/4242"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$active_root/data/local/Droidspaces/bin/droidspaces"
: > "$active_root/dev/dri/renderD128"
cat > "$active_root/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/container.config" <<'EOF'
name=rm11-alpine-324-turnip
rootfs_path=/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/rootfs
enable_hw_access=1
enable_gpu_mode=1
run_at_boot=1
EOF
printf 4242 > "$active_root/data/local/Droidspaces/Pids/rm11-alpine-324-turnip.pid"
active_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$active_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$active_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "container_runtime_ready"
assert obj["available"] is False
assert obj["runtime_ready"] is True
assert obj["selected_container"] == "rm11-alpine-324-turnip"
assert obj["container_selection_source"] == "active_pidfile"
assert obj["container_ref"] == "rm11-alpine-324-turnip"
assert obj["container_status"] == "active"
assert obj["display_status"] == "display_missing"
assert obj["runtime_status"] == "runtime_ready"
assert obj["requirement_status"] == "missing_requirements"
assert "missing:anland_env" in obj["missing_requirements"]
assert "missing:display_daemon_socket" in obj["missing_requirements"]
assert "missing:anland_producer" in obj["missing_requirements"]
assert obj["container_active"] is True
assert obj["container_pid"] == 4242
assert obj["checks"]["active_container_pidfile"] is True
assert obj["checks"]["container_config"] is True
assert obj["checks"]["rootfs_path"] is True
assert obj["checks"]["anland_env"] is False
assert obj["checks"]["display_daemon_socket"] is False
assert obj["checks"]["anland_producer"] is False
assert obj["selected_paths"]["pidfile"] == "/data/local/Droidspaces/Pids/rm11-alpine-324-turnip.pid"
assert obj["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/container.config"
assert "missing:anland_env" in obj["errors"]
assert "missing:display_daemon_socket" in obj["errors"]
assert "missing:anland_producer" in obj["errors"]
PY

stale_root="$tmp/device-root-stale"
mkdir -p "$stale_root/data/local/Droidspaces/bin" \
  "$stale_root/data/local/Droidspaces/Pids" \
  "$stale_root/data/local/Droidspaces/Containers/ubuntu/rootfs" \
  "$stale_root/data/local/Droidspaces/Containers/rm11-stale/rootfs" \
  "$stale_root/data/local/tmp" \
  "$stale_root/dev/dri"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$stale_root/data/local/Droidspaces/bin/droidspaces"
: > "$stale_root/dev/dri/renderD128"
cat > "$stale_root/data/local/Droidspaces/Containers/ubuntu/container.config" <<'EOF'
name=ubuntu
rootfs_path=/data/local/Droidspaces/Containers/ubuntu/rootfs
enable_hw_access=1
enable_gpu_mode=1
EOF
cat > "$stale_root/data/local/Droidspaces/Containers/rm11-stale/container.config" <<'EOF'
name=rm11-stale
rootfs_path=/data/local/Droidspaces/Containers/rm11-stale/rootfs
enable_hw_access=1
enable_gpu_mode=1
EOF
printf 99999 > "$stale_root/data/local/Droidspaces/Pids/rm11-stale.pid"
stale_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$stale_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$stale_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["selected_container"] == "ubuntu", obj
assert obj["container_selection_source"] == "default_fallback"
assert obj["container_active"] is False
assert obj["container_pid"] is None
assert obj["checks"]["active_container_pidfile"] is False
PY

mkdir -p "$active_root/data/local/Droidspaces/Containers/rm11-second/rootfs"
cat > "$active_root/data/local/Droidspaces/Containers/rm11-second/container.config" <<'EOF'
name=rm11-second
rootfs_path=/data/local/Droidspaces/Containers/rm11-second/rootfs
enable_hw_access=1
enable_gpu_mode=1
run_at_boot=1
EOF
mkdir -p "$active_root/proc/4243"
printf 4243 > "$active_root/data/local/Droidspaces/Pids/rm11-second.pid"
ambiguous_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$active_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$ambiguous_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "partial"
assert obj["available"] is False
assert obj["runtime_ready"] is False
assert obj["container_selection_source"] == "ambiguous_active_pidfiles"
assert obj["container_status"] == "ambiguous"
assert obj["requirement_status"] == "ambiguous_selection"
assert "ambiguous:active_containers" in obj["errors"]
PY

dock_preflight="$(sh "$cli" display lane dock preflight --json)"
python3 - "$dock_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display lane dock preflight"
assert obj["id"] == "dock_drm_lease_external"
assert obj["status"] == "paused_crash_gated"
assert obj["state"] == "paused_crash_gated"
assert obj["dock_lease_state"] == "paused_crash_gated"
assert obj["available"] is False
assert obj["mutating"] is False
assert obj["start_command_available"] is False
assert obj["evidence_captured"] is True
assert obj["operator_required"] is True
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
printf nx809j-test > "$props/ro.board.platform"
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

mkdir -p "$package_dir/com.droidspaces.app" \
  "$package_dir/com.elitedarkkaiser.redmagic" \
  "$modules_root/redmagic_powerdeck" \
  "$device_root/data/local/tmp/redmagic_powerdeck"
{
  printf 'id=redmagic_powerdeck\n'
  printf 'name=RedMagic PowerDeck\n'
  printf 'version=0.1.0\n'
  printf 'versionCode=1\n'
} > "$modules_root/redmagic_powerdeck/module.prop"
cat > "$device_root/data/local/tmp/redmagic_powerdeck/rm-powerdeck-apply.sh" <<'SH'
#!/system/bin/sh
exit 0
SH
chmod 755 "$device_root/data/local/tmp/redmagic_powerdeck/rm-powerdeck-apply.sh"
baseline="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_MODULES_ROOT="$modules_root" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_data" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  NEBULA_SYSROOT="$fixture" \
  sh "$cli" integrations baseline --json
)"
python3 - "$baseline" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "integrations baseline"
assert obj["baseline_id"] == "nebula_rm11pro_baseline"
assert obj["overall_status"] == "baseline_export_blocked_read_only"
assert obj["safe_default"] is True
assert obj["mutating_controls_enabled"] is False
items = {item["id"]: item for item in obj["integrations"]}
assert items["nebula_core"]["ready"] is True
assert items["waylandie"]["status"] == "blocked_export"
assert items["waylandie"]["state"] == "blocked_export"
assert items["waylandie"]["method_id"] == "phone_app_bridge"
assert items["waylandie"]["container_ref"] == "waylandie_app_imagefs"
assert items["waylandie"]["container_kind"] == "app_proot"
assert items["waylandie"]["container_status"] == "ready"
assert items["waylandie"]["display_status"] == "export_blocked"
assert items["waylandie"]["runtime_status"] == "runtime_export_blocked"
assert items["waylandie"]["requirement_status"] == "blocked_export"
assert "vulkan_export_real_buffer" in items["waylandie"]["missing_requirements"]
assert "a1_fasttest_env_not_run_adb_offline" in items["waylandie"]["missing_requirements"]
assert "game_client_runtime_proof_not_promoted_39bit_va" in items["waylandie"]["missing_requirements"]
assert items["waylandie"]["ready"] is False
assert items["waylandie"]["display_ready"] is False
assert items["waylandie"]["runtime_ready"] is False
assert items["waylandie"]["active_blocker"] == "vulkan_export_real_buffer"
assert items["waylandie"]["real_buffer_pass"] is False
assert items["waylandie"]["hardware_glx_pass"] is False
assert items["waylandie"]["software_glx_reproduced"] is True
assert items["waylandie"]["gl_renderer"] == "llvmpipe"
assert items["waylandie"]["vk_get_memory_fd_failures"] == 1199
assert items["waylandie"]["real_buffer_commits"] == 0
assert items["waylandie"]["no_buffer_commits"] == 8
assert items["waylandie"]["a1_fasttest_env_status"] == "staged_not_run_adb_offline"
assert items["waylandie"]["mutating"] is False
assert items["droidspaces"]["status"] == "preflight_ready"
assert items["droidspaces"]["method_id"] == "anland_surface"
assert items["droidspaces"]["installed"] is True
assert items["droidspaces"]["ready"] is True
assert items["droidspaces"]["runtime_ready"] is True
assert items["droidspaces"]["display_socket_ready"] is True
assert items["droidspaces"]["container_ref"] == "ubuntu"
assert items["droidspaces"]["container_kind"] == "droidspaces"
assert items["droidspaces"]["container_status"] == "ready"
assert items["droidspaces"]["display_status"] == "display_ready"
assert items["droidspaces"]["runtime_status"] == "runtime_ready"
assert items["droidspaces"]["requirement_status"] == "complete"
assert items["droidspaces"]["missing_requirements"] == []
assert items["droidspaces"]["bridge_module_installed"] is True
assert items["droidspaces"]["selected_container"] == "ubuntu"
assert items["droidspaces"]["container_selection_source"] == "default_fallback"
assert items["droidspaces"]["container_active"] is False
assert items["droidspaces"]["container_pid"] is None
assert items["droidspaces"]["checks"]["container_config"] is True
assert items["droidspaces"]["checks"]["active_container_pidfile"] is False
assert items["droidspaces"]["checks"]["rootfs_path"] is True
assert items["droidspaces"]["checks"]["display_daemon_socket_writable"] is True
assert items["droidspaces"]["checks"]["anland_producer"] is True
assert items["droidspaces"]["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
assert items["nubia_toolkit"]["status"] == "hook_framework_ready_scope_deferred"
assert items["nubia_toolkit"]["ready"] is False
assert items["nubia_toolkit"]["hook_ready"] is False
assert items["nubia_toolkit"]["hooks_active"] is False
assert items["nubia_toolkit"]["rezygisk_provider_state"] == "documented_not_installed"
assert items["nubia_toolkit"]["zygisk_provider"]["id"] == "rezygisk"
assert items["nubia_toolkit"]["zygisk_provider"]["provider_state"] == "documented_not_installed"
assert items["nubia_toolkit"]["zygisk_provider"]["installed"] is True
assert items["nubia_toolkit"]["zygisk_provider"]["enabled"] is True
assert items["nubia_toolkit"]["zygisk_provider"]["requires_magisk_builtin_zygisk_disabled"] is True
assert items["redmagic_control_center"]["status"] == "read_only_nodes_visible"
assert items["redmagic_control_center"]["ready"] is True
assert items["redmagic_control_center"]["writes_enabled"] is False
assert items["powerdeck"]["status"] == "external_module_detected_dry_run_required"
assert items["powerdeck"]["ready"] is True
assert items["powerdeck"]["dry_run_required"] is True
assert "status_before_mutation" in obj["guardrails"]
assert "wayland_export_blocker_not_glx_visuals" in obj["guardrails"]
assert obj["next_step"] == "bounded_a1_export_runtime_after_adb_live"
PY

rm -f "$active_root/data/local/Droidspaces/Pids/rm11-second.pid"
active_baseline="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_MODULES_ROOT="$modules_root" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_data" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  NEBULA_TEST_DEVICE_ROOT="$active_root" \
  NEBULA_SYSROOT="$fixture" \
  sh "$cli" integrations baseline --json
)"
python3 - "$active_baseline" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["overall_status"] == "baseline_export_blocked_read_only"
items = {item["id"]: item for item in obj["integrations"]}
ds = items["droidspaces"]
assert ds["status"] == "container_runtime_ready"
assert ds["ready"] is True
assert ds["runtime_ready"] is True
assert ds["display_socket_ready"] is False
assert ds["method_id"] == "anland_surface"
assert ds["container_ref"] == "rm11-alpine-324-turnip"
assert ds["container_kind"] == "droidspaces"
assert ds["container_status"] == "active"
assert ds["display_status"] == "display_missing"
assert ds["runtime_status"] == "runtime_ready"
assert ds["requirement_status"] == "missing_requirements"
assert "missing:anland_env" in ds["missing_requirements"]
assert "missing:display_daemon_socket" in ds["missing_requirements"]
assert "missing:anland_producer" in ds["missing_requirements"]
assert ds["selected_container"] == "rm11-alpine-324-turnip"
assert ds["container_selection_source"] == "active_pidfile"
assert ds["container_active"] is True
assert ds["container_pid"] == 4242
assert ds["checks"]["active_container_pidfile"] is True
assert ds["checks"]["container_config"] is True
assert ds["checks"]["anland_producer"] is False
assert ds["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/container.config"
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
display_method_containers_extra_arg="$(sh "$cli" display method-containers --json /tmp/path 2>/dev/null)"
display_method_containers_extra_code=$?
display_method_profiles_extra_arg="$(sh "$cli" display method-profiles --json /tmp/path 2>/dev/null)"
display_method_profiles_extra_code=$?
display_phone_extra_arg="$(sh "$cli" display lane phone preflight --json /tmp/path 2>/dev/null)"
display_phone_extra_code=$?
display_anland_extra_arg="$(sh "$cli" display lane anland preflight --json /tmp/path 2>/dev/null)"
display_anland_extra_code=$?
display_dock_extra_arg="$(sh "$cli" display lane dock preflight --json /tmp/path 2>/dev/null)"
display_dock_extra_code=$?
baseline_extra_arg="$(sh "$cli" integrations baseline --json /tmp/path 2>/dev/null)"
baseline_extra_code=$?
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
[[ "$display_method_containers_extra_code" -ne 0 ]]
[[ "$display_method_profiles_extra_code" -ne 0 ]]
[[ "$display_phone_extra_code" -ne 0 ]]
[[ "$display_anland_extra_code" -ne 0 ]]
[[ "$display_dock_extra_code" -ne 0 ]]
[[ "$baseline_extra_code" -ne 0 ]]
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
[[ "$(json_field "$display_method_containers_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_method_profiles_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_phone_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_anland_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$display_dock_extra_arg" error)" == "USAGE" ]]
[[ "$(json_field "$baseline_extra_arg" error)" == "USAGE" ]]

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
