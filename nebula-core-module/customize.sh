#!/system/bin/sh
MODDIR=${0%/*}

set_perm_recursive "$MODDIR" 0 0 0755 0644
set_perm "$MODDIR/bin/nebula-core" 0 0 0755
ui_print "Droidspaces: Nebula Core installed with all controls disabled by default."
