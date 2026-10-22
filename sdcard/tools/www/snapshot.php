<?php
// Current camera image as JPEG. Needs an ARM build of ffmpeg in
// tools/bin/ffmpeg and the RTSP stream enabled.
$ffmpeg = '/tmp/sd/tools/bin/ffmpeg';
$out = '/tmp/snapshot.jpg';

if (!is_file($ffmpeg)) {
	http_response_code(501);
	header('Content-Type: text/plain');
	exit("Snapshot needs tools/bin/ffmpeg on the SD card.\n");
}

@unlink($out);
shell_exec(escapeshellarg($ffmpeg) . ' -loglevel error -rtsp_transport tcp -i rtsp://127.0.0.1/live/ch00_0'
	. ' -frames:v 1 -f image2 -y ' . escapeshellarg($out) . ' < /dev/null > /dev/null 2>&1');

if (!is_file($out) || filesize($out) === 0) {
	http_response_code(503);
	header('Content-Type: text/plain');
	exit("Could not grab an image. Is RTSP_ENABLED=1?\n");
}
header('Content-Type: image/jpeg');
header('Cache-Control: no-store');
header('Content-Length: ' . filesize($out));
readfile($out);
