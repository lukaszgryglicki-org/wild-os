#!/bin/bash
nasm -f win64 wild_uefi.asm -o wild_uefi.obj
lld-link /entry:efi_main /subsystem:efi_application /nodefaultlib /out:BOOTX64.EFI wild_uefi.obj
./make_usb_img.sh usb_uefi.img BOOTX64.EFI
