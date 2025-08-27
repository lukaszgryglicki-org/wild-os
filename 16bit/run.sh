#!/bin/bash
qemu-system-i386 -boot a -drive format=raw,file=boot16.img,if=floppy -no-reboot -m 1
