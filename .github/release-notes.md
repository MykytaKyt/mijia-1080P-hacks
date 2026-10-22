## Install

1. Download **mijia-1080p-sdcard.zip** below.
2. Unzip it to the root of a FAT32 microSD card.
3. Put the card in the camera and power it on.
4. No Wi-Fi yet? After ~2 minutes connect to **Mijia-Setup-XXXX** (password `mijia1080`) and open **http://192.168.14.1**.
5. Open **http://&lt;camera-ip&gt;:8080** (user `root`, password `qwerty123456`) and change the password.

See the [README](https://github.com/MykytaKyt/mijia-1080P-hacks#readme) for all options.

## What's new

- **Wi-Fi setup mode**: the camera opens its own access point with a setup page when it has no Wi-Fi or cannot connect.
- **Settings web page** on port 8080 (password protected): status, all options, reboot, RTSP restart, LED blink, boot log.
- RTSP stream fixed and restarted automatically if it crashes. New `RTSP_ALLOW` setting limits who can watch it.
- Clock sync (NTP) and time zone, watchdog for SSH / web / Samba, numbered boot logs with cleanup.
- Fixed: SSH host key lost on every boot, broken `scp` link, unused Wi-Fi settings in `midgard.ini`, empty `CLOUD_DISABLED`, wrong firmware 0099 check, many bugs in the OTA persistence script (`inject.sh`).
- Safer: no shared SSH host key, web page needs a password, password hidden in logs, voice files no longer deleted.
- All scripts, comments and docs in English.

Not tested on every firmware version. If something fails, open an issue with `logs/boot-*.log` from the SD card.
