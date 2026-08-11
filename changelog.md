###### v0.1.0

- Primeiro release do deadhand (fork de nedorazrab0/abootloop).
- Gatilho: 4x no botao Power (rapido) dentro de uma janela configuravel.
- Acao: crypto-shred das chaves FBE/metadata/keystore + factory reset via BCB (recovery).
- Freios de seguranca: nasce DESARMADO (ARMED=0) e em SIMULACAO (DRY_RUN=1);
  janela de aborto por VOL+/VOL-; anti-repique; instancia unica do daemon.
- Botao Action arma/desarma e mostra estado + log.
