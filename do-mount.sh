#!/bin/bash

if [ ! -d /newroot ]; then
	mkdir /newroot
fi

mount /dev/vg0/rootfs /newroot
mount /dev/vg0/home /newroot/home
mount /dev/vg0/tmp /newroot/tmp
mount /dev/vg0/var /newroot/var
mount /dev/md0 /newroot/boot
mount --rbind /dev /newroot/dev
mount --rbind /proc /newroot/proc
mount --rbind /sys /newroot/sys
