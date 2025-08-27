#!/bin/bash
qemu-system-x86_64 -boot a -drive format=raw,file=boot64.img,if=floppy -no-reboot -m 1
