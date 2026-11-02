// 서비스가 내는 모든 로그 키가 두 언어로 번역되는지 확인한다. 새 로그 키를 추가하고 포맷터를
// 빠뜨리면 화면에 키 이름이 그대로 나오는데, 이 테스트가 그것을 잡는다.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/service.dart';
import 'package:lab_daemon/l10n/app_localizations.dart';
import 'package:lab_daemon/ui/log_format.dart';

/// 포맷터가 채워야 하는 인자의 예시 값.
const _args = <String, Object?>{
  'mac': 'aa:bb:cc:00:00:01',
  'ip': '192.168.50.100',
  'hostname': 'rk3568',
  'seconds': 3600,
  'reason': 'addressUnavailable',
  'server': '192.168.50.254',
  'from': '192.168.50.9',
  'to': '192.168.50.9',
  'error': 'boom',
  'address': '192.168.50.1',
  'port': 67,
  'start': '192.168.50.100',
  'end': '192.168.50.110',
  'mask': '255.255.255.0',
};

void main() {
  // 코어 코드에서 log(...)/_log(...)에 쓰는 'logDhcp…' 키를 소스에서 직접 모은다.
  final keys = <String>{
    for (final dir in ['lib/core', 'lib/state'])
      for (final file in Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        for (final m in RegExp(r"'(logDhcp[A-Za-z]+)'").allMatches(file.readAsStringSync())) m.group(1)!,
  };

  test('소스에서 로그 키를 찾았다', () {
    expect(keys.length, greaterThan(20));
  });

  for (final locale in AppLocalizations.supportedLocales) {
    test('${locale.languageCode}: 모든 로그 키가 번역되어 키 이름이 그대로 나오지 않는다', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final missing = <String>[];
      for (final key in keys) {
        final text = formatLog(l10n, LogEvent('dhcp', LogLevel.info, key, args: _args));
        if (text.startsWith(key)) missing.add(key);
        expect(text.trim(), isNotEmpty, reason: key);
        expect(text, isNot(contains('{')), reason: '$key: 채워지지 않은 자리표시자');
      }
      expect(missing, isEmpty, reason: 'log_format.dart에 빠진 키: $missing');
    });
  }

  test('ARB의 logDhcp 키는 모두 소스에서 실제로 쓰인다 (쓰지 않는 키가 쌓이지 않게)', () {
    final arb = jsonDecode(File('lib/l10n/app_ko.arb').readAsStringSync()) as Map<String, dynamic>;
    // logDhcpPacketIn/Out은 패킷 로깅 옵션을 켤 때만 쓰이지만 소스에는 문자열로 들어 있다.
    final unused = arb.keys.where((k) => k.startsWith('logDhcp') && !keys.contains(k)).toList();
    expect(unused, isEmpty);
  });

  test('알 수 없는 키는 숨기지 않고 키와 인자를 보여 준다', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(formatLog(l10n, LogEvent('x', LogLevel.info, 'logFuture', args: const {'a': 1})), 'logFuture {a: 1}');
    expect(formatLog(l10n, LogEvent('x', LogLevel.info, 'logFuture')), 'logFuture');
  });

  test('무제한 Lease와 값 없는 호스트 이름도 어색하지 않게 나온다', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final ack = formatLog(l10n, LogEvent('dhcp', LogLevel.info, 'logDhcpAck', args: const {'ip': '1.1.1.1', 'mac': 'm', 'seconds': null}));
    expect(ack, contains('lease Unlimited'));
    final discover = formatLog(l10n, LogEvent('dhcp', LogLevel.info, 'logDhcpDiscover', args: const {'mac': 'm', 'hostname': null}));
    expect(discover, 'DISCOVER from m');
  });
}
