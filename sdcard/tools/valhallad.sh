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
		elif [ $((_t - wifi_since)) -ge "$WIFI_SETUP_TIMEOUT" ]; then
			log "No Wi-Fi connection after ${WIFI_SETUP_TIMEOUT}s"
			setup_ap_start
			wifi_state=ap
			wifi_since=$_t
		fi
		;;
	ap)
		if [ -f "$RECONNECT_FLAG" ] ||
			{ [ $((_t - wifi_since)) -ge "$SETUP_RETRY" ] && wifi_credentials; }; then
			rm -f "$RECONNECT_FLAG"
			if wifi_credentials; then
				setup_ap_stop
				wifi_connect
				wifi_state=try
				wifi_since=$_t
			else
				wifi_since=$_t
			fi
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

ntp_tick()
{
	enabled "$NTP_ENABLED" || return 0
	wifi_connected || return 0
	_t=$(now)
	[ "$ntp_last" -eq 0 ] || [ $((_t - ntp_last)) -ge $NTP_INTERVAL ] || return 0
	ntp_last=$_t
	if command -v ntpd > /dev/null 2>&1; then
		_ntp="ntpd"
	elif busybox ntpd --help > /dev/null 2>&1; then
		_ntp="busybox ntpd"
	else
		log "NTP: ntpd not available on this firmware"
		NTP_ENABLED=0
		return 0
	fi
	if $_ntp -n -q -p "$NTP_SERVER" > /dev/null 2>&1; then
		log "NTP: clock set to $(date)"
	else
		log "NTP: sync with $NTP_SERVER failed"
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
