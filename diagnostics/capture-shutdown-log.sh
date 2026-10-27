#!/bin/bash
# Capture the kernel log from the last moment before power-off, so you can see
# how far shutdown got. Installs a systemd-shutdown hook; remove it when done.
#
#   sudo bash diagnostics/capture-shutdown-log.sh install   # then power off, boot, read /shutdown-dmesg.txt
#   sudo bash diagnostics/capture-shutdown-log.sh remove
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
HOOK=/usr/lib/systemd/system-shutdown/zz-debug.sh

case ${1:-} in
install)
    cat > "$HOOK" << 'EOF'
#!/bin/sh
# Runs as the very last step of systemd-shutdown ($1 = poweroff/reboot/halt)
sleep 3
mount -o remount,rw /
{
    echo "=== systemd-shutdown action: $1 at $(date) ==="
    cat /proc/acpi/wakeup
    dmesg
} > /shutdown-dmesg.txt
sync
mount -o remount,ro /
EOF
    chmod +x "$HOOK"
    echo "Installed. Power off, boot, then: tail -50 /shutdown-dmesg.txt" ;;
remove)
    rm -f "$HOOK" /shutdown-dmesg.txt
    echo "Removed." ;;
*)
    echo "usage: $0 install|remove"; exit 1 ;;
esac
