# deadhand

> Fork of [nedorazrab0/abootloop](https://github.com/Magisk-Modules-Alt-Repo/abootloop) (MIT).
> Magisk / KernelSU module. One single function: **wipe the device** when you
> **hold Volume-Down + Volume-Up together for 5 seconds**.

---

## AVISO / WARNING - READ THIS BEFORE ANYTHING ELSE

**This module destroys ALL data on the device. The result is CATASTROPHIC and IRREVERSIBLE.**

- There is no "undo".
- There is no data recovery after it fires: the encryption keys are destroyed, so the
  content becomes mathematical noise. Not even forensics gets it back.
- An accidental trigger costs exactly what a real one does: **a wiped device**.
- Treat this module with the same respect as a tool that erases disks. Because that is what
  it is.

If you are not **absolutely certain** you want this, **do not arm it and do not switch it to
live mode.** You are the only person responsible for what happens to your device.

**Back up anything that matters BEFORE arming.** Afterwards you cannot.

---

## What it does

When **armed** and in **live mode**, upon detecting **Volume-Down and Volume-Up held together
for HOLD_SECONDS** (default 5 s), deadhand:

1. **Crypto-shred**: overwrites and deletes the Android encryption key material
   (FBE in `/data/misc/vold`, metadata key in `/metadata`, keystore, gatekeeper).
   This makes `userdata` unreadable **instantly**, irreversibly.
2. **Factory reset**: writes the `--wipe_data` command into the BCB (bootloader control
   block, `misc` partition) and reboots into recovery, which formats `userdata`.

Releasing either key before the time is up **cancels** it. The hold itself is the
change-your-mind window.

### Why this way, and not "overwrite with dd"

On modern storage (eMMC/UFS with wear-leveling and overprovisioning) overwriting the
partition does **not** guarantee erasure: physical copies remain out of `dd`'s reach, it is
slow, and it wears the flash. On Android 10+ (FBE / metadata encryption) the **quality**
path is **crypto-shred**: destroy the AES keys wrapped by the TEE. With no key, the
ciphertext is unrecoverable in the same instant. The factory reset comes in as a second
mechanism (what the system calls "erase everything"). Belt and suspenders.

### Why a two-key hold, and not Power

The trigger is a Volume combo on purpose. On Android 12+ the OS grabs **rapid Power presses**
for its **Emergency SOS** feature: pressing Power several times fast pops the emergency
dialer (and can place an emergency call). So the system competes for the presses and Power is
both unreliable and dangerous as a wipe trigger. The Volume keys are not intercepted, do not
blank the screen, and read cleanly. A sustained **two-button hold** is also far harder to hit
by accident than any single-button gesture.

---

## Safety rails (all on by default)

Because the action is irreversible, the module ships **locked** and requires deliberate
steps to become dangerous:

| Rail | Default | What it does |
|---|---|---|
| **Disarmed** (`ARMED=0`) | on | Holding the combo does **nothing**. You must arm it on purpose. |
| **Simulation** (`DRY_RUN=1`) | on | Even armed, the combo only **vibrates and logs** "WOULD WIPE NOW". No wipe. |
| **Two-button hold** (`HOLD_SECONDS=5`) | on | Needs **both** Volume keys held **together** for the full time. Release either to cancel. |

For the module to actually wipe you must, **on purpose**: arm it **and** set `DRY_RUN=0`.
Two separate switches, so that no single accident is enough.

The device vibrates once when it sees both keys go down (your cue that the hold has started).
If you keep holding for the full time it vibrates again and fires. Let go to cancel.

---

## Installation

1. Install the zip via Magisk or KernelSU (Modules > Install from storage).
2. Reboot. The daemon starts on its own at boot (but **disarmed** and in **simulation**).

It asks nothing at install time and touches nothing until it is armed.

---

## Usage (in order, do not skip a step)

### 1. Test in simulation (mandatory before live mode)

1. Arm it with the **Action** button on the module screen in the manager (Magisk/KSU).
   Since `DRY_RUN=1`, this is safe.
2. Hold Volume-Down + Volume-Up together for 5 seconds.
3. Check the log:

   ```
   su -c 'tail -f /data/adb/deadhand/deadhand.log'
   ```

   You should see `WOULD WIPE NOW (no action taken)`. If it shows up, detection works on
   **your** device. If it does not, check the log for the "hold ... to trigger" line and
   adjust `HOLD_SECONDS`, then test again. **Never** switch to live mode without seeing the
   trigger in the log in simulation.

### 2. Switch to live mode (dangerous)

Only after validating in simulation:

```sh
su -c 'sed -i "s/^DRY_RUN=.*/DRY_RUN=0/" /data/adb/deadhand/config'
```

From here on, with the module **armed**, holding the combo for HOLD_SECONDS **wipes the
device**.

### 3. Arm / disarm day to day

Use the **Action** button on the module screen (Magisk/KSU). It toggles armed/disarmed and
shows the current state + the last log lines. Keep it **disarmed** whenever you are not in a
situation that justifies the risk.

---

## Configuration

File: `/data/adb/deadhand/config`

| Key | Default | Description |
|---|---|---|
| `ARMED` | `0` | `1` arms. Prefer the Action button. |
| `DRY_RUN` | `1` | `1` simulates (only logs). `0` = **live mode, wipes**. |
| `HOLD_SECONDS` | `5` | How long both Volume keys must be held together to fire. |
| `WIPE_REASON` | `deadhand` | Label written into the recovery command. |

`ARMED` and `DRY_RUN` take effect live. Changed `HOLD_SECONDS`? reboot (the daemon reads it at boot).

---

## How to cancel

Release **either** Volume key before HOLD_SECONDS is up. The wipe only starts once both keys
have been held together for the full time; after that point it **cannot be stopped**.

---

## Uninstall

Remove the module from the manager and reboot. Optionally, wipe the state:

```sh
su -c 'rm -rf /data/adb/deadhand'
```

---

## Limitations and responsibility

- Key detection relies on `getevent`; **always** test in simulation on your device before
  going live. The daemon reads all input nodes, so it does not depend on guessing which node
  carries the Volume keys.
- Screen-off deep sleep can delay a userspace daemon; validating the gesture in DRY_RUN on
  your own device (including with the screen off) is the way to confirm it behaves there.
- BCB writing and crypto-shred vary by manufacturer/ROM. Crypto-shred already makes the data
  unrecoverable even if the recovery factory reset fails.
- There is no warranty of any kind (see LICENSE). Use is **at your own risk**. The author is
  not responsible for data loss, misuse, or accidental triggering.
- Do not install this on a device that is not yours, nor on someone else's device without
  their explicit, informed consent.

---

## Credits

Fork of **abootloop** by [nedorazrab0](https://github.com/Magisk-Modules-Alt-Repo/abootloop),
under the MIT license. The `getevent` key-detection scaffold comes from there; the two-key
hold trigger, the crypto-shred, the factory reset and the safety rails belong to this fork.
