###### v0.2.0

- **Trigger changed from Power to Volume-Down (VOL-) 4x.** On Android 12+ rapid
  Power presses are grabbed by the OS Emergency SOS feature (which pops the
  emergency dialer and competes for the presses), so Power is unreliable and
  unsafe as a trigger. Volume-Down avoids that entirely and does not blank the
  screen. Cancel key is now VOL+.
- Detection now reads ALL input nodes instead of guessing one, fixing the
  wrong-node trap (KEY_VOLUMEDOWN is advertised by several devices; the real
  physical keys live on a specific node). Non-matching events never fork, so it
  stays cheap.

###### v0.1.0

- First release of deadhand (fork of nedorazrab0/abootloop).
- Trigger: 4x Power presses (rapid) within a configurable window.
- Action: crypto-shred of the FBE/metadata/keystore keys + factory reset via BCB (recovery).
- Safety rails: ships DISARMED (ARMED=0) and in SIMULATION (DRY_RUN=1);
  abort window; debounce; single-instance daemon.
- Action button arms/disarms and shows state + log.
