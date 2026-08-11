# deadhand - installation. Asks nothing; installs DISARMED and in DRY_RUN.
SKIPUNZIP=0

ui_print ""
ui_print "  ###############################################"
ui_print "  #                                             #"
ui_print "  #            d e a d h a n d                  #"
ui_print "  #        panic wipe / dead-man switch         #"
ui_print "  #                                             #"
ui_print "  ###############################################"
ui_print ""
ui_print "  [!] WARNING - READ CAREFULLY"
ui_print ""
ui_print "  This module WIPES THE DEVICE when the Power"
ui_print "  button is pressed 4x rapidly."
ui_print ""
ui_print "  The result is CATASTROPHIC and IRREVERSIBLE:"
ui_print "  crypto-shred of the keys + factory reset."
ui_print "  There is NO undo. There is NO recovery."
ui_print ""
ui_print "  For safety it ships:"
ui_print "    - DISARMED (ARMED=0): 4x Power does nothing"
ui_print "    - in SIMULATION (DRY_RUN=1): only logs"
ui_print ""
ui_print "  To use it for real you must, on purpose:"
ui_print "    1) Arm it (Action button in the manager)"
ui_print "    2) Test in DRY_RUN and check the log"
ui_print "    3) Only then set DRY_RUN=0 in the config"
ui_print ""
ui_print "  Config: /data/adb/deadhand/config"
ui_print "  Log:    /data/adb/deadhand/deadhand.log"
ui_print ""
ui_print "  BACK UP anything that matters BEFORE arming."
ui_print ""

# Create default state/config (disarmed + dry-run).
mkdir -p /data/adb/deadhand 2>/dev/null
chmod 700 /data/adb/deadhand 2>/dev/null
if [ ! -f /data/adb/deadhand/config ]; then
  cat > /data/adb/deadhand/config <<'EOF'
ARMED=0
DRY_RUN=1
WINDOW_MS=1500
DEBOUNCE_MS=120
ABORT_SECONDS=5
WIPE_REASON=deadhand
EOF
  chmod 600 /data/adb/deadhand/config 2>/dev/null
fi

set_perm_recursive "${MODPATH}" 0 0 0755 0644
set_perm "${MODPATH}/service.sh"      0 0 0755
set_perm "${MODPATH}/post-fs-data.sh" 0 0 0755
set_perm "${MODPATH}/action.sh"       0 0 0755
set_perm "${MODPATH}/common/functions.sh" 0 0 0755

ui_print "  Installed DISARMED. Reboot to load the daemon."
ui_print ""
