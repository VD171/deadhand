###### v0.1.0

- First release of deadhand (fork of nedorazrab0/abootloop).
- Trigger: 4x Power presses (rapid) within a configurable window.
- Action: crypto-shred of the FBE/metadata/keystore keys + factory reset via BCB (recovery).
- Safety rails: ships DISARMED (ARMED=0) and in SIMULATION (DRY_RUN=1);
  VOL+/VOL- abort window; debounce; single-instance daemon.
- Action button arms/disarms and shows state + log.
