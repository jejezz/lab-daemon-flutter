import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/lease_time.dart';

void main() {
  group('Ipv4', () {
    test('문자열과 바이트를 오간다', () {
      final ip = Ipv4.parse('192.168.50.100');
      expect(ip.toString(), '192.168.50.100');
      expect(ip.toBytes(), [192, 168, 50, 100]);
      expect(Ipv4.fromBytes([192, 168, 50, 100]), ip);
      expect(Ipv4.fromBytes([0, 0, 0, 0, 10, 0, 0, 1], 4).toString(), '10.0.0.1');
    });

    test('잘못된 주소는 거부한다', () {
      for (final bad in ['', '1.2.3', '1.2.3.4.5', '256.1.1.1', '1.2.3.-4', 'a.b.c.d', '01.2.3.4', '1..3.4', '1.2.3.4 5']) {
        expect(Ipv4.tryParse(bad), isNull, reason: bad);
      }
      expect(() => Ipv4.parse('x'), throwsFormatException);
      expect(Ipv4.tryParse(' 10.0.0.1 '), Ipv4.parse('10.0.0.1'));
    });

    test('산술과 비교', () {
      final ip = Ipv4.parse('10.0.0.255');
      expect((ip + 1).toString(), '10.0.1.0');
      expect(Ipv4.parse('10.0.0.1') < Ipv4.parse('10.0.0.2'), isTrue);
      expect(Ipv4.parse('255.255.255.255').value, 0xFFFFFFFF);
      expect((~Ipv4.parse('255.255.255.0')).toString(), '0.0.0.255');
    });

    test('서브넷 마스크 검증과 접두 길이', () {
      expect(Ipv4.parse('255.255.255.0').isValidMask, isTrue);
      expect(Ipv4.parse('255.255.255.0').prefixLength, 24);
      expect(Ipv4.parse('255.255.254.0').prefixLength, 23);
      expect(Ipv4.parse('255.255.255.252').prefixLength, 30);
      for (final bad in ['255.0.255.0', '0.0.0.0', '255.255.255.255', '0.255.255.255']) {
        expect(Ipv4.parse(bad).isValidMask, isFalse, reason: bad);
        expect(Ipv4.parse(bad).prefixLength, isNull, reason: bad);
      }
    });

    test('네트워크·브로드캐스트·소속 판정', () {
      final mask = Ipv4.parse('255.255.255.0');
      final ip = Ipv4.parse('192.168.50.77');
      expect(ip.networkOf(mask).toString(), '192.168.50.0');
      expect(ip.broadcastOf(mask).toString(), '192.168.50.255');
      expect(ip.isInSubnet(Ipv4.parse('192.168.50.0'), mask), isTrue);
      expect(ip.isInSubnet(Ipv4.parse('192.168.51.0'), mask), isFalse);
    });
  });

  group('MacAddress', () {
    test('여러 표기를 읽고 소문자 콜론으로 출력한다', () {
      for (final text in ['AA:BB:CC:11:22:33', 'aa-bb-cc-11-22-33', 'aabbcc112233']) {
        expect(MacAddress.parse(text).toString(), 'aa:bb:cc:11:22:33', reason: text);
      }
      expect(MacAddress.tryParse('aa:bb:cc'), isNull);
      expect(MacAddress.tryParse('zz:bb:cc:11:22:33'), isNull);
    });

    test('Map 키로 쓸 수 있다', () {
      final map = {MacAddress.parse('aa:bb:cc:11:22:33'): 1};
      expect(map[MacAddress([0xaa, 0xbb, 0xcc, 0x11, 0x22, 0x33])], 1);
      expect(map[MacAddress.parse('aa:bb:cc:11:22:34')], isNull);
    });
  });

  group('Lease Time', () {
    test('단위를 읽는다', () {
      expect(parseLeaseTime('30s'), const Duration(seconds: 30));
      expect(parseLeaseTime('10m'), const Duration(minutes: 10));
      expect(parseLeaseTime('12h'), const Duration(hours: 12));
      expect(parseLeaseTime('1d'), const Duration(days: 1));
      expect(parseLeaseTime('90'), const Duration(seconds: 90));
      expect(parseLeaseTime(' 5 M '), const Duration(minutes: 5));
    });

    test('infinite는 null', () {
      expect(parseLeaseTime('infinite'), isNull);
      expect(parseLeaseTime('INF'), isNull);
    });

    test('잘못된 값은 거부한다', () {
      for (final bad in ['', '0', '0s', '-5m', 'abc', '10x', '1.5h', '99999999999d']) {
        expect(() => parseLeaseTime(bad), throwsFormatException, reason: bad);
      }
    });

    test('표기를 다시 읽을 수 있다', () {
      expect(formatLeaseTime(const Duration(hours: 12)), '12h');
      expect(formatLeaseTime(const Duration(seconds: 90)), '90s');
      expect(formatLeaseTime(const Duration(days: 2)), '2d');
      expect(formatLeaseTime(null), 'infinite');
      for (final d in [const Duration(seconds: 45), const Duration(minutes: 7), const Duration(hours: 3)]) {
        expect(parseLeaseTime(formatLeaseTime(d)), d);
      }
    });
  });
}
