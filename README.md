# HP OMEN 16 (16-ap0xxx) won't power off on Linux

When you shut down Linux on an **HP OMEN 16-ap0xxx (board 8E35)**, the screen goes black but the laptop doesn't actually turn off. The fans, keyboard backlight and power LED stay on, the chassis gets warm, and the battery drains at about **20–30 W** until you hold the power button. Windows on the same machine shuts down fine.

This repo explains what's really going on, what I tried, and the fix I use now on a **Linux-only** install (Omarchy). The earlier workaround, routing every shutdown through Windows, only worked on dual-boot. It's documented in [docs/legacy-windows-route.md](docs/legacy-windows-route.md).

> **Status: installed and loading, not yet proven.** `omen_s5` reports `ready` on every boot since 2026-10-26. A real overnight battery test (see [Verify](#verify)) hasn't been done yet, so treat this as *expected to work*, based on other owners' measurements of about 21 W → 0.3–2 W, until `omen-drain report` says `OK: really off` on this machine.
>
> **For Claude or another AI agent:** follow [`CLAUDE.md`](CLAUDE.md).

---

## The machine
| | |
|---|---|
| Laptop | HP OMEN Gaming Laptop 16-ap0xxx, board `8E35` |
| BIOS | F.13. HP hasn't fixed this in any BIOS up to F.13. |
| CPU / iGPU | AMD Ryzen 9 8945HX / Radeon 610M |
| dGPU | NVIDIA RTX 5070 Laptop, `nvidia-open` |
| OS | Omarchy (Arch, Hyprland), Limine, LUKS and btrfs, Secure Boot off |

---

## How I narrowed it down

### 1. Did Linux actually finish shutting down? Yes.
The journal of the previous boot showed a normal shutdown, all the way to unmounting the disks. A systemd-shutdown hook that saves `dmesg` at the very last moment ([`diagnostics/capture-shutdown-log.sh`](diagnostics/capture-shutdown-log.sh)) showed the sequence completing. **Linux wasn't hanging**: it handed off to the firmware, and the firmware didn't cut power.

### 2. Is it "S3 instead of S5"? No.
My old notes blamed Linux for entering suspend (S3) instead of power-off (S5). That's not how it works: `systemctl poweroff` always ends in `acpi_power_off()`, which is S5. The battery numbers settled it. About 25–30 W while "off" is a **fully powered GPU**, not a sleeping laptop.

### 3. Things that didn't help (so don't repeat them)
| Attempt | Result |
|---|---|
| Disable every ACPI wake source right before power-off (`/proc/acpi/wakeup`: GPP*, XHC0/1/2, PS2K, TAAD) and every device's `power/wakeup` | No change: the battery went from 100 % to 94 % in about 7 min off |
| Unload `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm` and `nvidia` in a system-shutdown hook | The unload worked (logged), but the laptop still stayed on |
| `NVreg_DynamicPowerManagement=0x00` | No change, and it keeps the dGPU awake during normal use (+8–12 W). **Remove it.** |
| Kernel options `acpi=force`, `reboot=pci`, `reboot=efi` (reported by other owners) | No change |

### 4. Matching the hardware to known reports
Searching the exact board turned up the same symptom, on the same board `8E35`, on the NVIDIA and Arch forums, with a firmware-level root cause and a working fix.

---

## Root cause
Two problems together:

**Problem 1, in Linux.** During `kernel_power_off()`, `device_shutdown()` calls `pci_device_shutdown()` for each device, and that **runtime-resumes the device before shutting it down**. So a dGPU that had powered itself off (D3cold) gets switched fully **back on** moments before S5. A kernel patch to skip this was proposed in 2023 and never merged.

**Problem 2, in HP's firmware.** HP's S5 preparation method `_PTS(5)` never powers the dGPU off. If the GPU is on when the board enters S5, its power rail stays on. The firmware *does* have the code, but only for runtime power saving, behind two guards:
```
PEGP._PS3   (dGPU → D3)       If (OMPR == 0x03) { PG00._OFF() }   // OMPR: "power-off armed" flag
PG00._OFF   (cut the rail)    If (NVDE != One)  { Return }        // NVDE: set by the NVIDIA driver
```
Windows takes this path during shutdown; Linux never does. That's why the old route-through-Windows trick worked.

(The `AE_AML_BUFFER_LIMIT` / `WQBZ` ACPI errors in `dmesg` are a **separate, harmless** HP bug, not the cause.)

---

## The fix: `omen_s5`
A tiny kernel module that adds one step at the very end of power-off and calls HP's own GPU power-off code:
```
kernel_power_off()
 ├─ device_shutdown()                   ← dGPU gets resumed (problem 1)
 ├─ power-off-prepare handlers
 │    ├─ [224] acpi_power_off_prepare   _PTS(5)   ← does nothing for the dGPU (problem 2)
 │    └─ [192] omen_s5  →  \OS5F:  OMPR = 3;  PEGP._PS3()  →  PG00._OFF()  →  dGPU rail off
 └─ acpi_power_off()                    S5: the board really turns off
```
When it loads, it:
1. checks that the board is HP `8E35` and that `\_SB.PCI0.GPP0.PEGP._PS3` and `.OMPR` exist
2. loads a 211-byte SSDT containing one method, `\OS5F`
3. registers the handler at priority 192, so it runs right after ACPI's 224, when every driver is already shut down

**Why I trust it:**
- It uses HP's own power-off path. It only sets the flag and calls the method; it doesn't drive GPIOs or write to the EC.
- It only runs on power-off, not on reboot. There's no BIOS flash, no ACPI table edits on disk, and no boot loader change. After an uninstall, the next boot is stock.
- I reviewed it myself:
  - the C source, about 70 lines
  - the SSDT bytes: 211 bytes, valid checksum, and they reference only `PEGP.OMPR` and `PEGP._PS3`
  - the installer, which pins upstream commit `13740806` and refuses to build unless the 4 compiled files match their reviewed SHA-256 hashes

**Requirements:**
- the NVIDIA driver must be loaded (`nvidia` or `nvidia-open`). `PG00._OFF` checks `NVDE`, which only that driver sets; with nouveau it does nothing.
- Secure Boot off, or the module has to be signed
- DKMS and kernel headers, which the installer adds; DKMS rebuilds the module after kernel updates

The module is from [Adiakys/omen16-s5-fix](https://github.com/Adiakys/omen16-s5-fix), installed through [jacobdeanpugh/omen16-linux-fix](https://github.com/jacobdeanpugh/omen16-linux-fix). That repo adds an Arch installer, an ACPI layout checker, and a battery ledger.

---

## Install
```bash
git clone https://github.com/iammhador/omen16-linux-poweroff.git
cd omen16-linux-poweroff
sudo bash scripts/install.sh
```
The script:
1. refuses to run on any board other than `8E35`
2. clones `jacobdeanpugh/omen16-linux-fix` at the reviewed commit `e0de822`
3. runs `omen-acpi-check`, where **every check must PASS**; it confirms your firmware has the `_PTS`, `OMPR` and `NVDE` layout the fix depends on
4. installs `omen-drain`, a service that records battery energy at every shutdown and boot
5. builds and loads `omen_s5` through DKMS. It should end with `omen_s5: ready`.

Also remove any `NVreg_DynamicPowerManagement=0x00` from `/etc/modprobe.d/`, and rebuild the initramfs.

## Verify
```bash
bash scripts/verify.sh
```
The real proof is a measured off-window:
1. **Unplug the charger.** A USB-C dock that charges the laptop counts as a charger.
2. Run `systemctl poweroff`. Don't reboot.
3. Leave it off for **at least 1 hour**. Overnight is better.
4. Boot (still unplugged), log in, and run `~/omen16-linux-fix/bin/omen-drain report`.

| avg W while off | Meaning |
|---|---|
| ≤ 3 W | ✅ Really off |
| 3–8 W | Unclear; measure a longer window |
| ≥ 8 W | ❌ The dGPU stayed powered. Check `verify.sh`: is the module loaded, is the NVIDIA driver loaded? |

Don't boot Windows in between; the ledger can't see that time.

## After a BIOS update
Run `sudo ~/omen16-linux-fix/bin/omen-acpi-check` again. If HP changed the tables, the fix may no longer apply, or may no longer be needed. The script reports both cases.

## Uninstall
```bash
sudo ~/omen16-linux-fix/bin/omen-s5-install uninstall   # the module stays active until the next reboot
sudo ~/omen16-linux-fix/bin/omen-drain uninstall        # the ledger in /var/lib/omen-drain/ is kept
```

## Related
- [omen16-omarchy-power](https://github.com/iammhador/omen16-omarchy-power): battery-life tuning on the same laptop (dGPU runtime D3, 60 Hz on battery, keeping apps off the dGPU)
- [Adiakys/omen16-s5-fix](https://github.com/Adiakys/omen16-s5-fix), [jacobdeanpugh/omen16-linux-fix](https://github.com/jacobdeanpugh/omen16-linux-fix), [paolo-de-marinis/omen-acpi](https://github.com/paolo-de-marinis/omen-acpi) (original ACPI analysis)
- [NVIDIA forum: OMEN 16 battery drains after shutdown on Linux](https://forums.developer.nvidia.com/t/hp-omen-16-rtx-5060-battery-drains-after-shutdown-on-linux-gps-acpi-dsm-bug/364074)
- [HP Community: after shutting down from Linux, OMEN 16-ap0…](https://h30434.www3.hp.com/t5/Gaming-Notebooks/After-shuting-down-from-a-Linux-distribution-HP-OMEN-16/td-p/9624996)
