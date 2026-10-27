# The old workaround: shut down through Windows (dual-boot only)

Before switching to Omarchy only, this laptop dual-booted Fedora and Windows with **rEFInd** as the boot menu. Windows shut the laptop down properly and Linux didn't, so every Linux shutdown was routed through Windows. It worked, but it was a workaround and not a fix. It's written down here as history, and for anyone who still dual-boots.

## How it worked
```
Special key (AI button, KEY_PROG2) pressed in Linux
  → script edits refind.conf: timeout -1, default_selection "Windows"
  → script creates a flag file on the EFI partition, then reboots
rEFInd boots Windows straight away (no menu)
  → a SYSTEM-level Task Scheduler task ("At startup") finds the flag
  → it restores refind.conf (timeout 10, default "Fedora"), verifies the change, and only then deletes the flag
  → shutdown /s, and Windows powers off properly
```

## Why it worked
Windows' NVIDIA driver and HP's firmware turn the dGPU off together during shutdown. Linux never triggers that path; see the [README](../README.md#root-cause). So letting Windows do the final power-off avoided the bug entirely. The old notes said the cause was "Linux uses S3 instead of S5". **That was wrong.** Linux does ask for S5; the firmware just leaves the GPU powered.

## Hard-won lessons from that setup
- **Windows Fast Startup had to be off** (`powercfg /h off`). Otherwise Windows "boots" by resuming from hibernation, the at-startup task never runs, and the routing fails at random.
- **Only delete the flag after the config fix is confirmed.** If you delete it first and anything interrupts the fix, `refind.conf` stays broken and nothing ever retries.
- **`refind.conf` kept disappearing.** Fedora upgrades, HP's firmware repair routines, and FAT32 corruption on the EFI partition all wiped it at different times (chkdsk reported `first allocation unit is not valid`). A boot-time service restored it from a copy kept off the EFI partition, along with the rEFInd binary itself, which Windows kept overwriting with `bootmgfw.efi`.
- **`efibootmgr --bootnext` didn't work.** HP's firmware ignores or clears `BootNext` and deletes unknown boot entries, which is why the routing had to go through the `refind.conf` file.

## Why it was retired
- It only works when Windows is installed.
- Every shutdown is really a reboot into Windows, so it's slow and hard on the EFI partition.
- It treats the symptom, not the cause. The `omen_s5` module fixes the cause directly in Linux.
