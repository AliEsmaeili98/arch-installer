#!/bin/bash
set -e

# === CONFIG ===
DISK="/dev/nvme1n1"
HOSTNAME="arch"
USERNAME="ali"
LOCALE="en_US.UTF-8"
TIMEZONE="Australia/Sydney"
SSID="Pelak 79"
WIFI_PASS="hTV%6qY^vI^Ls%"

echo "[*] Setting up time sync..."
timedatectl set-ntp true

echo "[*] Partitioning disk $DISK..."
sgdisk -Z "$DISK"
sgdisk -n1:0:+512M -t1:ef00 -c1:EFI "$DISK"
sgdisk -n2:0:0 -t2:8300 -c2:ROOT "$DISK"

echo "[*] Formatting partitions..."
mkfs.fat -F32 "${DISK}p1"
mkfs.ext4 "${DISK}p2"

echo "[*] Mounting root and boot..."
mount "${DISK}p2" /mnt
mkdir /mnt/boot
mount "${DISK}p1" /mnt/boot

echo "[*] Installing base system..."
pacstrap -K /mnt base linux linux-firmware intel-ucode zsh sudo git grub efibootmgr os-prober networkmanager xdg-user-dirs xdg-utils nano wget curl

echo "[*] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "[*] Configuring system in chroot..."
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname
cat >> /etc/hosts <<END
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
END

echo "[*] Creating user $USERNAME..."
useradd -m -G wheel -s /bin/zsh $USERNAME
echo "%wheel ALL=(ALL:ALL) ALL" >> /etc/sudoers
chsh -s /bin/zsh root

echo "[*] Setting up NetworkManager..."
systemctl enable NetworkManager
nmcli dev wifi connect "$SSID" password "$WIFI_PASS"

echo "[*] Installing NVIDIA drivers and Hyprland..."
pacman -S --noconfirm nvidia nvidia-utils nvidia-settings \
    hyprland xdg-desktop-portal-hyprland \
    wl-clipboard waybar wofi foot network-manager-applet \
    zsh-autosuggestions zsh-syntax-highlighting noto-fonts noto-fonts-emoji ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono kitty dolphin firefox

echo "[*] NVIDIA kernel module settings..."
mkdir -p /etc/modprobe.d
echo 'options nvidia NVreg_RegistryDwords="PowerMizerEnable=0x1; PerfLevelSrc=0x2222; PowerMizerLevel=0x3; PowerMizerDefault=0x3; PowerMizerDefaultAC=0x3"' > /etc/modprobe.d/nvidia.conf
mkinitcpio -P

echo "[*] NVIDIA Wayland env vars..."
cat >> /etc/environment <<END
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
WLR_NO_HARDWARE_CURSORS=1
END

echo "[*] Installing GRUB + enabling os-prober..."
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
os-prober
grub-mkconfig -o /boot/grub/grub.cfg

echo "[*] Enabling autologin for $USERNAME..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOL
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USERNAME --noclear %I \$TERM
EOL

echo "[*] Hyprland autostart for $USERNAME..."
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config
sudo -u $USERNAME bash -c "echo '[[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]] && exec Hyprland' > /home/$USERNAME/.bash_profile"

echo "[*] Installing yay (AUR helper)..."
sudo -u $USERNAME bash -c '
cd ~
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
'

EOF

echo "[*] Installation complete. You can reboot now!"
