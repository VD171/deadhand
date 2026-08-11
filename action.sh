#!/system/bin/sh
# deadhand - manager Action button (Magisk/KSU): arm/disarm and show state.
MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"

ensure_state
. "${CONFIG}" 2>/dev/null

echo "==================================================="
echo "  deadhand - CATASTROPHIC, IRREVERSIBLE WIPE"
echo "==================================================="

if [ "${ARMED}" = "1" ]; then
  set_cfg ARMED 0
  log "DISARMED via Action"
  echo "  Previous state: ARMED"
  echo "  >> Now: DISARMED. The 4x Power does nothing."
else
  set_cfg ARMED 1
  log "ARMED via Action (DRY_RUN=${DRY_RUN})"
  echo "  Previous state: disarmed"
  echo "  >> Now: ARMED."
  if [ "${DRY_RUN}" = "1" ]; then
    echo "  SIMULATION MODE (DRY_RUN=1): 4x Power only writes to the log,"
    echo "  it does NOT wipe. Edit ${CONFIG} and set DRY_RUN=0 for live mode."
  else
    echo "  [!] LIVE MODE (DRY_RUN=0): 4x Power WILL WIPE the device."
    echo "  [!] Abort window: ${ABORT_SECONDS}s (VOL+ or VOL-)."
  fi
fi

echo "---------------------------------------------------"
echo "  Config: WINDOW_MS=${WINDOW_MS}  DEBOUNCE_MS=${DEBOUNCE_MS}"
echo "          ABORT_SECONDS=${ABORT_SECONDS}  DRY_RUN=${DRY_RUN}"
echo "  File: ${CONFIG}"
echo "---------------------------------------------------"
echo "  Last log lines (${LOG}):"
tail -n 8 "${LOG}" 2>/dev/null | sed 's/^/    /'
echo "==================================================="
