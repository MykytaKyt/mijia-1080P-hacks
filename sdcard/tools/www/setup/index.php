<?php
// Wi-Fi setup page, shown on the "Mijia-Setup" access point.
require_once('/tmp/sd/tools/www/lib/midgard.php');

// No login on the setup network (192.168.14.x, protected by SETUP_AP_PASS).
// From anywhere else, e.g. /setup/ on port 8080, require the camera login.
$remote = isset($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : '';
if (strpos($remote, '192.168.14.') !== 0) require_login();

$msg = '';
$err = '';
$done = false;
$values = midgard_read();

if (same_origin_post()) {
	$ssid = midgard_clean(isset($_POST['ssid']) ? $_POST['ssid'] : '', true);
	$pass = midgard_clean(isset($_POST['pass']) ? $_POST['pass'] : '', true);
	$open = !empty($_POST['open']);
	$root = midgard_clean(isset($_POST['root']) ? $_POST['root'] : '');

	if ($ssid === '') {
		$err = 'Enter the network name.';
	} elseif (!$open && (strlen($pass) < 8 || strlen($pass) > 63)) {
		$err = 'A WPA password has 8 to 63 characters.';
	} elseif ($root !== '' && strlen($root) < 8) {
		$err = 'The camera password needs at least 8 characters.';
	} else {
		$updates = array(
			'miio_ssid' => $ssid,
			'miio_passwd' => $open ? '' : $pass,
			'miio_key_mgmt' => $open ? 'NONE' : 'WPA',
		);
		if ($root !== '') $updates['SSH_ROOT_PASS'] = $root;
		$updates['CLOUD_DISABLED'] = empty($_POST['nocloud']) ? '0' : '1';
		if (midgard_write($updates)) {
			if ($root !== '') apply_root_password($root);
			touch('/tmp/wifi_reconnect');
			$done = true;
		} else {
			$err = 'Could not write midgard.ini on the SD card.';
		}
	}
}

$networks = wifi_scan_list();
$default_pass = (isset($values['SSH_ROOT_PASS']) ? $values['SSH_ROOT_PASS'] : '') === 'qwerty123456';
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Camera Wi-Fi setup</title>
<link rel="stylesheet" href="/style.css">
</head>
<body>
<main>
<h1>Camera Wi-Fi setup</h1>
<?php if ($done): ?>
	<div class="card">
		<h2>Connecting to “<?= h($ssid) ?>”…</h2>
		<p>The camera is now joining your network, and this setup network will disappear.</p>
		<p>Reconnect your phone to your usual Wi-Fi. The camera's address is shown in your router's list of devices.</p>
		<p class="hint">If the setup network comes back after about a minute, the password was wrong. Connect to it again and retry.</p>
	</div>
<?php else: ?>
	<?php if ($err): ?><div class="msg err"><?= h($err) ?></div><?php endif; ?>
	<form method="post" class="card">
		<label for="ssid">Network name</label>
		<input type="text" id="ssid" name="ssid" list="networks" autocomplete="off" required
			value="<?= h(isset($_POST['ssid']) ? $_POST['ssid'] : (isset($values['miio_ssid']) ? $values['miio_ssid'] : '')) ?>">
		<datalist id="networks">
			<?php foreach ($networks as $n): ?><option value="<?= h($n) ?>"><?php endforeach; ?>
		</datalist>
		<?php if ($networks): ?><div class="hint">Networks found: <?= h(implode(', ', $networks)) ?></div><?php endif; ?>

		<label for="pass">Wi-Fi password</label>
		<input type="password" id="pass" name="pass" autocomplete="off">
		<div class="row"><input type="checkbox" id="open" name="open" value="1"><label for="open">Open network (no password)</label></div>

		<label for="root">New camera password <?= $default_pass ? '(recommended)' : '(optional)' ?></label>
		<input type="password" id="root" name="root" autocomplete="new-password">
		<div class="hint">For SSH and the web interface, user <b>root</b>.<?= $default_pass ? ' The default password is still in use.' : '' ?></div>

		<div class="row">
			<input type="checkbox" id="nocloud" name="nocloud" value="1" <?= ($_SERVER['REQUEST_METHOD'] !== 'POST' || !empty($_POST['nocloud'])) ? 'checked' : '' ?>>
			<div><label for="nocloud">Turn off the Xiaomi cloud</label>
			<div class="hint">A camera set up here cannot be used with the Mi Home app. Takes effect after a reboot.</div></div>
		</div>

		<div class="actions"><button type="submit">Connect</button></div>
	</form>
<?php endif; ?>
</main>
</body>
</html>
