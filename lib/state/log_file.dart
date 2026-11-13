// 서비스 로그를 날짜별 파일로 저장한다 (`<폴더>/<서비스>-YYYY-MM-DD.log`). 화면의 로그 버퍼([LogBus])를 그대로 듣고,
// 1초에 한 번 모아서 쓴다. 로그를 쓰는 경로(패킷 처리)에는 아무것도 더하지 않는다.
// 파일은 영어 문구로 남긴다 (언어를 바꿔도 같은 형식이라 나중에 읽거나 검색하기 쉽다).

import 'dart:async';
import 'dart:io';

import '../core/service.dart';

class LogFileSink {
  LogFileSink({required this.directory, required this.serviceId, required this.format, this.keepDays = 14});

  /// 로그 파일을 두는 폴더.
  final String directory;
  final String serviceId;

  /// 로그 한 줄의 문구 (번역한 본문).
  final String Function(LogEvent event) format;

  /// 이 날짜보다 오래된 파일은 켤 때 지운다.
  final int keepDays;

  StreamSubscription<LogEvent>? _subscription;
  Timer? _timer;
  final _pending = <LogEvent>[];
  bool _flushing = false;

  /// 마지막 쓰기 오류 (없으면 null).
  String? lastError;

  bool get attached => _subscription != null;

  String pathFor(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = time.toLocal();
    return '$directory${Platform.pathSeparator}$serviceId-${t.year}-${two(t.month)}-${two(t.day)}.log';
  }

  /// [bus]의 로그를 파일에 쓰기 시작한다.
  void attach(LogBus bus) {
    if (attached) return;
    _purgeOld();
    _subscription = bus.stream.listen(_pending.add);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => flush());
  }

  /// 듣기를 멈추고 남은 것을 쓴다.
  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
    _timer?.cancel();
    _timer = null;
    await flush();
  }

  /// 모인 로그를 날짜별 파일에 덧붙인다.
  Future<void> flush() async {
    if (_pending.isEmpty || _flushing) return;
    _flushing = true;
    final batch = List<LogEvent>.of(_pending);
    _pending.clear();
    try {
      final byFile = <String, StringBuffer>{};
      for (final e in batch) {
        (byFile[pathFor(e.time)] ??= StringBuffer()).write(line(e));
      }
      await Directory(directory).create(recursive: true);
      for (final MapEntry(key: path, value: text) in byFile.entries) {
        await File(path).writeAsString(text.toString(), mode: FileMode.append, flush: true);
      }
      lastError = null;
    } catch (e) {
      lastError = '$e'; // 이번 묶음은 버린다 (디스크가 차도 메모리에 쌓이지 않게)
    } finally {
      _flushing = false;
    }
  }

  /// `2026-11-13 12:42:39.016 INFO  [RRQ] 본문` + 덧붙임(16진수 덤프 등)은 들여써서 이어 쓴다.
  String line(LogEvent e) {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = e.time.toLocal();
    final stamp = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
    final level = e.level.name.toUpperCase().padRight(5);
    final kind = e.kind == null ? '' : '[${e.kind}] ';
    final b = StringBuffer('$stamp $level $kind${format(e)}\n');
    final detail = e.detail;
    if (detail != null && detail.isNotEmpty) {
      for (final l in detail.split('\n')) {
        b.write('    $l\n');
      }
    }
    return b.toString();
  }

  void _purgeOld() {
    try {
      final dir = Directory(directory);
      if (!dir.existsSync()) return;
      final limit = DateTime.now().subtract(Duration(days: keepDays));
      for (final f in dir.listSync()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name.startsWith('$serviceId-') && name.endsWith('.log') && f.lastModifiedSync().isBefore(limit)) f.deleteSync();
      }
    } catch (_) {
      // 지우지 못해도 로그는 계속 쓴다.
    }
  }
}
