#!/system/bin/sh
# deadhand - garante o diretorio de estado/config cedo no boot.
# NAO dispara nada aqui: o gatilho e' so pelo daemon do service.sh.
MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"
ensure_state
