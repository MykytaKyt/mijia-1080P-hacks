#!/bin/sh
## inject.sh - called by post-ota.sh after a Xiaomi firmware (OTA) update.
##
## The update replaces the data partition (/dev/mtdblock3) and with it the
## patched wifi_start.sh that starts this hack. This script frees the
## partition, mounts it read-write and writes the patched wifi_start.sh
## back, so the hack keeps working after the update.
##
## During the update only the copies of busybox and the loader in /tmp are
## safe to use, hence the $BB prefix.

BB="/tmp/ld-uClibc.so.0 /tmp/busybox"
sd_mountdir=/tmp/sd
pathDest=/tmp/Key
SRC=$sd_mountdir/tools/wifi_start.sh
DST=$pathDest/ot_wifi_tool/wifi_start.sh

log()
{
	$BB echo -e "$*" | $BB logger -t miio_ota
}

## Run a command and send its output to the log; keeps the exit code.
run()
{
	_out=$("$@" 2>&1)
	_rc=$?
	[ -n "$_out" ] && log "$_out"
	return $_rc
}

log "Injector start"
log "----------------------------------------------------"
$BB sync
$BB mkdir -p $pathDest

log "/proc/mtd:"
run $BB cat /proc/mtd

## Stop the RTSP server: it runs from the SD card and keeps it busy.
log "Stopping RTSP server"
$BB touch /tmp/rtsp.stop
if [ -f /var/run/rtsp_watchdog.pid ]; then
	$BB kill "$($BB cat /var/run/rtsp_watchdog.pid)" 2>/dev/null
fi
$BB killall -9 rtsp_basic 2>/dev/null

log "Mounts:"
run $BB mount

cd /

## Stop every process running from the data partition so it can be unmounted.
log "Processes on /mnt/data:"
run $BB sh -c "$BB ps | $BB grep /mnt/data | $BB grep -v grep"
listProcessPID=$($BB ps | $BB grep /mnt/data | $BB grep -v grep | $BB awk '{print $1}')
for process in $listProcessPID; do
	log "Killing PID $process"
	$BB kill -9 "$process" 2>/dev/null
	$BB usleep 1000000
done
$BB usleep 5000000
log "Processes on /mnt/data after kill:"
run $BB sh -c "$BB ps | $BB grep /mnt/data | $BB grep -v grep"

$BB sync
$BB usleep 2000000

log "Unmounting /dev/mtdblock3"
if ! run $BB umount /dev/mtdblock3; then
	log "umount /dev/mtdblock3 FAILED"
	exit 0
fi

log "Mounting /dev/mtdblock3 on $pathDest"
## A read-only mount first lets jffs2 finish scanning the new partition.
run $BB mount -o ro -t jffs2 /dev/mtdblock3 $pathDest
$BB usleep 5000000
run $BB umount $pathDest
if ! run $BB mount -o rw -t jffs2 /dev/mtdblock3 $pathDest; then
	log "mount /dev/mtdblock3 FAILED"
	exit 0
fi

if [ -d $pathDest/ot_wifi_tool ]; then
	for tries in 1 2 3 4 5 6 7 8 9 10; do
		log "[$tries] writing $DST"
		run $BB cp $SRC $DST
		run $BB chmod 755 $DST
		$BB sync
		## Remount to make sure the data really reached the flash.
		run $BB umount $pathDest
		$BB usleep 2000000
		run $BB mount -o rw -t jffs2 /dev/mtdblock3 $pathDest
		if $BB cmp -s $SRC $DST; then
			log "wifi_start.sh written and verified"
			break
		fi
		log "wifi_start.sh does not match, retrying"
	done
else
	log "Error: $pathDest/ot_wifi_tool does not exist"
fi

$BB sync
run $BB umount $pathDest
$BB sync
$BB umount /mnt/media/mmcblk0p1 2>/dev/null
$BB umount /mnt/media/mmcblk0 2>/dev/null

log "Injector end"
exit 0
