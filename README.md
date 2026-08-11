# deadhand

> Fork of [nedorazrab0/abootloop](https://github.com/Magisk-Modules-Alt-Repo/abootloop) (MIT).
> Magisk / KernelSU module. One single function: **wipe the device** when the
> **Power** button is pressed **4x rapidly**.

---

## AVISO / WARNING - READ THIS BEFORE ANYTHING ELSE

**This module destroys ALL data on the device. The result is CATASTROPHIC and IRREVERSIBLE.**

- There is no "undo".
- There is no data recovery after it fires: the encryption keys are destroyed, so the
  content becomes mathematical noise. Not even forensics gets it back.
- An accidental trigger costs exactly what a real one does: **a wiped device**.
- The Power button gets pressed by accident all day. Treat this module with the same
  respect as a tool that erases disks. Because that is what it is.

If you are not **absolutely certain** you want this, **do not arm it and do not switch it to
live mode.** You are the only person responsible for what happens to your device.

**Back up anything that matters BEFORE arming.** Afterwards you cannot.

---

## What it does

When **armed** and in **live mode**, upon detecting **4 Power presses** within a short
window (default 1.5 s), deadhand:

1. **Crypto-shred**: overwrites and deletes the Android encryption key material
   (FBE in `/data/misc/vold`, metadata key in `/metadata`, keystore, gatekeeper).
   This makes `userdata` unreadable **instantly**, irreversibly.
2. **Factory reset**: writes the `--wipe_data` command into the BCB (bootloader control
   block, `misc` partition) and reboots into recovery, which formats `userdata`.

### Why this way, and not "overwrite with dd"

On modern storage (eMMC/UFS with wear-leveling and overprovisioning) overwriting the
partition does **not** guarantee erasure: physical copies remain out of `dd`'s reach, it is
slow, and it wears the flash. On Android 10+ (FBE / metadata encryption) the **quality**
path is **crypto-shred**: destroy the AES keys wrapped by the TEE. With no key, the
ciphertext is unrecoverable in the same instant. The factory reset comes in as a second
mechanism (what the system calls "erase everything"). Belt and suspenders.

---

## Safety rails (all on by default)

Because the action is irreversible, the module ships **locked** and requires deliberate
steps to become dangerous:

| Rail | Default | What it does |
|---|---|---|
| **Disarmed** (`ARMED=0`) | on | The 4x Power does **nothing**. You must arm it on purpose. |
| **Simulation** (`DRY_RUN=1`) | on | Even armed, the 4x Power only **vibrates and logs** "WOULD WIPE NOW". No wipe. |
| **Abort window** (`ABORT_SECONDS=5`) | on | After the 4th press there are 5 s to **cancel with VOL+ or VOL-**. |
| **Debounce** (`DEBOUNCE_MS=120`) | on | Ignores presses too close together (button bounce) to avoid false counts. |
| **Tight window** (`WINDOW_MS=1500`) | on | The 4 presses must fit in 1.5 s, otherwise the count resets. |

For the module to actually wipe you must, **on purpose**: arm it **and** set `DRY_RUN=0`.
Two separate switches, so that no single accident is enough.

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
2. Press Power 4x rapidly.
3. Check the log:

   ```
   su -c 'tail -f /data/adb/deadhand/deadhand.log'
   ```

   You should see `WOULD WIPE NOW (no action taken)`. If it shows up, detection works on
   **your** device. If it does not, tune `WINDOW_MS`/`DEBOUNCE_MS` in the config and test
   again. **Never** switch to live mode without seeing the trigger in the log in simulation.

### 2. Switch to live mode (dangerous)

Only after validating in simulation:

```sh
su -c 'sed -i "s/^DRY_RUN=.*/DRY_RUN=0/" /data/adb/deadhand/config'
```

From here on, with the module **armed**, 4x Power **wipes the device** (respecting the
abort window).

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
| `WINDOW_MS` | `1500` | Total window for the 4 presses (ms). |
| `DEBOUNCE_MS` | `120` | Ignore presses closer together than this (ms). |
| `ABORT_SECONDS` | `5` | Window to cancel with VOL+/VOL-. `0` disables it (not recommended). |
| `WIPE_REASON` | `deadhand` | Label written into the recovery command. |

`ARMED` and `DRY_RUN` take effect live. Changed the others? reboot (the daemon reads them at boot).

---

## How to cancel a trigger in progress

After the 4th press, while `ABORT_SECONDS` lasts, press **VOL+ or VOL-**. The device
vibrates when it enters the abort window. Once the window passes without a cancel, the wipe
begins and **cannot be stopped**.

---

## Uninstall

Remove the module from the manager and reboot. Optionally, wipe the state:

```sh
su -c 'rm -rf /data/adb/deadhand'
```

---

## Limitations and responsibility

- Key detection relies on `getevent`; **always** test in simulation on your device.
- BCB writing and crypto-shred vary by manufacturer/ROM. Crypto-shred already makes the data
  unrecoverable even if the recovery factory reset fails.
- There is no warranty of any kind (see LICENSE). Use is **at your own risk**. The author is
  not responsible for data loss, misuse, or accidental triggering.
- Do not install this on a device that is not yours, nor on someone else's device without
  their explicit, informed consent.

---

## Credits

Fork of **abootloop** by [nedorazrab0](https://github.com/Magisk-Modules-Alt-Repo/abootloop),
under the MIT license. The `getevent` key-detection scaffold comes from there; the 4x Power
trigger, the crypto-shred, the factory reset and the safety rails belong to this fork.
