#!/bin/sh
#
# apt install -y mt-st zstd
#
#
TAPE_MOUNTPOINT=/tape
TAPE_DEVICE_NAME=10WT097544
ZFS_DATASET=zdata
TAPE_DEVICE_PATH=/dev/tape/by-id/scsi-$TAPE_DEVICE_NAME-nst

create_dir() {
	if [ ! -d "$TAPE_MOUNTPOINT" ]; then
		mkdir $TAPE_MOUNTPOINT
	fi
	return 0
}

remove_dir () {
	rm -rf $TAPE_MOUNTPOINT
}

tape_umount() {
	mountpoint $TAPE_MOUNTPOINT > /dev/null 2>&1

	if [ "$?" -eq "0" ]; then
		echo "Unmount $TAPE_MOUNTPOINT"
		umount $TAPE_MOUNTPOINT
	fi
}

destroy_zfs_snapshots() {
	zfs destroy -r "$ZFS_DATASET@backup-tape-full" > /dev/null 2>&1
	zfs destroy -r "$ZFS_DATASET@backup-tape-1" > /dev/null 2>&1
	zfs destroy -r "$ZFS_DATASET@backup-tape-2" > /dev/null 2>&1
	zfs destroy -r "$ZFS_DATASET@backup-tape-3" > /dev/null 2>&1
}

tape_is_load() {
	mt -f $TAPE_DEVICE_PATH load > /dev/null 2>&1
	if [ "$?" -eq "0" ]; then
		return 0
	fi
	return 1
}

wipe_tape() {
	echo "rewind tape...."

	mt -f $TAPE_DEVICE_PATH rewind
	if [ "$?" -ne "0" ]; then
		echo "rewind tape failed"
		return 1
	fi

	echo "erase tape...."

	mt -f $TAPE_DEVICE_PATH erase 0

	if [ "$?" -ne "0" ]; then
        echo "wipe tape failed"
        return 1
    fi
	
	echo "rewind tape....."
	mt -f $TAPE_DEVICE_PATH rewind

	if [ "$?" -ne "0" ]; then
		echo "rewind tape failed"
		return 1
	fi

	return 0
}

set_tape_param() {
	mt -f $TAPE_DEVICE_PATH setblk 0
	mt -f $TAPE_DEVICE_PATH defblksize 0
	mt -f $TAPE_DEVICE_PATH defcompression 1
	mt -f $TAPE_DEVICE_PATH compression 1
}

full_backup() {
	tape_is_load

	if [ "$?" -ne "0" ]; then
		echo "no tape in drive"
		exit 1
	fi
	
	wipe_tape

	if [ "$?" -ne "0" ]; then
		exit 1
	fi

	echo "wipe the tape succeeded."

	set_tape_param

	destroy_zfs_snapshots

	ZFS_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-full"
	zfs snapshot -r $ZFS_SNAPSHOT_NAME

	if [ "$?" -ne "0" ]; then
		echo "failed create zfs snapshot $ZFS_SNAPSHOT_NAME"
		tape_umount
		exit 1
	fi

	echo "create zfs snapshot $ZFS_SNAPSHOT_NAME successful."
	
	echo "Backing up zfs data to tape...."

	zfs send -R $ZFS_SNAPSHOT_NAME | zstdmt | mbuffer -m 1G -L -P 80 | dd of=$TAPE_DEVICE_PATH bs=256K iflag=fullblock
	
	if [ "$?" -ne "0" ]; then
		echo "Failed to backup data to tape."
		exit 1
	fi
	echo "Successfully backed up zfs data to tape."
}

inc_backup() {
	tape_is_load

	if [ "$?" -ne "0" ]; then
		echo "no tape in drive"
		exit 1
	fi

	set_tape_param

	mt -f $TAPE_DEVICE_PATH eod

	if [ "$?" -ne "0" ]; then
		echo "move tape to eod failed"
		exit 1
	fi
	
	zfs destroy -r $ZFS_SNAPSHOT_NAME > /dev/null 2>&1

	zfs snapshot -r $ZFS_SNAPSHOT_NAME
	if [ "$?" -ne "0" ]; then
		echo "failed create zfs snapshot $ZFS_SNAPSHOT_NAME"
		tape_umount
		exit 1
	fi

	zfs send -R -i $ZFS_PREV_SNAPSHOT_NAME $ZFS_SNAPSHOT_NAME | zstdmt | mbuffer -m 1G -L -P 80 | dd of=$TAPE_DEVICE_PATH bs=256K iflag=fullblock

	if [ "$?" -ne "0" ]; then
		echo "Failed to backup data to tape."
		exit 1
	fi

	echo "Successfully backed up zfs data to tape."
}


inc_backup_1() {
	ZFS_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-1"
	ZFS_PREV_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-full"

	inc_backup
}

inc_backup_2() {
	ZFS_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-2"
	ZFS_PREV_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-1"

	inc_backup
}


inc_backup_3() {
	ZFS_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-3"
	ZFS_PREV_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-2"

	inc_backup
}

inc_backup_4() {
	ZFS_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-4"
	ZFS_PREV_SNAPSHOT_NAME="$ZFS_DATASET@backup-tape-3"

	inc_backup
}


case "$1" in
	"full") full_backup
	;;
	"inc1") inc_backup_1
	;;
	"inc2") inc_backup_2
	;;
	"inc3") inc_backup_3
	;;
	"inc4") inc_backup_4
	;;
esac
