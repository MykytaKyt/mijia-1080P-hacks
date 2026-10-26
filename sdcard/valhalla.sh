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

SCRIPT_VERSION="2.7"

sd_mountdir=/tmp/sd
TOOLS=$sd_mountdir/tools
INI=$sd_mountdir/midgard.ini
LOGDIR=$sd_mountdir/logs
LOGFILE=""

## log, run, cfg, enabled and the Wi-Fi helpers
. "$TOOLS/valhalla_lib.sh"

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
	HTTP_ENABLED=$(cfg HTTP_ENABLED 1)
	SAMBA_ENABLED=$(cfg SAMBA_ENABLED 0)
	ENGLISH_VOICE=$(cfg ENGLISH_VOICE 1)
	WIFI_SSID=$(cfg_raw miio_ssid)
	WIFI_PASSWD=$(cfg_raw miio_passwd)
	WIFI_KEY_MGMT=$(cfg miio_key_mgmt "WPA")
	RTSP_ALLOW=$(cfg RTSP_ALLOW "")
	TIMEZONE=$(cfg TIMEZONE "")
	LOG_KEEP=$(cfg LOG_KEEP 10)

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
	log "  miio_ssid='$WIFI_SSID'"
	log "  RTSP_ALLOW=$RTSP_ALLOW"
	log "  TIMEZONE=$TIMEZONE"

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
## the Mi Home app (nvram).
connect_wifi_override()
{
	[ -n "$WIFI_SSID" ] || return 0
	## wifi_start.sh reads midgard.ini itself when it called us.
	[ "$VALHALLA_FROM_WIFI" = "1" ] && return 0
	# shellcheck disable=SC2034 # used by wifi_connect
	[ "$WIFI_KEY_MGMT" = "NONE" ] && WIFI_PASSWD=""
	wifi_connect
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
	## Runs during S50gm, before the cloud services start (S59..S99), so
	## replacing their init scripts in the /etc overlay is enough. The stubs
	## on the binaries stop restartd from bringing them back.
	if enabled "$CLOUD_DISABLED"; then
		log "Disabling Xiaomi cloud (Mi Home app, BLE pairing, OTA)"
		for _s in S59miio_agent S90miot_qrcode S93ble S93miio_client S93miot_devicekit \
			S94miio_bt S94miot_qrcode S95miio_ota S95miio_smb S99restartd; do
			if [ -f "/etc/init.d/$_s" ]; then
				printf '#!/bin/sh\nexit 0\n' > "/etc/init.d/$_s"
				log "  disabled $_s"
			fi
		done
		for _b in /mnt/data/ot_wifi_tool/miio_client /mnt/data/miio_ota/miio_ota \
			/mnt/data/miio/miio_agent; do
			stub_file "$_b" "exit 0"
		done
		killall miio_client miio_bt miot_devicekit miot_qrcode miio_ota miio_smb restartd \
			> /dev/null 2>&1
	fi
	## miio_avstreamer also records to the SD card and plays the voice
	## prompts, so it only goes with CLOUD_STREAMING_DISABLED.
	if enabled "$CLOUD_STREAMING_DISABLED"; then
		log "Disabling Xiaomi video streaming (miio_avstreamer, also stops SD card recording)"
		[ -f /etc/init.d/S60miio_avstreamer ] && printf '#!/bin/sh\nexit 0\n' > /etc/init.d/S60miio_avstreamer
		stub_file /mnt/data/miio_av/miio_avstreamer "exit 0"
		killall miio_avstreamer > /dev/null 2>&1
	fi
}

