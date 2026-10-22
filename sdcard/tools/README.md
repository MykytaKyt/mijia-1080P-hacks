# Tools

Binaries and helper scripts used by `valhalla.sh`. See the main README for details.

* `rtsp_start.sh`: RTSP launcher and watchdog (`start|stop|status`)
* `wifi_start.sh`: patched firmware Wi-Fi script that starts the hack, installed after an OTA
* `post-ota.sh`, `inject.sh`: keep the hack after a firmware update
* `pre-ota.sh`: reference copy of the firmware's pre-update script (not used)
* `sign_ft_boot.sh`: re-signs `../ft/ft_boot.sh` (run on a PC)
* `build.txt`: how to build lighttpd, PHP and Samba
* `valhalla_lib.sh`: shared shell helpers (config, logging, Wi-Fi), sourced by the scripts above
* `valhallad.sh`: background helper (Wi-Fi setup mode, service watchdog, NTP)
* `www/`: settings page (`index.php`, port 8080), Wi-Fi setup page (`setup/`, port 80 in setup mode), `snapshot.php`
* `etc/lighttpd-setup.conf`: web server config for the setup page
