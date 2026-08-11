#!/system/bin/sh
# deadhand - starts the panic daemon at boot (late_start service).
MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"

ensure_state

# Launch the daemon detached. It only TRIGGERS if ARMED=1 in the config;
# installed disarmed and in DRY_RUN, so starting it here is safe.
( run_daemon ) &
