#!/bin/sh
## valhallad.sh - background helper started by valhalla.sh.
##
## Runs from /tmp (copied by valhalla.sh) and does:
##   * Wi-Fi setup mode: when the camera has no Wi-Fi settings or cannot
##     connect, start the "Mijia-Setup-XXXX" access point with a setup page
##     at http://192.168.14.1. Retry the configured network regularly.
##   * Restart SSH, the web server and Samba if they die.
##   * Sync the clock with NTP.
##   * Switch the image between the day and night profiles.
##
## Stop it with: touch /tmp/valhalla.stop

## ifconfig, iwconfig, reboot... live in /sbin, which is not in PATH
## when the daemon is restarted from an SSH session.
PATH=/sbin:/usr/sbin:/bin:/usr/bin:$PATH
export PATH

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
	ok)
		link_tick
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

## --- Wi-Fi link watchdog ---------------------------------------------
## The router can drop the camera (seen: "Received disassociation request
## on mlan0"), and the camera then stayed offline. mlan0 keeps its IP
## address after that, so check that the gateway answers instead, and
## join the network again after LINK_TIMEOUT seconds without it.

LINK_TIMEOUT=60
link_lost=0

gateway()
{
	awk '$1 == "mlan0" && $2 == "00000000" {
		g = $3
		printf "%d.%d.%d.%d\n", "0x" substr(g, 7, 2), "0x" substr(g, 5, 2), "0x" substr(g, 3, 2), "0x" substr(g, 1, 2)
		exit
	}' /proc/net/route
}

link_ok()
{
	_gw=$(gateway)
	[ -n "$_gw" ] || return 1
	ping -c 1 -W 2 "$_gw" > /dev/null 2>&1 || ping -c 1 -W 2 "$_gw" > /dev/null 2>&1
}

link_tick()
{
	## Only with a network from midgard.ini, and every other tick.
	wifi_credentials || return 0
	[ $((_n % 2)) -eq 0 ] || return 0
	_t=$(now)
	if link_ok; then
		if [ "$link_lost" -ne 0 ]; then
			log "Wi-Fi: gateway reachable again"
			link_lost=0
		fi
		return 0
	fi
	if [ "$link_lost" -eq 0 ]; then
		link_lost=$_t
		return 0
	fi
	[ $((_t - link_lost)) -ge "$LINK_TIMEOUT" ] || return 0
	log "Wi-Fi: no gateway for $((_t - link_lost))s, connecting to '$WIFI_SSID' again"
	wifi_connect
	link_lost=$_t
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
	_err=""
	for _url in http://captive.apple.com/ http://connectivitycheck.gstatic.com/generate_204 \
		http://www.msftconnecttest.com/connecttest.txt; do
		_out=$(wget -S -O /dev/null -T 10 "$_url" 2>&1)
		case "$_out" in
		*"nrecognized option"* | *"nvalid option"* | *"Usage:"*)
			## Older busybox wget without -T
			_out=$(wget -S -O /dev/null "$_url" 2>&1)
			;;
		esac
		_d=$(echo "$_out" | sed -n 's/^ *[Dd]ate: *//p' | head -n 1 | tr -d '\r')
		[ -n "$_d" ] && break
		_err="$_url: $(echo "$_out" | grep -v '^ *$' | tail -n 1)"
	done
	if [ -z "$_d" ]; then
		log "Time: no Date header from any server (last: $_err)"
		return 1
	fi
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

## --- night mode ------------------------------------------------------
## The stock firmware switches day/night in miot_devicekit, which the
## cloud options stop. It also drives the IR LEDs, and writing to the IR
## LED from the hack hangs the camera. So only the image profile is
## switched here (black and white, more gain), from the scene brightness
## the ISP measures. The IR LEDs and the IR-cut filter are not touched.

NIGHT_MODE=$(cfg NIGHT_MODE off)
NIGHT_EV_ON=$(cfg NIGHT_EV_ON 150)
NIGHT_EV_OFF=$(cfg NIGHT_EV_OFF 500)
NIGHT_TICKS=3
ISP_CMD=/proc/isp328/command
ISP_CFG=/gm/config/isp328_ov2718

## The firmware starts in the day profile.
night_state=day
night_count=0
night_hold=0

isp_ev()
{
	sed -n 's/^ *ev value *\([0-9][0-9]*\).*/\1/p' /proc/isp328/ae/info 2>/dev/null | head -n 1
}

night_set()
{
	[ -w "$ISP_CMD" ] || return 1
	if [ "$1" = night ]; then
		echo "w daynight 1" > "$ISP_CMD"
		echo "w dr_mode 0" > "$ISP_CMD"
		echo "w reload_cfg ${ISP_CFG}_night.cfg" > "$ISP_CMD"
	else
		echo "w daynight 0" > "$ISP_CMD"
		echo "w reload_cfg ${ISP_CFG}.cfg" > "$ISP_CMD"
	fi
	night_state=$1
	echo "$1" > /tmp/night_state
	log "Night mode: $1 ($2)"
}

night_tick()
{
	case $NIGHT_MODE in
	night)
		[ "$night_state" = night ] || night_set night "always on"
		return 0
		;;
	auto) ;;
	*) return 0 ;;
	esac
	## Let the exposure settle after a switch.
	if [ "$night_hold" -gt 0 ]; then
		night_hold=$((night_hold - 1))
		return 0
	fi
	_ev=$(isp_ev)
	[ -n "$_ev" ] || return 0
	echo "$_ev" > /tmp/night_ev
	_want=$night_state
	if [ "$_ev" -lt "$NIGHT_EV_ON" ]; then
		_want=night
	elif [ "$_ev" -gt "$NIGHT_EV_OFF" ]; then
		_want=day
	fi
	if [ "$_want" = "$night_state" ]; then
		night_count=0
		return 0
	fi
	night_count=$((night_count + 1))
	[ "$night_count" -ge "$NIGHT_TICKS" ] || return 0
	night_count=0
	night_hold=6
	night_set "$_want" "EV $_ev"
}

## --- main loop -------------------------------------------------------

echo $$ > "$PIDFILE"
rm -f "$STOPFILE"
log "valhallad started"
_n=0
while [ ! -f "$STOPFILE" ]; do
	wifi_tick
	night_tick
	if [ $((_n % 12)) -eq 0 ]; then
		services_tick
		ntp_tick
	fi
	_n=$((_n + 1))
	sleep $TICK
done
log "valhallad stopped"
rm -f "$PIDFILE"
