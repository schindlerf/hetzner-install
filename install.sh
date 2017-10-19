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
###############################################################################
# set hostname
h "setting hostname"
if [ -z "$TARGET_HOSTNAME" ]; then
  echo "Type the hostname, followed by [ENTER]:"
  read $TARGET_HOSTNAME;
fi
hostname $TARGET_HOSTNAME
wait_for_key
###############################################################################

# clean old partition layout
h "cleanup old partition layout"
# deactivate all lvm 
vgchange -a n

# umount
umount /dev/md*

# Stop raid devices
mdadm --stop /dev/md*

# Zero 'em all
mdadm --zero-superblock /dev/sd*

mdadm -S --scan

# Partition setup
# Delte them all
# TODO There may be more than 5 partitions
for disk in `lsblk -d -o NAME -n | grep sd`; do
  sgdisk -Z $disk 
done
wait_for_key
###############################################################################


for d in `lsblk -d -o NAME -n | grep sd`; do
  parted -a optimal /dev/$d --script \
    unit s \
    mklabel gpt \
    mkpart mbr 2048 4095 \
    mkpart grub 4096 128MB \
    mkpart raid 128MB 100GB \
    mkpart btrfs 100GB 100% \
    set 1 bios_grub on \
    set 2 boot on \
    set 2 esp on \
    set 3 raid on;
done
###############################################################################

# create raid devices
yes | mdadm --create -n 2 -l 1 /dev/md0 /dev/sd[ab]2
yes | mdadm --create -n 2 -l 1 /dev/md1 /dev/sd[ab]3

###############################################################################

if [ -z "$TARGET_LUKS_PASS" ]; then
  echo "Type the luks passprase, followed by [ENTER]:"
  read $TARGET_LUKS_PASS;
fi

echo -n $CRYPT_PASSWD | cryptsetup --batch-mode -c aes-cbc-essiv:sha256 -s 256 -y luksFormat /dev/md1
echo -n $CRYPT_PASSWD |cryptsetup luksOpen /dev/md1 crypt

###############################################################################

# setup lvm
h "setting up lvm"
pvcreate -ff -y /dev/mapper/crypt
vgcreate vg-`hostname` /dev/mapper/crypt

lvcreate -n swap -L 16G vg-`hostname`
lvcreate -n tmp -L 16G vg-`hostname`
lvcreate -n usr -L 10G vg-`hostname`
lvcreate -n home -L 20G vg-`hostname`
lvcreate -n root -L 5G vg-`hostname`
lvcreate -n var-log -L 8G vg-`hostname`
lvcreate -n var -l100%FREE vg-`hostname` /dev/mapper/crypt

pvs
vgs
lvs
wait_for_key
###############################################################################

# create filesystems
h "creating filesystems"
mkfs.ext4 -L boot /dev/md0
mkswap -f /dev/vg-`hostname`/swap
mkfs.ext4 -L home /dev/vg-`hostname`/home
mkfs.ext4 -L tmp /dev/vg-`hostname`/tmp
mkfs.ext4 -L usr /dev/vg-`hostname`/usr
mkfs.ext4 -L var /dev/vg-`hostname`/var
mkfs.ext4 -L var /dev/vg-`hostname`/var-log
mkfs.ext4 -L root /dev/vg-`hostname`/root
wait_for_key
###############################################################################

# mount filesystems stage 1
h "mounting filesystems - stage 1"
swapon -v /dev/vg-`hostname`/swap

if [ ! -d /target ]; then
    mkdir -pv /target
fi

mount -v /dev/vg-$(hostname)/root /target/
mkdir -p /target/{boot,usr,tmp,home,var,proc,dev,sys}
mount -v /dev/vg-`hostname`/home /target/home/
mount -v /dev/vg-`hostname`/tmp /target/tmp/
mount -v /dev/vg-`hostname`/usr /target/usr/
mount -v /dev/vg-`hostname`/var /target/var/
mkdir -pv /target/var/log
mount -v /dev/vg-`hostname`/var-log /target/var/log/
mount -v /dev/md0 /target/boot
wait_for_key
###############################################################################

h "running debootstrap"
debootstrap \
  --components=main,contrib,non-free \
  --verbose ${DEBIAN_VERSION} \
  /target \
  http://deb.debian.org/debian/
wait_for_key
###############################################################################

h "writing fstab"

###############################################################################

cat >/newroot/etc/fstab <<EOF

# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# Boot
/dev/md0 /boot ext4 rw,noatime,discard,data=ordered,commit=600 0 1

# Sys
proc /proc proc defaults 0 0
#sysfs /sys sysfs nosuid,nodev,noexec 0 0
none            /dev/pts        devpts  gid=5,mode=620 0 0

# LVM
/dev/mapper/vg--$(hostname)-swap none swap  sw,discard 0  0
/dev/mapper/vg--$(hostname)-root / ext4 rw,noatime,discard,data=ordered 0 1
/dev/mapper/vg--$(hostname)-usr /usr ext4 rw,noatime,discard,data=ordered 0 1
/dev/mapper/vg--$(hostname)-home /home ext4 rw,noatime,discard,data=ordered,noexec,nodev,nosuid 0 1
/dev/mapper/vg--$(hostname)-tmp /tmp ext4 rw,noatime,discard,data=ordered,noexec,nodev,nosuid 0 1
/dev/mapper/vg--$(hostname)-var /var ext4 rw,noatime,discard,acl,user_xattr,barrier=1,data=ordered,usrquota,grpquota 0 1
/dev/mapper/vg--$(hostname)-var--log /var/log ext4 rw,noatime,discard,acl,user_xattr,barrier=1,data=ordered 0 1

