#!/bin/bash

if [ ! -d /newroot ]; then
	mkdir /newroot
fi

mount /dev/vg0/rootfs /newroot
mount /dev/md0 /newroot/boot
mount --rbind /dev /newroot/dev
mount --rbind /proc /newroot/proc
mount --rbind /sys /newroot/sys
