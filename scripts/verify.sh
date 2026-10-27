#!/bin/bash
# Is the shutdown fix installed, loaded, and has it been proven with a real off-window?
FIX=$HOME/omen16-linux-fix
ok()   { printf '  [ OK ] %s\n' "$*"; }
bad()  { printf '  [FAIL] %s\n' "$*"; }

echo "== Machine"
board=$(cat /sys/class/dmi/id/board_name)
echo "  board $board, BIOS $(cat /sys/class/dmi/id/bios_version), kernel $(uname -r)"
[[ $board == 8E35 ]] && ok "board 8E35" || bad "board is not 8E35: this fix doesn't apply"

echo "== Module"
if [[ -d /sys/module/omen_s5 ]]; then
    ok "omen_s5 loaded"
    journalctl -k -b -q --no-pager -g 'omen_s5' | tail -1 | sed 's/^/  /'
else
    bad "omen_s5 NOT loaded: the dGPU will stay powered after shutdown"
fi
grep -q 'Open Kernel Module\|NVIDIA' /proc/driver/nvidia/version 2>/dev/null \
    && ok "NVIDIA driver loaded (PG00._OFF needs NVDE=1, which only it sets)" \
    || bad "NVIDIA driver not loaded: the fix will run but do nothing"

echo "== Proof (battery drain while off)"
if [[ -x $FIX/bin/omen-drain ]]; then
    "$FIX/bin/omen-drain" report | sed 's/^/  /'
    echo "  ≤ 3 W = really off.  ≥ 8 W = dGPU still powered."
else
    bad "omen-drain not installed (run scripts/install.sh)"
fi
