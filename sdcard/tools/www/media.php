<?php
// Recordings browser: lists /tmp/sd/MIJIA_RECORD_VIDEO and streams files
// (with HTTP Range support, needed for seeking and for Safari).
require_once('/tmp/sd/tools/www/lib/midgard.php');
require_login();

$base = '/tmp/sd/MIJIA_RECORD_VIDEO';
$rel = isset($_GET['p']) ? trim((string)$_GET['p'], '/') : '';
$path = realpath($base . '/' . $rel);
$root = realpath($base);

if ($root === false) {
	http_response_code(404);
	exit('No recordings folder on the SD card yet.');
}
if ($path === false || ($path !== $root && strpos($path, $root . '/') !== 0)) {
	http_response_code(404);
	exit('Not found.');
}

if (is_file($path)) {
	$size = filesize($path);
	$types = array('mp4' => 'video/mp4', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg', 'png' => 'image/png');
	$ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
	$start = 0;
	$end = $size - 1;
	if (isset($_SERVER['HTTP_RANGE']) && preg_match('/^bytes=(\d*)-(\d*)$/', $_SERVER['HTTP_RANGE'], $m)) {
		if ($m[1] === '' && $m[2] !== '') {
			$start = max(0, $size - (int)$m[2]);
		} else {
			$start = (int)$m[1];
			if ($m[2] !== '') $end = min((int)$m[2], $size - 1);
		}
		if ($start > $end || $start >= $size) {
			http_response_code(416);
			header("Content-Range: bytes */$size");
			exit;
		}
		http_response_code(206);
		header("Content-Range: bytes $start-$end/$size");
	}
	header('Content-Type: ' . (isset($types[$ext]) ? $types[$ext] : 'application/octet-stream'));
	header('Accept-Ranges: bytes');
	header('Content-Length: ' . ($end - $start + 1));
	header('Content-Disposition: inline; filename="' . basename($path) . '"');
	while (ob_get_level()) ob_end_clean();
	$fp = fopen($path, 'rb');
	fseek($fp, $start);
	$left = $end - $start + 1;
	while ($left > 0 && !feof($fp)) {
		$chunk = fread($fp, min(65536, $left));
		if ($chunk === false || $chunk === '') break;
		echo $chunk;
		flush();
		$left -= strlen($chunk);
	}
	fclose($fp);
	exit;
}

$dirs = array();
$files = array();
foreach (scandir($path) as $name) {
	if ($name[0] === '.') continue;
	if (is_dir("$path/$name")) $dirs[] = $name; else $files[] = $name;
}
rsort($dirs);
rsort($files);
$here = ($path === $root) ? '' : substr($path, strlen($root) + 1);
$up = ($here === '') ? null : dirname($here);
?><!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Recordings</title>
<link rel="stylesheet" href="/setup/style.css">
</head>
<body>
<main>
<h1>Recordings<?= $here !== '' ? ' / ' . h($here) : '' ?></h1>
<div class="card">
	<p><a href="/">← Settings</a><?php if ($up !== null): ?> · <a href="?p=<?= h(urlencode($up === '.' ? '' : $up)) ?>">↑ Up</a><?php endif; ?></p>
	<?php if (!$dirs && !$files): ?><p class="hint">Empty.</p><?php endif; ?>
	<?php foreach ($dirs as $d): ?>
		<div><a href="?p=<?= h(urlencode(ltrim("$here/$d", '/'))) ?>">📁 <?= h($d) ?></a></div>
	<?php endforeach; ?>
	<?php foreach ($files as $f): ?>
		<div><a href="?p=<?= h(urlencode(ltrim("$here/$f", '/'))) ?>" target="_blank"><?= h($f) ?></a>
			<span class="hint"><?= h(round(filesize("$path/$f") / 1048576, 1)) ?> MB</span></div>
	<?php endforeach; ?>
</div>
</main>
</body>
</html>
