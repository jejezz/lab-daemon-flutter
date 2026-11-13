import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/pool.dart';
import 'package:lab_daemon/core/ipv4.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 2, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

Ipv4 ip(String s) => Ipv4.parse(s);
MacAddress mac(int n) => MacAddress([0xaa, 0xbb, 0xcc, 0, 0, n]);

LeasePool _pool(_Clock clock, {String start = '192.168.50.100', String end = '192.168.50.102', Duration? leaseTime = const Duration(hours: 1)}) =>
    LeasePool(
      start: ip(start),
      end: ip(end),
      mask: ip('255.255.255.0'),
      leaseTime: leaseTime,
      excluded: [ip('192.168.50.101')], // 예: 게이트웨이
      clock: clock.call,
    );

void main() {
  group('설정 검증', () {
    test('잘못된 범위는 거부한다', () {
      final mask = ip('255.255.255.0');
      expect(() => LeasePool(start: ip('192.168.50.20'), end: ip('192.168.50.10'), mask: mask), throwsA(isA<PoolConfigException>()));
      expect(() => LeasePool(start: ip('192.168.50.10'), end: ip('192.168.51.10'), mask: mask), throwsA(isA<PoolConfigException>()));
      expect(() => LeasePool(start: ip('192.168.50.0'), end: ip('192.168.50.10'), mask: mask), throwsA(isA<PoolConfigException>()));
      expect(() => LeasePool(start: ip('192.168.50.10'), end: ip('192.168.50.255'), mask: mask), throwsA(isA<PoolConfigException>()));
      expect(() => LeasePool(start: ip('192.168.50.10'), end: ip('192.168.50.20'), mask: ip('255.0.255.0')), throwsA(isA<PoolConfigException>()));
    });

    test('용량은 제외 주소를 뺀다', () {
      expect(_pool(_Clock()).capacity, 2);
    });
  });

  group('offer / confirm', () {
    test('제외 주소를 건너뛰고 순서대로 나눠 준다', () {
      final pool = _pool(_Clock());
      expect(pool.offer(mac(1))!.ip, ip('192.168.50.100'));
      expect(pool.offer(mac(2))!.ip, ip('192.168.50.102'));
      expect(pool.offer(mac(3)), isNull, reason: '풀이 찼다');
    });

    test('같은 MAC은 같은 주소를 받는다', () {
      final pool = _pool(_Clock());
      final first = pool.offer(mac(1))!;
      expect(pool.offer(mac(1))!.ip, first.ip);
      expect(pool.leases, hasLength(1));
    });

    test('요청한 주소가 비어 있으면 그 주소를 준다', () {
      final pool = _pool(_Clock());
      expect(pool.offer(mac(1), requested: ip('192.168.50.102'))!.ip, ip('192.168.50.102'));
      expect(pool.offer(mac(2), requested: ip('192.168.50.102'))!.ip, ip('192.168.50.100'), reason: '이미 제안됨');
      expect(pool.offer(mac(3), requested: ip('10.0.0.5')), isNull, reason: '범위 밖 요청은 무시하고 첫 빈 주소, 그러나 풀이 참');
    });

    test('REQUEST로 확정하면 bound가 되고 Lease Time이 적용된다', () {
      final clock = _Clock();
      final pool = _pool(clock, leaseTime: const Duration(minutes: 30));
      final offered = pool.offer(mac(1), hostname: 'rk3568')!;
      expect(offered.state, LeaseState.offered);
      final bound = pool.confirm(mac(1), offered.ip)!;
      expect(bound.state, LeaseState.bound);
      expect(bound.hostname, 'rk3568');
      expect(bound.expiresAt, clock.now.add(const Duration(minutes: 30)));
      expect(pool.boundCount, 1);
    });

    test('다른 주소를 요청하면 NAK(null)', () {
      final pool = _pool(_Clock());
      pool.offer(mac(1));
      pool.confirm(mac(1), ip('192.168.50.100'));
      expect(pool.confirm(mac(2), ip('192.168.50.100')), isNull, reason: '다른 MAC이 쓰는 주소');
      expect(pool.confirm(mac(2), ip('192.168.50.101')), isNull, reason: '제외 주소');
      expect(pool.confirm(mac(2), ip('10.1.1.1')), isNull, reason: '범위 밖');
    });

    test('Lease가 없던 클라이언트가 비어 있는 주소를 직접 요청하면 확정한다 (INIT-REBOOT)', () {
      final pool = _pool(_Clock());
      expect(pool.confirm(mac(1), ip('192.168.50.102'))!.state, LeaseState.bound);
    });

    test('갱신하면 만료 시각이 다시 Lease Time만큼 늘어난다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      pool.offer(mac(1));
      pool.confirm(mac(1), ip('192.168.50.100'));
      clock.advance(const Duration(minutes: 40));
      final renewed = pool.confirm(mac(1), ip('192.168.50.100'))!;
      expect(renewed.expiresAt, clock.now.add(const Duration(hours: 1)));
    });

    test('무제한 Lease는 만료되지 않는다', () {
      final clock = _Clock();
      final pool = _pool(clock, leaseTime: null);
      pool.offer(mac(1));
      final lease = pool.confirm(mac(1), ip('192.168.50.100'))!;
      expect(lease.expiresAt, isNull);
      expect(lease.remaining(clock.now), isNull);
      clock.advance(const Duration(days: 365));
      expect(pool.expire(), isEmpty);
    });

    test('Lease Time을 바꾸면 다음 확정부터 적용된다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      pool.offer(mac(1));
      final before = pool.confirm(mac(1), ip('192.168.50.100'))!.expiresAt;
      pool.leaseTime = const Duration(minutes: 5);
      pool.offer(mac(2));
      final after = pool.confirm(mac(2), ip('192.168.50.102'))!.expiresAt;
      expect(before, clock.now.add(const Duration(hours: 1)));
      expect(after, clock.now.add(const Duration(minutes: 5)));
    });
  });

  group('만료', () {
    test('제안은 보류 시간이 지나면 사라지고 주소가 반환된다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      pool.offer(mac(1));
      pool.offer(mac(2));
      expect(pool.offer(mac(3)), isNull);
      clock.advance(const Duration(seconds: 61));
      expect(pool.offer(mac(3)), isNotNull, reason: '만료된 제안의 주소를 재사용');
      expect(pool.leases.map((l) => l.mac), isNot(contains(mac(1))));
    });

    test('bound Lease는 Lease Time 뒤에 사라지고 expire가 돌려준다', () {
      final clock = _Clock();
      final pool = _pool(clock, leaseTime: const Duration(minutes: 10));
      pool.offer(mac(1));
      pool.confirm(mac(1), ip('192.168.50.100'));
      clock.advance(const Duration(minutes: 9, seconds: 59));
      expect(pool.expire(), isEmpty);
      clock.advance(const Duration(seconds: 1));
      final gone = pool.expire();
      expect(gone.map((l) => l.mac), [mac(1)]);
      expect(pool.leases, isEmpty);
    });

    test('남은 시간은 0 아래로 내려가지 않는다', () {
      final clock = _Clock();
      final pool = _pool(clock, leaseTime: const Duration(minutes: 1));
      pool.offer(mac(1));
      final lease = pool.confirm(mac(1), ip('192.168.50.100'))!;
      expect(lease.remaining(clock.now), const Duration(minutes: 1));
      clock.advance(const Duration(minutes: 5));
      expect(lease.remaining(clock.now), Duration.zero);
    });
  });

  group('해제', () {
    test('MAC·IP로 해제하고 주소를 다시 쓴다', () {
      final pool = _pool(_Clock());
      pool.confirm(mac(1), ip('192.168.50.100'));
      expect(pool.releaseIp(ip('192.168.50.100'))!.mac, mac(1));
      expect(pool.releaseIp(ip('192.168.50.100')), isNull);
      pool.confirm(mac(2), ip('192.168.50.102'));
      expect(pool.releaseMac(mac(2))!.ip, ip('192.168.50.102'));
      expect(pool.offer(mac(3))!.ip, ip('192.168.50.100'));
    });

    test('releaseAll은 예약을 남기고 Lease만 지운다', () {
      final pool = _pool(_Clock());
      pool.reserve(mac(9), ip('192.168.50.50'));
      pool.confirm(mac(1), ip('192.168.50.100'));
      pool.confirm(mac(2), ip('192.168.50.102'));
      final released = pool.releaseAll();
      expect(released.map((l) => l.mac), [mac(1), mac(2)]);
      expect(pool.leases, isEmpty);
      expect(pool.reservations, hasLength(1));
    });

    test('DECLINE한 주소는 격리 시간 동안 나눠 주지 않는다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      pool.offer(mac(1));
      pool.decline(ip('192.168.50.100'));
      expect(pool.leaseOfIp(ip('192.168.50.100')), isNull);
      expect(pool.offer(mac(2))!.ip, ip('192.168.50.102'));
      pool.releaseAll();
      expect(pool.offer(mac(3))!.ip, ip('192.168.50.102'), reason: '100은 격리 중');
      clock.advance(const Duration(minutes: 11));
      pool.releaseAll();
      expect(pool.offer(mac(4))!.ip, ip('192.168.50.100'));
    });
  });

  group('예약', () {
    test('예약된 MAC은 항상 그 주소를 받고 다른 MAC은 받지 못한다', () {
      final pool = _pool(_Clock());
      pool.reserve(mac(7), ip('192.168.50.100'));
      expect(pool.offer(mac(1))!.ip, ip('192.168.50.102'), reason: '100은 mac7 몫');
      expect(pool.offer(mac(7))!.ip, ip('192.168.50.100'));
      expect(pool.confirm(mac(7), ip('192.168.50.102')), isNull, reason: '예약과 다른 주소는 NAK');
      expect(pool.confirm(mac(7), ip('192.168.50.100')), isNotNull);
    });

    test('예약 주소는 풀 범위 밖이어도 서브넷 안이면 된다', () {
      final pool = _pool(_Clock());
      pool.reserve(mac(7), ip('192.168.50.20'));
      // 범위 밖이라 자동 할당 대상은 아니므로 offer는 풀에서 고른다 (범위 밖 예약은 아직 지원하지 않음).
      expect(pool.reservations[mac(7)], ip('192.168.50.20'));
    });

    test('서브넷 밖·네트워크·브로드캐스트·중복 예약은 거부한다', () {
      final pool = _pool(_Clock());
      expect(() => pool.reserve(mac(1), ip('10.0.0.1')), throwsA(isA<PoolConfigException>()));
      expect(() => pool.reserve(mac(1), ip('192.168.50.0')), throwsA(isA<PoolConfigException>()));
      expect(() => pool.reserve(mac(1), ip('192.168.50.255')), throwsA(isA<PoolConfigException>()));
      pool.reserve(mac(1), ip('192.168.50.100'));
      expect(() => pool.reserve(mac(2), ip('192.168.50.100')), throwsA(isA<PoolConfigException>()));
      pool.reserve(mac(1), ip('192.168.50.100')); // 같은 MAC 재등록은 허용
      pool.unreserve(mac(1));
      pool.reserve(mac(2), ip('192.168.50.100'));
    });
  });
  group('복원과 범위 밖 예약', () {
    test('저장한 Lease를 확정 상태로 되살리고, 맞지 않는 것은 거부한다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      final lease = pool.restore(mac: mac(1), ip: ip('192.168.50.100'), hostname: 'board', grantedAt: clock.now, expiresAt: clock.now.add(const Duration(minutes: 5)));
      expect(lease!.state, LeaseState.bound);
      expect(lease.hostname, 'board');
      expect(pool.leaseOfIp(ip('192.168.50.100'))!.mac, mac(1));

      final soon = clock.now.add(const Duration(minutes: 5));
      expect(pool.restore(mac: mac(2), ip: ip('192.168.50.100'), grantedAt: clock.now, expiresAt: soon), isNull, reason: '같은 주소가 이미 있음');
      expect(pool.restore(mac: mac(1), ip: ip('192.168.50.102'), grantedAt: clock.now, expiresAt: soon), isNull, reason: '같은 MAC이 이미 있음');
      expect(pool.restore(mac: mac(3), ip: ip('192.168.50.101'), grantedAt: clock.now, expiresAt: soon), isNull, reason: '제외 주소');
      expect(pool.restore(mac: mac(4), ip: ip('192.168.50.150'), grantedAt: clock.now, expiresAt: soon), isNull, reason: '범위 밖');
      expect(pool.restore(mac: mac(5), ip: ip('192.168.50.102'), grantedAt: clock.now, expiresAt: clock.now), isNull, reason: '이미 만료');
      expect(pool.restore(mac: mac(6), ip: ip('192.168.50.102'), grantedAt: clock.now, expiresAt: null)!.expiresAt, isNull, reason: '무제한');
    });

    test('다른 MAC에 예약된 주소나 다른 주소로 예약된 MAC의 Lease는 되살리지 않는다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      pool.reserve(mac(1), ip('192.168.50.100'));
      final soon = clock.now.add(const Duration(minutes: 5));
      expect(pool.restore(mac: mac(2), ip: ip('192.168.50.100'), grantedAt: clock.now, expiresAt: soon), isNull);
      expect(pool.restore(mac: mac(1), ip: ip('192.168.50.102'), grantedAt: clock.now, expiresAt: soon), isNull);
      expect(pool.restore(mac: mac(1), ip: ip('192.168.50.100'), grantedAt: clock.now, expiresAt: soon), isNotNull);
    });

    test('범위 밖 주소로 예약해도 그 MAC에는 그 주소를 준다', () {
      final pool = _pool(_Clock());
      pool.reserve(mac(1), ip('192.168.50.20'));
      expect(pool.offer(mac(1))!.ip, ip('192.168.50.20'));
      expect(pool.offer(mac(2))!.ip, isNot(ip('192.168.50.20')));
    });
  });
  group('제안할 주소 미리 보기', () {
    test('candidateFor는 offer가 고를 주소를 바꾸지 않고 알려 준다', () {
      final clock = _Clock();
      final pool = _pool(clock);
      expect(pool.candidateFor(mac(1)), ip('192.168.50.100'));
      expect(pool.leases, isEmpty, reason: '아무것도 바꾸지 않는다');
      expect(pool.candidateFor(mac(1), requested: ip('192.168.50.102')), ip('192.168.50.102'));
      pool.reserve(mac(1), ip('192.168.50.20'));
      expect(pool.candidateFor(mac(1)), ip('192.168.50.20'), reason: '예약이 먼저');
      final offered = pool.offer(mac(1))!;
      expect(offered.ip, ip('192.168.50.20'));
      expect(pool.candidateFor(mac(1)), ip('192.168.50.20'), reason: '이미 Lease가 있으면 그 주소');
    });
  });
}
