#!/system/bin/sh
DATA_DIR=/data/adb/nebula

while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
  sleep 2
done

mkdir -p "$DATA_DIR/logs" "$DATA_DIR/state"
printf '%s\n' "$$" > "$DATA_DIR/state/service.pid"
printf '%s service ready\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" >> "$DATA_DIR/logs/nebula-core.log"

adb_wifi_reason=
if [ -f "$DATA_DIR/state/adb_wifi_auto_enable" ]; then
  adb_wifi_reason=state_flag
elif [ "$(settings get global enable_wireless_switch 2>/dev/null | tr -d '\r')" = "1" ]; then
  adb_wifi_reason=ui_switch_setting
elif [ "$(settings get global adb_wifi_enabled 2>/dev/null | tr -d '\r')" = "1" ]; then
  adb_wifi_reason=android_setting
fi

if [ -n "$adb_wifi_reason" ]; then
  if settings put global adb_enabled 1 >/dev/null 2>&1 && \
     settings put global adb_wifi_enabled 1 >/dev/null 2>&1 && \
     settings put global enable_wireless_switch 1 >/dev/null 2>&1; then
    printf '%s adb wifi auto-enable applied reason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$adb_wifi_reason" >> "$DATA_DIR/logs/nebula-core.log"
  else
    printf '%s adb wifi auto-enable failed reason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$adb_wifi_reason" >> "$DATA_DIR/logs/nebula-core.log"
  fi
fi
