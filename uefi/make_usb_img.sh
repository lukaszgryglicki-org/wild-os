#!/usr/bin/env bash
# make_usb_img.sh  usb_uefi.img  BOOTX64.EFI
set -euo pipefail
IMG="${1:-usb_uefi.img}"
EFI="${2:?path to BOOTX64.EFI}"
SIZE_MB=64

rm -f "$IMG"
# Create sparse image
truncate -s ${SIZE_MB}M "$IMG"

# Partition as GPT with one ESP
parted -s "$IMG" mklabel gpt
parted -s "$IMG" mkpart ESP fat32 1MiB 100%
parted -s "$IMG" set 1 esp on

# Map partitions via loop device
LOOP=$(sudo losetup --show -f -P "$IMG")
trap 'sudo losetup -d "$LOOP"' EXIT

# Format the ESP (partition p1)
sudo mkfs.fat -F32 -n UEFI "${LOOP}p1"

# Mount, copy BOOTX64.EFI
TMP=$(mktemp -d)
sudo mount "${LOOP}p1" "$TMP"
sudo mkdir -p "$TMP/EFI/BOOT"
sudo cp "$EFI" "$TMP/EFI/BOOT/BOOTX64.EFI"
sync
sudo umount "$TMP"
rmdir "$TMP"
sudo losetup -d "$LOOP"
trap - EXIT

echo "Created $IMG"

