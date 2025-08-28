# UEFI firmware (OVMF) + USB mass storage device
qemu-system-x86_64 -m 256 \
  -drive if=pflash,format=raw,readonly=on,file=./OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=./OVMF_VARS.fd \
  -machine q35 \
  -vga std \
  -device qemu-xhci \
  -drive id=usbstick,if=none,format=raw,file=usb_uefi.img \
  -device usb-storage,drive=usbstick,removable=on

