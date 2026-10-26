#!/bin/sh
## Wi-Fi start script, based on the stock /mnt/data/ot_wifi_tool/wifi_start.sh
## of firmware 3.3.6_0099. /etc/init.d/S41wifi runs it in the background.
##
## Differences from the stock script:
##   * the network in midgard.ini on the SD card (miio_ssid, miio_passwd,
##     miio_key_mgmt) wins over the one stored by the Mi Home app (nvram),
##     so the camera joins it directly instead of opening the pairing network
##   * udhcpc keeps trying in the background instead of giving up after 1 s
##   * start_valhalla runs the hack from the SD card (used when this script
##     was written to flash after a firmware update, see inject.sh)
##
## valhalla.sh bind-mounts it over the stock script on every boot (RAM only).

WPA_SUPPLICANT_CONFIG_FILE="/tmp/wpa_supplicant.conf"
INI=/tmp/sd/midgard.ini

## Value of KEY in midgard.ini, exactly as written (spaces kept, CR removed).
ini_get()
{
    grep "^$1=" $INI 2>/dev/null | tail -n 1 | cut -d '=' -f 2- | tr -d '\r'
}

update_wpa_conf()
{
    {
        echo "ctrl_interface=/var/run/wpa_supplicant"
        echo "update_config=1"
        echo "network={"
        printf '\tssid="%s"\n' "$1"
        if [ -z "$2" ]; then
            printf '\tkey_mgmt=NONE\n'
        else
            printf '\tpsk="%s"\n' "$2"
            printf '\tkey_mgmt=WPA-PSK\n'
            printf '\tproto=WPA WPA2\n'
        fi
        printf '\tscan_ssid=1\n'
        echo "}"
    } > $WPA_SUPPLICANT_CONFIG_FILE
    chmod 600 $WPA_SUPPLICANT_CONFIG_FILE
}

wifi_ap_mode()
{
    echo "Enabling wifi AP mode"

    # wifi stop
    ifconfig mlan0 down
    killall udhcpc wpa_supplicant hostapd dhcpd udhcpd
    ifconfig uap0 up
    ifconfig uap0 192.168.14.1 netmask 255.255.255.0

    MODEL=`/usr/sbin/nvram get model`
    [ -n "$MODEL" ] || MODEL=`/usr/sbin/nvram factory get model`
    vendor=`echo ${MODEL} | cut -d '.' -f 1`
    product=`echo ${MODEL} | cut -d '.' -f 2`
    version=`echo ${MODEL} | cut -d '.' -f 3`

    cp /etc/hostapd.conf /tmp/
    echo "ssid=${vendor}-${product}-${version}_mibt$1" >> /tmp/hostapd.conf
    mkdir -p /var/run/hostapd
    hostapd /tmp/hostapd.conf -B

    mkdir -p /var/lib/misc
    touch /var/lib/misc/udhcpd.leases
    udhcpd
}

wifi_sta_mode()
{
    echo "Enabling wifi STA mode"

    get_ssid_passwd
    update_wpa_conf "$ssid" "$passwd"

    #stop uap interfce
    killall udhcpc wpa_supplicant hostapd dhcpd udhcpd
    ifconfig uap0 down

    ifconfig mlan0 up
    iwconfig mlan0 mode Managed
    mkdir -p /var/run/wpa_supplicant
    wpa_supplicant -Dnl80211 -imlan0 -c $WPA_SUPPLICANT_CONFIG_FILE -B

    ## -b: keep asking for an address in the background if the first try fails
    udhcpc -i mlan0 -b

    # check if we've got ip
    echo "get ip addr :"
    ifconfig mlan0 | grep "inet addr" | cut -d ':' -f 2 |cut -d ' ' -f 1
}

get_ssid_passwd()
{
    ## The network from midgard.ini on the SD card wins.
    ssid=`ini_get miio_ssid`
    if [ -n "$ssid" ]; then
        key_mgmt=`ini_get miio_key_mgmt`
        passwd=`ini_get miio_passwd`
    else
        ssid=`/usr/sbin/nvram get miio_ssid`
        key_mgmt=`/usr/sbin/nvram get miio_key_mgmt`
        passwd=`/usr/sbin/nvram get miio_passwd`
    fi
    if [ "$key_mgmt" = "NONE" ]; then
        passwd=""
    fi
}

start()
{
    wifi_ready=`ini_get miio_ssid`
    [ -n "$wifi_ready" ] || wifi_ready=`/usr/sbin/nvram get miio_ssid`

    if [ -n "$wifi_ready" ]; then
        wifi_sta_mode
    else
        STRING=`ifconfig mlan0`

        macstring=${STRING##*HWaddr }
        macstring=`echo ${macstring} | cut -d ' ' -f 1`

        mac1=`echo ${macstring} | cut -d ':' -f 5`
        mac2=`echo ${macstring} | cut -d ':' -f 6`
        MAC=${mac1}${mac2}

        wifi_ap_mode $MAC
    fi
}

## Mount the SD card and run the hack (valhalla.sh) once per boot. Needed
## when this script lives in flash (after a firmware update); when
## valhalla.sh already runs, its lock makes this a no-op.
start_valhalla()
{
    sd_mountdir=/tmp/sd
    [ -f /tmp/valhalla.pid ] && return
    echo 1 > /tmp/valhalla.pid

    if ! grep -q " $sd_mountdir " /proc/mounts; then
        mmc_device=""
        if [ -b /dev/mmcblk0p1 ]; then
            mmc_device=/dev/mmcblk0p1
        elif [ -b /dev/mmcblk0 ]; then
            mmc_device=/dev/mmcblk0
        fi
        if [ -z "$mmc_device" ]; then
            echo "start_valhalla: no SD card found" | logger -t valhalla
            return
        fi
        mkdir -p $sd_mountdir
        if ! mount -t vfat $mmc_device $sd_mountdir; then
            echo "start_valhalla: cannot mount $mmc_device" | logger -t valhalla
            return
        fi
    fi

    if [ ! -f $sd_mountdir/valhalla.sh ]; then
        echo "start_valhalla: $sd_mountdir/valhalla.sh not found" | logger -t valhalla
        return
    fi

    echo "start_valhalla: running valhalla.sh" | logger -t valhalla
    VALHALLA_FROM_WIFI=1 sh $sd_mountdir/valhalla.sh
}

start_valhalla

start
