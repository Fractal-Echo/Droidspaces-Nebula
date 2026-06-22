#!/system/bin/sh
DATA_DIR=/data/adb/nebula
mkdir -p "$DATA_DIR/logs"
printf '%s module uninstall requested\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)" >> "$DATA_DIR/logs/nebula-core.log"
