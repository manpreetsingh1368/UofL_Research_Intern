#!/bin/bash

set -e

# === CONFIGURATION ===
DISK="/dev/nvme0n1"       # CHANGE if your NVMe is different
EFI="${DISK}p1"
ROOT="${DISK}p2"

HOSTNAME="archlinux"
LOCALE="en_US.UTF-8"
TIMEZONE="UTC"
USERNAME="user"
PASSWORD="password"

# === 1. Partitioning ===
echo "==> Partitioning $DISK..."
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"

# === 2. Format partitions ===
echo "==> Formatting partitions..."
mkfs.fat -F32 "$EFI"
mkfs.ext4 "$ROOT"

# === 3. Mount filesystems ===
echo "==> Mounting partitions..."
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# === 4. Install base system ===
echo "==> Installing base system..."
pacstrap -K /mnt base linux linux-firmware vim sudo networkmanager systemd-boot

# === 5. Generate fstab ===
echo "==> Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# === 6. Chroot and configure system ===
echo "==> Entering chroot..."
arch-chroot /mnt /bin/bash <<EOF
# Timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale
sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

# Hostname and hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Root password
echo "root:$PASSWORD" | chpasswd

# New user
useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Enable services
systemctl enable NetworkManager

# Install systemd-boot
bootctl install

PARTUUID=\$(blkid -s PARTUUID -o value "$ROOT")

cat > /boot/loader/loader.conf <<LOADER
default arch
timeout 3
editor no
LOADER

cat > /boot/loader/entries/arch.conf <<ENTRY
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=\$PARTUUID rw
ENTRY
EOF

# === 7. Cleanup and reboot ===
echo "==> Unmounting..."
umount -R /mnt
echo "==> Installation complete. You can reboot now."

