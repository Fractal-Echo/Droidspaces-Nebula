#!/system/bin/sh
DATA_DIR=/data/adb/nebula

current_bssid() {
  cmd wifi status 2>/dev/null \
    | sed -n 's/.*BSSID: \([0-9A-Fa-f:][0-9A-Fa-f:]*\),.*/\1/p' \
    | head -n 1 \
    | tr -d '\r'
}

valid_bssid() {
  case "$1" in
    [0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f]:[0-9A-Fa-f][0-9A-Fa-f])
      [ "$1" != "02:00:00:00:00:00" ]
      ;;
    *) return 1 ;;
  esac
}

wireless_port() {
  parcel="$(service call adb 10 2>/dev/null | tr -d '\r')"
  value="$(printf '%s\n' "$parcel" | sed -n 's/.*00000000 \([0-9A-Fa-f][0-9A-Fa-f]*\).*/\1/p' | head -n 1)"
  if [ -n "$value" ]; then
    printf '%d' "0x$value" 2>/dev/null && return 0
  fi
  return 2
}

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
    bssid="$(current_bssid)"
    manager=unavailable
    if valid_bssid "$bssid" && service call adb 4 i32 1 s16 "$bssid" >/dev/null 2>&1; then
      manager=allowWirelessDebugging
    fi
    port="$(wireless_port 2>/dev/null || printf 0)"
    if [ -n "$port" ] && [ "$port" -gt 0 ] 2>/dev/null; then
      state=live
    else
      state=manual_toggle_required
    fi
    printf '%s adb wifi auto-enable requested reason=%s manager=%s state=%s port=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$adb_wifi_reason" "$manager" "$state" "$port" >> "$DATA_DIR/logs/nebula-core.log"
  else
    printf '%s adb wifi auto-enable failed reason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" "$adb_wifi_reason" >> "$DATA_DIR/logs/nebula-core.log"
  fi
fi
