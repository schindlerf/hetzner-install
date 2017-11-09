#!/bin/bash
# Wo möglich Funktionen aus dem Hetzner Installimage Script benutzen

exit

# clean old partition layout
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
for disk in `lsblk -d -o NAME -n | grep sd`; do
  sgdisk -Z /dev/$disk 
done

###############################################################################


for d in `lsblk -d -o NAME -n | grep sd`; do
  parted -a optimal /dev/$d --script \
    unit s \
    mklabel gpt \
    mkpart mbr 2048 4095 \
    mkpart grub 4096 256MB \
    mkpart raid 256MB 100% \
    set 1 bios_grub on \
    set 2 boot on \
    set 3 raid on;
done
partprobe
###############################################################################

# create raid devices

yes | mdadm -q --create -n 2 -l 1 /dev/md0 /dev/sda2 /dev/sdb2;
yes | mdadm -q --create -n 2 -l 1 /dev/md1 /dev/sda3 /dev/sdb3;


###############################################################################
CRYPT_PASSWD='test'
echo -n $CRYPT_PASSWD | cryptsetup --batch-mode -c aes-cbc-essiv:sha256 -s 256 -y luksFormat /dev/md1
echo -n $CRYPT_PASSWD |cryptsetup luksOpen /dev/md1 crypt

###############################################################################

# setup lvm
pvcreate -ff -y /dev/mapper/crypt
vgcreate vg-`hostname` /dev/mapper/crypt

lvcreate -n swap -L 16G vg-`hostname`
lvcreate -n tmp -L 16G vg-`hostname`
lvcreate -n usr -L 10G vg-`hostname`
lvcreate -n home -L 10G vg-`hostname`
lvcreate -n root -L 5G vg-`hostname`
lvcreate -n var-log -L 10G vg-`hostname`
lvcreate -n var -L 10G vg-`hostname`
lvcreate -n gluster -l100%FREE vg-`hostname` /dev/mapper/crypt

pvs
vgs
lvs
###############################################################################

# create filesystems
mkfs.ext4 -L boot /dev/md0
mkswap -f /dev/vg-`hostname`/swap
mkfs.ext4 -L tmp /dev/vg-`hostname`/tmp
mkfs.ext4 -L usr /dev/vg-`hostname`/usr
mkfs.ext4 -L home /dev/vg-`hostname`/home
mkfs.ext4 -L root /dev/vg-`hostname`/root
mkfs.ext4 -L varlog /dev/vg-`hostname`/var-log
mkfs.ext4 -L var /dev/vg-`hostname`/var
mkfs.ext4 -L gluster /dev/vg-`hostname`/gluster
###############################################################################

# mount filesystems stage 1
swapon -v /dev/vg-`hostname`/swap

if [ ! -d /hdd ]; then
    mkdir -pv /hdd
fi

mount -v /dev/vg-$(hostname)/root /hdd/
mkdir -p /hdd/{boot,usr,tmp,home,var,proc,dev,sys}
mount -v /dev/vg-`hostname`/home /hdd/home/
mount -v /dev/vg-`hostname`/tmp /hdd/tmp/
mount -v /dev/vg-`hostname`/usr /hdd/usr/
mount -v /dev/vg-`hostname`/var /hdd/var/
mkdir -pv /hdd/var/log
mount -v /dev/vg-`hostname`/var-log /hdd/var/log/
mount -v /dev/md0 /hdd/boot
###############################################################################

h "running debootstrap"
debootstrap \
  --components=main,contrib,non-free \
  --verbose stretch \
  /hdd \
  http://deb.debian.org/debian/
###############################################################################


cat >/hdd/etc/fstab <<EOF

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

chroot /hdd /bin/bash -c "grep -v swap /etc/fstab >/etc/mtab"

mount -v --rbind /proc/ /hdd/proc/
mount -v --rbind /dev/ /hdd/dev/
mount -v --rbind /sys/ /hdd/sys/

