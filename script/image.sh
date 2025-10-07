#! /bin/bash
set -ex

rm -rf /output/*

cp /root/linux-source-$KERNEL_SOURCE_VERSION/vmlinux /output/kernel
cp /root/linux-source-$KERNEL_SOURCE_VERSION/.config /output/config

truncate -s 5G /output/rootfs.ext4
mkfs.ext4 /output/rootfs.ext4

mount /output/rootfs.ext4 /rootfs
debootstrap --variant=minbase --include openssh-server,systemd,unzip,rsync,apt,curl,git,ca-certificates,gnupg,libicu74,iputils-ping,sudo,iproute2 noble /rootfs http://archive.ubuntu.com/ubuntu/

mount --bind / /rootfs/mnt
chroot /rootfs /bin/bash /mnt/script/provision.sh

umount /rootfs/mnt
umount /rootfs

cd /output
tar czvf ubuntu-noble.tar.gz rootfs.ext4 kernel config
cd /