setup_rtsp()
{
	enabled "$RTSP_ENABLED" || return 0
	log "Enabling RTSP: rtsp://<camera-ip>/live/ch00_0"
	if ! enabled "$CLOUD_STREAMING_DISABLED"; then
		log "WARNING: miio_avstreamer shares the encoder with RTSP, the stream will be blocky; set CLOUD_STREAMING_DISABLED=1"
	fi
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
	## The pages check the login (root / SSH_ROOT_PASS) themselves.
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

## Number the logs by boot (the clock is often wrong at boot) and keep
## only the newest LOG_KEEP of them.
open_log()
{
	mkdir -p "$LOGDIR"
	_n=$(cat "$LOGDIR/.boot_count" 2>/dev/null)
	case "$_n" in
	'' | *[!0-9]*) _n=0 ;;
	esac
	_n=$((_n + 1))
	echo "$_n" > "$LOGDIR/.boot_count"
	LOGFILE=$LOGDIR/boot-$(printf '%05d' "$_n")-$(date +"%Y%m%d%H%M").log

	case "$LOG_KEEP" in
	'' | *[!0-9]*) LOG_KEEP=10 ;;
	esac
	## Newest first (by boot number); keep LOG_KEEP logs including this one.
	ls -1r "$LOGDIR"/boot-*.log 2>/dev/null | tail -n +"$LOG_KEEP" | while read -r _old; do
		rm -f "$_old"
	done
}

set_timezone()
{
	[ -n "$TIMEZONE" ] || return 0
	[ -f /etc/.valhalla ] || return 0
	log "Setting time zone to $TIMEZONE"
	echo "$TIMEZONE" > /etc/TZ
	export TZ="$TIMEZONE"
}

## rtsp_basic has no password. Optionally limit who can reach it.
setup_rtsp_firewall()
{
	enabled "$RTSP_ENABLED" || return 0
	[ -n "$RTSP_ALLOW" ] || return 0
	if ! command -v iptables > /dev/null 2>&1; then
		log "WARNING: iptables not available, RTSP_ALLOW is ignored"
		return 0
	fi
	log "Allowing RTSP only from: $RTSP_ALLOW"
	iptables -N VALHALLA_RTSP 2>/dev/null || iptables -F VALHALLA_RTSP
	iptables -A VALHALLA_RTSP -i lo -j ACCEPT
	for _net in $(echo "$RTSP_ALLOW" | tr ',' ' '); do
		run iptables -A VALHALLA_RTSP -s "$_net" -j ACCEPT
	done
	iptables -A VALHALLA_RTSP -j DROP
	iptables -C INPUT -p tcp --dport 554 -j VALHALLA_RTSP 2>/dev/null ||
		run iptables -I INPUT -p tcp --dport 554 -j VALHALLA_RTSP
}

## Background helper: Wi-Fi setup mode, service watchdog, NTP.
start_daemon()
{
	if [ -f /var/run/valhallad.pid ] && kill -0 "$(cat /var/run/valhallad.pid)" 2>/dev/null; then
		return 0
	fi
	cp "$TOOLS/valhalla_lib.sh" /tmp/valhalla_lib.sh
	cp "$TOOLS/valhallad.sh" /tmp/valhallad.sh
	{
		echo "sd_mountdir='$sd_mountdir'"
		echo "TOOLS='$TOOLS'"
		echo "INI='$INI'"
		echo "LOGFILE='$LOGFILE'"
		echo "HTTP_ENABLED='$HTTP_ENABLED'"
		echo "SAMBA_ENABLED='$SAMBA_ENABLED'"
	} > /tmp/valhalla.env
	log "Starting valhallad (Wi-Fi setup mode, watchdog, NTP)"
	sh /tmp/valhallad.sh < /dev/null > /dev/null 2>&1 &
}

## --- main ------------------------------------------------------------

valhalla_main()
{
	if ! mkdir /tmp/valhalla.lock 2>/dev/null; then
		echo "valhalla.sh already ran on this boot, skipping"
		return 0
	fi
	LOG_KEEP=$(cfg LOG_KEEP 10)
	open_log

	log "Valhalla script v$SCRIPT_VERSION starting"
	load_config
	log_versions

	## Factory-test boot hook: force mode 4 while we set things up.
	echo 4 > /tmp/ft_mode

	setup_etc_overlay && set_root_password
	set_timezone
	start_ssh
	enabled "$ENGLISH_VOICE" && set_english_voice
	setup_ota
	hostname "$CAM_HOSTNAME"
	restart_wifi
	connect_wifi_override
	init_gm_driver
	setup_cloud
	setup_rtsp
	setup_rtsp_firewall
	start_http
	start_samba
	start_daemon

	log "Valhalla script finished OK"
	blink_leds
}

valhalla_main "$@"
