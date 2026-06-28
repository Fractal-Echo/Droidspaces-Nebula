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

node "$repo_root/scripts/validate-dock-lease-schema.js"

dock_plan="$(node "$repo_root/scripts/dock-lease-command-plan-report.js" --json)"
python3 - "$dock_plan" <<'PY'
import json, sys

obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "dock lease command-plan report"
assert obj["host_only"] is True
assert obj["profile_set_dock"] == "BLOCKED_NOT_READY"
assert obj["start_command_available"] is False
assert obj["runtime_allowlists_modified"] is False
assert obj["app_allowlists_modified"] is False
assert obj["lane"] == "dock_drm_lease_external"
assert "NO_ADB" in obj["safety_locks"]
assert "NO_DRM_MUTATION" in obj["safety_locks"]
assert "NO_CREATE_LEASE" in obj["safety_locks"]
assert len(obj["plans"]) >= 4
for plan in obj["plans"]:
    assert plan["execute"] is False
    assert plan["mutation_allowed_by_policy"] is False
    assert plan["external_display_only"] is True
    assert plan["dynamic_discovery_required"] is True
    assert plan["inputs"]["allow_raw_shell"] is False
    assert plan["inputs"]["allow_manual_connector_id"] is False
    assert plan["inputs"]["allow_manual_crtc_id"] is False
    assert plan["inputs"]["allow_manual_plane_id"] is False
    assert plan["inputs"]["allow_manual_fd"] is False
    assert plan["inputs"]["allow_internal_panel"] is False
    assert plan["inputs"]["allow_whole_card_takeover"] is False
    assert plan["observed_fixture_values"]["hardcoded_forbidden"] is True
    assert plan["required_guards"]["auto_retry_allowed"] is False
    assert "HOST_ONLY_FIXTURE" in plan["result_errors"]
PY

python3 - "$repo_root/app/src/main/java/io/droidspaces/nebula/core/NebulaCoreClient.java" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
active_first = r'if [ -x \"$NEBULA_CORE_ACTIVE\" ]; then'
pending_fallback = r'elif [ -x \"$NEBULA_CORE_PENDING\" ]; then NEBULA_CORE_CLI=\"$NEBULA_CORE_PENDING\";'
assert 'fixed_active_first_nebula_core_cli' in text
assert 'NEBULA_CORE_DEBUG_PENDING' in text
assert 'pending module rejected by anti-regression guard' in text
assert active_first in text
assert pending_fallback in text
assert text.index(active_first) < text.index(pending_fallback)
assert 'fixed_pending_or_active_nebula_core_cli' not in text
PY

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
assert phone["real_buffer_pass"] is True
assert phone["hardware_glx_pass"] is False
assert phone["software_glx_reproduced"] is True
assert phone["active_blocker"] == "NONE_WAYLAND_DISPLAY"
assert phone["vk_get_memory_fd_failures"] == 0
assert phone["real_buffer_commits"] == 2
assert phone["runtime_blocker"] == "GAME_CLIENT_RUNTIME_NOT_PROMOTED_39BIT_VA"
assert model["dock"]["dock_lease_state"] == "proven_reference_not_wired"
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
    "integrations.standalone",
    "nubia.toolkit.status",
    "runtime.waylandie.status",
    "runtime.waylandie.proton-smoke",
    "display.lanes",
    "display.method-containers",
    "display.method-profiles",
    "display.lane.phone.preflight",
    "display.lane.anland.preflight",
    "display.anland.recipes",
    "display.anland.status-check",
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
assert obj["path_policy"] == "live_package_path_first_stable_app_data"
assert obj["package_path"].endswith("/io.droidspaces.nebula.waylandie/base.apk")
assert obj["native_lib_dir"].endswith("/waylandie-lib")
assert obj["glibc_loader"].endswith("/libld_glibc.so")
assert obj["proot_path"].endswith("/libproot.so")
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
assert obj["bridge_path"].endswith("/files/imagefs/usr/local/bin/waylandie-wayland-bridge")
assert obj["gamescope_path"].endswith("/xwayland-gamescope-14-exportable-fence-guard-a4-473ba531/usr/local/bin/gamescope")
assert obj["xwayland_path"].endswith("/xwayland-gamescope-06-xwayland-9f1a3d62/usr/bin/Xwayland")
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
if [ -n "${NEBULA_DROIDSPACES_MARKER:-}" ]; then
  printf 'invoked %s\n' "$*" >> "$NEBULA_DROIDSPACES_MARKER"
