## Install

1. Download **mijia-1080p-sdcard.zip** below.
2. Unzip it to the root of a FAT32 microSD card.
3. Put the card in the camera and power it on.
4. No Wi-Fi yet? After ~30 seconds connect to **Mijia-Setup-XXXX** (password `mijia1080`) or to the camera's own **mijia-camera-…_mibtXXXX** network, and open **http://192.168.14.1**.
5. Open **http://&lt;camera-ip&gt;:8080** (user `root`, password `qwerty123456`) and change the password.

See the [README](https://github.com/MykytaKyt/mijia-1080P-hacks#readme) for all options.

## Changes in this release

- **`CLOUD_DISABLED` fixed for firmware 3.3.6**: it now turns off the real services of this firmware (`miio_client`, `miio_bt`, BLE, `miot_devicekit`, `miot_qrcode`, `miio_ota`, `miio_smb`, `restartd`). It no longer stops `miio_avstreamer`, the video service that records to the SD card. Stopping that is now only done by `CLOUD_STREAMING_DISABLED`.
- **Clock sync without ntpd**: firmware without `ntpd` (3.3.6_0099) now gets the time from the `Date` header of a plain HTTP request. Before, the clock stayed at 1970.
- **Setup page**: new checkbox *Turn off the Xiaomi cloud* (on by default), because a camera set up there cannot be used with Mi Home anyway.
- From v1.0.1: the setup page also works on the camera's own pairing network, and setup mode starts after ~20 s when no Wi-Fi is configured.

Tested on firmware **3.3.6_0099**: setup through the access point, joining the home Wi-Fi and the settings page work.

## Since v1.0.0

Wi-Fi setup mode, settings web page on port 8080, a fixed RTSP stream with automatic restart, NTP and time zone, a watchdog, and many fixes in the original scripts. See the [v1.0.0 notes](https://github.com/MykytaKyt/mijia-1080P-hacks/releases/tag/v1.0.0).
