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
for disk in `lsblk -d -o NAME -n`; do
  sgdisk -Z $disk 
done
