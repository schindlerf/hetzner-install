#!/bin/bash

export LANG="C"

source ./commom.conf
source ./$1.conf

function h {
	echo ">>>>> $@ <<<<<"
}

function wait_for_key {
  echo -e "done: press any key to continue\n\n"
  read
}

# set hostname
h "setting hostname"
./steps/0.0_set_hostname.sh
wait_for_key

# clean old partition layout
h "cleanup old partition layout"
./steps/1.0_delete_old_partition.sh
wait_for_key

# setup lvm
h "setting up lvm"
pvcreate -ff -y /dev/md1
vgcreate vg0 /dev/md1
lvcreate -L20G -n rootfs vg0
lvcreate -L32G -n swap vg0
lvcreate -l 100%FREE -n datafs vg0
pvs
vgs
lvs
wait_for_key

# create filesystems
h "creating filesystems"
mkfs.ext4 -L boot /dev/md0
mkfs.ext4 -L rootfs /dev/vg0/rootfs
mkfs.ext4 -L datafs /dev/vg0/datafs
mkswap -f -L swap /dev/vg0/swap
wait_for_key

# mount filesystems stage 1
h "mounting filesystems - stage 1"
swapon -v /dev/vg0/swap
mkdir -v /newroot
mount -v -t ext4 /dev/vg0/rootfs /newroot
mkdir -v /newroot/tmp /newroot/var /newroot/home
mkdir /newroot/boot
mount -v -t ext4 /dev/md0 /newroot/boot
wait_for_key

# download and install debootstrap
h "installing debootstrap"
wget http://archive.ubuntu.com/ubuntu/pool/main/d/debootstrap/debootstrap_${DEBOOTSTRAP_VERSION}_all.deb
dpkg -i debootstrap_${DEBOOTSTRAP_VERSION}_all.deb
rm debootstrap_*.deb
wait_for_key

h "running debootstrap"
debootstrap --arch=amd64 --components=main,restricted,universe,multiverse --verbose ${UBUNTU_VERSION} /newroot http://archive.ubuntu.com/ubuntu/
wait_for_key

h "writing fstab"
cat >/newroot/etc/fstab <<EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
proc            /proc           proc    defaults  0 0
none            /dev/pts        devpts  gid=5,mode=620 0 0
#sys             /sys            sysfs   nodev,noexec,nosuid 0 0
/dev/vg0/rootfs /               ext4    defaults            0 0
/dev/md/0       /boot           ext4    defaults            0 1
/dev/vg0/swap   none            swap    sw                  0 0
EOF
chroot /newroot /bin/bash -c "grep -v swap /etc/fstab >/etc/mtab"
wait_for_key

h "mounting filesystems - stage 2"
mount -v --rbind /dev /newroot/dev
#mount -v --rbind /dev/pts /newroot/dev/pts
mount -v --rbind /proc /newroot/proc
mount -v --rbind /sys /newroot/sys
chroot /newroot locale-gen en_US.UTF-8
chroot /newroot update-locale LANG=en_US.UTF-8
wait_for_key

chroot /newroot dpkg-reconfigure tzdata

h "configure networking"
# TODO
cat >/newroot/etc/network/interfaces <<EOF
# Loopback device:
auto lo
iface lo inet loopback

## device: eth0
auto eth0
iface eth0 inet static
  address ${TARGET_IPADDR}
  netmask ${TARGET_NETMASK}
  gateway ${TARGET_GATEWAY}
#  post-up mii-tool -F 100baseTx-FD eth0
EOF

# TODO
cat >/newroot/etc/resolvconf/resolv.conf.d/original <<EOF
search ${TARGET_DOMAIN}
nameserver 8.8.8.8
nameserver 213.133.98.98
EOF

