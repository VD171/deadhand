#!/system/bin/sh
# deadhand - inicia o daemon de panico no boot (late_start service).
MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"

ensure_state

# Sobe o daemon destacado. O daemon so DISPARA se ARMED=1 no config;
# instalado desarmado e em DRY_RUN, entao subir aqui e' seguro.
( run_daemon ) &
