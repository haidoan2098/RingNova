#!/usr/bin/env bash
# scripts/gdb_connect.sh - Connect GDB to QEMU

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KERNEL="${PROJECT_ROOT}/build/kernel.elf"
GDB_PORT="1234"

if [ ! -f "$KERNEL" ]; then
    echo "[ERROR] Kernel ELF not found: $KERNEL"
    echo "        Run 'make PLATFORM=qemu' first."
    exit 1
fi

echo "[INFO] Starting GDB..."
echo "       Kernel  : $KERNEL"
echo "       Port    : $GDB_PORT"
echo ""

# Create temporary GDB commands file
GDB_CMDS=$(mktemp)
trap 'rm -f "$GDB_CMDS"' EXIT
cat > "$GDB_CMDS" << EOF
target remote :$GDB_PORT
set architecture armv7-a
set endian little
break _start
break kmain
break uart_init
continue
EOF

echo "[INFO] GDB commands loaded:"
echo "       - target remote :$GDB_PORT"
echo "       - break _start"
echo "       - break kmain" 
echo "       - break uart_init"
echo "       - continue"
echo ""
echo "[INFO] Debug commands:"
echo "       (gdb) stepi      # Step instruction"
echo "       (gdb) nexti      # Next instruction"
echo "       (gdb) info registers"
echo "       (gdb) x/10i \$pc # Show instructions"
echo "       (gdb) x/20x \$sp # Show stack"
echo ""

# Start GDB with commands
arm-none-eabi-gdb -x "$GDB_CMDS" "$KERNEL"


