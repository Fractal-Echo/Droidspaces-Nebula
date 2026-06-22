#!/system/bin/sh
DATA_DIR=/data/adb/nebula
SAFE_MODE_FILE="$DATA_DIR/safe_mode"

mkdir -p "$DATA_DIR/logs" "$DATA_DIR/state"
if [ -f "$SAFE_MODE_FILE" ]; then
  rm -f "$SAFE_MODE_FILE"
  printf '%s\n' phone > "$DATA_DIR/state/profile"
  printf 'Nebula Core safe mode disabled\n'
else
  touch "$SAFE_MODE_FILE"
  printf '%s\n' safe > "$DATA_DIR/state/profile"
  printf 'Nebula Core safe mode enabled\n'
fi