###############################################################################
chroot /hdd /bin/bash -c "apt install locales"
chroot /hdd /bin/bash -c "locale-gen de_DE.UTF-8"
chroot /hdd /bin/bash -c "update-locale LANG=de_DE.UTF-8"

###############################################################################
chroot /hdd /bin/bash -c "dpkg-reconfigure tzdata"

###############################################################################

cat >/hdd/etc/network/interfaces <<EOF
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
cp /etc/resolv.conf /hdd/etc/resolv.conf
sed -i -e 's/your-server.de/'${TARGET_DOMAIN}'/g' /hdd/etc/resolv.conf

cat >/hdd/etc/hosts <<EOF
127.0.0.1	localhost
${TARGET_IPADDR} ${TARGET_HOSTNAME}.${TARGET_DOMAIN} ${TARGET_HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

echo "${TARGET_HOSTNAME}" >/hdd/etc/hostname

###############################################################################

# install missing packages

cp -f /hdd/etc/apt/sources.list /newroot/etc/apt/sources.list.orig
cat <<EOF > /hdd/etc/apt/sources.list

# Packages from the Hetzner Debian Mirror
#deb ftp://mirror.hetzner.de/debian/packages ${DEBIAN_VERSION} main contrib non-free
deb ftp://mirror.hetzner.de/debian/packages ${DEBIAN_VERSION} main contrib non-free
deb ftp://mirror.hetzner.de/debian/security ${DEBIAN_VERSIION}/updates main contrib non-free
deb ftp://ftp.de.debian.org/debian/ ${DEBIAN_VERSION} main contrib non-free
deb http://security.debian.org/ ${DEBIAN_VERSION}/updates main contrib non-free

deb http://ftp.de.debian.org/debian/ ${DEBIAN_VERSION}-backports main contrib non-free
deb http://ftp.de.debian.org/debian ${DEBIAN_VERSION}-proposed-updates main contrib non-free
EOF
###############################################################################

h "update package index and install missing packages"
chmod go+w /hdd/tmp
chmod o+t /hdd/tmp
chroot /hdd apt-get -y update
chroot /hdd apt-get -y install openssh-server lvm2 mdadm initramfs-tools
chroot /hdd /bin/bash -c "/usr/share/mdadm/mkconf > /etc/mdadm/mdadm.conf"
chroot /hdd /bin/bash -c "apt-get -y install console-common manpages-de ifupdown cryptsetup \
  manpages-dev sudo vim console-data htop aptitude rkhunter glances \
  git busybox manpages-posix-dev dropbear-initramfs \
  apt-listchanges logcheck hashalot john firmware-realtek debsecan manpages-de-dev \
  chkrootkit bzip2 bash-completion task-german keyboard-configuration most \
  less exim4-daemon-light etckeeper locales manpages-posix \
  iotop smartmontools iftop intel-microcode deborphan command-not-found nfs-common \
  pciutils pv htop radvd tmux fail2ban python-gamin debian-security-support \
  dnsutils console-setup parted unattended-upgrades"

chroot /hdd /bin/bash -c "dpkg-reconfigure -plow unattended-upgrades"

###############################################################################

chroot /hdd apt-get -y install linux-image-amd64
chroot /hdd apt-get -y install grub2
chroot /hdd /bin/bash -c "update-initramfs -k all -u"
for disk in `lsblk -d -o NAME -n | grep sd`; do
  chroot /hdd /bin/bash -c "grub-install --no-floppy --recheck /dev/$disk"
done
chroot /hdd /bin/bash -c "update-grub2"
###############################################################################


mkdir -m 0700 /hdd/root/.ssh
cat >/hdd/root/.ssh/authorized_keys <<EOF
${SSH_KEY}
EOF

chroot /hdd passwd -S root
cat <<EOF | chroot /hdd passwd root
${INITIAL_ROOT_PASSWORD}
${INITIAL_ROOT_PASSWORD}
EOF

echo "now reboot into the new machine "

exit