fi
printf 'droidspaces fixture\n'
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
assert lanes["phone_app_bridge"]["status"] == "wayland_display_pass"
assert lanes["phone_app_bridge"]["state"] == "wayland_display_pass"
assert lanes["phone_app_bridge"]["method_id"] == "phone_app_bridge"
assert lanes["phone_app_bridge"]["available"] is True
assert lanes["phone_app_bridge"]["container_ref"] == "waylandie_app_imagefs"
assert lanes["phone_app_bridge"]["container_kind"] == "app_proot"
assert lanes["phone_app_bridge"]["container_status"] == "ready"
assert lanes["phone_app_bridge"]["display_status"] == "display_proven"
assert lanes["phone_app_bridge"]["runtime_status"] == "runtime_ready"
assert lanes["phone_app_bridge"]["requirement_status"] == "display_requirements_met"
assert "vulkan_export_real_buffer" not in lanes["phone_app_bridge"]["missing_requirements"]
assert "a1_fasttest_env_not_run_adb_offline" not in lanes["phone_app_bridge"]["missing_requirements"]
assert "game_client_runtime_proof_not_promoted_39bit_va" in lanes["phone_app_bridge"]["missing_requirements"]
assert lanes["phone_app_bridge"]["mutating"] is False
assert lanes["phone_app_bridge"]["launch_command_available"] is False
assert lanes["phone_app_bridge"]["active_blocker"] == "NONE_WAYLAND_DISPLAY"
assert lanes["phone_app_bridge"]["canonical_blocker"] == "NONE_WAYLAND_DISPLAY"
assert lanes["phone_app_bridge"]["proof_classification"] == "NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS"
assert lanes["phone_app_bridge"]["proof_metrics"]["summary_failures"] == 0
assert lanes["phone_app_bridge"]["proof_metrics"]["vkGetMemoryFdKHR_failures"] == 0
assert lanes["phone_app_bridge"]["proof_metrics"]["vk_get_memory_fd_failures"] == 0
assert lanes["phone_app_bridge"]["proof_metrics"]["real_buffer_commits"] == 2
assert lanes["phone_app_bridge"]["lead_status"] == "display_proven"
assert lanes["phone_app_bridge"]["proven_trick"] == "gamescope_force_composition_full_size_ar24_parent_xdg_dmabuf"
assert lanes["phone_app_bridge"]["next_reversa_action"] == "bounded_game_client_runtime_before_steam"
assert lanes["phone_app_bridge"]["steam_allowed"] is False
assert lanes["phone_app_bridge"]["kernel_va_bits_constraint"] == 39
assert lanes["phone_app_bridge"]["kernel_va_bits_evidence"] == "live_proc_config_gz"
assert lanes["phone_app_bridge"]["runtime_blocker"] == "GAME_CLIENT_RUNTIME_NOT_PROMOTED_39BIT_VA"
assert lanes["phone_app_bridge"]["real_buffer_pass"] is True
assert lanes["phone_app_bridge"]["hardware_glx_pass"] is False
assert lanes["phone_app_bridge"]["software_glx_reproduced"] is True
assert lanes["phone_app_bridge"]["vk_get_memory_fd_failures"] == 0
assert lanes["phone_app_bridge"]["real_buffer_commits"] == 2
assert lanes["phone_app_bridge"]["path_policy"] == "live_package_path_first_stable_app_data"
assert lanes["phone_app_bridge"]["package_path"].endswith("/io.droidspaces.nebula.waylandie/base.apk")
assert lanes["phone_app_bridge"]["native_lib_dir"].endswith("/waylandie-lib")
assert lanes["phone_app_bridge"]["glibc_loader"].endswith("/libld_glibc.so")
assert lanes["phone_app_bridge"]["selected_icd"].endswith("/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json")
assert lanes["phone_app_bridge"]["selected_vulkan_driver"].endswith("/files/imagefs/usr/local/lib/libvulkan_freedreno.so")
assert lanes["phone_app_bridge"]["loader_pin"]["VK_ICD_FILENAMES"] == lanes["phone_app_bridge"]["selected_icd"]
assert lanes["phone_app_bridge"]["loader_pin"]["VK_DRIVER_FILES"] == lanes["phone_app_bridge"]["selected_icd"]
assert lanes["phone_app_bridge"]["checks"]["display_ready"] is True
assert lanes["phone_app_bridge"]["checks"]["runtime_ready"] is True
assert lanes["phone_app_bridge"]["checks"]["native_lib_dir_present"] is True
assert lanes["phone_app_bridge"]["checks"]["glibc_loader_present"] is True
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
assert lanes["dock_drm_lease_external"]["status"] == "proven_reference_not_wired"
assert lanes["dock_drm_lease_external"]["state"] == "proven_reference_not_wired"
assert lanes["dock_drm_lease_external"]["dock_lease_state"] == "proven_reference_not_wired"
assert lanes["dock_drm_lease_external"]["method_id"] == "dock_drm_lease_external"
assert lanes["dock_drm_lease_external"]["container_ref"] == "none"
assert lanes["dock_drm_lease_external"]["container_kind"] == "none"
assert lanes["dock_drm_lease_external"]["display_status"] == "reference_only"
assert lanes["dock_drm_lease_external"]["runtime_status"] == "not_required"
assert lanes["dock_drm_lease_external"]["requirement_status"] == "reference_requirements_known"
assert "external_display_discovery_required" in lanes["dock_drm_lease_external"]["missing_requirements"]
assert lanes["dock_drm_lease_external"]["evidence_captured"] is True
assert lanes["dock_drm_lease_external"]["operator_required"] is True
assert lanes["dock_drm_lease_external"]["external_display_only"] is True
assert lanes["dock_drm_lease_external"]["start_command_available"] is False
assert lanes["dock_drm_lease_external"]["reported_objects"]["hardcoded_forbidden"] is True
assert lanes["compatibility"]["method_id"] == "compatibility_software"
assert lanes["compatibility"]["status"] == "not_wired"
assert lanes["compatibility"]["state"] == "not_wired"
assert lanes["compatibility"]["requirement_status"] == "not_wired"
assert "implementation_not_wired" in lanes["compatibility"]["missing_requirements"]
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
assert containers["phone_app_bridge"]["status"] == "display_proven"
assert containers["phone_app_bridge"]["state"] == "wayland_display_pass"
assert containers["phone_app_bridge"]["current_limit"] == "game_client_runtime_proof_not_promoted_39bit_va"
assert containers["phone_app_bridge"]["real_buffer_pass"] is True
assert containers["phone_app_bridge"]["hardware_glx_pass"] is False
assert containers["phone_app_bridge"]["software_glx_reproduced"] is True
assert containers["phone_app_bridge"]["vk_get_memory_fd_failures"] == 0
assert containers["phone_app_bridge"]["real_buffer_commits"] == 2
anland = containers["anland_surface"]
assert anland["container_kind"] == "droidspaces"
assert anland["container_ref"] == "ubuntu"
assert anland["recommended_container"] == "anland-ubuntu26-kde"
assert anland["selected_is_recommended"] is False
assert "bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock" in anland["required_config"]
assert "enable_pulseaudio=1" in anland["required_config"]
assert "ANLAND_SOCKET=/run/display.sock" in anland["required_env"]
assert "MESA_LOADER_DRIVER_OVERRIDE=kgsl" in anland["required_env"]
assert "PULSE_SERVER=unix:/tmp/.pulse-socket" in anland["required_env"]
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
assert obj["status"] == "wayland_display_pass"
assert obj["state"] == "wayland_display_pass"
assert obj["available"] is True
assert obj["mutating"] is False
assert obj["launch_command_available"] is False
assert obj["active_blocker"] == "NONE_WAYLAND_DISPLAY"
assert obj["proof_classification"] == "NEBULA_R6_WAYLAND_WORKING_REAL_BUFFER_PASS"
assert obj["lead_status"] == "display_proven"
assert obj["next_reversa_action"] == "bounded_game_client_runtime_before_steam"
assert obj["steam_allowed"] is False
assert obj["kernel_va_bits_constraint"] == 39
assert obj["kernel_va_bits_evidence"] == "live_proc_config_gz"
assert obj["runtime_blocker"] == "GAME_CLIENT_RUNTIME_NOT_PROMOTED_39BIT_VA"
assert obj["real_buffer_pass"] is True
assert obj["hardware_glx_pass"] is False
assert obj["software_glx_reproduced"] is True
assert obj["vk_get_memory_fd_failures"] == 0
assert obj["real_buffer_commits"] == 2
assert obj["path_policy"] == "live_package_path_first_stable_app_data"
assert obj["package_path"].endswith("/io.droidspaces.nebula.waylandie/base.apk")
assert obj["native_lib_dir"].endswith("/waylandie-lib")
assert obj["glibc_loader"].endswith("/libld_glibc.so")
assert obj["bridge_path"].endswith("/files/imagefs/usr/local/bin/waylandie-wayland-bridge")
assert obj["gamescope_path"].endswith("/xwayland-gamescope-14-exportable-fence-guard-a4-473ba531/usr/local/bin/gamescope")
assert obj["xwayland_path"].endswith("/xwayland-gamescope-06-xwayland-9f1a3d62/usr/bin/Xwayland")
assert obj["checks"]["display_ready"] is True
assert obj["checks"]["runtime_ready"] is True
assert obj["checks"]["native_lib_dir_present"] is True
assert obj["checks"]["glibc_loader_present"] is True
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
assert "PULSE_SERVER=unix:/tmp/.pulse-socket" in obj["required_env"]
assert obj["setup_commands"]["recommended_container"] == "anland-ubuntu26-kde"
assert "--rootfs-arc=/sdcard/Download/anland-ubuntu26-kde.tar.xz" in obj["setup_commands"]["droidspaces_create_rootfs_img"]
assert "--bind=/data/local/tmp/display_daemon.sock:/run/display.sock" in obj["setup_commands"]["droidspaces_start_recommended"]
assert obj["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
assert obj["selected_paths"]["rootfs_mode"] == "directory"
PY

anland_recipes="$(
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  sh "$cli" display anland recipes --json
)"
python3 - "$anland_recipes" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "display anland recipes"
assert obj["mutating"] is False
assert obj["executor_available"] is False
assert obj["recipe_manifest_only"] is True
assert obj["artifact"]["sha256"] == "848bab354f6f1a46f842cc32536d558518d21e0280e299f814a9a1fbaf73e4ec"
assert obj["artifact"]["public_repo_payloads_committed"] is False
assert obj["preflight"]["selected_container"] == "ubuntu"
assert obj["preflight"]["container_selection_source"] == "default_fallback"
assert obj["preflight"]["runtime_ready"] is True
assert obj["preflight"]["display_ready"] is True
checks = obj["preflight"]["checks"]
assert checks["droidspaces_binary"] is True
assert checks["container_config"] is True
assert checks["rootfs_path"] is True
assert checks["rootfs_image"] is False
assert checks["anland_env"] is True
assert checks["display_daemon_socket"] is True
assert checks["display_daemon_socket_writable"] is True
assert checks["render_node"] is True
assert checks["config_socket_bind"] is True
assert checks["env_socket"] is True
assert checks["env_kgsl"] is True
assert checks["anland_producer"] is True
recipes = {item["id"]: item for item in obj["recipes"]}
required = {
    "open_anland_consumer",
    "install_or_verify_anland_consumer_apk",
    "install_or_verify_anland_daemon_module",
    "create_anland_rootfs_image",
    "phone_setup_container",
    "restart_display_daemon",
    "stop_container",
    "start_container",
    "restart_selected_with_socket",
    "start_kde_producer",
    "status_check",
    "capture_screenshot",
    "terminal_enter",
    "verify_requirements",
    "audio_fix",
    "browser_install",
    "steam_install",
}
assert required <= recipes.keys()
assert all(item["exposed_by_nebula"] is False for item in recipes.values())
assert recipes["status_check"]["mutating"] is False
assert recipes["verify_requirements"]["mutating"] is False
assert recipes["terminal_enter"]["status"] == "not_allowed_in_apk"
assert recipes["steam_install"]["status"] == "research_reference_only"
assert "/opt/anland/startup.sh" in recipes["start_kde_producer"]["fixed_command_reference"]
assert "startanland-kde.sh" in recipes["start_kde_producer"]["fixed_command_reference"]
assert "--rootfs-arc=/sdcard/Download/anland-ubuntu26-kde.tar.xz" in recipes["create_anland_rootfs_image"]["fixed_command_reference"]
assert "anland-daemon" in recipes["install_or_verify_anland_daemon_module"]["fixed_command_reference"]
assert "virtual-drm-daemon" in recipes["install_or_verify_anland_daemon_module"]["fixed_command_reference"]
assert "ps -A" in recipes["status_check"]["fixed_command_reference"]
assert "no_arbitrary_shell" in obj["guardrails"]
assert "no_terminal_enter_from_apk" in obj["guardrails"]
assert "no_steam_proton_wine_dxvk_game_launch_from_recipe_manifest" in obj["guardrails"]
assert "preserve_waylandie_known_good_frontier" in obj["guardrails"]
assert any("container=Ubuntu or ubuntu" in item for item in obj["source_drift"])
PY

