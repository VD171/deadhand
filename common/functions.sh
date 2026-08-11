# deadhand - biblioteca de funcoes (POSIX sh / busybox).
#
# ##########################################################################
# #  ATENCAO: este modulo APAGA O APARELHO. As funcoes abaixo destroem     #
# #  dados de forma IRREVERSIVEL. Nao chame do_wipe/crypto_shred a mao     #
# #  sem entender exatamente o que fazem.                                  #
# ##########################################################################

STATE=/data/adb/deadhand
CONFIG="${STATE}/config"
LOG="${STATE}/deadhand.log"
PIDFILE="${STATE}/daemon.pid"

# ---------------------------------------------------------------------------
# Estado e configuracao
# ---------------------------------------------------------------------------

log() {
  # Log datado. Mantem no maximo ~500 linhas para nao crescer sem limite.
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
# deadhand - configuracao de runtime.
# ##########################################################################
# #  MODULO DE WIPE CATASTROFICO. Ler o README antes de mexer aqui.        #
# ##########################################################################
#
# ARMED : 0 = desarmado (os 4x Power nao fazem NADA). 1 = armado.
#         Prefira armar/desarmar pelo botao Action do gerenciador (Magisk/KSU).
# DRY_RUN : 1 = simula (so vibra e escreve no log "APAGARIA AGORA"; nao apaga).
#           0 = MODO REAL. Os 4x Power APAGAM o aparelho.
# WINDOW_MS : janela total para os 4 toques, em milissegundos.
# DEBOUNCE_MS : ignora toques mais juntos que isto (anti-repique do botao).
# ABORT_SECONDS : janela para CANCELAR com VOL+ ou VOL- depois do 4o toque.
#                 0 desliga o cancelamento (nao recomendado).
# WIPE_REASON : rotulo gravado no comando de recovery (rastro no log do wipe).
#
# Alterou WINDOW_MS/DEBOUNCE_MS/ABORT_SECONDS? reinicie o aparelho (o daemon le
# esses valores ao subir). ARMED e DRY_RUN sao lidos a cada disparo (valem na hora).

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

# set_cfg CHAVE VALOR  -> grava/atualiza a chave no arquivo de config
set_cfg() {
  k="$1"; v="$2"
  ensure_state
  if grep -q "^${k}=" "${CONFIG}" 2>/dev/null; then
    sed -i "s/^${k}=.*/${k}=${v}/" "${CONFIG}"
  else
    echo "${k}=${v}" >> "${CONFIG}"
  fi
}

# Relogio em milissegundos, tolerante a busybox/toybox sem %N.
now_ms() {
  n=$(date +%s%N 2>/dev/null)
  case "${n}" in
    ""|*[!0-9]*) echo $(( $(date +%s) * 1000 ));;
    *)           echo $(( n / 1000000 ));;
  esac
}

# ---------------------------------------------------------------------------
# Deteccao de teclas
# ---------------------------------------------------------------------------

# Descobre os nos /dev/input/eventN que anunciam KEY_POWER.
get_pow_nodes() {
  getevent -lp 2>/dev/null | awk '
    /add device [0-9]+:/ { path=$4 }
    /KEY_POWER/ && path   { print path; path="" }
  '
}

# Feedback tatil, melhor esforco (varia por aparelho).
vibrate() {
  ms="${1:-200}"
  echo "${ms}" > /sys/class/timed_output/vibrator/enable 2>/dev/null && return 0
  echo "${ms}" > /sys/class/leds/vibrator/duration 2>/dev/null
  echo 1       > /sys/class/leds/vibrator/activate 2>/dev/null
}

# Janela de cancelamento. Retorna 0 se o usuario cancelou (VOL+/VOL-),
# 1 se a contagem terminou sem cancelamento (segue para o wipe).
abort_wait() {
  s="${ABORT_SECONDS:-5}"
  case "${s}" in ""|*[!0-9]*) s=0;; esac
  [ "${s}" -gt 0 ] || return 1
  log "janela de aborto: ${s}s (VOL+ ou VOL- cancela)"
  vibrate 400
  if timeout "${s}" getevent -lq 2>/dev/null | grep -m1 -qE 'KEY_VOLUME(UP|DOWN).*DOWN'; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Destruicao dos dados (IRREVERSIVEL)
# ---------------------------------------------------------------------------

