import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/host.dart';
import 'package:lab_daemon/core/netcheck.dart';
import 'package:lab_daemon/core/service.dart';
import 'package:lab_daemon/core/tftp/server.dart';
import 'package:lab_daemon/state/log_file.dart';
import 'package:lab_daemon/state/service_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('logfile_'));
  tearDown(() => dir.deleteSync(recursive: true));

  LogFileSink sink({int keepDays = 14}) => LogFileSink(directory: '${dir.path}${Platform.pathSeparator}logs', serviceId: 'tftp', keepDays: keepDays, format: (e) => 'text(${e.key})');

  LogEvent event(String key, {LogLevel level = LogLevel.info, String? kind, String? detail, DateTime? time}) =>
      LogEvent('tftp', level, key, kind: kind, detail: detail, time: time ?? DateTime(2026, 11, 13, 12, 42, 39, 16));

  test('로그를 날짜별 파일에 한 줄씩 쓰고, 덧붙임(덤프)은 들여써서 잇는다', () async {
    final bus = LogBus();
    final s = sink()..attach(bus);
    bus.add(event('logTftpRrq', kind: 'RRQ'));
    bus.add(event('logTftpFailed', level: LogLevel.error, detail: 'aa bb\ncc dd'));
    bus.add(event('logTftpStopped', time: DateTime(2026, 11, 14, 0, 0, 1)));
    await s.detach();

    final day1 = File(s.pathFor(DateTime(2026, 11, 13))).readAsStringSync();
    expect(day1, '2026-11-13 12:42:39.016 INFO  [RRQ] text(logTftpRrq)\n'
        '2026-11-13 12:42:39.016 ERROR text(logTftpFailed)\n'
        '    aa bb\n'
        '    cc dd\n');
    expect(File(s.pathFor(DateTime(2026, 11, 14))).readAsStringSync(), '2026-11-14 00:00:01.000 INFO  text(logTftpStopped)\n');
    await bus.dispose();
  });

  test('다시 붙여도 이어서 쓴다 (덮어쓰지 않는다)', () async {
    final bus = LogBus();
    final s = sink()..attach(bus);
    bus.add(event('a'));
    await s.detach();
    s.attach(bus);
    bus.add(event('b'));
    await s.detach();
    final lines = File(s.pathFor(DateTime(2026, 11, 13))).readAsLinesSync();
    expect(lines.map((l) => l.split(' ').last), ['text(a)', 'text(b)']);
    await bus.dispose();
  });

  test('켤 때 보관 기간이 지난 파일만 지운다', () async {
    final logs = Directory('${dir.path}${Platform.pathSeparator}logs')..createSync();
    final old = File('${logs.path}${Platform.pathSeparator}tftp-2026-01-01.log')..writeAsStringSync('old');
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
    final recent = File('${logs.path}${Platform.pathSeparator}tftp-2026-11-12.log')..writeAsStringSync('recent');
    final other = File('${logs.path}${Platform.pathSeparator}ftp-2026-01-01.log')..writeAsStringSync('ftp');
    other.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));

    final bus = LogBus();
    final s = sink()..attach(bus);
    await s.detach();
    expect(old.existsSync(), isFalse);
    expect(recent.existsSync(), isTrue);
    expect(other.existsSync(), isTrue, reason: '다른 서비스의 파일은 건드리지 않는다');
    await bus.dispose();
  });

  test('쓰지 못하면 오류를 기억하고 앱은 계속 돈다', () async {
    File('${dir.path}${Platform.pathSeparator}logs').writeAsStringSync('폴더 자리에 파일이 있다');
    final bus = LogBus();
    final s = sink()..attach(bus);
    bus.add(event('a'));
    await s.detach();
    expect(s.lastError, isNotNull);
    await bus.dispose();
  });

  group('모델의 [로그를 파일에도 저장]', () {
    Future<(TftpModel, LogFileSink)> make() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = sink();
      final model = TftpModel(host: InProcessHost(TftpServer(snapshotInterval: Duration.zero)), prefs: prefs, checker: PreStartChecker(isWindows: false), logSink: s, notifyDelay: Duration.zero);
      addTearDown(() async {
        await s.detach();
        model.dispose();
      });
      return (model, s);
    }

    test('기본은 꺼짐이고, 켜면 로그가 파일로 가고 설정이 저장된다', () async {
      final (model, s) = await make();
      expect(model.logToFile, isFalse);
      expect(s.attached, isFalse);
      model.logs.add(event('before'));

      await model.setLogToFile(true);
      expect(model.logToFile, isTrue);
      expect(s.attached, isTrue);
      model.logs.add(event('after'));
      await model.flushLogs();
      final text = File(s.pathFor(DateTime(2026, 11, 13))).readAsStringSync();
      expect(text, contains('text(after)'));
      expect(text, isNot(contains('text(before)')), reason: '켠 뒤의 로그만 쓴다');

      await model.setLogToFile(false);
      expect(s.attached, isFalse);
      expect((await SharedPreferences.getInstance()).getBool('tftp_log_file'), isFalse);
    });

    test('저장된 설정이 켜져 있으면 모델을 만들 때 바로 붙는다', () async {
      SharedPreferences.setMockInitialValues({'tftp_log_file': true});
      final prefs = await SharedPreferences.getInstance();
      final s = sink();
      final model = TftpModel(host: InProcessHost(TftpServer(snapshotInterval: Duration.zero)), prefs: prefs, checker: PreStartChecker(isWindows: false), logSink: s, notifyDelay: Duration.zero);
      addTearDown(() async {
        await s.detach();
        model.dispose();
      });
      expect(s.attached, isTrue);
    });

    test('파일 저장 기능이 없는 모델은 폴더가 없고 켜도 아무 일 없다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final model = TftpModel(host: InProcessHost(TftpServer(snapshotInterval: Duration.zero)), prefs: prefs, checker: PreStartChecker(isWindows: false), notifyDelay: Duration.zero);
      addTearDown(model.dispose);
      expect(model.logDirectory, isNull);
      await model.setLogToFile(true);
      expect(model.logToFile, isFalse);
    });
  });
}
