#!/bin/sh
## Re-create ft/secret.bin after editing ft/ft_boot.sh.
##
## The camera only runs ft/ft_boot.sh when ft/secret.bin holds the
## RSA-encrypted output of "md5sum /tmp/sd/ft/ft_boot.sh". Run this on a
## PC with openssl, from the root of the SD card:
##     sh tools/sign_ft_boot.sh
set -e
cd "$(dirname "$0")/.."
md5=$(md5sum ft/ft_boot.sh | cut -d ' ' -f 1)
printf '%s  /tmp/sd/ft/ft_boot.sh\n' "$md5" |
	openssl pkeyutl -encrypt -inkey tools/prikey.pem -out ft/secret.bin
## Self-check
openssl pkeyutl -decrypt -inkey tools/prikey.pem -in ft/secret.bin | grep -q "^$md5 " &&
	echo "ft/secret.bin updated for ft_boot.sh ($md5)"
