#!/usr/bin/env bash
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
adb="${ADB:-/mnt/c/platform-tools/adb.exe}"
log_dir="/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-22-nebula-fast-reboot-test-07"
with_app_ui=0
operator_manual_assisted="${NEBULA_MANUAL_ASSISTED:-0}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --with-app-ui)
      with_app_ui=1
      ;;
    --manual-assisted)
      operator_manual_assisted=1
      ;;
    --log-dir)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--log-dir requires a path" >&2
        exit 2
      fi
      log_dir="$1"
      ;;
    --help|-h)
      cat <<'EOF'
Usage: run-fast-reboot-test.sh [--log-dir DIR] [--with-app-ui] [--manual-assisted]

Default behavior reboots, waits for wireless ADB recovery, writes
classification.json/result.md, and stops. Use --with-app-ui only when app
launch/UI evidence is part of the current target. Use --manual-assisted if the
Wireless debugging toggle was touched during the run.
EOF
      exit 0
      ;;
    --*)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
    *)
      log_dir="$1"
      ;;
  esac
  shift
done

mkdir -p "$log_dir"
cd "$repo_root" || exit 2

module_cli=/data/adb/modules/nebula_core/bin/nebula-core
expected_model="${NEBULA_ADB_MODEL:-NX809J}"

app_su() {
  local serial="$1"
  local command="$2"
  "$adb" -s "$serial" shell run-as io.droidspaces.nebula /system/bin/su -c "$command"
}

shell_su_diagnostic() {
  local serial="$1"
  local output="$2"
  "$adb" -s "$serial" shell su -c \
    "id; getenforce; settings get global adb_enabled; settings get global adb_wifi_enabled; settings get global enable_wireless_switch; $module_cli status --json; $module_cli adb-wifi status --json; tail -n 40 /data/adb/nebula/logs/nebula-core.log" \
    > "$output" 2>&1 || true
}

classify_recovery() {
  python3 - "$log_dir" "$operator_manual_assisted" "$expected_model" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

log_dir = Path(sys.argv[1])
manual_assisted = sys.argv[2].lower() in {"1", "true", "yes", "y"}
expected_model = sys.argv[3]

def read_text(name: str) -> str:
    try:
        return (log_dir / name).read_text(errors="ignore").strip()
    except FileNotFoundError:
        return ""

def read_json(name: str) -> dict:
    text = read_text(name)
    if not text:
        return {}
    try:
        return json.loads(text)
    except json.JSONDecodeError as exc:
        return {"_parse_error": str(exc), "_raw": text[:400]}

def key_values(name: str) -> dict:
    values = {}
    for line in read_text(name).splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values

def truthy(obj: dict, key: str) -> bool:
    return obj.get(key) is True

start = key_values("reboot-start.txt")
failure = read_text("failure.txt")
post_state = read_text("post-adb-state.txt")
post_boot = read_text("post-boot-completed.txt")
post_model = read_text("post-model.txt")
core = read_json("post-core-status-app-su.json")
adb_wifi = read_json("post-adb-wifi-status-app-su.json")
core_log = read_text("post-nebula-core-log-app-su.txt")
reboot_sent = start.get("reboot_sent_utc", "")

manager_lines = []
for line in core_log.splitlines():
    if "manager=allowWirelessDebugging" not in line:
        continue
    stamp = line[:20]
    if reboot_sent and len(stamp) == 20 and stamp < reboot_sent:
        continue
    manager_lines.append(line)

checks = {
    "post_state_device": post_state == "device",
    "post_boot_completed": post_boot == "1",
    "post_model_expected": post_model == expected_model,
    "core_commit_present": bool(core.get("git_commit")),
    "adb_debugging_true": truthy(adb_wifi, "adb_debugging"),
    "wireless_debugging_true": truthy(adb_wifi, "wireless_debugging"),
    "settings_wireless_debugging_true": truthy(adb_wifi, "settings_wireless_debugging"),
    "ui_wireless_switch_true": truthy(adb_wifi, "ui_wireless_switch"),
    "settings_requested_true": truthy(adb_wifi, "settings_requested"),
    "manual_toggle_required_false": adb_wifi.get("manual_toggle_required") is False,
    "activation_state_live": adb_wifi.get("activation_state") == "live",
    "auto_enable_true": truthy(adb_wifi, "auto_enable"),
    "wireless_port_positive": isinstance(adb_wifi.get("wireless_port"), int) and adb_wifi["wireless_port"] > 0,
    "manager_bssid_available": truthy(adb_wifi, "manager_bssid_available"),
    "adb_wifi_errors_empty": adb_wifi.get("errors") == [],
    "manager_log_after_reboot": bool(manager_lines),
}

if "POST_REBOOT_ADB_UNRESOLVED" in failure:
    classification = "ADB_UNRESOLVED"
    reason = "resolver did not recover wireless ADB before timeout"
elif post_model and post_model != expected_model:
    classification = "WRONG_DEVICE"
    reason = f"post model {post_model!r} did not match {expected_model!r}"
elif manual_assisted:
    classification = "MANUAL_ASSISTED_OR_UNPROVEN"
    reason = "operator marked the run manual-assisted"
elif not checks["post_state_device"] or not checks["post_boot_completed"]:
    classification = "ADB_UNRESOLVED"
    reason = "post-reboot adb state or boot-completed proof missing"
elif not all(checks.values()):
    classification = "RECOVERY_UNPROVEN"
    missing = [key for key, value in checks.items() if not value]
    reason = "missing required proof: " + ", ".join(missing)
else:
    classification = "PASS_UNATTENDED"
    reason = "post-reboot app KSU proof and manager-path log are present"

summary = {
    "classification": classification,
    "reason": reason,
    "manual_assisted": manual_assisted,
    "expected_model": expected_model,
    "head": start.get("head", "unknown"),
    "start_utc": start.get("start_utc", "unknown"),
    "reboot_sent_utc": reboot_sent or "unknown",
    "post_serial": read_text("post-serial.txt"),
    "post_state": post_state,
    "post_boot_completed": post_boot,
    "post_model": post_model,
    "module_commit": core.get("git_commit", "unknown"),
    "wireless_port": adb_wifi.get("wireless_port"),
    "manager_line": manager_lines[-1] if manager_lines else "",
    "checks": checks,
}

(log_dir / "classification.json").write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n")

lines = [
    "# Nebula Fast Reboot Classification",
    "",
    f"Classification: {classification}",
    "",
    f"Reason: {reason}",
    "",
    "## Evidence",
    "",
    f"- Head: `{summary['head']}`",
    f"- Reboot sent: `{summary['reboot_sent_utc']}`",
    f"- Post serial: `{summary['post_serial'] or 'unknown'}`",
    f"- Post state: `{post_state or 'unknown'}`",
    f"- Post boot completed: `{post_boot or 'unknown'}`",
    f"- Post model: `{post_model or 'unknown'}`",
    f"- Module commit: `{summary['module_commit']}`",
    f"- Wireless port: `{summary['wireless_port']}`",
    f"- Manager line: `{summary['manager_line'] or 'missing'}`",
    "",
    "## Checks",
    "",
]
for key, value in checks.items():
    lines.append(f"- {key}: `{str(value).lower()}`")
lines.extend([
    "",
    "## Guardrails",
    "",
    "- App/UI smoke collection is opt-in with `--with-app-ui`.",
    "- Plain `adb shell su` output is diagnostic only; app-granted KSU JSON is canonical.",
])
(log_dir / "result.md").write_text("\n".join(lines) + "\n")

print(classification)
PY
}