# TODO
cat >/newroot/etc/hosts <<EOF
127.0.0.1	localhost
${TARGET_IPADDR} ${TARGET_HOSTNAME}.${TARGET_DOMAIN} ${TARGET_HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# TODO
echo "${TARGET_HOSTNAME}" >/newroot/etc/hostname
wait_for_key

h "setting up apt"
# install missing packages
cp -f /newroot/etc/apt/sources.list /newroot/etc/apt/sources.list.orig
cat >/newroot/etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_VERSION} main restricted universe multiverse 
#deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_VERSION} main restricted universe multiverse 
deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_VERSION}-updates main restricted universe multiverse 
#deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_VERSION}-updates main restricted universe multiverse 
#deb http://archive.ubuntu.com/ubuntu/ ${UBUNTU_VERSION}-backports main restricted universe multiverse 
#deb-src http://archive.ubuntu.com/ubuntu/ ${UBUNTU_VERSION}-backports main restricted universe multiverse 
deb http://security.ubuntu.com/ubuntu ${UBUNTU_VERSION}-security main restricted universe multiverse 
#deb-src http://security.ubuntu.com/ubuntu ${UBUNTU_VERSION}-security main restricted universe multiverse 
EOF
wait_for_key

h "update package index and install missing packages"
chroot /newroot apt-get -y update
chroot /newroot apt-get -y install openssh-server lvm2 mdadm initramfs-tools
chroot /newroot /bin/bash -c "/usr/share/mdadm/mkconf > /etc/mdadm/mdadm.conf"
wait_for_key

h "install kernel and bootloader"
chroot /newroot apt-get -y install linux-generic
chroot /newroot apt-get -y install grub-pc
chroot /newroot /bin/bash -c "update-initramfs -k all -u"
#chroot /newroot /bin/bash -c 'echo -e "device (hd0) /dev/sda\nroot (hd0,0)\nsetup (hd0)\nquit"|grub --batch'
# TODO
cat >/newroot/etc/default/grub <<EOF
# If you change this file, run 'update-grub' afterwards to update
# /boot/grub/grub.cfg.
# For full documentation of the options in this file, see:
#   info -f grub -n 'Simple configuration'

GRUB_DEFAULT=0
#GRUB_HIDDEN_TIMEOUT=0
GRUB_HIDDEN_TIMEOUT_QUIET=true
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT="nomodeset"
GRUB_CMDLINE_LINUX="bootdegraded=true"

# Uncomment to enable BadRAM filtering, modify to suit your needs
# This works with Linux (no patch required) and with any kernel that obtains
# the memory map information from GRUB (GNU Mach, kernel of FreeBSD ...)
#GRUB_BADRAM="0x01234567,0xfefefefe,0x89abcdef,0xefefefef"

# Uncomment to disable graphical terminal (grub-pc only)
GRUB_TERMINAL=console

# The resolution used on graphical terminal
# note that you can use only modes which your graphic card supports via VBE
# you can see them in real GRUB with the command \`vbeinfo'
#GRUB_GFXMODE=640x480

# Uncomment if you don't want GRUB to pass "root=UUID=xxx" parameter to Linux
#GRUB_DISABLE_LINUX_UUID=true

# Uncomment to disable generation of recovery mode menu entries
#GRUB_DISABLE_RECOVERY="true"

# Uncomment to get a beep at grub start
#GRUB_INIT_TUNE="480 440 1"

GRUB_VIDEO_BACKEND="vga"
GRUB_GFXPAYLOAD_LINUX="text"
EOF
chroot /newroot /bin/bash -c "grub-install --no-floppy --recheck /dev/sda"
chroot /newroot /bin/bash -c "grub-install --no-floppy --recheck /dev/sdb"
chroot /newroot /bin/bash -c "update-grub"
wait_for_key

h "installing authorized_keys"
mkdir -m 0700 /newroot/root/.ssh
# TODO
cat >/newroot/root/.ssh/authorized_keys <<EOF
${SSH_KEY}
EOF

h "setting root password"
chroot /newroot passwd -S root
# TODO
cat <<EOF | chroot /newroot passwd root
${INITIAL_ROOT_PASSWORD}
${INITIAL_ROOT_PASSWORD}
EOF
wait_for_key

echo "now reboot into the new machine and exec:"
echo "  apt-get install ubuntu-standard tasksel"
echo "  tasksel install server"
echo "  dpkg-reconfigure postfix"
echo "etc..."

exit
