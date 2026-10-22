![Mijia 1080p](images/mijia_1080p/Mijia1080.png?raw=true "Mijia 1080p")

# mijia-1080P-hacks

A toolset that runs from the SD card and adds features to the Xiaomi Mijia
1080p camera. Nothing is flashed: take the card out and the camera boots
the stock firmware again (except for the English voice prompts and the OTA
hook, see below).

## Features

| Feature | Setting in `midgard.ini` | Default |
|---|---|---|
| SSH and SFTP server (dropbear, port 22) | `SSH_ROOT_PASS` | always on |
| English voice prompts instead of Chinese | `ENGLISH_VOICE` | on |
| Local RTSP stream, restarted automatically if it crashes | `RTSP_ENABLED`, `CONFIG_LINE` | off |
| Block video streaming to the Xiaomi cloud | `CLOUD_STREAMING_DISABLED` | off |
| Cut the camera off from the Xiaomi cloud | `CLOUD_DISABLED` | off |
| Block firmware (OTA) updates | `DISABLED_OTA` | off |
| Web server with password, recordings under `/media` (port 8080) | `HTTP_ENABLED` | off |
| Samba share `rec` with the recordings | `SAMBA_ENABLED` | off |
| Wi-Fi network set from the SD card | `miio_ssid`, `miio_passwd`, `miio_key_mgmt` | empty |
| Custom hostname | `HOSTNAME` | `Valhalla` |

## Installation

1. Format a microSD card as **FAT32**.
2. Copy the **contents** of the `sdcard/` folder to the root of the card
   (`ft/`, `tools/`, `ft_config.ini`, `midgard.ini`, `valhalla.sh`, ...).
3. Edit `midgard.ini`. At least **change `SSH_ROOT_PASS`** (8+ characters).
4. Put the card in the camera and power it on. When the hack has finished
   starting, both LEDs blink for about 5 seconds.
5. Check `logs/log-*.log` on the card if something does not work.

`midgard.ini` may be edited on Windows: Windows line endings are handled.
Do not edit the `.sh` files with an editor that saves Windows line endings.

## Usage

All services use the user **`root`** and the password from `SSH_ROOT_PASS`.

* **SSH:** `ssh root@<camera-ip>`
* **SFTP / scp:** `sftp root@<camera-ip>`. OpenSSH 9+ `scp` works too, because it
  uses SFTP. SFTP only works when the camera mounts the card at
  `/mnt/media/mmcblk0p1`, the normal case.
* **RTSP:** `rtsp://<camera-ip>/live/ch00_0`, for example in VLC or ffmpeg:
  `ffplay rtsp://192.168.1.50/live/ch00_0`.
  The stream starts about 15 seconds after the script runs.
  `CONFIG_LINE` sets bitrate (`-b`, kbps), frame rate (`-f`), size
  (`-w`/`-h`) and bitrate mode (`-m`: 1 CBR, 2 VBR, 3 enhanced CBR,
  4 enhanced VBR). Set `RTSP_LOG=1` to log the server output to `logs/rtsp.log`.
  Control it over SSH with `/tmp/rtsp_start.sh start|stop|status`.
* **Web:** `http://<camera-ip>:8080`. Recordings are under `/media`.
* **Samba:** `\\<camera-ip>\rec`. `nmbd` does not work, so connect by IP.

The SSH host key is created on the first boot and saved to
`tools/dropbear/dropbear_ecdsa_host_key`, so it stays the same after reboots.

### Wi-Fi

Leave `miio_ssid` empty to keep the network set up in the Mi Home app.
When it is set, the camera joins that network on every boot. Set
`miio_key_mgmt=NONE` for an open network. The settings are not written to
the camera, so remove the card and the camera goes back to its own Wi-Fi
settings.

### Cloud options

* `CLOUD_STREAMING_DISABLED=1`: the Mi Home app still controls the camera,
  but no video leaves your network.
* `CLOUD_DISABLED=1`: stops all Xiaomi cloud services (miio client/agent,
  BLE, OTA, video). The Mi Home app will not work. Use RTSP to watch.

## How it works

* The firmware has a factory-test boot hook: when the card has
  `ft_config.ini` and `ft/ft_boot.sh` with a matching signature
  (`ft/secret.bin`), the camera runs `ft_boot.sh` at boot. That script mounts
  the card at `/tmp/sd` and runs `valhalla.sh`.
* `valhalla.sh` reads `midgard.ini`, copies `/etc` to a writable copy in
  `/tmp`, sets the root password, starts the services, and logs every step to
  `logs/`. A lock file makes sure it runs only once per boot.
* **Survives updates:** unless `DISABLED_OTA=1`, `tools/post-ota.sh` is
  installed as the firmware's post-update hook. After an update,
  `tools/inject.sh` writes `tools/wifi_start.sh` into the new data partition.
  That patched script starts `valhalla.sh` at boot.
* **Changes to the camera's flash:** the English voice prompts (symlinks in
  `/mnt/data/sound`) and the OTA hook (`/mnt/data/miio_ota/post-ota.sh`). Both
  are written only when needed.

### Editing `ft/ft_boot.sh`

The camera checks `ft/secret.bin` against the MD5 of `ft_boot.sh`. If you
change `ft_boot.sh`, sign it again on a PC that has `openssl`:

```sh
cd /path/to/sdcard
sh tools/sign_ft_boot.sh
```

## Files

| Path | Purpose |
|---|---|
| `ft_config.ini`, `ft/` | Factory-test boot hook and its signature |
| `midgard.ini` | User configuration |
| `valhalla.sh` | Main script |
| `tools/rtsp_start.sh` | RTSP launcher and watchdog |
| `tools/wifi_start.sh` | Patched Wi-Fi start script, installed after an OTA |
| `tools/post-ota.sh`, `tools/inject.sh` | OTA persistence |
| `tools/sign_ft_boot.sh` | Re-signs `ft/ft_boot.sh` |
| `tools/dropbear/`, `tools/sftp-server` | SSH/SFTP server |
| `tools/rtsp_basic` | RTSP server ([source](https://github.com/willthrom/rtspServer_gm)) |
| `tools/bin/`, `tools/etc/`, `tools/www/` | lighttpd, PHP, Samba (see `tools/build.txt`) |

## Security notes

* Change the default password. It protects SSH, the web interface and Samba.
* RTSP has **no authentication**. Anyone on your network can watch the
  stream. Do not expose it to the Internet.
* Older releases shipped a shared SSH host key. It has been removed: each
  camera now creates its own on first boot.

## Development

Development details are in the
[wiki](https://github.com/Filipowicz251/mijia-1080P-hacks/wiki).
