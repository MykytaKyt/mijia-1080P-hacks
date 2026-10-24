#!/bin/sh
## valhallad.sh - background helper started by valhalla.sh.
##
## Runs from /tmp (copied by valhalla.sh) and does:
##   * Wi-Fi setup mode: when the camera has no Wi-Fi settings or cannot
##     connect, start the "Mijia-Setup-XXXX" access point with a setup page
##     at http://192.168.14.1. Retry the configured network regularly.
##   * Restart SSH, the web server and Samba if they die.
##   * Sync the clock with NTP.
##
## Stop it with: touch /tmp/valhalla.stop

. /tmp/valhalla.env
. /tmp/valhalla_lib.sh

PIDFILE=/var/run/valhallad.pid
STOPFILE=/tmp/valhalla.stop
RECONNECT_FLAG=/tmp/wifi_reconnect
TICK=5

WIFI_SETUP_AP=$(cfg WIFI_SETUP_AP 1)
WIFI_SETUP_TIMEOUT=$(cfg WIFI_SETUP_TIMEOUT 120)
SETUP_RETRY=$(cfg SETUP_RETRY 600)
NO_WIFI_DELAY=20
NTP_ENABLED=$(cfg NTP_ENABLED 1)
NTP_SERVER=$(cfg NTP_SERVER pool.ntp.org)
NTP_INTERVAL=21600

now()
{
	cut -d '.' -f 1 /proc/uptime
}

## --- Wi-Fi state machine ---------------------------------------------
## boot: waiting for the first connection
## ok:   connected (or setup mode disabled)
## ap:   setup access point is running
## try:  setup mode, testing the configured network

wifi_state=boot
wifi_since=$(now)
ap_started=$wifi_since

## The setup page saved a network: try it now.
wifi_try_saved()
{
	rm -f "$RECONNECT_FLAG"
	wifi_credentials || return 1
	setup_ap_stop
	wifi_connect
	wifi_state=try
	wifi_since=$(now)
}

wifi_tick()
{
	_t=$(now)
	case $wifi_state in
	boot)
		if wifi_connected; then
			log "Wi-Fi connected, IP $(wifi_ip)"
			wifi_state=ok
		elif ! enabled "$WIFI_SETUP_AP"; then
			wifi_state=ok
		elif [ -f "$RECONNECT_FLAG" ]; then
			wifi_try_saved
		elif ap_is_up; then
			## The firmware's pairing network is up: serve the page there and
			## leave it alone, so a phone already on it is not disconnected.
			setup_web_start
		elif ! wifi_credentials && [ $((_t - wifi_since)) -ge "$NO_WIFI_DELAY" ]; then
			## Nothing to connect to: no need to wait for the full timeout.
			log "No Wi-Fi network configured"
			setup_ap_start
			wifi_state=ap
			wifi_since=$_t
			ap_started=$_t
		elif [ $((_t - wifi_since)) -ge "$WIFI_SETUP_TIMEOUT" ]; then
			log "No Wi-Fi connection after ${WIFI_SETUP_TIMEOUT}s"
			setup_ap_start
			wifi_state=ap
			wifi_since=$_t
			ap_started=$_t
		fi
		;;
	ap)
		## The firmware may restart Wi-Fi and kill our access point.
		if ! pidof hostapd > /dev/null 2>&1 && [ $((_t - ap_started)) -ge 30 ]; then
			log "Setup access point is gone, starting it again"
			setup_ap_start
			ap_started=$_t
		fi
		if [ -f "$RECONNECT_FLAG" ]; then
			wifi_try_saved || wifi_since=$_t
		elif [ $((_t - wifi_since)) -ge "$SETUP_RETRY" ]; then
			wifi_try_saved || wifi_since=$_t
		fi
		;;
	try)
		if wifi_connected; then
			log "Wi-Fi connected, IP $(wifi_ip)"
			wifi_state=ok
		elif [ $((_t - wifi_since)) -ge 60 ]; then
			log "Could not connect to '$WIFI_SSID', back to setup mode"
			setup_ap_start
			wifi_state=ap
			wifi_since=$_t
			ap_started=$_t
		fi
		;;
	esac
	echo "$wifi_state" > /tmp/wifi_state
}

