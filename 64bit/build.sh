#!/bin/bash
set -e

# Assemble
as --64 -o wild64.o wild64.S

# Link at VMA 0x7C00 but place at file offset 0
ld -o wild64.elf wild64.o -T boot.ld -nostdlib -n

# Extract a flat 512B sector from the .boot section
objcopy -O binary -j .boot wild64.elf wild64.bin

# Sanity: must be 512 bytes; last two must be 55 aa
stat -c %s wild64.bin
od -An -tx1 -j510 -N2 wild64.bin   # expect: 55 aa

# (Easiest) Boot as a floppy image
dd if=/dev/zero of=wild64.img bs=512 count=2880
dd conv=notrunc if=wild64.bin of=wild64.img

# Run (shows VGA text in a window). For SSH-only terminals, use -curses.
qemu-system-x86_64 -fda wild64.img -boot a -no-reboot -m 64
# or terminal UI:
# qemu-system-x86_64 -curses -fda wild64.img -boot a -no-reboot -m 64

