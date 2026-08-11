###### v0.1.0

- Primeiro release do deadhand (fork de nedorazrab0/abootloop).
- Gatilho: 4x no botão Power (rápido) dentro de uma janela configurável.
- Ação: crypto-shred das chaves FBE/metadata/keystore + factory reset via BCB (recovery).
- Freios de segurança: nasce DESARMADO (ARMED=0) e em SIMULAÇÃO (DRY_RUN=1);
  janela de aborto por VOL+/VOL-; anti-repique; instancia única do daemon.
- Botão Action arma/desarma e mostra estado + log.
