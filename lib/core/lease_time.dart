// Lease Time 입력 형식: `30s`, `10m`, `12h`, `1d`, 단위 없는 숫자(초), `infinite`.
// null은 무제한이다. DHCP option 51에서는 0xFFFFFFFF로 보낸다.

/// 가장 긴 유한 Lease Time (option 51은 부호 없는 32비트 초, 0xFFFFFFFF는 무제한 예약값).
const maxLeaseSeconds = 0xFFFFFFFE;

/// 사용자가 입력한 [text]를 Lease Time으로 바꾼다. 무제한이면 null.
/// 형식이 틀렸거나 0이거나 너무 길면 [FormatException].
Duration? parseLeaseTime(String text) {
  final input = text.trim().toLowerCase();
  if (input == 'infinite' || input == 'inf') return null;
  final match = RegExp(r'^([0-9]+)[ ]*([smhd]?)$').firstMatch(input);
  if (match == null) throw FormatException('Invalid lease time', text);
  final amount = int.parse(match.group(1)!);
  final seconds = amount *
      switch (match.group(2)) {
        'm' => 60,
        'h' => 3600,
        'd' => 86400,
        _ => 1,
      };
  if (seconds <= 0 || seconds > maxLeaseSeconds) throw FormatException('Lease time out of range', text);
  return Duration(seconds: seconds);
}

/// [parseLeaseTime]이 다시 읽을 수 있는 가장 짧은 표기.
String formatLeaseTime(Duration? time) {
  if (time == null) return 'infinite';
  final s = time.inSeconds;
  if (s % 86400 == 0) return '${s ~/ 86400}d';
  if (s % 3600 == 0) return '${s ~/ 3600}h';
  if (s % 60 == 0) return '${s ~/ 60}m';
  return '${s}s';
}
