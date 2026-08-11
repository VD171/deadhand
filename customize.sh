# deadhand - instalacao. Nao pede nada; instala DESARMADO e em DRY_RUN.
SKIPUNZIP=0

ui_print ""
ui_print "  ###############################################"
ui_print "  #                                             #"
ui_print "  #            d e a d h a n d                  #"
ui_print "  #        panic wipe / dead-man switch         #"
ui_print "  #                                             #"
ui_print "  ###############################################"
ui_print ""
ui_print "  [!] ATENCAO - LEIA COM CUIDADO"
ui_print ""
ui_print "  Este modulo APAGA O APARELHO quando o botao"
ui_print "  Power e' pressionado 4x rapidamente."
ui_print ""
ui_print "  O resultado e' CATASTROFICO e IRREVERSIVEL:"
ui_print "  crypto-shred das chaves + factory reset."
ui_print "  NAO ha desfazer. NAO ha recuperacao."
ui_print ""
ui_print "  Por seguranca ele nasce:"
ui_print "    - DESARMADO (ARMED=0): 4x Power nao faz nada"
ui_print "    - em SIMULACAO (DRY_RUN=1): so escreve no log"
ui_print ""
ui_print "  Para usar de verdade voce precisa, de proposito:"
ui_print "    1) Armar (botao Action no gerenciador)"
ui_print "    2) Testar em DRY_RUN e conferir o log"
ui_print "    3) So entao por DRY_RUN=0 no config"
ui_print ""
ui_print "  Config: /data/adb/deadhand/config"
ui_print "  Log:    /data/adb/deadhand/deadhand.log"
ui_print ""
ui_print "  Faca BACKUP do que importa ANTES de armar."
ui_print ""

# Cria estado/config padrao (desarmado + dry-run).
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

ui_print "  Instalado DESARMADO. Reinicie para carregar o daemon."
ui_print ""
