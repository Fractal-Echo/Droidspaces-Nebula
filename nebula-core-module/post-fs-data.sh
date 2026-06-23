#!/system/bin/sh
DATA_DIR=/data/adb/nebula
mkdir -p "$DATA_DIR/logs" "$DATA_DIR/state"
touch "$DATA_DIR/state/profile"
if [ ! -s "$DATA_DIR/state/profile" ]; then
  printf '%s\n' safe > "$DATA_DIR/state/profile"
fi

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

if [ -f "$DATA_DIR/state/adb_wifi_auto_enable" ]; then
  (
    attempt=1
    while [ "$attempt" -le 24 ]; do
      if settings get global adb_enabled >/dev/null 2>&1; then
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
            printf '%s adb wifi early auto-enable requested attempt=%s manager=%s state=%s port=%s\n' \
              "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
              "$attempt" "$manager" "$state" "$port" >> "$DATA_DIR/logs/nebula-core.log"
            exit 0
          else
            state=manual_toggle_required
            printf '%s adb wifi early auto-enable requested attempt=%s manager=%s state=%s port=%s\n' \
              "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
              "$attempt" "$manager" "$state" "$port" >> "$DATA_DIR/logs/nebula-core.log"
          fi
        fi
      fi
      attempt=$((attempt + 1))
      sleep 3
    done
    printf '%s adb wifi early auto-enable unavailable\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
      >> "$DATA_DIR/logs/nebula-core.log"
  ) &
fi
