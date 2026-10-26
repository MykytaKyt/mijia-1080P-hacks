## Install

1. Download **mijia-1080p-sdcard.zip** below.
2. Unzip it to the root of a FAT32 microSD card.
3. Put the card in the camera and power it on.
4. No Wi-Fi yet? After ~30 seconds connect to **Mijia-Setup-XXXX** (password `mijia1080`) or to the camera's own **mijia-camera-…_mibtXXXX** network, and open **http://192.168.14.1**.
5. Open **http://&lt;camera-ip&gt;:8080** (user `root`, password `qwerty123456`) and change the password.

See the [README](https://github.com/MykytaKyt/mijia-1080P-hacks#readme) for all options.

## Changes in this release

- **Setup mode no longer mistakes a downed access point for a running one.** The check looked only at the 192.168.14.1 address, which stays on the interface after it goes down. With a wrong Wi-Fi name the camera could then wait forever without opening `Mijia-Setup`. It now also checks that the interface is up and hostapd runs.
- **Time sync**: retries without `-T` on busybox builds whose `wget` lacks it, and logs why it failed (`Time: no Date header ... (last: ...)`).
- From v1.0.6: Wi-Fi names and passwords keep leading and trailing spaces (`Extreme `); RTSP needs `CLOUD_STREAMING_DISABLED=1`.

From v1.0.4: the web login is checked by the PHP pages (the bundled lighttpd rejected every password), and recordings are served by `/media.php` with seeking.

From v1.0.3: the camera keeps its own pairing network while you use the setup page. From v1.0.2: `CLOUD_DISABLED` fixed for firmware 3.3.6, clock sync without `ntpd`.

**Updating:** keep your own `midgard.ini`. The zip contains one with default settings, so copy everything except that file.

Tested on firmware **3.3.6_0099**: setup through the access point, joining the home Wi-Fi and the settings page work.

## Since v1.0.0

Wi-Fi setup mode, settings web page on port 8080, a fixed RTSP stream with automatic restart, NTP and time zone, a watchdog, and many fixes in the original scripts. See the [v1.0.0 notes](https://github.com/MykytaKyt/mijia-1080P-hacks/releases/tag/v1.0.0).
