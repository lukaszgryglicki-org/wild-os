#!/usr/bin/env bash
set -euo pipefail

as --32 -o boot.o boot.S
ld -m elf_i386 -Ttext 0x7C00 --nmagic -nostdlib -e _start -o boot.elf boot.o
objcopy -O binary -j .text boot.elf boot.bin

size=$(stat -c%s boot.bin)
echo "Built boot.bin (${size} bytes)"
if [ "$size" -ne 512 ]; then
  echo "ERROR: boot.bin must be exactly 512 bytes" >&2
  exit 1
fi

echo
echo "Run with:"
echo "  qemu-system-i386 -boot a -drive file=boot.bin,if=floppy,format=raw"

