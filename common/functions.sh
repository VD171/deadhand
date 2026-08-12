# deadhand - function library (POSIX sh / busybox).
#
# ##########################################################################
# #  WARNING: this module WIPES THE DEVICE. The functions below destroy    #
# #  data IRREVERSIBLY. Do not call do_wipe/crypto_shred by hand unless     #
# #  you understand exactly what they do.                                   #
# ##########################################################################
#
# Trigger: HOLD Volume-Down + Volume-Up together for HOLD_SECONDS (default 5s).
#          Release either key before the time is up to CANCEL.
# (Volume is used instead of Power because on Android 12+ rapid Power presses
#  are grabbed by the OS Emergency SOS feature; see the README.)

STATE=/data/adb/deadhand
CONFIG="${STATE}/config"
LOG="${STATE}/deadhand.log"
PIDFILE="${STATE}/daemon.pid"

# ---------------------------------------------------------------------------
# State and configuration
# ---------------------------------------------------------------------------

log() {
  # Timestamped log. Keeps at most ~500 lines so it does not grow forever.
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "${LOG}" 2>/dev/null
  if [ -f "${LOG}" ]; then
    lines=$(wc -l < "${LOG}" 2>/dev/null || echo 0)
    if [ "${lines}" -gt 600 ] 2>/dev/null; then
      tail -n 400 "${LOG}" > "${LOG}.tmp" 2>/dev/null && mv "${LOG}.tmp" "${LOG}" 2>/dev/null
    fi
  fi
}

ensure_state() {
  mkdir -p "${STATE}" 2>/dev/null
  chmod 700 "${STATE}" 2>/dev/null
  if [ ! -f "${CONFIG}" ]; then
    cat > "${CONFIG}" <<'EOF'
# deadhand - runtime configuration.
# ##########################################################################
# #  CATASTROPHIC WIPE MODULE. Read the README before touching this.       #
# ##########################################################################
#
# Trigger: HOLD Volume-Down + Volume-Up together for HOLD_SECONDS.
#          Release either key before the time is up to cancel.
#
# ARMED : 0 = disarmed (holding the combo does NOTHING). 1 = armed.
#         Prefer arming/disarming from the manager Action button (Magisk/KSU).
# DRY_RUN : 1 = simulate (only vibrates and logs "WOULD WIPE NOW"; no wipe).
#           0 = LIVE MODE. Holding the combo for HOLD_SECONDS WIPES the device.
# HOLD_SECONDS : how long both keys must be held together to fire.
# WIPE_REASON : label written into the recovery command (trace in the wipe log).
#
# Changed HOLD_SECONDS? reboot (the daemon reads it at start). ARMED and DRY_RUN
# are read on every trigger (they take effect live).

ARMED=0
DRY_RUN=1
HOLD_SECONDS=5
WIPE_REASON=deadhand
EOF
    chmod 600 "${CONFIG}" 2>/dev/null
  fi
}

# set_cfg KEY VALUE  -> write/update the key in the config file
set_cfg() {
  k="$1"; v="$2"
  ensure_state
  if grep -q "^${k}=" "${CONFIG}" 2>/dev/null; then
    sed -i "s/^${k}=.*/${k}=${v}/" "${CONFIG}"
  else
    echo "${k}=${v}" >> "${CONFIG}"
  fi
}

# ---------------------------------------------------------------------------
# Key detection
# ---------------------------------------------------------------------------

# List the /dev/input/eventN nodes that advertise the volume keys (diagnostic;
# the daemon reads ALL nodes, this is only logged at startup).
list_volume_nodes() {
  getevent -lp 2>/dev/null | awk '
    /add device [0-9]+:/                 { path=$4 }
    /KEY_VOLUMEUP|KEY_VOLUMEDOWN/ && path { print path; path="" }
  ' | sort -u
}

# Haptic feedback, best effort (varies by device).
vibrate() {
  ms="${1:-200}"
  echo "${ms}" > /sys/class/timed_output/vibrator/enable 2>/dev/null && return 0
  echo "${ms}" > /sys/class/leds/vibrator/duration 2>/dev/null
  echo 1       > /sys/class/leds/vibrator/activate 2>/dev/null
}

# Both keys are currently down. Wait HOLD_SECONDS; if EITHER volume key is
# released in that time, the user let go -> cancel. If the window elapses with
# no release, the combo was held the whole time -> fire.
# Returns 0 = held the full window (fire), 1 = released early (cancel).
#
# Why a second getevent stream: during a static hold NO events flow, so we
# cannot measure the elapsed time by reading events. `timeout` provides the
# clock; grep provides the early-release abort. evdev broadcasts to every
# reader, so this stream sees the release even though the main loop also reads.
hold_check() {
  hs="${HOLD_SECONDS:-5}"
  case "${hs}" in ""|*[!0-9]*) hs=5;; esac
  if timeout "${hs}" getevent -lq 2>/dev/null \
       | grep -m1 -qE 'KEY_VOLUME(UP|DOWN)[[:space:]]+UP'; then
    return 1   # a release event arrived within the window
  fi
  return 0     # window elapsed with no release -> still held
}

# ---------------------------------------------------------------------------
# Data destruction (IRREVERSIBLE)
# ---------------------------------------------------------------------------