set +e
bad_anland_recipes="$(sh "$cli" display anland recipes --json /tmp/bad)"
bad_anland_recipes_code=$?
set -e
[[ "$bad_anland_recipes_code" -eq 2 ]]
python3 - "$bad_anland_recipes" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["ok"] is False
assert obj["error"] == "USAGE"
PY

anland_status_marker="$tmp/anland-status-droidspaces-marker"
anland_status_check="$(
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  NEBULA_DROIDSPACES_MARKER="$anland_status_marker" \
  sh "$cli" display anland status-check --json
)"
test ! -e "$anland_status_marker"
python3 - "$anland_status_check" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
payload = json.dumps(obj)
assert obj["protocol_version"] == 1
assert obj["command"] == "display anland status-check"
assert obj["ok"] is True
assert obj["mutating"] is False
assert obj["executor_available"] is False
assert obj["status_check_ready"] is True
assert obj["status"] == "preflight_ready"
assert obj["available"] is True
assert obj["runtime_ready"] is True
assert obj["display_ready"] is True
assert obj["selected_container"] == "ubuntu"
assert obj["container_selection_source"] == "default_fallback"
assert obj["preflight"]["runtime_ready"] is True
assert obj["preflight"]["display_ready"] is True
checks = obj["preflight"]["checks"]
assert checks["droidspaces_binary"] is True
assert checks["container_config"] is True
assert checks["rootfs_path"] is True
assert checks["rootfs_image"] is False
assert checks["anland_env"] is True
assert checks["display_daemon_socket"] is True
assert checks["display_daemon_socket_writable"] is True
assert checks["render_node"] is True
assert checks["config_socket_bind"] is True
assert checks["env_socket"] is True
assert checks["env_kgsl"] is True
assert checks["anland_producer"] is True
assert obj["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
assert obj["selected_paths"]["display_socket_host"] == "/data/local/tmp/display_daemon.sock"
assert obj["selected_paths"]["display_socket_guest"] == "/run/display.sock"
assert obj["active_container"]["active"] is False
assert obj["active_container"]["pid"] is None
policy = obj["probe_policy"]
assert policy["fixed_path_only"] is True
assert policy["droidspaces_runtime_invoked"] is False
assert policy["process_inventory_invoked"] is False
assert policy["daemon_log_tail_invoked"] is False
assert policy["image_rootfs_producer_verify_invoked"] is False
assert "no_droidspaces_runtime_invocation" in obj["guardrails"]
assert "no_recipes" in obj["guardrails"]
assert "recipes" not in obj
assert "setup_commands" not in obj
for forbidden in [
    "fixed_command_reference",
    "producer_run_command",
    "adb ",
    "am ",
    "ksud ",
    "pkill",
    "nohup",
    "screencap",
]:
    assert forbidden not in payload
PY

set +e
bad_anland_status_check="$(sh "$cli" display anland status-check --json /tmp/bad)"
bad_anland_status_check_code=$?
set -e
[[ "$bad_anland_status_check_code" -eq 2 ]]
python3 - "$bad_anland_status_check" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["ok"] is False
assert obj["error"] == "USAGE"
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
active_image_status_marker="$tmp/active-image-status-droidspaces-marker"
active_image_anland_status_check="$(
  NEBULA_TEST_DEVICE_ROOT="$image_root" \
  NEBULA_ANLAND_CONTAINER=anland-ubuntu26-kde \
  NEBULA_DROIDSPACES_MARKER="$active_image_status_marker" \
  sh "$cli" display anland status-check --json
)"
test ! -e "$active_image_status_marker"
python3 - "$active_image_anland_status_check" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["command"] == "display anland status-check"
assert obj["mutating"] is False
assert obj["executor_available"] is False
assert obj["status_check_ready"] is False
assert obj["status"] == "container_runtime_ready", obj
assert obj["available"] is False
assert obj["runtime_ready"] is True
assert obj["display_ready"] is False
assert obj["selected_container"] == "anland-ubuntu26-kde"
assert obj["active_container"]["active"] is True
assert obj["active_container"]["pid"] == 4343
assert obj["preflight"]["checks"]["rootfs_image"] is True
assert obj["preflight"]["checks"]["anland_producer"] is False
assert obj["probe_policy"]["droidspaces_runtime_invoked"] is False
assert obj["probe_policy"]["image_rootfs_producer_verify_invoked"] is False
assert "unknown:anland_producer_inside_rootfs_image_run_verify_required" in obj["preflight"]["errors"]
PY
mkdir -p "$image_root/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/rootfs" \
  "$image_root/proc/4444"
