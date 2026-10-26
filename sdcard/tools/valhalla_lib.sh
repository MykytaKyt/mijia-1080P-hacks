#!/bin/sh
## Shared helpers for valhalla.sh and valhallad.sh. Source it, do not run it.
## valhalla.sh copies it to /tmp so the daemon does not keep the SD card busy.
##
## Expects: INI (path of midgard.ini), LOGFILE (may be empty).

## --- logging and config ----------------------------------------------

log()
{
	echo "$*"
	[ -n "$LOGFILE" ] && echo "$(date +"%Y-%m-%d %H:%M:%S") $*" >> "$LOGFILE" 2>/dev/null
}

## Run a command and append its output to the log.
run()
{
	if [ -n "$LOGFILE" ]; then
		"$@" >> "$LOGFILE" 2>&1
	else
		"$@" > /dev/null 2>&1
	fi
}

## cfg KEY DEFAULT - read KEY from midgard.ini (tolerates CRLF and spaces).
cfg()
{
	_v=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$INI" 2>/dev/null | tail -n 1 |
		cut -d '=' -f 2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	[ -z "$_v" ] && _v=$2
	echo "$_v"
}

## cfg_raw KEY - like cfg, but keeps leading and trailing spaces. Used for
## the Wi-Fi name and password, which may end in a space ("Extreme ").
cfg_raw()
{
	grep -E "^[[:space:]]*$1[[:space:]]*=" "$INI" 2>/dev/null | tail -n 1 | cut -d '=' -f 2- | tr -d '\r'
}

enabled()
{
	[ "$1" = "1" ]
}

## --- Wi-Fi -----------------------------------------------------------

AP_IP=192.168.14.1

wifi_connected()
{
	ifconfig mlan0 2>/dev/null | grep -q "inet addr"
}

wifi_ip()
{
	ifconfig mlan0 2>/dev/null | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1
}

## Sets WIFI_SSID, WIFI_PASSWD, WIFI_KEY_MGMT. midgard.ini wins over the
## network stored by the Mi Home app. Returns 1 when none is configured.
wifi_credentials()
{
	WIFI_SSID=$(cfg_raw miio_ssid)
	WIFI_PASSWD=$(cfg_raw miio_passwd)
	WIFI_KEY_MGMT=$(cfg miio_key_mgmt "WPA")
	if [ -z "$WIFI_SSID" ] && [ -x /usr/sbin/nvram ]; then
		WIFI_SSID=$(/usr/sbin/nvram get miio_ssid 2>/dev/null)
		WIFI_KEY_MGMT=$(/usr/sbin/nvram get miio_key_mgmt 2>/dev/null)
		WIFI_PASSWD=$(/usr/sbin/nvram get miio_passwd 2>/dev/null)
	fi
	[ "$WIFI_KEY_MGMT" = "NONE" ] && WIFI_PASSWD=""
	[ -n "$WIFI_SSID" ]
}

## Join WIFI_SSID as a client (same steps as the stock wifi_start.sh).
wifi_connect()
{
	log "Connecting to Wi-Fi '$WIFI_SSID'"
	_conf=/tmp/wpa_supplicant.conf
	{
		echo "ctrl_interface=/var/run/wpa_supplicant"
		echo "update_config=1"
		echo "network={"
		printf '\tssid="%s"\n' "$WIFI_SSID"
		if [ -z "$WIFI_PASSWD" ]; then
			printf '\tkey_mgmt=NONE\n'
		else
			printf '\tpsk="%s"\n' "$WIFI_PASSWD"
			printf '\tkey_mgmt=WPA-PSK\n'
			printf '\tproto=WPA WPA2\n'
		fi
		printf '\tscan_ssid=1\n'
		echo "}"
	} > "$_conf"
	chmod 600 "$_conf"
	killall udhcpc wpa_supplicant hostapd udhcpd wpa_cli > /dev/null 2>&1
	ifconfig uap0 down 2>/dev/null
	ifconfig mlan0 up
	iwconfig mlan0 mode Managed 2>/dev/null
	mkdir -p /var/run/wpa_supplicant
	run wpa_supplicant -Dnl80211 -imlan0 -c "$_conf" -B
	[ -x /mnt/data/ot_wifi_tool/wpa_event.sh ] &&
		wpa_cli -i mlan0 -B -a /mnt/data/ot_wifi_tool/wpa_event.sh > /dev/null 2>&1
	run udhcpc -i mlan0 -S -b
}

