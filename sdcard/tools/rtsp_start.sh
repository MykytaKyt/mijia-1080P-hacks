#!/bin/sh
## RTSP server launcher with a watchdog.
##
## valhalla.sh copies this script to /tmp/rtsp_start.sh and writes:
##   /tmp/rtsp.args     encoder options (CONFIG_LINE from midgard.ini)
##   /tmp/rtsp.logfile  where to send the server output
##
## Usage: rtsp_start.sh start|stop|status
## Stream URL: rtsp://<camera-ip>/live/ch00_0

BIN=/tmp/sd/tools/rtsp_basic
PIDFILE=/var/run/rtsp_watchdog.pid
STOPFILE=/tmp/rtsp.stop
STDIN_FIFO=/tmp/rtsp.stdin
START_DELAY=15
RESTART_DELAY=10

is_running()
{
	[ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

watchdog()
{
	ARGS=$(cat /tmp/rtsp.args 2>/dev/null)
	LOG=$(cat /tmp/rtsp.logfile 2>/dev/null)
	[ -n "$LOG" ] || LOG=/dev/null

	## rtsp_basic waits for 'q' on stdin. Give it a FIFO that never sends
	## data and never reaches end-of-file, so it neither exits nor spins.
	[ -p "$STDIN_FIFO" ] || mkfifo "$STDIN_FIFO"
	exec 3<> "$STDIN_FIFO"

	## Give the video driver time to come up during boot.
	sleep $START_DELAY
	while [ ! -f "$STOPFILE" ]; do
		echo "$(date +"%Y-%m-%d %H:%M:%S") starting rtsp_basic $ARGS" >> "$LOG"
		# shellcheck disable=SC2086 # ARGS holds several options
		"$BIN" $ARGS <&3 >> "$LOG" 2>&1
		echo "$(date +"%Y-%m-%d %H:%M:%S") rtsp_basic exited with code $?" >> "$LOG"
		[ -f "$STOPFILE" ] && break
		sleep $RESTART_DELAY
	done
	rm -f "$PIDFILE"
}

case "$1" in
start)
	if is_running; then
		echo "RTSP server already running"
		exit 0
	fi
	if [ ! -f "$BIN" ]; then
		echo "RTSP server not found: $BIN"
		exit 1
	fi
	rm -f "$STOPFILE"
	mkdir -p /var/run
	watchdog < /dev/null > /dev/null 2>&1 &
	echo $! > "$PIDFILE"
	echo "RTSP server started"
	;;
stop)
	touch "$STOPFILE"
	is_running && kill "$(cat "$PIDFILE")" 2>/dev/null
	rm -f "$PIDFILE"
	killall rtsp_basic > /dev/null 2>&1
	echo "RTSP server stopped"
	;;
status)
	if is_running; then
		echo "RTSP server running"
	else
		echo "RTSP server not running"
		exit 1
	fi
	;;
*)
	echo "Usage: $0 start|stop|status"
	exit 1
	;;
esac
exit 0