cat > "$image_root/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/container.config" <<'EOF'
name=rm11-alpine-324-turnip
rootfs_path=/data/local/Droidspaces/Containers/rm11-alpine-324-turnip/rootfs
enable_hw_access=1
enable_gpu_mode=1
run_at_boot=1
EOF
printf 4444 > "$image_root/data/local/Droidspaces/Pids/rm11-alpine-324-turnip.pid"
mixed_active_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$image_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$mixed_active_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "preflight_ready", obj
assert obj["available"] is True
assert obj["runtime_ready"] is True
assert obj["selected_container"] == "anland-ubuntu26-kde"
assert obj["container_selection_source"] == "active_pidfile"
assert obj["container_status"] == "active"
assert obj["requirement_status"] == "complete"
assert obj["missing_requirements"] == []
assert obj["container_active"] is True
assert obj["container_pid"] == 4343
assert obj["checks"]["active_container_pidfile"] is True
assert obj["checks"]["anland_producer"] is True
assert obj["errors"] == []
PY
rm -f "$image_root/data/local/Droidspaces/Pids/anland-ubuntu26-kde.pid"
idle_recommended_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$image_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$idle_recommended_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["status"] == "container_runtime_ready", obj
assert obj["available"] is False
assert obj["runtime_ready"] is True
assert obj["selected_container"] == "anland-ubuntu26-kde"
assert obj["container_selection_source"] == "recommended_profile"
assert obj["container_ref"] == "anland-ubuntu26-kde"
assert obj["container_status"] == "ready"
assert obj["display_status"] == "display_missing"
assert obj["runtime_status"] == "runtime_ready"
assert obj["requirement_status"] == "missing_requirements"
assert obj["container_active"] is False
assert obj["container_pid"] is None
assert obj["checks"]["active_container_pidfile"] is False
assert obj["checks"]["container_config"] is True
assert obj["checks"]["rootfs_path"] is True
assert obj["checks"]["rootfs_image"] is True
assert obj["checks"]["anland_env"] is True
assert obj["checks"]["display_daemon_socket"] is True
assert obj["checks"]["anland_producer"] is False
assert obj["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/anland-ubuntu26-kde/container.config"
assert obj["selected_paths"]["rootfs_path"] == "/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img"
assert "unknown:anland_producer_inside_rootfs_image_run_verify_required" in obj["errors"]
PY

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
assert obj["status"] == "partial"
assert obj["available"] is False
assert obj["runtime_ready"] is False
assert obj["selected_container"] == "ubuntu"
assert obj["container_selection_source"] == "default_fallback"
assert obj["container_ref"] == "ubuntu"
assert obj["container_status"] == "missing"
assert obj["display_status"] == "display_missing"
assert obj["runtime_status"] == "runtime_missing"
assert obj["requirement_status"] == "missing_requirements"
assert "missing:container_config" in obj["missing_requirements"]
assert "missing:anland_env" in obj["missing_requirements"]
assert "missing:display_daemon_socket" in obj["missing_requirements"]
assert "missing:rootfs_path" in obj["missing_requirements"]
assert "missing:anland_producer" in obj["missing_requirements"]
assert obj["container_active"] is False
assert obj["container_pid"] is None
assert obj["checks"]["active_container_pidfile"] is False
assert obj["checks"]["container_config"] is False
assert obj["checks"]["rootfs_path"] is False
assert obj["checks"]["anland_env"] is False
assert obj["checks"]["display_daemon_socket"] is False
assert obj["checks"]["anland_producer"] is False
assert obj["selected_paths"]["pidfile"] is None
assert obj["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
assert "missing:container_config" in obj["errors"]
assert "missing:anland_env" in obj["errors"]
assert "missing:display_daemon_socket" in obj["errors"]
assert "missing:rootfs_path" in obj["errors"]
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

stale_reuse_root="$tmp/device-root-stale-reuse"
mkdir -p "$stale_reuse_root/data/local/Droidspaces/bin" \
  "$stale_reuse_root/data/local/Droidspaces/Pids" \
  "$stale_reuse_root/data/local/Droidspaces/Containers/ubuntu/rootfs" \
  "$stale_reuse_root/data/local/Droidspaces/Containers/anland-ubuntu26-kde" \
  "$stale_reuse_root/proc/3296"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$stale_reuse_root/data/local/Droidspaces/bin/droidspaces"
cat > "$stale_reuse_root/data/local/Droidspaces/Containers/ubuntu/container.config" <<'EOF'
name=ubuntu
rootfs_path=/data/local/Droidspaces/Containers/ubuntu/rootfs
enable_hw_access=1
enable_gpu_mode=1
EOF
cat > "$stale_reuse_root/data/local/Droidspaces/Containers/anland-ubuntu26-kde/container.config" <<'EOF'
name=anland-ubuntu26-kde
rootfs_path=/data/local/Droidspaces/Containers/anland-ubuntu26-kde/rootfs.img
enable_hw_access=1
enable_gpu_mode=1
EOF
printf 3296 > "$stale_reuse_root/data/local/Droidspaces/Pids/anland-ubuntu26-kde.pid"
printf '/system/bin/audioserver\0' > "$stale_reuse_root/proc/3296/cmdline"
cat > "$stale_reuse_root/proc/3296/status" <<'EOF'
Name:	AudioOut_1D
Pid:	3296
Uid:	1041	1041	1041	1041
Gid:	1005	1005	1005	1005
EOF
stale_reuse_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$stale_reuse_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$stale_reuse_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["selected_container"] == "ubuntu", obj
assert obj["container_selection_source"] == "default_fallback"
assert obj["container_active"] is False
assert obj["container_pid"] is None
assert obj["checks"]["active_container_pidfile"] is False
PY

traversal_root="$tmp/device-root-traversal"
mkdir -p "$traversal_root/data/local/Droidspaces/bin" \
  "$traversal_root/data/local/Droidspaces/Containers/ubuntu" \
  "$traversal_root/data/local/Droidspaces/Containers/other/rootfs" \
  "$traversal_root/dev/dri"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$traversal_root/data/local/Droidspaces/bin/droidspaces"
: > "$traversal_root/dev/dri/renderD128"
cat > "$traversal_root/data/local/Droidspaces/Containers/ubuntu/container.config" <<'EOF'
name=ubuntu
rootfs_path=/data/local/Droidspaces/Containers/ubuntu/../other/rootfs
enable_hw_access=1
enable_gpu_mode=1
EOF
traversal_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$traversal_root" \
  sh "$cli" display lane anland preflight --json
)"
python3 - "$traversal_anland_preflight" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["selected_container"] == "ubuntu", obj
assert obj["checks"]["rootfs_path"] is False
assert "invalid:rootfs_path_outside_container" in obj["errors"]
PY

ambiguous_profile_root="$tmp/device-root-ambiguous-profile"
mkdir -p "$ambiguous_profile_root/data/local/Droidspaces/bin" \
  "$ambiguous_profile_root/data/local/Droidspaces/Pids" \
  "$ambiguous_profile_root/data/local/Droidspaces/Containers/anland-one/rootfs" \
  "$ambiguous_profile_root/data/local/Droidspaces/Containers/anland-two/rootfs" \
  "$ambiguous_profile_root/proc/4243" \
  "$ambiguous_profile_root/proc/4244"
cp "$device_root/data/local/Droidspaces/bin/droidspaces" \
  "$ambiguous_profile_root/data/local/Droidspaces/bin/droidspaces"
cat > "$ambiguous_profile_root/data/local/Droidspaces/Containers/anland-one/container.config" <<'EOF'
name=anland-one
rootfs_path=/data/local/Droidspaces/Containers/anland-one/rootfs
enable_hw_access=1
enable_gpu_mode=1
env_file=/data/local/Droidspaces/Containers/anland-one/anland.env
bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock
EOF
cat > "$ambiguous_profile_root/data/local/Droidspaces/Containers/anland-two/container.config" <<'EOF'
name=anland-two
rootfs_path=/data/local/Droidspaces/Containers/anland-two/rootfs
enable_hw_access=1
enable_gpu_mode=1
env_file=/data/local/Droidspaces/Containers/anland-two/anland.env
bind_mounts=/data/local/tmp/display_daemon.sock:/run/display.sock
EOF
printf 4243 > "$ambiguous_profile_root/data/local/Droidspaces/Pids/anland-one.pid"
printf 4244 > "$ambiguous_profile_root/data/local/Droidspaces/Pids/anland-two.pid"
ambiguous_anland_preflight="$(
  NEBULA_TEST_DEVICE_ROOT="$ambiguous_profile_root" \
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
assert obj["status"] == "proven_reference_not_wired"
assert obj["state"] == "proven_reference_not_wired"
assert obj["dock_lease_state"] == "proven_reference_not_wired"
assert obj["available"] is False
assert obj["mutating"] is False
assert obj["start_command_available"] is False
assert obj["evidence_captured"] is True
assert obj["operator_required"] is True
assert obj["external_display_only"] is True
assert obj["internal_panel_allowed"] is False
assert obj["whole_card_takeover"] is False
assert obj["display_status"] == "reference_only"
assert obj["requirement_status"] == "reference_requirements_known"
assert "external_display_discovery_required" in obj["missing_requirements"]
assert "lease_receiver_not_wired" in obj["missing_requirements"]
assert obj["reported_objects"]["connector"] == 89
assert obj["reported_objects"]["hardcoded_forbidden"] is True
assert obj["reference_package_status"] == "captured_validated_reference_only"
assert obj["reference_package_sha256"] == "d680e50c50c3f4081fc0319cf6130efbb955d3c7a91678b7f4599a340e939558"
assert obj["binary_import_allowed"] is False
assert obj["rebuild_required_before_binary_import"] is True
assert obj["runtime_execution_allowed"] is False
assert obj["mutation_allowed_by_policy"] is False
assert obj["vendor_guidance_policy"] == "provenance_only_no_copied_vendor_text_no_vendor_blobs"
assert "vulkan_first" in obj["adreno_runtime_guardrails"]
assert "driver_version_workarounds_require_runtime_probe" in obj["adreno_runtime_guardrails"]
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
assert obj["overall_status"] == "baseline_ready_read_only"
assert obj["safe_default"] is True
assert obj["mutating_controls_enabled"] is False
items = {item["id"]: item for item in obj["integrations"]}
assert items["nebula_core"]["ready"] is True
assert items["waylandie"]["status"] == "display_ready"
assert items["waylandie"]["state"] == "wayland_display_pass"
assert items["waylandie"]["method_id"] == "phone_app_bridge"
assert items["waylandie"]["path_policy"] == "live_package_path_first_stable_app_data"
assert items["waylandie"]["package_path"].endswith("/io.droidspaces.nebula.waylandie/base.apk")
assert items["waylandie"]["native_lib_dir"].endswith("/waylandie-lib")
assert items["waylandie"]["glibc_loader"].endswith("/libld_glibc.so")
assert items["waylandie"]["selected_icd"].endswith("/files/imagefs/usr/local/etc/vulkan/icd.d/freedreno_icd.json")
assert items["waylandie"]["selected_vulkan_driver"].endswith("/files/imagefs/usr/local/lib/libvulkan_freedreno.so")
assert items["waylandie"]["loader_pin"]["VK_ICD_FILENAMES"] == items["waylandie"]["selected_icd"]
assert items["waylandie"]["loader_pin"]["VK_DRIVER_FILES"] == items["waylandie"]["selected_icd"]
assert items["waylandie"]["container_ref"] == "waylandie_app_imagefs"
assert items["waylandie"]["container_kind"] == "app_proot"
assert items["waylandie"]["container_status"] == "ready"
assert items["waylandie"]["display_status"] == "display_proven"
assert items["waylandie"]["runtime_status"] == "runtime_ready"
assert items["waylandie"]["requirement_status"] == "display_requirements_met"
assert "vulkan_export_real_buffer" not in items["waylandie"]["missing_requirements"]
assert "a1_fasttest_env_not_run_adb_offline" not in items["waylandie"]["missing_requirements"]
assert "game_client_runtime_proof_not_promoted_39bit_va" in items["waylandie"]["missing_requirements"]
assert items["waylandie"]["ready"] is True
assert items["waylandie"]["display_ready"] is True
assert items["waylandie"]["runtime_ready"] is True
assert items["waylandie"]["active_blocker"] == "NONE_WAYLAND_DISPLAY"
assert items["waylandie"]["real_buffer_pass"] is True
assert items["waylandie"]["hardware_glx_pass"] is False
assert items["waylandie"]["software_glx_reproduced"] is True
assert items["waylandie"]["vk_get_memory_fd_failures"] == 0
assert items["waylandie"]["real_buffer_commits"] == 2
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
assert "preserve_wayland_real_buffer_pass" in obj["guardrails"]
assert obj["next_step"] == "bounded_game_client_runtime_before_steam"
PY

standalone="$(
  NEBULA_TEST_PACKAGE_DIR="$package_dir" \
  NEBULA_MODULES_ROOT="$modules_root" \
  NEBULA_WAYLANDIE_DATA_DIR="$waylandie_data" \
  NEBULA_WAYLANDIE_NATIVE_LIB_DIR="$waylandie_lib" \
  NEBULA_WAYLANDIE_UID=10518 \
  NEBULA_TEST_DEVICE_ROOT="$device_root" \
  NEBULA_SYSROOT="$fixture" \
  sh "$cli" integrations standalone --json
)"
python3 - "$standalone" <<'PY'
import json, sys
obj = json.loads(sys.argv[1])
assert obj["protocol_version"] == 1
assert obj["command"] == "integrations standalone"
assert obj["standalone_id"] == "nebula_one_apk_one_module_control_deck"
assert obj["mode"] == "authority_registry"
assert obj["apk_package"] == "io.droidspaces.nebula"
assert obj["module_id"] == "nebula_core"
contract = obj["contract"]
assert contract["single_apk"] is True
assert contract["single_core_module"] is True
assert contract["fixed_commands_only"] is True
assert contract["active_module_first"] is True
assert contract["pending_module_default"] is False
assert contract["status_before_mutation"] is True
baseline = obj["baseline"]
assert baseline["command"] == "integrations baseline"
assert baseline["overall_status"] == "baseline_ready_read_only"
layers = {item["id"]: item for item in obj["ownership_layers"]}
assert layers["nebula_apk"]["bundled_in"] == "apk"
assert layers["nebula_apk"]["mutation_authority"] is False
assert layers["nebula_core"]["bundled_in"] == "module"
assert layers["nebula_core"]["mutation_authority"] is True
assert layers["nebula_core"]["mutation_policy"] == "allowlisted_only"
assert layers["waylandie"]["promotion_state"] == "display_proven_runtime_smoke_next"
assert layers["droidspaces_anland"]["bundled_in"] == "external_container_assets"
assert layers["droidspaces_anland"]["promotion_state"] == "preflight_or_copyable_config_only"
assert layers["nubia_hooks"]["promotion_state"] == "status_only_scope_deferred"
assert layers["redmagic_hardware"]["promotion_state"] == "read_only_nodes_preview"
assert layers["powerdeck"]["promotion_state"] == "preview_snapshot_only"
modes = {item["id"]: item for item in obj["compatibility_modes"]}
assert modes["rm11pro_waylandie"]["rank"] == 1
assert modes["anland_droidspaces"]["rank"] == 2
assert modes["droidspaces_native_profiles"]["promotion"] == "per_profile_proof_required"
assert "no_arbitrary_shell" in obj["standalone_guardrails"]
assert "preserve_active_module_known_good_frontier" in obj["standalone_guardrails"]
assert obj["next_engineering_action"] == "bounded_game_client_runtime_before_steam"
PY

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
assert obj["overall_status"] == "baseline_ready_read_only"
items = {item["id"]: item for item in obj["integrations"]}
ds = items["droidspaces"]
assert ds["status"] == "partial"
assert ds["ready"] is False
assert ds["runtime_ready"] is False
assert ds["display_socket_ready"] is False
assert ds["method_id"] == "anland_surface"
assert ds["container_ref"] == "ubuntu"
assert ds["container_kind"] == "droidspaces"
assert ds["container_status"] == "missing"
assert ds["display_status"] == "display_missing"
assert ds["runtime_status"] == "runtime_missing"
assert ds["requirement_status"] == "missing_requirements"
assert "missing:container_config" in ds["missing_requirements"]
assert "missing:anland_env" in ds["missing_requirements"]
assert "missing:display_daemon_socket" in ds["missing_requirements"]
assert "missing:rootfs_path" in ds["missing_requirements"]
assert "missing:anland_producer" in ds["missing_requirements"]
assert ds["selected_container"] == "ubuntu"
assert ds["container_selection_source"] == "default_fallback"
assert ds["container_active"] is False
assert ds["container_pid"] is None
assert ds["checks"]["active_container_pidfile"] is False
assert ds["checks"]["container_config"] is False
assert ds["checks"]["anland_producer"] is False
assert ds["selected_paths"]["container_config"] == "/data/local/Droidspaces/Containers/ubuntu/container.config"
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
standalone_extra_arg="$(sh "$cli" integrations standalone --json /tmp/path 2>/dev/null)"
standalone_extra_code=$?
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
[[ "$standalone_extra_code" -ne 0 ]]
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
[[ "$(json_field "$standalone_extra_arg" error)" == "USAGE" ]]

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
