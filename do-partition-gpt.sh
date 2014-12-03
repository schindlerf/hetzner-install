#!/bin/bash

vgchange -a n
mdadm -S --scan

DISKS="sda sdb"

for d in $DISKS; do
	# zap the disk(s)
	sgdisk -Z /dev/$d

	# create BIOS boot partition
	sgdisk -n 3:2048:+1M -t 3:ef02 /dev/$d
	#sgdisk -t 3:ef02 /dev/$d

	# create md0 partition
	sgdisk -n 1:0:+1G -t 1:fd00 /dev/$d
	#sgdisk -t 1:fd00 /dev/$d
	#sgdisk -c 1:md0 /dev/$d

	# create md1 partition
	sgdisk -n 2:0:0 -t 2:fd00 /dev/$d
done

# create raid devices
mdadm -C /dev/md0 -b internal -l 1 -n 2 /dev/sda1 /dev/sdb1
mdadm -C /dev/md1 -b internal -l 1 -n 2 /dev/sda2 /dev/sdb2
