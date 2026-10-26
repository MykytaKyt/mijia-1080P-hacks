<?php
// Shared helpers for the web pages: read/write midgard.ini, camera status.
// Runs on the camera's PHP 7.1, keep the syntax compatible.

define('MIDGARD_INI', '/tmp/sd/midgard.ini');
define('TOOLS_DIR', '/tmp/sd/tools');

function h($s)
{
	return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8');
}

// Settings shown on the settings page, grouped. Types: bool, text, password, number, select.
function midgard_schema()
{
	return array(
		'Wi-Fi' => array(
			'miio_ssid' => array('text', 'Network name (SSID)', 'Empty: use the network set in the Mi Home app.'),
			'miio_passwd' => array('password', 'Network password', 'Leave empty to keep the current one.'),
			'miio_key_mgmt' => array('select', 'Security', '', array('WPA' => 'WPA/WPA2', 'NONE' => 'Open network')),
			'WIFI_SETUP_AP' => array('bool', 'Setup mode', 'Start the "Mijia-Setup" access point when the camera cannot connect.'),
			'WIFI_SETUP_TIMEOUT' => array('number', 'Setup mode after (seconds)', 'How long to wait for a connection at boot.'),
			'SETUP_AP_PASS' => array('text', 'Setup access point password', 'At least 8 characters. Empty: open access point.'),
		),
		'Video' => array(
			'RTSP_ENABLED' => array('bool', 'RTSP stream', 'rtsp://<camera-ip>/live/ch00_0. For a clean picture also turn off the Xiaomi video service: it reads the same encoder channel, and the stream loses frames.'),
			'CONFIG_LINE' => array('text', 'Encoder options', '-bBITRATE -fFPS -wWIDTH -hHEIGHT -mMODE (1 CBR, 2 VBR, 3/4 enhanced)'),
			'RTSP_ALLOW' => array('text', 'Allow RTSP only from', 'Comma-separated IPs or networks, e.g. 192.168.1.0/24. Empty: everyone.'),
			'RTSP_LOG' => array('bool', 'RTSP debug log', 'Writes logs/rtsp.log on the SD card.'),
		),
		'Xiaomi cloud' => array(
			'CLOUD_DISABLED' => array('bool', 'Turn off the Xiaomi cloud', 'Stops the Mi Home app connection, BLE pairing, OTA and restartd. The video service (SD card recording) keeps running.'),
			'CLOUD_STREAMING_DISABLED' => array('bool', 'Turn off the Xiaomi video service', 'Stops miio_avstreamer: no cloud video, but also no recording to the SD card and no voice prompts.'),
			'DISABLED_OTA' => array('bool', 'Block firmware updates', ''),
		),
		'Services' => array(
			'HTTP_ENABLED' => array('bool', 'Web interface (this page)', 'Turning it off removes this page after the next boot.'),
			'SAMBA_ENABLED' => array('bool', 'Samba share "rec"', ''),
			'ENGLISH_VOICE' => array('bool', 'English voice prompts', ''),
		),
		'System' => array(
			'SSH_ROOT_PASS' => array('password', 'Camera password (user root)', 'Used by SSH, Samba and this page. Leave empty to keep it.'),
			'HOSTNAME' => array('text', 'Hostname', ''),
			'TIMEZONE' => array('text', 'Time zone (POSIX)', 'e.g. UTC0, CET-1CEST,M3.5.0,M10.5.0/3, MSK-3. Empty: firmware default.'),
			'NTP_ENABLED' => array('bool', 'Sync clock (NTP)', ''),
			'NTP_SERVER' => array('text', 'NTP server', ''),
			'LOG_KEEP' => array('number', 'Boot logs to keep', ''),
		),
	);
}

// The Wi-Fi name and password are kept exactly as typed: a network can be
// called "Extreme " with a trailing space. Other values are trimmed.
function midgard_is_raw($key)
{
	return $key === 'miio_ssid' || $key === 'miio_passwd';
}

function midgard_read()
{
	$values = array();
	$lines = @file(MIDGARD_INI, FILE_IGNORE_NEW_LINES);
	if ($lines === false) return $values;
	foreach ($lines as $line) {
		$line = rtrim($line, "\r");
		if (preg_match('/^\s*([A-Za-z0-9_]+)\s*=(.*)$/', $line, $m)) {
			$values[$m[1]] = midgard_is_raw($m[1]) ? $m[2] : trim($m[2]);
		}
	}
	return $values;
}

// Values must be a single line. $raw keeps leading and trailing spaces.
function midgard_clean($value, $raw = false)
{
	$value = str_replace(array("\r", "\n"), '', (string)$value);
	return $raw ? $value : trim($value);
}

