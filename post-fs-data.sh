#!/system/bin/sh
# deadhand - make sure the state/config directory exists early at boot.
# Does NOT trigger anything here: the trigger is only via the service.sh daemon.
MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"
ensure_state