## --- service watchdog ------------------------------------------------

pid_alive()
{
	[ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null
}

services_tick()
{
	if [ -f "$TOOLS/dropbear/dropbearmulti" ] && ! pid_alive /var/run/dropbear.pid; then
		log "Watchdog: restarting SSH server"
		run "$TOOLS/dropbear/dropbearmulti" dropbear -R -p 22 -P /var/run/dropbear.pid
	fi
	if enabled "$HTTP_ENABLED" && ! pid_alive /var/run/lighttpd.pid; then
		log "Watchdog: restarting web server"
		run "$TOOLS/bin/lighttpd" -f "$TOOLS/etc/lighttpd.conf"
	fi
	if enabled "$SAMBA_ENABLED" && ! pidof smbd > /dev/null 2>&1; then
		log "Watchdog: restarting Samba"
		run "$TOOLS/bin/smbd" -D
	fi
}

## --- NTP -------------------------------------------------------------

ntp_last=0

## Fallback when the firmware has no ntpd: take the time from the Date
## header of a plain HTTP request (accurate to about a second).
http_time_sync()
{
	_d=""
	for _url in http://captive.apple.com/ http://connectivitycheck.gstatic.com/generate_204 \
		http://www.msftconnecttest.com/connecttest.txt; do
		_d=$(wget -S -O /dev/null -T 10 "$_url" 2>&1 | sed -n 's/^ *[Dd]ate: *//p' | head -n 1 | tr -d '\r')
		[ -n "$_d" ] && break
	done
	[ -n "$_d" ] || return 1
	## "Sat, 24 Oct 2026 15:04:05 GMT"
	# shellcheck disable=SC2086 # split the date into words
	set -- $_d
	[ $# -ge 5 ] || return 1
	_day=${2#0}
	_mon=$(echo "JanFebMarAprMayJunJulAugSepOctNovDec" | awk -v m="$3" '{ print (index($0, m) + 2) / 3 }')
	[ "$_mon" -ge 1 ] 2>/dev/null || return 1
	date -u -s "$4-$(printf '%02d' "$_mon")-$(printf '%02d' "$_day") $5" > /dev/null 2>&1
}

ntp_tick()
{
	enabled "$NTP_ENABLED" || return 0
	wifi_connected || return 0
	_t=$(now)
	[ "$ntp_last" -eq 0 ] || [ $((_t - ntp_last)) -ge $NTP_INTERVAL ] || return 0
	ntp_last=$_t
	if command -v ntpd > /dev/null 2>&1 && ntpd -n -q -p "$NTP_SERVER" > /dev/null 2>&1; then
		log "Time: clock set by NTP to $(date)"
	elif busybox ntpd --help > /dev/null 2>&1 && busybox ntpd -n -q -p "$NTP_SERVER" > /dev/null 2>&1; then
		log "Time: clock set by NTP to $(date)"
	elif http_time_sync; then
		log "Time: clock set from an HTTP server to $(date)"
	else
		log "Time: sync failed, retrying in 5 minutes"
		ntp_last=$((_t - NTP_INTERVAL + 300))
	fi
}

## --- main loop -------------------------------------------------------

echo $$ > "$PIDFILE"
rm -f "$STOPFILE"
log "valhallad started"
_n=0
while [ ! -f "$STOPFILE" ]; do
	wifi_tick
	if [ $((_n % 12)) -eq 0 ]; then
		services_tick
		ntp_tick
	fi
	_n=$((_n + 1))
	sleep $TICK
done
log "valhallad stopped"
rm -f "$PIDFILE"
