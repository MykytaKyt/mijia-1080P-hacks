## Install

1. Download **mijia-1080p-sdcard.zip** below.
2. Unzip it to the root of a FAT32 microSD card.
3. Put the card in the camera and power it on.
4. No Wi-Fi yet? After ~30 seconds connect to **Mijia-Setup-XXXX** (password `mijia1080`) or to the camera's own **mijia-camera-…_mibtXXXX** network, and open **http://192.168.14.1**.
5. Open **http://&lt;camera-ip&gt;:8080** (user `root`, password `qwerty123456`) and change the password.

See the [README](https://github.com/MykytaKyt/mijia-1080P-hacks#readme) for all options.

## Changes in this release

- **Phones are no longer kicked off the camera's pairing network.** When the firmware's own network (`mijia-camera-…_mibtXXXX`) is up, the setup page runs there and the camera no longer replaces it with `Mijia-Setup` after 20 s. `Mijia-Setup` only starts when no network is up.
- *Connect* on the setup page now works on the pairing network too (before, only on `Mijia-Setup`).
- Script version 2.3 in the boot log, so you can tell which release is on the card.

From v1.0.2: `CLOUD_DISABLED` fixed for firmware 3.3.6 (keeps the video service that records to the SD card), clock sync without `ntpd`, and a *Turn off the Xiaomi cloud* checkbox on the setup page.

**Updating:** keep your own `midgard.ini`. The zip contains one with default settings, so copy everything except that file.

Tested on firmware **3.3.6_0099**: setup through the access point, joining the home Wi-Fi and the settings page work.

## Since v1.0.0

Wi-Fi setup mode, settings web page on port 8080, a fixed RTSP stream with automatic restart, NTP and time zone, a watchdog, and many fixes in the original scripts. See the [v1.0.0 notes](https://github.com/MykytaKyt/mijia-1080P-hacks/releases/tag/v1.0.0).
