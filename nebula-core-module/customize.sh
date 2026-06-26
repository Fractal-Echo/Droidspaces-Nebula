#!/system/bin/sh
MODDIR=""
for candidate in "$MODPATH" /data/adb/modules_update/nebula_core /data/adb/modules/nebula_core; do
  if [ -n "$candidate" ] && [ -d "$candidate" ]; then
    MODDIR="$candidate"
    break
  fi
done

if [ -z "$MODDIR" ]; then
  ui_print "Nebula Core install path not found."
  exit 1
fi

set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm "$MODDIR/bin/nebula-core" 0 0 0755
ui_print "Droidspaces: Nebula Core installed with all controls disabled by default."
