#!/bin/bash


MOUNTPOINT=/tmp/mnt/do-snapshot
mkdir -p $MOUNTPOINT

DEV=`mount | grep btrfs | grep 'subvol=/arch' | awk '{print $1}'`

# mount the root filesystem
mount -t btrfs -o rw,noatime,compress=lzo,ssd,discard,space_cache,autodefrag $DEV $MOUNTPOINT


cd $MOUNTPOINT/snapshots


function create_snapshot()
{
	name=$1
	suffix=`date +%Y%m%d`
	if [ -d ${name}_bak_$suffix ]; then
		number=1
		while [ -d ${name}_bak_$suffix.$number ]; do
			number=`expr $number + 1`
		done
		# create readonly snapshot
		btrfs subvolume snapshot -r ../${name}/ ${name}_bak_$suffix.$number
	else
		# create readonly snapshot
		btrfs subvolume snapshot -r ../${name}/ ${name}_bak_$suffix
	fi
}

function remove_snapshot()
{
	name=$1
	suffix=`date +%Y%m%d -d "31 day ago"`
	snapshots=`find . -maxdepth 1 -type d -name "${name}_bak_${suffix}*"`
	if [ $? -eq 0 ]; then
		for snapshot in ${snapshots}; do
			# delete the snapshot
			btrfs subvolume delete $snapshot
		done
	fi
}

# create arch subvol snapshot
create_snapshot arch
# create home subvol snapshot
create_snapshot home

# remove expired snapshots
remove_snapshot arch
remove_snapshot home


cd /tmp
umount $MOUNTPOINT
