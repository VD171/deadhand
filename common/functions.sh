# deadhand - function library (POSIX sh / busybox).
#
# ##########################################################################
# #  WARNING: this module WIPES THE DEVICE. The functions below destroy    #
# #  data IRREVERSIBLY. Do not call do_wipe/crypto_shred by hand unless     #
# #  you understand exactly what they do.                                   #
# ##########################################################################
#
# Trigger: KEY_VOLUMEDOWN pressed 4x rapidly.  Abort: KEY_VOLUMEUP.
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
# Trigger: Volume-Down (VOL-) pressed 4x rapidly.  Cancel: Volume-Up (VOL+).
#
# ARMED : 0 = disarmed (the 4x VOL- does NOTHING). 1 = armed.
#         Prefer arming/disarming from the manager Action button (Magisk/KSU).
# DRY_RUN : 1 = simulate (only vibrates and logs "WOULD WIPE NOW"; no wipe).
#           0 = LIVE MODE. The 4x VOL- WIPES the device.
# WINDOW_MS : total window for the 4 presses, in milliseconds.
# DEBOUNCE_MS : ignore presses closer together than this (button bounce guard).
# ABORT_SECONDS : window to CANCEL with VOL+ after the 4th press.
#                 0 disables cancellation (not recommended).
# WIPE_REASON : label written into the recovery command (trace in the wipe log).
#
# Changed WINDOW_MS/DEBOUNCE_MS/ABORT_SECONDS? reboot (the daemon reads these
# at start). ARMED and DRY_RUN are read on every trigger (they take effect live).

ARMED=0
DRY_RUN=1
WINDOW_MS=1500
DEBOUNCE_MS=120
ABORT_SECONDS=5
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

# Clock in milliseconds, tolerant of busybox/toybox without %N support.
now_ms() {
  n=$(date +%s%N 2>/dev/null)
  case "${n}" in
    ""|*[!0-9]*) echo $(( $(date +%s) * 1000 ));;
    *)           echo $(( n / 1000000 ));;
  esac
}

# ---------------------------------------------------------------------------
# Key detection
# ---------------------------------------------------------------------------

# List the /dev/input/eventN nodes that advertise KEY_VOLUMEDOWN (diagnostic;
# the daemon reads ALL nodes, this is only logged at startup).
list_voldown_nodes() {
  getevent -lp 2>/dev/null | awk '
    /add device [0-9]+:/    { path=$4 }
    /KEY_VOLUMEDOWN/ && path { print path; path="" }
  '
}

# Haptic feedback, best effort (varies by device).
vibrate() {
  ms="${1:-200}"
  echo "${ms}" > /sys/class/timed_output/vibrator/enable 2>/dev/null && return 0
  echo "${ms}" > /sys/class/leds/vibrator/duration 2>/dev/null
  echo 1       > /sys/class/leds/vibrator/activate 2>/dev/null
}

# Cancellation window. Returns 0 if the user cancelled (VOL+),
# 1 if the countdown ended without cancellation (proceed to the wipe).
abort_wait() {
  s="${ABORT_SECONDS:-5}"
  case "${s}" in ""|*[!0-9]*) s=0;; esac
  [ "${s}" -gt 0 ] || return 1
  log "abort window: ${s}s (press VOL+ to cancel)"
  vibrate 400
  if timeout "${s}" getevent -lq 2>/dev/null | grep -m1 -qE 'KEY_VOLUMEUP.*DOWN'; then
    return 0
  fi
  return 1
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

# Called when the 4x VOL- is detected within the window.
trigger_sequence() {
  # Read fresh ARMED/DRY_RUN/ABORT_SECONDS from disk (they take effect live).
  . "${CONFIG}" 2>/dev/null
  if [ "${ARMED}" != "1" ]; then
    log "4x VOL- pattern seen, but DISARMED - ignored"
    return 0
  fi
  log "TRIGGER: 4x VOL- detected (armed)"
  vibrate 300
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY_RUN=1 -> WOULD WIPE NOW (no action taken)"
    vibrate 120; vibrate 120
    return 0
  fi
  if abort_wait; then
    log "ABORTED by user during the cancellation window"
    vibrate 120
    return 0
  fi
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
  log "daemon started (pid $$); VOL- nodes: $(list_voldown_nodes | tr '\n' ' ')"

  while : ; do
    # Read ALL input devices and filter for KEY_VOLUMEDOWN. Reading every node
    # (instead of guessing one) avoids the wrong-node trap: KEY_VOLUMEDOWN is
    # advertised by several devices. Non-matching events (e.g. touch) cost only
    # a case test and never fork, so this stays cheap. The while body runs in
    # the same subshell, so t1..t4 and prev persist across events.
    getevent -lq 2>/dev/null | while IFS= read -r line; do
      case "${line}" in
        *KEY_VOLUMEDOWN*DOWN*) : ;;
        *) continue ;;
      esac
      : "${t1:=0}" "${t2:=0}" "${t3:=0}" "${t4:=0}" "${prev:=0}"

      now=$(now_ms)
      # Debounce.
      if [ "${prev}" -ne 0 ] && [ $(( now - prev )) -lt "${DEBOUNCE_MS}" ]; then
        continue
      fi
      prev="${now}"

      # Sliding window over the last 4 presses.
      t1="${t2}"; t2="${t3}"; t3="${t4}"; t4="${now}"
      if [ "${t1}" -ne 0 ]; then
        span=$(( t4 - t1 ))
        if [ "${span}" -le "${WINDOW_MS}" ]; then
          t1=0; t2=0; t3=0; t4=0
          trigger_sequence
        fi
      fi
    done
    # getevent died (hotplug/error): restart without a busy-loop.
    sleep 2
  done
}
