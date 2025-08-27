#!/bin/bash
qemu-system-i386 -boot a -drive file=boot.bin,if=floppy,format=raw -no-reboot -m 1