# Crypto-shred: destroi o material de chave da criptografia (FBE + metadata +
# gatekeeper/keystore). Em aparelhos criptografados isso torna o userdata
# ilegivel na hora, sem depender de sobrescrever o flash (que e' incompleto por
# wear-leveling). E' o "cinto" que garante irreversibilidade mesmo que o wipe
# do recovery seja interrompido.
crypto_shred() {
  log "crypto-shred: destruindo chaves FBE/metadata/keystore"
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

# Localiza a particao 'misc' (bloco de controle do bootloader / BCB).
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

# Escreve no BCB o comando "boot-recovery" + "--wipe_data". No proximo boot o
# recovery faz o factory reset (em FBE, isso descarta as chaves de classe).
# Layout do bootloader_message: command[32], status[32], recovery[768...].
write_bcb() {
  misc=$(find_misc) || return 1
  tmp="${STATE}/bcb.img"
  {
    printf 'boot-recovery'                # 13 bytes
    dd if=/dev/zero bs=1 count=19 2>/dev/null   # completa command[32]
    dd if=/dev/zero bs=1 count=32 2>/dev/null   # status[32]
    printf 'recovery\n--wipe_data\n--reason=%s\n' "${WIPE_REASON:-deadhand}"
  } > "${tmp}" 2>/dev/null
  dd if="${tmp}" of="${misc}" bs=1 conv=notrunc 2>/dev/null || { rm -f "${tmp}"; return 1; }
  rm -f "${tmp}" 2>/dev/null
  log "BCB gravado em ${misc}"
  return 0
}

do_reboot_recovery() {
  sync
  reboot recovery 2>/dev/null \
    || svc power reboot recovery 2>/dev/null \
    || /system/bin/reboot recovery 2>/dev/null \
    || setprop sys.powerctl reboot,recovery 2>/dev/null
}

# Sequencia catastrofica: mata as chaves, arma o recovery e reinicia.
do_wipe() {
  log "!!! EXECUTANDO WIPE !!!"
  crypto_shred
  if write_bcb; then
    log "rebootando para o recovery (factory reset)"
    do_reboot_recovery
  else
    log "misc/BCB indisponivel - fallback /cache + framework"
    mkdir -p /cache/recovery 2>/dev/null
    printf -- '--wipe_data\n--reason=%s\n' "${WIPE_REASON:-deadhand}" \
      > /cache/recovery/command 2>/dev/null
    sync
    am broadcast -a android.intent.action.FACTORY_RESET \
      --receiver-permission android.permission.MASTER_CLEAR -p android 2>/dev/null
    do_reboot_recovery
  fi
}

# Chamado quando os 4x Power sao detectados dentro da janela.
trigger_sequence() {
  # Le ARMED/DRY_RUN/ABORT_SECONDS frescos do disco (valem na hora).
  . "${CONFIG}" 2>/dev/null
  if [ "${ARMED}" != "1" ]; then
    log "padrao 4x Power visto, mas DESARMADO - ignorado"
    return 0
  fi
  log "GATILHO: 4x Power detectado (armado)"
  vibrate 300
  if [ "${DRY_RUN}" = "1" ]; then
    log "DRY_RUN=1 -> APAGARIA AGORA (nenhuma acao tomada)"
    vibrate 120; vibrate 120
    return 0
  fi
  if abort_wait; then
    log "ABORTADO pelo usuario na janela de cancelamento"
    vibrate 120
    return 0
  fi
  do_wipe
}

# ---------------------------------------------------------------------------
# Daemon persistente
# ---------------------------------------------------------------------------

run_daemon() {
  ensure_state
  . "${CONFIG}" 2>/dev/null

  # Instancia unica.
  if [ -f "${PIDFILE}" ] && kill -0 "$(cat "${PIDFILE}" 2>/dev/null)" 2>/dev/null; then
    log "daemon ja rodando (pid $(cat "${PIDFILE}")) - saindo"
    return 0
  fi
  echo $$ > "${PIDFILE}"
  log "daemon iniciado (pid $$)"

  while : ; do
    node=$(get_pow_nodes | head -n1)   # vazio = monitora todos os nos
    # Fluxo continuo de eventos. O corpo do while roda no mesmo subshell,
    # entao t1..t4 e prev persistem entre os eventos.
    getevent -lq ${node} 2>/dev/null | while read -r line; do
      case "${line}" in
        *KEY_POWER*DOWN*) : ;;
        *) continue ;;
      esac
      : "${t1:=0}" "${t2:=0}" "${t3:=0}" "${t4:=0}" "${prev:=0}"

      now=$(now_ms)
      # Anti-repique.
      if [ "${prev}" -ne 0 ] && [ $(( now - prev )) -lt "${DEBOUNCE_MS}" ]; then
        continue
      fi
      prev="${now}"

      # Janela deslizante dos ultimos 4 toques.
      t1="${t2}"; t2="${t3}"; t3="${t4}"; t4="${now}"
      if [ "${t1}" -ne 0 ]; then
        span=$(( t4 - t1 ))
        if [ "${span}" -le "${WINDOW_MS}" ]; then
          t1=0; t2=0; t3=0; t4=0
          trigger_sequence
        fi
      fi
    done
    # getevent caiu (hotplug/erro): recomeca sem busy-loop.
    sleep 2
  done
}
