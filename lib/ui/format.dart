// 숫자 표시: 크기는 KB/MB/GB(1024 기준, 소수 첫째 자리 — localization.md §6), 속도, 경과 시간.

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}

String formatRate(num bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

/// `1:02:03` 또는 `2:03`.
String formatElapsed(Duration d) {
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours > 0) return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
  return '${d.inMinutes}:$s';
}
