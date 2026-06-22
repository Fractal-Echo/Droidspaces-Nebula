#!/system/bin/sh
DATA_DIR=/data/adb/nebula

while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
  sleep 2
done

mkdir -p "$DATA_DIR/logs" "$DATA_DIR/state"
printf '%s\n' "$$" > "$DATA_DIR/state/service.pid"
printf '%s service ready\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" >> "$DATA_DIR/logs/nebula-core.log"
