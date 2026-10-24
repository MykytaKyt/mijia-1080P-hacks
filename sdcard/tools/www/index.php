<?php
// Camera settings page (port 8080, login root / SSH_ROOT_PASS).
require_once('/tmp/sd/tools/www/lib/midgard.php');
require_login();

$schema = midgard_schema();
$msg = '';
$err = '';

if (same_origin_post()) {
	$action = isset($_POST['action']) ? $_POST['action'] : '';

	if ($action === 'save' || $action === 'save_reboot') {
		$updates = array();
		foreach ($schema as $fields) {
			foreach ($fields as $key => $f) {
				$v = isset($_POST[$key]) ? midgard_clean($_POST[$key]) : '';
				if ($f[0] === 'bool') $v = ($v === '1') ? '1' : '0';
				if ($f[0] === 'number' && $v !== '' && !preg_match('/^[0-9]+$/', $v)) {
					$err = $f[1] . ': enter a whole number.';
				}
				if ($f[0] === 'password' && $v === '') continue; // keep current
				$updates[$key] = $v;
			}
		}
		if (isset($updates['SSH_ROOT_PASS']) && strlen($updates['SSH_ROOT_PASS']) < 8) {
			$err = 'The camera password needs at least 8 characters.';
		}
		if (isset($updates['SETUP_AP_PASS']) && $updates['SETUP_AP_PASS'] !== ''
			&& strlen($updates['SETUP_AP_PASS']) < 8) {
			$err = 'The setup access point password needs at least 8 characters (or leave it empty).';
		}
		if ($err === '') {
			if (midgard_write($updates)) {
				if (isset($updates['SSH_ROOT_PASS'])) apply_root_password($updates['SSH_ROOT_PASS']);
				if ($action === 'save_reboot') {
					shell_exec('(sleep 3; sync; reboot) > /dev/null 2>&1 &');
					$msg = 'Saved. The camera is rebooting, reload this page in about a minute.';
				} else {
					$msg = 'Saved. Most settings take effect after a reboot.';
				}
			} else {
				$err = 'Could not write midgard.ini on the SD card.';
			}
		}
	} elseif ($action === 'reboot') {
		shell_exec('(sleep 3; sync; reboot) > /dev/null 2>&1 &');
		$msg = 'The camera is rebooting, reload this page in about a minute.';
	} elseif ($action === 'rtsp_restart') {
		shell_exec('/tmp/rtsp_start.sh stop > /dev/null 2>&1; /tmp/rtsp_start.sh start > /dev/null 2>&1');
		$msg = 'RTSP server restarted. The stream is back in about 15 seconds.';
	} elseif ($action === 'blink') {
		shell_exec('(L=/mnt/data/miot/ledctl; $L 0 50 2 300 300 2; $L 1 50 2 400 200 2; sleep 5; '
			. '$L 0 1 1 100 200 2; $L 1 1 1 100 200 2) > /dev/null 2>&1 &');
		$msg = 'The LEDs blink for 5 seconds.';
	}
}

$values = midgard_read();
$st = cam_status();
$show_log = isset($_GET['log']);
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mijia camera</title>
<link rel="stylesheet" href="/setup/style.css">
</head>
<body>
<main>
<h1>Mijia camera</h1>

<?php if ($msg): ?><div class="msg ok"><?= h($msg) ?></div><?php endif; ?>
<?php if ($err): ?><div class="msg err"><?= h($err) ?></div><?php endif; ?>
<?php if ((isset($values['SSH_ROOT_PASS']) ? $values['SSH_ROOT_PASS'] : '') === 'qwerty123456'): ?>
	<div class="msg err">The default password is still in use. Set a new one under System.</div>
<?php endif; ?>

<div class="card">
	<h2>Status</h2>
	<dl>
		<dt>IP address</dt><dd><?= h($st['ip'] ? $st['ip'] : 'not connected') ?></dd>
		<dt>Wi-Fi</dt><dd><?= h($st['wifi'] ? $st['wifi'] : 'unknown') ?></dd>
		<dt>RTSP</dt><dd><?= h($st['rtsp'] ? $st['rtsp'] : 'not running') ?>
			<?php if ($st['ip']): ?><br><code>rtsp://<?= h($st['ip']) ?>/live/ch00_0</code><?php endif; ?></dd>
		<dt>Time</dt><dd><?= h($st['time']) ?></dd>
		<dt>Uptime</dt><dd><?= h($st['uptime']) ?></dd>
		<dt>SD card</dt><dd><?= h($st['free']) ?></dd>
	</dl>
	<p>
		<a href="/media.php">Recordings</a> ·
		<?php if ($st['snapshot']): ?><a href="/snapshot.php" target="_blank">Snapshot</a> · <?php endif; ?>
		<a href="?log=1#log">Latest boot log</a>
	</p>
	<form method="post" class="actions">
		<button class="secondary" name="action" value="rtsp_restart">Restart RTSP</button>
		<button class="secondary" name="action" value="blink">Blink LEDs</button>
		<button class="secondary" name="action" value="reboot" onclick="return confirm('Reboot the camera?')">Reboot</button>
	</form>
</div>

<form method="post">
<?php foreach ($schema as $group => $fields): ?>
	<div class="card">
		<h2><?= h($group) ?></h2>
		<?php foreach ($fields as $key => $f):
			list($type, $label, $hint) = $f;
			$val = isset($values[$key]) ? $values[$key] : '';
			if ($type === 'bool'): ?>
			<div class="row">
				<input type="hidden" name="<?= h($key) ?>" value="0">
				<input type="checkbox" id="<?= h($key) ?>" name="<?= h($key) ?>" value="1" <?= $val === '1' ? 'checked' : '' ?>>
				<div><label for="<?= h($key) ?>"><?= h($label) ?></label>
				<?php if ($hint): ?><div class="hint"><?= h($hint) ?></div><?php endif; ?></div>
			</div>
			<?php else: ?>
			<label for="<?= h($key) ?>"><?= h($label) ?></label>
			<?php if ($type === 'select'): ?>
				<select id="<?= h($key) ?>" name="<?= h($key) ?>">
				<?php foreach ($f[3] as $ov => $ol): ?>
					<option value="<?= h($ov) ?>" <?= $val === $ov ? 'selected' : '' ?>><?= h($ol) ?></option>
				<?php endforeach; ?>
				</select>
			<?php elseif ($type === 'password'): ?>
				<input type="password" id="<?= h($key) ?>" name="<?= h($key) ?>" autocomplete="new-password" placeholder="unchanged">
			<?php else: ?>
				<input type="<?= $type === 'number' ? 'number' : 'text' ?>" id="<?= h($key) ?>" name="<?= h($key) ?>" value="<?= h($val) ?>">
			<?php endif; ?>
			<?php if ($hint): ?><div class="hint"><?= h($hint) ?></div><?php endif; ?>
			<?php endif; ?>
		<?php endforeach; ?>
	</div>
<?php endforeach; ?>
	<div class="actions">
		<button name="action" value="save">Save</button>
		<button name="action" value="save_reboot">Save and reboot</button>
	</div>
</form>

<?php if ($show_log): ?>
	<div class="card" id="log">
		<h2>Latest boot log</h2>
		<pre><?= h(latest_log()) ?></pre>
	</div>
<?php endif; ?>
</main>
</body>
</html>