## Save the list of visible networks for the setup page.
wifi_scan()
{
	_out=/tmp/wifi_scan.txt
	: > "$_out.new"
	ifconfig mlan0 up 2>/dev/null
	if pidof wpa_supplicant > /dev/null 2>&1; then
		wpa_cli -i mlan0 scan > /dev/null 2>&1
		sleep 4
		wpa_cli -i mlan0 scan_results 2>/dev/null |
			awk -F '\t' 'NR > 1 && $5 != "" { print $5 }' >> "$_out.new"
	fi
	if [ ! -s "$_out.new" ] && command -v iwlist > /dev/null 2>&1; then
		iwlist mlan0 scan 2>/dev/null | sed -n 's/.*ESSID:"\(.*\)".*/\1/p' >> "$_out.new"
	fi
	sort -u "$_out.new" | grep -v '^$' > "$_out"
	rm -f "$_out.new"
}

## Start the setup access point with the Wi-Fi setup page on port 80.
setup_ap_start()
{
	_pass=$(cfg SETUP_AP_PASS "mijia1080")
	_mac=$(cat /sys/class/net/mlan0/address 2>/dev/null | tr -d ':' | tr 'a-f' 'A-F')
	_ssid="Mijia-Setup-$(echo "$_mac" | tail -c 5)"
	[ ${#_mac} -ge 4 ] || _ssid="Mijia-Setup"

	wifi_scan
	log "Starting setup access point '$_ssid', setup page: http://$AP_IP"

	killall udhcpc wpa_supplicant hostapd udhcpd wpa_cli > /dev/null 2>&1
	ifconfig mlan0 down 2>/dev/null
	ifconfig uap0 up
	ifconfig uap0 $AP_IP netmask 255.255.255.0

	_conf=/tmp/valhalla_hostapd.conf
	if [ -f /etc/hostapd.conf ]; then
		grep -v -E '^(ssid|wpa|wpa_passphrase|wpa_key_mgmt|wpa_pairwise|rsn_pairwise|auth_algs)=' \
			/etc/hostapd.conf > "$_conf"
	else
		printf 'interface=uap0\ndriver=nl80211\nhw_mode=g\nchannel=6\nctrl_interface=/var/run/hostapd\n' > "$_conf"
	fi
	echo "ssid=$_ssid" >> "$_conf"
	if [ ${#_pass} -ge 8 ]; then
		printf 'auth_algs=1\nwpa=2\nwpa_key_mgmt=WPA-PSK\nrsn_pairwise=CCMP\nwpa_passphrase=%s\n' \
			"$_pass" >> "$_conf"
	else
		[ -n "$_pass" ] && log "WARNING: SETUP_AP_PASS is shorter than 8 characters, the access point is open"
	fi
	mkdir -p /var/run/hostapd
	run hostapd "$_conf" -B

	mkdir -p /var/lib/misc
	touch /var/lib/misc/udhcpd.leases
	cat > /tmp/valhalla_udhcpd.conf << EOF
interface uap0
start 192.168.14.100
end 192.168.14.150
option subnet 255.255.255.0
option router $AP_IP
lease_file /var/lib/misc/udhcpd.leases
EOF
	run udhcpd /tmp/valhalla_udhcpd.conf

	echo "$_ssid" > /tmp/setup_ap.ssid
	setup_web_start

	sleep 1
	pidof hostapd > /dev/null 2>&1 || log "ERROR: hostapd is not running"
	pidof udhcpd > /dev/null 2>&1 || log "ERROR: udhcpd is not running, phones will not get an address"
}

## True while an access point is up on uap0: ours, or the firmware's own
## Mi Home pairing network ("...-camera-..._mibtXXXX"), both on 192.168.14.1.
ap_is_up()
{
	ifconfig uap0 2>/dev/null | grep -q "inet addr:$AP_IP"
}

## Serve the Wi-Fi setup page on http://192.168.14.1 (port 80).
setup_web_start()
{
	if [ -f /var/run/lighttpd-setup.pid ] && kill -0 "$(cat /var/run/lighttpd-setup.pid)" 2>/dev/null; then
		return 0
	fi
	[ -s /tmp/wifi_scan.txt ] || wifi_scan
	log "Starting Wi-Fi setup page on http://$AP_IP"
	mkdir -p /var/run
	if run "$TOOLS/bin/lighttpd" -f "$TOOLS/etc/lighttpd-setup.conf"; then
		log "Setup page is running"
	else
		log "ERROR: setup web server failed to start (see tools/tmp/lighttpd-setup.log)"
	fi
}

setup_ap_stop()
{
	log "Stopping setup access point"
	if [ -f /var/run/lighttpd-setup.pid ]; then
		kill "$(cat /var/run/lighttpd-setup.pid)" 2>/dev/null
		rm -f /var/run/lighttpd-setup.pid
	fi
	killall hostapd udhcpd > /dev/null 2>&1
	ifconfig uap0 down 2>/dev/null
	rm -f /tmp/setup_ap.ssid
}