classification_exit_code() {
  case "$1" in
    PASS_UNATTENDED) printf '%s' 0 ;;
    ADB_UNRESOLVED) printf '%s' 23 ;;
    WRONG_DEVICE) printf '%s' 24 ;;
    MANUAL_ASSISTED_OR_UNPROVEN) printf '%s' 25 ;;
    *) printf '%s' 26 ;;
  esac
}

{
  printf 'start_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'head=%s\n' "$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
  echo 'pre_devices_begin'
  "$adb" devices -l
  echo 'pre_devices_end'
  echo 'pre_mdns_begin'
  "$adb" mdns services
  echo 'pre_mdns_end'
} | tee "$log_dir/reboot-start.txt"

ADB="$adb" NEBULA_ADB_MODEL="$expected_model" ./scripts/resolve-rm11-adb-serial.sh --prefer-wireless --env \
  | tee "$log_dir/pre-resolved-adb.env"
serial="$(awk -F= '$1 == "ADB_SERIAL" { print $2; exit }' "$log_dir/pre-resolved-adb.env")"
if [ -z "$serial" ]; then
  echo "ADB resolver did not emit ADB_SERIAL" | tee "$log_dir/failure.txt"
  exit "$(classification_exit_code ADB_UNRESOLVED)"
fi
printf 'pre_serial=%s\n' "$serial" | tee -a "$log_dir/reboot-start.txt"
"$adb" -s "$serial" get-state | tee "$log_dir/pre-adb-state.txt"
"$adb" -s "$serial" shell getprop sys.boot_completed | tee "$log_dir/pre-boot-completed.txt"
"$adb" -s "$serial" shell \
  'settings get global adb_enabled; settings get global adb_wifi_enabled; settings get global enable_wireless_switch' \
  | tee "$log_dir/pre-adb-wifi-settings.txt"
app_su "$serial" "$module_cli adb-wifi status --json" \
  | tee "$log_dir/pre-adb-wifi-status-app-su.json"
shell_su_diagnostic "$serial" "$log_dir/pre-shell-su-diagnostic.txt"

"$adb" -s "$serial" reboot
printf 'reboot_sent_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$log_dir/reboot-start.txt"

