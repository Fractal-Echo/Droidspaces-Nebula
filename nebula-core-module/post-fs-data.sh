#!/system/bin/sh
DATA_DIR=/data/adb/nebula
mkdir -p "$DATA_DIR/logs" "$DATA_DIR/state"
touch "$DATA_DIR/state/profile"
if [ ! -s "$DATA_DIR/state/profile" ]; then
  printf '%s\n' safe > "$DATA_DIR/state/profile"
fi
