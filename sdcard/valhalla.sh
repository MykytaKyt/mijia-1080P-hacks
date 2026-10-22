#!/bin/sh
## =====================================================================
##  valhalla.sh - main script of the Mijia 1080p hack.
##
##  Runs from the SD card (mounted at /tmp/sd) in two ways:
##    * sourced by ft/ft_boot.sh (factory-test boot hook), or
##    * executed by the patched /mnt/data/ot_wifi_tool/wifi_start.sh.
##  A lock in /tmp makes sure the work is only done once per boot.
##
##  All settings live in midgard.ini on the SD card root.
## =====================================================================

SCRIPT_VERSION="2.0"

sd_mountdir=/tmp/sd
TOOLS=$sd_mountdir/tools
INI=$sd_mountdir/midgard.ini
LOGDIR=$sd_mountdir/logs
LOGFILE=$LOGDIR/log-$(date +"%Y%m%d%H%M").log

## --- helpers ---------------------------------------------------------

log()
{
	echo "$*"
	echo "$(date +"%Y-%m-%d %H:%M:%S") $*" >> "$LOGFILE" 2>/dev/null
}

## Run a command and append its output to the log.
run()
{
	"$@" >> "$LOGFILE" 2>&1
}

## cfg KEY DEFAULT - read KEY from midgard.ini (tolerates CRLF and spaces).
cfg()
{
	_v=$(grep -E "^[[:space:]]*$1[[:space:]]*=" "$INI" 2>/dev/null | tail -n 1 |
		cut -d '=' -f 2- | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	[ -z "$_v" ] && _v=$2
	echo "$_v"
}

enabled()
{
	[ "$1" = "1" ]
}

## Replace a file that lives on a read-only/flash location with a stub
## script, by bind-mounting a copy from /tmp over it.
stub_file()
{
	_target=$1
	_code=$2
	[ -f "$_target" ] || return 0
	grep -q " $_target " /proc/mounts && return 0
	_stub=/tmp/stub_$(basename "$_target")
	printf '#!/bin/sh\n%s\n' "$_code" > "$_stub"
	chmod 755 "$_stub"
	run mount --bind "$_stub" "$_target" && log "  stubbed $_target"
}

## --- steps -----------------------------------------------------------

load_config()
{
	CLOUD_DISABLED=$(cfg CLOUD_DISABLED 0)
	CLOUD_STREAMING_DISABLED=$(cfg CLOUD_STREAMING_DISABLED 0)
	RTSP_ENABLED=$(cfg RTSP_ENABLED 0)
	CONFIG_LINE=$(cfg CONFIG_LINE "-b4096 -f20 -w1920 -h1080 -m1")
	RTSP_LOG=$(cfg RTSP_LOG 0)
	SSH_ROOT_PASS=$(cfg SSH_ROOT_PASS "qwerty123456")
	CAM_HOSTNAME=$(cfg HOSTNAME "Valhalla")
	DISABLED_OTA=$(cfg DISABLED_OTA 0)
	HTTP_ENABLED=$(cfg HTTP_ENABLED 0)
	SAMBA_ENABLED=$(cfg SAMBA_ENABLED 0)
	ENGLISH_VOICE=$(cfg ENGLISH_VOICE 1)
	WIFI_SSID=$(cfg miio_ssid "")
	WIFI_PASSWD=$(cfg miio_passwd "")
	WIFI_KEY_MGMT=$(cfg miio_key_mgmt "WPA")

	log "Configuration:"
	log "  CLOUD_DISABLED=$CLOUD_DISABLED"
	log "  CLOUD_STREAMING_DISABLED=$CLOUD_STREAMING_DISABLED"
	log "  RTSP_ENABLED=$RTSP_ENABLED"
	log "  CONFIG_LINE=$CONFIG_LINE"
	log "  SSH_ROOT_PASS=<hidden, ${#SSH_ROOT_PASS} chars>"
	log "  HOSTNAME=$CAM_HOSTNAME"
	log "  DISABLED_OTA=$DISABLED_OTA"
	log "  HTTP_ENABLED=$HTTP_ENABLED"
	log "  SAMBA_ENABLED=$SAMBA_ENABLED"
	log "  ENGLISH_VOICE=$ENGLISH_VOICE"
	log "  miio_ssid=$WIFI_SSID"

	if [ "$SSH_ROOT_PASS" = "qwerty123456" ]; then
		log "WARNING: the default root password is in use, change SSH_ROOT_PASS in midgard.ini"
	fi
	if [ ${#SSH_ROOT_PASS} -lt 8 ]; then
		log "WARNING: SSH_ROOT_PASS is shorter than 8 characters"
	fi
}

log_versions()
{
	for _f in /mnt/media/mmcblk0p1/os-release /etc/os-release; do
		if [ -f "$_f" ]; then
			log "Contents of $_f:"
			run cat "$_f"
		fi
	done
}

## /etc is on the read-only root filesystem. Copy it to /tmp and bind the
## copy over /etc so we can set the root password and add init scripts.
setup_etc_overlay()
{
	if [ -f /etc/.valhalla ]; then
		return 0
	fi
	log "Creating writable /etc overlay"
	mkdir -p /tmp/etc
	cp -a /etc/. /tmp/etc/ 2>>"$LOGFILE" || cp -r /etc/. /tmp/etc/ 2>>"$LOGFILE"
	if run mount --rbind /tmp/etc /etc; then
		touch /etc/.valhalla
	else
		log "ERROR: could not mount the /etc overlay"
		return 1
	fi
}

set_root_password()
{
	log "Setting root password"
	printf '%s\n%s\n' "$SSH_ROOT_PASS" "$SSH_ROOT_PASS" | passwd root >> "$LOGFILE" 2>&1 ||
		log "ERROR: passwd failed"
}

start_ssh()
{
	_db=$TOOLS/dropbear/dropbearmulti
	if [ ! -f "$_db" ]; then
		log "SSH server not found: $_db"
		return 1
	fi
	if pidof dropbear > /dev/null 2>&1 || pidof dropbearmulti > /dev/null 2>&1; then
		log "SSH server already running"
		return 0
	fi

	mkdir -p /etc/dropbear /var/run

	## Keep one host key per camera on the SD card so clients do not get
	## "host key changed" warnings after every reboot.
	_key=dropbear_ecdsa_host_key
	if [ -s "$TOOLS/dropbear/$_key" ]; then
		cp "$TOOLS/dropbear/$_key" "/etc/dropbear/$_key"
	else
		log "Generating SSH host key"
		run "$_db" dropbearkey -t ecdsa -f "/etc/dropbear/$_key" &&
			cp "/etc/dropbear/$_key" "$TOOLS/dropbear/$_key"
	fi
	chmod 600 "/etc/dropbear/$_key" 2>/dev/null

	for _applet in scp dbclient dropbearkey; do
		ln -sf "$_db" "/etc/dropbear/$_applet"
	done

	log "Starting SSH server on port 22"
	## -R creates any other missing host key type on demand.
	run "$_db" dropbear -R -p 22 -P /var/run/dropbear.pid || log "ERROR: dropbear failed to start"

	## The bundled dropbear has the SFTP server path compiled in.
	if [ ! -f /mnt/media/mmcblk0p1/tools/sftp-server ]; then
		log "WARNING: /mnt/media/mmcblk0p1/tools/sftp-server not found, SFTP will not work"
	fi
}

set_english_voice()
{
	_dir=/mnt/data/sound
	if [ ! -d "$_dir/en" ]; then
		log "English voice files not found in $_dir/en"
		return 0
	fi
	case "$(ls -l "$_dir/booting" 2>/dev/null)" in
	*en/booting*)
		log "English voice already installed"
		return 0
		;;
	esac
	log "Switching voice prompts to English"
	for _f in "$_dir"/en/*; do
		[ -f "$_f" ] || continue
		ln -sf "$_f" "$_dir/$(basename "$_f")"
	done
	sync
}

setup_ota()
{
	if enabled "$DISABLED_OTA"; then
		log "Blocking firmware (OTA) updates"
		stub_file /mnt/data/miio_ota/pre-ota.sh "exit 1"
		return 0
	fi

	## Hook into the OTA process so the hack survives a firmware update:
	## post-ota.sh runs inject.sh, which writes the patched wifi_start.sh
	## back into the new data partition. Only write flash when it changed.
	if [ -d /mnt/data/miio_ota ] && ! cmp -s "$TOOLS/post-ota.sh" /mnt/data/miio_ota/post-ota.sh; then
		log "Installing OTA persistence hook"
		run cp "$TOOLS/post-ota.sh" /mnt/data/miio_ota/post-ota.sh
		sync
	fi
	cp "$TOOLS/inject.sh" /tmp/inject.sh
}

## Join the Wi-Fi network from midgard.ini instead of the one stored by
## the Mi Home app (nvram). Same steps as the stock wifi_start.sh.
connect_wifi_override()
{
	[ -n "$WIFI_SSID" ] || return 0
	## wifi_start.sh reads midgard.ini itself when it called us.
	[ "$VALHALLA_FROM_WIFI" = "1" ] && return 0

	log "Connecting to Wi-Fi '$WIFI_SSID' (from midgard.ini)"
	_conf=/tmp/wpa_supplicant.conf
	{
		echo "ctrl_interface=/var/run/wpa_supplicant"
		echo "update_config=1"
		echo "network={"
		echo "	ssid=\"$WIFI_SSID\""
		if [ "$WIFI_KEY_MGMT" = "NONE" ] || [ -z "$WIFI_PASSWD" ]; then
			echo "	key_mgmt=NONE"
		else
			echo "	psk=\"$WIFI_PASSWD\""
			echo "	key_mgmt=WPA-PSK"
			echo "	proto=WPA WPA2"
		fi
		echo "	scan_ssid=1"
		echo "}"
	} > "$_conf"
	killall udhcpc wpa_supplicant hostapd udhcpd wpa_cli > /dev/null 2>&1
	ifconfig uap0 down 2>/dev/null
	ifconfig mlan0 up
	iwconfig mlan0 mode Managed 2>/dev/null
	mkdir -p /var/run/wpa_supplicant
	run wpa_supplicant -Dnl80211 -imlan0 -c "$_conf" -B
	[ -x /mnt/data/ot_wifi_tool/wpa_event.sh ] &&
		wpa_cli -i mlan0 -B -a /mnt/data/ot_wifi_tool/wpa_event.sh
	run udhcpc -i mlan0 -S -b
}

restart_wifi()
{
	## Factory-test mode brings Wi-Fi up as an access point. Switch back to
	## the normal mode (0) and restart Wi-Fi, unless wifi_start.sh called us
	## (it starts Wi-Fi itself right after).
	echo 0 > /tmp/ft_mode
	if [ "$VALHALLA_FROM_WIFI" = "1" ]; then
		return 0
	fi
	if [ -x /etc/init.d/S41wifi ]; then
		log "Restarting Wi-Fi"
		run /etc/init.d/S41wifi restart
	fi
}

init_gm_driver()
{
	## Firmware 0099 does not initialise the video driver in factory mode.
	case "$(grep XIAOMI_VERSION /etc/os-release 2>/dev/null)" in
	*0099*)
		log "Initialising GM video driver (firmware 0099)"
		run sh /gm/config/vg_boot.sh /gm/config
		;;
	esac
}

setup_cloud()
{
	if enabled "$CLOUD_DISABLED"; then
		log "Disabling Xiaomi cloud"
		for _s in S59miio_agent S60miio_avstreamer S93ble S93miio_client S94miio_bt \
			S94miot_qrcode S95miio_ota; do
			if [ -f "/etc/init.d/$_s" ]; then
				printf '#!/bin/sh\nexit 0\n' > "/etc/init.d/$_s"
			fi
		done
		for _b in /mnt/data/miio_av/miio_avstreamer /mnt/data/ot_wifi_tool/miio_client \
			/mnt/data/miio/miio_agent /mnt/data/miio_ota/miio_ota; do
			stub_file "$_b" "exit 0"
		done
		killall miio_avstreamer miio_client miio_agent miio_ota > /dev/null 2>&1
	elif enabled "$CLOUD_STREAMING_DISABLED"; then
		log "Disabling Xiaomi cloud streaming"
		stub_file /mnt/data/miio_av/miio_avstreamer "exit 0"
		killall miio_avstreamer > /dev/null 2>&1
	fi
}

setup_rtsp()
{
	enabled "$RTSP_ENABLED" || return 0
	log "Enabling RTSP: rtsp://<camera-ip>/live/ch00_0"
	echo "...Enabling RTSP..." > /dev/kmsg 2>/dev/null

	## The launcher runs from /tmp so it does not keep the SD card busy.
	cp "$TOOLS/rtsp_start.sh" /tmp/rtsp_start.sh
	chmod 755 /tmp/rtsp_start.sh
	echo "$CONFIG_LINE" > /tmp/rtsp.args
	if enabled "$RTSP_LOG"; then
		echo "$LOGDIR/rtsp.log" > /tmp/rtsp.logfile
	else
		echo /dev/null > /tmp/rtsp.logfile
	fi

	## Started both from the end of the boot sequence and right away; the
	## launcher ignores a second start.
	if [ -d /etc/init.d ] && [ -f /etc/.valhalla ]; then
		cat << 'EOF' > /etc/init.d/S99zerlot
#!/bin/sh
case "$1" in
  start) /tmp/rtsp_start.sh start ;;
  stop) /tmp/rtsp_start.sh stop ;;
esac
exit 0
EOF
		chmod 755 /etc/init.d/S99zerlot
	fi
	/tmp/rtsp_start.sh start
}

start_http()
{
	enabled "$HTTP_ENABLED" || return 0
	if pidof lighttpd > /dev/null 2>&1; then
		return 0
	fi
	log "Starting web server on port 8080"
	## Basic auth for the web interface, same credentials as SSH.
	echo "root:$SSH_ROOT_PASS" > /tmp/lighttpd.user
	chmod 600 /tmp/lighttpd.user
	mkdir -p /var/run
	run "$TOOLS/bin/lighttpd" -f "$TOOLS/etc/lighttpd.conf" || log "ERROR: lighttpd failed to start"
}

start_samba()
{
	enabled "$SAMBA_ENABLED" || return 0
	if pidof smbd > /dev/null 2>&1; then
		return 0
	fi
	log "Starting Samba"
	mkdir -p "$TOOLS/tmp/samba" /var/run
	printf '%s\n%s\n' "$SSH_ROOT_PASS" "$SSH_ROOT_PASS" | "$TOOLS/bin/smbpasswd" -a -s root >> "$LOGFILE" 2>&1
	run "$TOOLS/bin/smbd" -D || log "ERROR: smbd failed to start"
}

blink_leds()
{
	_led=/mnt/data/miot/ledctl
	[ -x "$_led" ] || return 0
	$_led 0 50 2 300 300 2
	$_led 1 50 2 400 200 2
	sleep 5
	$_led 0 1 1 100 200 2
	$_led 1 1 1 100 200 2
}

## --- main ------------------------------------------------------------

valhalla_main()
{
	if ! mkdir /tmp/valhalla.lock 2>/dev/null; then
		echo "valhalla.sh already ran on this boot, skipping"
		return 0
	fi
	mkdir -p "$LOGDIR"

	log "Valhalla script v$SCRIPT_VERSION starting"
	load_config
	log_versions

	## Factory-test boot hook: force mode 4 while we set things up.
	echo 4 > /tmp/ft_mode

	setup_etc_overlay && set_root_password
	start_ssh
	enabled "$ENGLISH_VOICE" && set_english_voice
	setup_ota
	hostname "$CAM_HOSTNAME"
	restart_wifi
	connect_wifi_override
	init_gm_driver
	setup_cloud
	setup_rtsp
	start_http
	start_samba

	log "Valhalla script finished OK"
	blink_leds
}

valhalla_main "$@"
