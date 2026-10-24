## Install

1. Download **mijia-1080p-sdcard.zip** below.
2. Unzip it to the root of a FAT32 microSD card.
3. Put the card in the camera and power it on.
4. No Wi-Fi yet? After ~30 seconds connect to **Mijia-Setup-XXXX** (password `mijia1080`) or to the camera's own **mijia-camera-…_mibtXXXX** network, and open **http://192.168.14.1**.
5. Open **http://&lt;camera-ip&gt;:8080** (user `root`, password `qwerty123456`) and change the password.

See the [README](https://github.com/MykytaKyt/mijia-1080P-hacks#readme) for all options.

## Changes in this release

- **Wi-Fi setup page also works on the camera's own pairing network** (`mijia-camera-…_mibtXXXX`). In v1.0.0 a phone on that network got "cannot open this page" at 192.168.14.1.
- **Setup mode starts after ~20 seconds** when no Wi-Fi is configured at all (was 2 minutes). With a saved network that cannot be reached, the camera still waits `WIFI_SETUP_TIMEOUT` (120 s).
- The setup access point starts again if the firmware stops it.
- The boot log now shows whether the access point, DHCP server and setup page are running.

Tested on firmware **3.3.6_0099**: the hack starts, SSH and the settings page run, the setup access point comes up.

## Since v1.0.0

Wi-Fi setup mode, settings web page on port 8080, a fixed RTSP stream with automatic restart, NTP and time zone, a watchdog, and many fixes in the original scripts. See the [v1.0.0 notes](https://github.com/MykytaKyt/mijia-1080P-hacks/releases/tag/v1.0.0).
