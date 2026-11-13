// 서비스 설정 모델(입력 문자열 → 검증 → 서비스 설정)과 저장.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/state/dhcp_settings.dart';
import 'package:lab_daemon/state/ftp_settings.dart';
import 'package:lab_daemon/state/tftp_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('settings_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('DHCP', () {
    test('NIC를 고르면 빈 칸과 다른 망의 값만 새 망 기준으로 채운다', () {
      const old = DhcpSettings(serverIp: '10.10.0.32', rangeStart: '10.10.0.100', rangeEnd: '10.10.0.200', gateway: '10.10.0.1');
      final moved = old.copyWith(serverIp: '172.20.0.1').withSuggestionsFor(Ipv4.parse('172.20.0.1'));
      expect([moved.rangeStart, moved.rangeEnd, moved.gateway], ['172.20.0.100', '172.20.0.200', '172.20.0.1']);
      expect(moved.validate(), isEmpty);

      const custom = DhcpSettings(serverIp: '192.168.50.1', rangeStart: '192.168.50.20', rangeEnd: '192.168.50.30', gateway: '192.168.50.254');
      final kept = custom.withSuggestionsFor(Ipv4.parse('192.168.50.1'));
      expect([kept.rangeStart, kept.rangeEnd, kept.gateway], ['192.168.50.20', '192.168.50.30', '192.168.50.254'], reason: '같은 망의 값은 그대로');
    });
  });

  group('DHCP 예약', () {
    const base = DhcpSettings(serverIp: '192.168.50.1', rangeStart: '192.168.50.100', rangeEnd: '192.168.50.110', gateway: '192.168.50.1');

    test('올바른 예약은 설정 검증을 통과하고 서비스 설정으로 넘어간다 (범위 밖 주소도 가능)', () {
      final s = base.copyWith(reservations: [('AA-BB-CC-00-11-22', '192.168.50.20'), ('aabbcc001133', '192.168.50.105')]);
      expect(s.validate(), isEmpty);
      final config = s.toConfig();
      expect(config.reservations.length, 2);
      expect(config.reservations.values.map((ip) => '$ip'), ['192.168.50.20', '192.168.50.105']);
    });

    test('잘못된 MAC·주소·망 밖·서버/게이트웨이와 같음·중복을 잡는다', () {
      FieldError? check(String mac, String ip, [List<(String, String)> others = const []]) => base.copyWith(reservations: others).checkNewReservation(mac, ip);
      expect(check('', '192.168.50.20'), FieldError.required);
      expect(check('xyz', '192.168.50.20'), FieldError.invalidMac);
      expect(check('aa:bb:cc:00:11:22', '192.168.50.x'), FieldError.invalidIp);
      expect(check('aa:bb:cc:00:11:22', '10.0.0.5'), FieldError.notInSubnet);
      expect(check('aa:bb:cc:00:11:22', '192.168.50.255'), FieldError.notHostAddress);
      expect(check('aa:bb:cc:00:11:22', '192.168.50.1'), FieldError.duplicate, reason: '서버·게이트웨이 주소');
      expect(check('aa:bb:cc:00:11:22', '192.168.50.20', [('aa:bb:cc:00:11:22', '192.168.50.30')]), FieldError.duplicate, reason: '같은 MAC');
      expect(check('aa:bb:cc:00:11:33', '192.168.50.30', [('aa:bb:cc:00:11:22', '192.168.50.30')]), FieldError.duplicate, reason: '같은 주소');
      expect(check('aa:bb:cc:00:11:22', '192.168.50.20'), isNull);

      final bad = base.copyWith(reservations: [('aa:bb:cc:00:11:22', '10.0.0.5')]);
      expect(bad.validate()[DhcpField.reservations], FieldError.notInSubnet, reason: '서브넷을 바꿔서 어긋난 예약은 시작을 막는다');
    });

    test('예약은 JSON으로 저장하고 다시 읽는다 (깨진 값은 빈 목록)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await base.copyWith(reservations: [('aa:bb:cc:00:11:22', '192.168.50.20')]).save(prefs);
      expect(DhcpSettings.load(prefs).reservations, [('aa:bb:cc:00:11:22', '192.168.50.20')]);
      await prefs.setString('dhcp_reservations', '이건 JSON이 아님');
      expect(DhcpSettings.load(prefs).reservations, isEmpty);
    });
  });

  group('TFTP', () {
    test('폴더가 없거나 숫자가 범위 밖이면 오류, 맞으면 설정으로 바뀐다', () {
      expect(const TftpSettings().validate().keys, contains(TftpField.rootDir));
      final bad = TftpSettings(rootDir: root.path, port: '70000', maxBlockSize: '4', bindIp: 'x');
      expect(bad.validate().keys, containsAll([TftpField.port, TftpField.maxBlockSize, TftpField.bindIp]));
      final good = TftpSettings(rootDir: root.path, bindIp: '192.168.50.1', allowWrite: true);
      expect(good.validate(), isEmpty);
      final config = good.toConfig();
      expect(config.bindAddress, Ipv4.parse('192.168.50.1'));
      expect(config.allowWrite, isTrue);
      expect(TftpSettings(rootDir: root.path).toConfig().bindAddress, isNull, reason: '빈 NIC = 모든 NIC');
    });

    test('저장했다가 다시 읽는다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await TftpSettings(rootDir: root.path, port: '6969', allowWrite: true).save(prefs);
      final again = TftpSettings.load(prefs);
      expect([again.rootDir, again.port, again.allowWrite], [root.path, '6969', true]);
    });
  });

  group('FTP', () {
    test('로그인 방법(계정 또는 익명)이 있어야 하고, 사용자 이름을 바꾸면 비밀번호를 다시 정해야 한다', () {
      final base = FtpSettings(rootDir: root.path);
      expect(base.validate().keys, containsAll([FtpField.username, FtpField.password]));
      expect(base.copyWith(allowAnonymous: true).validate(), isEmpty);

      final withAccount = base.copyWith(username: 'board').withPassword('pw');
      expect(withAccount.hasPassword, isTrue);
      expect(withAccount.validate(), isEmpty);
      expect(withAccount.toConfig().account!.verify('pw'), isTrue);

      final renamed = withAccount.copyWith(username: 'other');
      expect(renamed.hasPassword, isFalse);
      expect(renamed.validate().keys, contains(FtpField.password));
      expect(withAccount.withPassword('').account, isNull, reason: '빈 비밀번호는 계정을 지운다');
    });

    test('패시브 범위가 거꾸로면 오류, 기본 범위는 Windows 동적 포트 범위 밖이다', () {
      final s = FtpSettings(rootDir: root.path, allowAnonymous: true);
      expect(int.parse(s.passiveEnd), lessThan(49152));
      expect(s.copyWith(passiveStart: '41000', passiveEnd: '40000').validate().keys, contains(FtpField.passiveEnd));
    });

    test('비밀번호는 평문으로 저장되지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await FtpSettings(rootDir: root.path, username: 'board').withPassword('secret-pw').save(prefs);
      final raw = prefs.getString('ftp_account')!;
      expect(raw, isNot(contains('secret-pw')));
      expect(jsonDecode(raw), containsPair('username', 'board'));
      final again = FtpSettings.load(prefs);
      expect(again.hasPassword, isTrue);
      expect(again.account!.verify('secret-pw'), isTrue);
    });
  });
}
