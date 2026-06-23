#!/system/bin/sh
DATA_DIR=/data/adb/nebula
mkdir -p "$DATA_DIR/logs" "$DATA_DIR/state"
touch "$DATA_DIR/state/profile"
if [ ! -s "$DATA_DIR/state/profile" ]; then
  printf '%s\n' safe > "$DATA_DIR/state/profile"
fi

if [ -f "$DATA_DIR/state/adb_wifi_auto_enable" ]; then
  (
    attempt=1
    while [ "$attempt" -le 24 ]; do
      if settings get global adb_enabled >/dev/null 2>&1; then
        if settings put global adb_enabled 1 >/dev/null 2>&1 && \
           settings put global adb_wifi_enabled 1 >/dev/null 2>&1 && \
           settings put global enable_wireless_switch 1 >/dev/null 2>&1; then
          printf '%s adb wifi early auto-enable applied attempt=%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" \
            "$attempt" >> "$DATA_DIR/logs/nebula-core.log"
          exit 0
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
