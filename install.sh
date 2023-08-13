#!/bin/bash
required_binaries=('blkid' 'parted' 'lsblk' 'awk' 'wget')

if [ "$USER" != 'root' ]; then
	echo -e "You're not running the script as root, you're likely to face issues\n"
fi

echo -e "Checking for all required binaries\n"
for i in "${required_binaries[@]}"; do
	if which "$i" 2>/dev/null >/dev/null; then
		true # do nothing if it's found
	else
		echo "$0: binary missing $i"
		exit 1
	fi
done

echo "Checking for/downloading arch filesystem"
[ -f "archlinux-bootstrap-x86_64.tar.gz" ] || wget "https://geo.mirror.pkgbuild.com/iso/latest/archlinux-bootstrap-x86_64.tar.gz"

lsblk
read -rp "Disk to partition? " disk

if [ -b "$disk" ]; then
	echo "$0: Disk ($disk) exists."
else
	echo "$0: Disk doesn't exist."
	exit 1
fi

echo "READ THIS PART VERY CAREFULLY"
read -rp "This *WILL* destroy data on [$disk], do you want to continue [y\n] " destroy_perms
if [ "$destroy_perms" != 'y' ]; then
	echo "Goodbye!"
	exit 0
fi

echo "Running wipefs on $disk"
wipefs -fa "$disk"

echo "Trying to partition disk"
parted "${disk}" --script 'mklabel gpt'
parted "${disk}" --script 'mkpart primary fat32 0 512M'
parted "${disk}" --script 'mkpart primary ext4 512M 100%'

mkfs.fat -F32 -n 'EFI' "${disk}1"
mkfs.ext4 -L rootfs "${disk}2"

echo "Making folder for mount points"
mkdir /mnt/arch

echo "Mounting rootfs"
mount "${disk}2" /mnt/arch

echo "Extracting arch tarball"
tar -xvf archlinux-bootstrap-x86_64.tar.gz
mv root.x86_64/* /mnt/arch

echo "Mounting filesystems"
mkdir -p /mnt/arch/boot/efi

mount "${disk}1" /mnt/arch/boot/efi
cp /etc/resolv.conf /mnt/arch/etc/resolv.conf
echo -e '\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >> /mnt/arch/etc/pacman.d/mirrorlist

mount --types proc /proc /mnt/arch/proc
mount --rbind /sys /mnt/arch/sys
mount --make-rslave /mnt/arch/sys
mount --rbind /dev /mnt/arch/dev
mount --make-rslave /mnt/arch/dev
mount --bind /run /mnt/arch/run
mount --make-slave /mnt/arch/run

echo "Running swapoff (required to create swap in chroot)"
[ -f /swapfile ] && swapoff /swapfile

echo "Disk partitioned. Attempting to create fstab"
awk 'NR==1 { print "UUID="$0"\t/boot/efi\tvfat\tdefaults\t0 1" } END { print "UUID="$1"\t/\text4\tdefaults\t0 1" }' <(blkid -s UUID -o value "${disk}"*) > /mnt/arch/etc/fstab

echo "Running chroot script in chroot"
cp ./chroot-script /mnt/arch/chroot-script
chroot /mnt/arch /chroot-script "${disk}"