# Network
nfs.hetzner.de:/nfs /mnt/hetzner_nfs nfs ro 0 0
//u129418.your-storagebox.de/backup  /mnt/hetzner_backup cifs uid=0,gid=0,_netdev,credentials=/root/.smbcredentials.u129418 0 0
//u130753.your-backup.de/backup  /mnt/hetzner_$(hostname) cifs uid=0,gid=0,_netdev,credentials=/root/.smbcredentials.u130753 0 0

# Rebind
/tmp /var/tmp none bind
EOF
###############################################################################

chroot /target /bin/bash -c "grep -v swap /etc/fstab >/etc/mtab"
wait_for_key

h "mounting filesystems - stage 2"
mount -v --rbind /proc/ /target/proc/
mount -v --rbind /dev/ /target/dev/
mount -v --rbind /sys/ /target/sys/
#mount -v --rbind /dev/pts /target/dev/pts

###############################################################################
chroot /target locale-gen de_DE.UTF-8
chroot /target update-locale LANG=de_DE.UTF-8
wait_for_key

###############################################################################
chroot /target dpkg-reconfigure tzdata

###############################################################################
h "configure networking"

cat >/target/etc/network/interfaces <<EOF
# cat /etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

auto lo
iface lo inet loopback

# device: eth0
auto eth0
iface eth0 inet static
dns-nameservers 213.133.98.96 213.133.99.99 213.133.98.98 213.133.100.100
address ${TARGET_IPADDR}
netmask ${TARGET_NETMASK}
gateway ${TARGET_GATEWAY}
pointopoint ${TARGET_GATEWAY}
#up ip addr add 176.9.67.11/32  dev eth0
#down ip addr del 176.9.67.11/32 dev eth0

#iface eth0 inet6 static
#address 2a01:4f8:151:820a::2
#netmask 128
#gateway fe80::1
#privext 2
#down ip addr del 2a01:4f8:151:820a::53/128 dev eth0
#up ip addr add 2a01:4f8:151:820a::53/128 dev eth0

EOF

###############################################################################
cp /etc/resolv.conf /target/etc/resolv.conf
sed -i -e 's/your-server.de/'${TARGET_DOMAIN}'/g' /target/etc/resolv.conf

cat >/target/etc/hosts <<EOF
127.0.0.1	localhost
${TARGET_IPADDR} ${TARGET_HOSTNAME}.${TARGET_DOMAIN} ${TARGET_HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

echo "${TARGET_HOSTNAME}" >/target/etc/hostname
wait_for_key

###############################################################################

h "setting up apt"
# install missing packages

cp -f /newroot/etc/apt/sources.list /newroot/etc/apt/sources.list.orig
cat <<EOF > /target/etc/apt/sources.list

# Packages from the Hetzner Debian Mirror
#deb ftp://mirror.hetzner.de/debian/packages ${DEBIAN_VERSION} main contrib non-free
deb ftp://mirror.hetzner.de/debian/packages ${DEBIAN_VERSION} main contrib non-free
deb ftp://mirror.hetzner.de/debian/security ${DEBIAN_VERSIION}/updates main contrib non-free
deb ftp://ftp.de.debian.org/debian/ ${DEBIAN_VERSION} main contrib non-free
deb http://security.debian.org/ ${DEBIAN_VERSION}/updates main contrib non-free

deb http://ftp.de.debian.org/debian/ ${DEBIAN_VERSION}-backports main contrib non-free
deb http://ftp.de.debian.org/debian ${DEBIAN_VERSION}-proposed-updates main contrib non-free
EOF
wait_for_key
###############################################################################

h "update package index and install missing packages"
chroot /target apt-get -y update
chroot /target apt-get -y install openssh-server lvm2 mdadm initramfs-tools
chroot /target /bin/bash -c "/usr/share/mdadm/mkconf > /etc/mdadm/mdadm.conf"
chroot /target apt-get -y install console-common,manpages-de,ifupdown,cryptsetup,\
  manpages-dev,sudo,vim,console-data,salt-minion,htop,aptitude,rkhunter,glances,\
  git,busybox,openssh-blacklist,manpages-posix-dev,dropbear-initramfs,salt-master,\
  apt-listchanges,logcheck,hashalot,john,firmware-realtek,debsecan,manpages-de-dev,\
  chkrootkit,bzip2,bash-completion,task-german,keyboard-configuration,most,\
  debootstrap,less,exim4-daemon-light,sensord,etckeeper,locales,manpages-posix,\
  iotop,smartmontools,iftop,intel-microcode,deborphan,command-not-found,nfs-common,\
  pciutils,pv,htop,radvd,tmux,fail2ban,python-gamin,debian-security-support,\
  dnsutils,console-setup,ebtables,parted

chroot /target /bin/bash -c "dpkg-reconfigure -plow unattended-upgrades"

wait_for_key
###############################################################################

h "install kernel and bootloader"
chroot /target apt-get -y install linux-image-amd64
chroot /target apt-get -y install grub2
chroot /target /bin/bash -c "update-initramfs -k all -u"
for disk in `lsblk -d -o NAME -n | grep sd`; do
  chroot /target /bin/bash -c "grub-install --no-floppy --recheck /dev/$disk"
done
chroot /target /bin/bash -c "update-grub2"
wait_for_key
###############################################################################


h "installing authorized_keys"
mkdir -m 0700 /newroot/root/.ssh
cat >/newroot/root/.ssh/authorized_keys <<EOF
${SSH_KEY}
EOF

h "setting root password"
chroot /newroot passwd -S root
cat <<EOF | chroot /newroot passwd root
${INITIAL_ROOT_PASSWORD}
${INITIAL_ROOT_PASSWORD}
EOF
wait_for_key

echo "now reboot into the new machine "

exit
