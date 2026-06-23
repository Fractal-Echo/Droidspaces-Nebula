#!/usr/bin/env bash
set -u

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
adb="${ADB:-/mnt/c/platform-tools/adb.exe}"
log_dir="${1:-/home/richtofen/.android/repositories/nebula-assets/logs/2026-06-22-nebula-fast-reboot-test-07}"

mkdir -p "$log_dir"
cd "$repo_root" || exit 2

module_cli=/data/adb/modules/nebula_core/bin/nebula-core

app_su() {
  local serial="$1"
  local command="$2"
  "$adb" -s "$serial" shell run-as io.droidspaces.nebula /system/bin/su -c "$command"
}

shell_su_diagnostic() {
  local serial="$1"
  local output="$2"
  "$adb" -s "$serial" shell su -c \
    "id; getenforce; settings get global adb_enabled; settings get global adb_wifi_enabled; $module_cli status --json; $module_cli adb-wifi status --json; tail -n 40 /data/adb/nebula/logs/nebula-core.log" \
    > "$output" 2>&1 || true
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

serial="$(./scripts/resolve-rm11-adb-serial.sh)"
printf 'pre_serial=%s\n' "$serial" | tee -a "$log_dir/reboot-start.txt"
"$adb" -s "$serial" get-state | tee "$log_dir/pre-adb-state.txt"
"$adb" -s "$serial" shell getprop sys.boot_completed | tee "$log_dir/pre-boot-completed.txt"
"$adb" -s "$serial" shell \
  'settings get global adb_enabled; settings get global adb_wifi_enabled' \
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
  candidate="$(./scripts/resolve-rm11-adb-serial.sh 2>"$log_dir/resolve-last.err" || true)"
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
  exit 23
fi

printf '%s\n' "$resolved" > "$log_dir/post-serial.txt"
printf 'post_serial=%s\n' "$resolved"
"$adb" -s "$resolved" get-state | tee "$log_dir/post-adb-state.txt"
"$adb" -s "$resolved" shell getprop sys.boot_completed | tee "$log_dir/post-boot-completed.txt"
"$adb" -s "$resolved" shell getprop ro.product.model | tee "$log_dir/post-model.txt"
"$adb" -s "$resolved" shell \
  'settings get global adb_enabled; settings get global adb_wifi_enabled' \
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