// Update keys in midgard.ini, keeping comments and order. Returns true on success.
function midgard_write($updates)
{
	$text = @file_get_contents(MIDGARD_INI);
	if ($text === false) $text = '';
	$eol = (strpos($text, "\r\n") !== false) ? "\r\n" : "\n";
	$lines = ($text === '') ? array() : preg_split('/\r?\n/', rtrim($text, "\r\n"));

	foreach ($updates as $key => $value) {
		$value = midgard_clean($value, midgard_is_raw($key));
		$found = false;
		foreach ($lines as $i => $line) {
			if (preg_match('/^\s*' . preg_quote($key, '/') . '\s*=/', $line)) {
				$lines[$i] = $key . '=' . $value;
				$found = true;
			}
		}
		if (!$found) $lines[] = $key . '=' . $value;
	}

	$tmp = MIDGARD_INI . '.new';
	if (@file_put_contents($tmp, implode($eol, $lines) . $eol) === false) return false;
	if (!@rename($tmp, MIDGARD_INI)) return false;
	shell_exec('sync');
	return true;
}

// Only accept POSTs sent from our own pages (basic CSRF protection).
function same_origin_post()
{
	if ($_SERVER['REQUEST_METHOD'] !== 'POST') return false;
	$host = isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : '';
	foreach (array('HTTP_ORIGIN', 'HTTP_REFERER') as $hdr) {
		if (!empty($_SERVER[$hdr])) {
			$h = parse_url($_SERVER[$hdr], PHP_URL_HOST);
			$p = parse_url($_SERVER[$hdr], PHP_URL_PORT);
			$origin = $p ? "$h:$p" : $h;
			return $origin === $host || $h === $host;
		}
	}
	return true; // old browsers send neither header
}

// Apply a new root password right away (it is also applied on every boot).
// The web pages read it from midgard.ini on every request.
function apply_root_password($pass)
{
	$p = escapeshellarg($pass);
	shell_exec("printf '%s\\n%s\\n' $p $p | passwd root > /dev/null 2>&1");
}

function camera_password()
{
	$values = midgard_read();
	$pass = isset($values['SSH_ROOT_PASS']) ? $values['SSH_ROOT_PASS'] : '';
	return ($pass === '') ? 'qwerty123456' : $pass;
}

// HTTP basic login: user root, password SSH_ROOT_PASS. Done in PHP because
// basic auth in the bundled lighttpd build rejects every password.
function require_login()
{
	$user = null;
	$pass = null;
	if (isset($_SERVER['PHP_AUTH_USER'])) {
		$user = $_SERVER['PHP_AUTH_USER'];
		$pass = isset($_SERVER['PHP_AUTH_PW']) ? $_SERVER['PHP_AUTH_PW'] : '';
	} else {
		foreach (array('HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION') as $k) {
			if (!empty($_SERVER[$k]) && stripos($_SERVER[$k], 'Basic ') === 0) {
				$pair = explode(':', (string)base64_decode(substr($_SERVER[$k], 6)), 2);
				if (count($pair) === 2) list($user, $pass) = $pair;
				break;
			}
		}
	}
	if ($user === 'root' && $pass !== null && hash_equals(camera_password(), $pass)) {
		return;
	}
	header('WWW-Authenticate: Basic realm="Mijia camera", charset="UTF-8"');
	http_response_code(401);
	header('Content-Type: text/plain');
	exit("Login required: user root, password from SSH_ROOT_PASS in midgard.ini.\n");
}

function wifi_scan_list()
{
	$list = @file('/tmp/wifi_scan.txt', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
	return $list ? $list : array();
}

function cam_status()
{
	$s = array();
	$s['ip'] = trim(shell_exec("ifconfig mlan0 2>/dev/null | grep 'inet addr' | cut -d ':' -f 2 | cut -d ' ' -f 1"));
	$up = (int)@file_get_contents('/proc/uptime');
	$s['uptime'] = sprintf('%dd %02dh %02dm', $up / 86400, ($up / 3600) % 24, ($up / 60) % 60);
	$s['time'] = trim(shell_exec('date'));
	$states = array(
		'boot' => 'Connecting…',
		'ok' => 'Connected',
		'ap' => 'Setup mode (access point)',
		'try' => 'Trying the saved network…',
	);
	$state = trim(@file_get_contents('/tmp/wifi_state'));
	$s['wifi'] = isset($states[$state]) ? $states[$state] : $state;
	$s['rtsp'] = trim(shell_exec('/tmp/rtsp_start.sh status 2>/dev/null'));
	$s['free'] = trim(shell_exec("df -h /tmp/sd 2>/dev/null | tail -n 1 | awk '{print $4 \" free of \" $2}'"));
	$s['snapshot'] = is_file(TOOLS_DIR . '/bin/ffmpeg');
	return $s;
}

function latest_log()
{
	$logs = glob('/tmp/sd/logs/boot-*.log');
	if (!$logs) return '';
	sort($logs);
	$file = end($logs);
	$text = @file_get_contents($file);
	if (strlen($text) > 20000) $text = '...' . substr($text, -20000);
	return basename($file) . "\n\n" . $text;
}
