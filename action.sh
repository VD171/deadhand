#!/system/bin/sh
# deadhand - botao Action do gerenciador (Magisk/KSU): arma/desarma e mostra estado.
MODDIR="${0%/*}"
. "${MODDIR}/common/functions.sh"

ensure_state
. "${CONFIG}" 2>/dev/null

echo "==================================================="
echo "  deadhand - WIPE CATASTROFICO E IRREVERSIVEL"
echo "==================================================="

if [ "${ARMED}" = "1" ]; then
  set_cfg ARMED 0
  log "DESARMADO via Action"
  echo "  Estado anterior: ARMADO"
  echo "  >> Agora: DESARMADO. Os 4x Power nao fazem nada."
else
  set_cfg ARMED 1
  log "ARMADO via Action (DRY_RUN=${DRY_RUN})"
  echo "  Estado anterior: desarmado"
  echo "  >> Agora: ARMADO."
  if [ "${DRY_RUN}" = "1" ]; then
    echo "  MODO SIMULACAO (DRY_RUN=1): 4x Power so escreve no log,"
    echo "  NAO apaga. Edite ${CONFIG} e ponha DRY_RUN=0 para o modo real."
  else
    echo "  [!] MODO REAL (DRY_RUN=0): 4x Power VAO APAGAR o aparelho."
    echo "  [!] Janela de aborto: ${ABORT_SECONDS}s (VOL+ ou VOL-)."
  fi
fi

echo "---------------------------------------------------"
echo "  Config: WINDOW_MS=${WINDOW_MS}  DEBOUNCE_MS=${DEBOUNCE_MS}"
echo "          ABORT_SECONDS=${ABORT_SECONDS}  DRY_RUN=${DRY_RUN}"
echo "  Arquivo: ${CONFIG}"
echo "---------------------------------------------------"
echo "  Ultimas linhas do log (${LOG}):"
tail -n 8 "${LOG}" 2>/dev/null | sed 's/^/    /'
echo "==================================================="
