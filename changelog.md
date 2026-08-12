###### v0.3.0

- **Trigger changed to a hold-combo: HOLD Volume-Down + Volume-Up together for
  HOLD_SECONDS (default 5s).** Release either key before the time is up to
  cancel. A sustained two-button hold is far harder to hit by accident than a
  tap count, and the hold itself is the change-your-mind window.
- Detection now tracks the pressed state of both keys and measures the hold with
  a `timeout getevent` clock (no events flow during a static hold, so a plain
  event loop cannot time it). A release event within the window cancels.
- Config: `WINDOW_MS`/`DEBOUNCE_MS`/`ABORT_SECONDS` replaced by `HOLD_SECONDS`.
  Existing installs keep their config; `HOLD_SECONDS` defaults to 5 if absent.

###### v0.2.0

- Trigger changed from Power to Volume-Down (VOL-) 4x. On Android 12+ rapid
  Power presses are grabbed by the OS Emergency SOS feature, so Power is
  unreliable and unsafe as a trigger. Detection reads all input nodes instead of
  guessing one.

###### v0.1.0

- First release of deadhand (fork of nedorazrab0/abootloop).
- Trigger: 4x Power presses (rapid) within a configurable window.
- Action: crypto-shred of the FBE/metadata/keystore keys + factory reset via BCB (recovery).
- Safety rails: ships DISARMED (ARMED=0) and in SIMULATION (DRY_RUN=1);
  abort window; debounce; single-instance daemon.
- Action button arms/disarms and shows state + log.
