#!/usr/bin/env bash

# Author:  Jonathan Raffre <nk@nyuu.eu>
#          Massively based on official build script from Docker
# Purpose: Generate a minimal filesystem for archlinux
#          requires root, do this in an empty shell 
#          (LXC, dedicated instance, VM...)

set -e

export LC_ALL="C"
export LANG="C"

hash pacstrap &>/dev/null || {
	echo -e "Could not find pacstrap. Install it with: \npacman -S arch-install-scripts\n"
	exit 1
}

hash expect &>/dev/null || {
	echo -e "Could not find expect. Install it with : \npacman -S expect\n"
	exit 1
}


ROOTFS=$(mktemp -d ${TMPDIR:-/var/tmp}/rootfs-archlinux-XXXXXXXXXX)
chmod 755 $ROOTFS

# packages to ignore for space savings
PKGIGNORE=(
    cryptsetup
    device-mapper
    dhcpcd
    iproute2
    jfsutils
    linux
    lvm2
    man-db
    man-pages
    mdadm
    nano
    netctl
    openresolv
    pciutils
    pcmciautils
    reiserfsprogs
    s-nail
    systemd-sysvcompat
    usbutils
    vi
    xfsprogs
)
IFS=','
PKGIGNORE="${PKGIGNORE[*]}"
unset IFS

expect <<EOF
	set send_slow {1 .1}
	proc send {ignore arg} {
		sleep .1
		exp_send -s -- \$arg
	}
	set timeout 60

	spawn pacstrap -C ./mkimage-pacman-config.conf -c -d -G -i $ROOTFS base haveged --ignore $PKGIGNORE
	expect {
		-exact "anyway? \[Y/n\] " { send -- "n\r"; exp_continue }
		-exact "(default=all): " { send -- "\r"; exp_continue }
		-exact "installation? \[Y/n\]" { send -- "y\r"; exp_continue }
	}
EOF

# man not installed, dirty cleaning for size
arch-chroot $ROOTFS /bin/sh -c 'rm -r /usr/share/man/*'
# install haveged, no entropy in a container
arch-chroot $ROOTFS /bin/sh -c "haveged -w 1024; pacman-key --init; pkill haveged; pacman -Rs --noconfirm haveged; pacman-key --populate archlinux; pkill gpg-agent"
# UTC by default, en_US
arch-chroot $ROOTFS /bin/sh -c "ln -s /usr/share/zoneinfo/UTC /etc/localtime"
echo 'en_US.UTF-8 UTF-8' > $ROOTFS/etc/locale.gen
arch-chroot $ROOTFS locale-gen
# kernel.org mirrors, best mirrors with CDN-like autopick
arch-chroot $ROOTFS /bin/sh -c 'echo "Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist'

# create devices nodes as systemd/udev does not run inside docker
DEV=$ROOTFS/dev
rm -rf $DEV
mkdir -p $DEV
mknod -m 666 $DEV/null c 1 3
mknod -m 666 $DEV/zero c 1 5
mknod -m 666 $DEV/random c 1 8
mknod -m 666 $DEV/urandom c 1 9
mkdir -m 755 $DEV/pts
mkdir -m 1777 $DEV/shm
mknod -m 666 $DEV/tty c 5 0
mknod -m 600 $DEV/console c 5 1
mknod -m 666 $DEV/tty0 c 4 0
mknod -m 666 $DEV/full c 1 7
mknod -m 600 $DEV/initctl p
mknod -m 666 $DEV/ptmx c 5 2
ln -sf /proc/self/fd $DEV/fd

tar --numeric-owner --xattrs --acls --use-compress-program=xz -C $ROOTFS -cf archlinux-rootfs.tar.xz .

# uncomment for autoimport into your local docker
# tar --numeric-owner --xattrs --acls -C $ROOTFS -c . | docker import - archlinux
# docker run -t archlinux echo Success.

# cleaning
rm -rf $ROOTFS
