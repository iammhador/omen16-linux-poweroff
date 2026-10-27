# Runbook for Claude: make the HP OMEN 16 (8E35) really power off on Linux

[`README.md`](README.md) explains the cause. This file is the procedure.

## Rules
- The user types the sudo password. Give root commands for them to run **in their own terminal**, not through Claude's `!` prefix (it can't prompt for a password), then check the result yourself.
- Read any third-party code before it runs as root. `scripts/install.sh` pins `jacobdeanpugh/omen16-linux-fix` at `e0de822`, and that installer pins `Adiakys/omen16-s5-fix` at `13740806` with SHA-256 checks. If you move to newer commits, review the diff first.
- Don't use ACPI wake-source tweaks, NVIDIA unload hooks or `reboot=`/`acpi=` kernel options as fixes. They were tested and don't help ([README § 3](README.md#3-things-that-didnt-help-so-dont-repeat-them)).
- Don't claim it works until `omen-drain report` shows a valid window with `OK: really off`.

## Steps
1. **Confirm the hardware:** `cat /sys/class/dmi/id/{board_name,bios_version}`. The board must be `8E35`. If the BIOS is newer than F.13, the ACPI check in step 3 decides whether the fix still applies.
2. **Prerequisites:**
   - NVIDIA proprietary or open driver loaded: `lsmod | grep ^nvidia`
   - Secure Boot off: `bootctl status | grep 'Secure Boot'`
   - Remove any `NVreg_DynamicPowerManagement=0x00` in `/etc/modprobe.d/`, then rebuild the initramfs (`limine-mkinitcpio` on Omarchy)
3. **Install:** the user runs `sudo bash scripts/install.sh`.
   - Every `omen-acpi-check` line must be `PASS`. If any FAILs, stop and read the dump in `~/omen-acpi-dump/`.
   - It must end with `omen_s5: ready`.
4. **Check after a reboot:** `bash scripts/verify.sh`. The module should be loaded and the NVIDIA driver loaded.
5. **Prove it:** ask the user to unplug, run `systemctl poweroff`, leave it off for at least 1 hour, boot unplugged, and then run `~/omen16-linux-fix/bin/omen-drain report`.
   - `invalid: charger connected` or `too short` means repeat the test properly.
   - `OK: really off` (≤ 3 W) means it's done. Update the **Status** line in README.md.
   - `FAIL` (≥ 8 W): check that `journalctl -k -b -1 -g omen_s5` from the shutdown boot showed `ready`, and that the NVIDIA driver was loaded at shutdown. To see the last kernel messages before power-off, use `sudo bash diagnostics/capture-shutdown-log.sh install`.

## Ledger quirks seen on this machine
- A shutdown that never reaches `ExecStop`, such as the battery dying or holding the power button, leaves no `shutdown` row. The next boot pairs with nothing, so there's no window.
- A boot with `ac=1` invalidates the window. The user often plugs in before booting, so remind them to stay unplugged until after logging in.