# Crypto-shred: destroys the encryption key material (FBE + metadata +
# gatekeeper/keystore). On encrypted devices this makes userdata unreadable
# instantly, without relying on overwriting the flash (which is incomplete due
# to wear-leveling). This is the "belt" that guarantees irreversibility even if
# the recovery wipe is interrupted.
crypto_shred() {
  log "crypto-shred: destroying FBE/metadata/keystore keys"
  targets="
    /data/misc/vold
    /data/vold
    /metadata/vold
    /data/misc/keystore
    /data/misc/keystore2
    /data/system_de
    /data/system/locksettings.db
    /data/system/locksettings.db-wal
    /data/system/locksettings.db-shm
    /data/system/gatekeeper.password.key
    /data/system/gatekeeper.pattern.key
  "
  for p in ${targets}; do
    [ -e "${p}" ] || continue
    find "${p}" -type f 2>/dev/null | while read -r f; do
      dd if=/dev/urandom of="${f}" bs=4096 count=1 conv=notrunc 2>/dev/null
    done
    rm -rf "${p}" 2>/dev/null
    log "  shredded: ${p}"
  done
  sync
}

# Locate the 'misc' partition (bootloader control block / BCB).
find_misc() {
  for p in \
    /dev/block/by-name/misc \
    /dev/block/bootdevice/by-name/misc \
    /dev/block/platform/*/by-name/misc \
    /dev/block/platform/*/*/by-name/misc ; do
    [ -e "${p}" ] && { echo "${p}"; return 0; }
  done
  return 1
}

# Write "boot-recovery" + "--wipe_data" into the BCB. On the next boot the
# recovery performs the factory reset (on FBE, that discards the class keys).
# bootloader_message layout: command[32], status[32], recovery[768...].
write_bcb() {
  misc=$(find_misc) || return 1
  tmp="${STATE}/bcb.img"
  {
    printf 'boot-recovery'                # 13 bytes
    dd if=/dev/zero bs=1 count=19 2>/dev/null   # pad command[32]
    dd if=/dev/zero bs=1 count=32 2>/dev/null   # status[32]
    printf 'recovery\n--wipe_data\n--reason=%s\n' "${WIPE_REASON:-deadhand}"
  } > "${tmp}" 2>/dev/null
  dd if="${tmp}" of="${misc}" bs=1 conv=notrunc 2>/dev/null || { rm -f "${tmp}"; return 1; }
  rm -f "${tmp}" 2>/dev/null
  log "BCB written to ${misc}"
  return 0
}

do_reboot_recovery() {
  sync
  reboot recovery 2>/dev/null \
    || svc power reboot recovery 2>/dev/null \
    || /system/bin/reboot recovery 2>/dev/null \
    || setprop sys.powerctl reboot,recovery 2>/dev/null
}

# Catastrophic sequence: kill the keys, arm the recovery, reboot.
do_wipe() {
  log "!!! EXECUTING WIPE !!!"
  crypto_shred
  if write_bcb; then
    log "rebooting into recovery (factory reset)"
    do_reboot_recovery
  else
    log "misc/BCB unavailable - falling back to /cache + framework"
    mkdir -p /cache/recovery 2>/dev/null
    printf -- '--wipe_data\n--reason=%s\n' "${WIPE_REASON:-deadhand}" \
      > /cache/recovery/command 2>/dev/null
    sync
    am broadcast -a android.intent.action.FACTORY_RESET \
      --receiver-permission android.permission.MASTER_CLEAR -p android 2>/dev/null
    do_reboot_recovery
  fi
}

# Called when the combo has been held for the full HOLD_SECONDS.
trigger_sequence() {
  # Read fresh ARMED/DRY_RUN from disk (they take effect live).
  . "${CONFIG}" 2>/dev/null
  if [ "${ARMED}" != "1" ]; then
    log "combo held, but DISARMED - ignored"
    return 0
  fi
  log "TRIGGER: combo held for ${HOLD_SECONDS:-5}s (armed)"
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY_RUN=1 -> WOULD WIPE NOW (no action taken)"
    vibrate 120; vibrate 120
    return 0
  fi
  vibrate 600
  do_wipe
}

# ---------------------------------------------------------------------------
# Persistent daemon
# ---------------------------------------------------------------------------

run_daemon() {
  ensure_state
  . "${CONFIG}" 2>/dev/null

  # Single instance.
  if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    log "daemon already running (pid $(cat "${PIDFILE}")) - exiting"
    return 0
  fi
  echo $$ > "${PIDFILE}"
  log "daemon started (pid $$); volume nodes: $(list_volume_nodes | tr '\n' ' ')"

  while : ; do
    # Read ALL input devices and track the pressed state of both volume keys.
    # Reading every node (instead of guessing one) avoids the wrong-node trap:
    # KEY_VOLUME* is advertised by several devices. Non-matching events cost
    # only a case test and never fork. The while body runs in the same subshell,
    # so vd/vu persist across events.
    getevent -lq 2>/dev/null | while IFS= read -r line; do
      case "${line}" in
        *KEY_VOLUMEDOWN*DOWN*) vd=1 ;;
        *KEY_VOLUMEDOWN*UP*)   vd=0 ;;
        *KEY_VOLUMEUP*DOWN*)   vu=1 ;;
        *KEY_VOLUMEUP*UP*)     vu=0 ;;
        *) continue ;;
      esac

      # Both keys down right now? Start the hold check.
      if [ "${vd:-0}" = 1 ] && [ "${vu:-0}" = 1 ]; then
        log "VOL- + VOL+ down; hold ${HOLD_SECONDS:-5}s to trigger (release cancels)"
        vibrate 150
        if hold_check; then
          vd=0; vu=0
          trigger_sequence
        else
          log "combo released early - cancelled"
          vd=0; vu=0
        fi
      fi
    done
    # getevent died (hotplug/error): restart without a busy-loop.
    sleep 2
  done
}