sleep 12
resolved=""
for i in $(seq 1 96); do
  "$adb" devices -l > "$log_dir/devices-poll.txt" 2>&1 || true
  "$adb" mdns services > "$log_dir/mdns-poll.txt" 2>&1 || true
  ADB="$adb" NEBULA_ADB_MODEL="$expected_model" ./scripts/resolve-rm11-adb-serial.sh --prefer-wireless --env \
    > "$log_dir/resolve-last.env" 2>"$log_dir/resolve-last.err" || true
  candidate="$(awk -F= '$1 == "ADB_SERIAL" { print $2; exit }' "$log_dir/resolve-last.env" 2>/dev/null || true)"
  if [ -n "$candidate" ]; then
    adb_state="$("$adb" -s "$candidate" get-state 2>/dev/null | tr -d '\r' || true)"
    boot="$("$adb" -s "$candidate" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    model="$("$adb" -s "$candidate" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
    printf 'poll=%s\tserial=%s\tstate=%s\tmodel=%s\tboot=%s\n' "$i" "$candidate" "$adb_state" "$model" "$boot" \
      | tee -a "$log_dir/reboot-poll.tsv"
    if [ "$boot" = "1" ]; then
      resolved="$candidate"
      break
    fi
  else
    printf 'poll=%s\tserial=unresolved\tboot=unknown\n' "$i" | tee -a "$log_dir/reboot-poll.tsv"
  fi
  sleep 5
done

if [ -z "$resolved" ]; then
  echo "POST_REBOOT_ADB_UNRESOLVED" | tee "$log_dir/failure.txt"
  classification="$(classify_recovery)"
  printf 'classification=%s\n' "$classification" | tee -a "$log_dir/reboot-start.txt"
  printf 'end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$log_dir/reboot-start.txt"
  exit "$(classification_exit_code "$classification")"
fi

printf '%s\n' "$resolved" > "$log_dir/post-serial.txt"
printf 'post_serial=%s\n' "$resolved"
"$adb" -s "$resolved" get-state | tee "$log_dir/post-adb-state.txt"
"$adb" -s "$resolved" shell getprop sys.boot_completed | tee "$log_dir/post-boot-completed.txt"
"$adb" -s "$resolved" shell getprop ro.product.model | tee "$log_dir/post-model.txt"
"$adb" -s "$resolved" shell \
  'settings get global adb_enabled; settings get global adb_wifi_enabled; settings get global enable_wireless_switch' \
  | tee "$log_dir/post-adb-wifi-settings.txt"
shell_su_diagnostic "$resolved" "$log_dir/post-shell-su-diagnostic.txt"

app_su "$resolved" "$module_cli status --json" \
  | tee "$log_dir/post-core-status-app-su.json"
app_su "$resolved" "$module_cli adb-wifi status --json" \
  | tee "$log_dir/post-adb-wifi-status-app-su.json"
app_su "$resolved" "$module_cli legacy modules --json" \
  | tee "$log_dir/post-legacy-modules-app-su.json"
app_su "$resolved" "$module_cli cooling policy --json" \
  | tee "$log_dir/post-cooling-policy-app-su.json"
app_su "$resolved" "tail -n 160 /data/adb/nebula/logs/nebula-core.log" \
  | tee "$log_dir/post-nebula-core-log-app-su.txt" || true

classification="$(classify_recovery)"
printf 'classification=%s\n' "$classification" | tee -a "$log_dir/reboot-start.txt"
classification_rc="$(classification_exit_code "$classification")"

if [ "$with_app_ui" != "1" ]; then
  printf 'end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$log_dir/reboot-start.txt"
  exit "$classification_rc"
fi

"$adb" -s "$resolved" shell su -c \
  'ls -ld /data/adb/modules/nebula_core /data/adb/modules_update/nebula_core /data/adb/modules/droidspaces /data/adb/modules/rm11-droidspace-bridge-fd 2>/dev/null; ls -l /data/adb/modules/droidspaces/disable /data/adb/modules/rm11-droidspace-bridge-fd/disable /data/adb/modules/nebula_core/disable 2>/dev/null' \
  > "$log_dir/post-module-paths-shell-su-diagnostic.txt" 2>&1 || true

"$adb" -s "$resolved" shell am force-stop io.droidspaces.nebula || true
"$adb" -s "$resolved" shell logcat -c || true
"$adb" -s "$resolved" shell am start -n io.droidspaces.nebula/.MainActivity | tee "$log_dir/app-start.txt"
sleep 5
"$adb" -s "$resolved" shell pidof io.droidspaces.nebula | tee "$log_dir/app-pid.txt"
"$adb" -s "$resolved" shell logcat -d -t 900 \
  | grep -iE 'io.droidspaces.nebula|FATAL EXCEPTION|AndroidRuntime|nebula-core|Cannot run|Permission|denied|avc' \
  | tail -180 | tee "$log_dir/app-log-filtered.txt" || true

"$adb" -s "$resolved" shell uiautomator dump /sdcard/nebula-reboot-ui.xml >/tmp/nebula-reboot-ui.out 2>&1 || true
"$adb" -s "$resolved" shell cat /sdcard/nebula-reboot-ui.xml > "$log_dir/app-home-ui.xml" 2>/dev/null || true
python3 - "$log_dir/app-home-ui.xml" <<'PY' | tee "$log_dir/app-home-text.txt"
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text(errors="ignore")
for match in re.finditer(r'text="([^"]*)"', text):
    value = match.group(1)
    if value:
        print(value)
PY

printf 'end_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$log_dir/reboot-start.txt"
exit "$classification_rc"
