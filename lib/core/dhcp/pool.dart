// IP 풀과 Lease 표. 소켓·타이머 없이 시계만 주입받으므로 단위 테스트로 모든 전이를 확인할 수 있다.
//
// Lease 생애: DISCOVER → [offered] (제안 보류 시간 안에 REQUEST가 없으면 사라짐) → REQUEST → [bound]
// (Lease Time이 지나면 사라짐, 무제한이면 해제할 때까지). 같은 MAC은 항상 한 개의 Lease만 가진다.

import '../ipv4.dart';

enum LeaseState { offered, bound }

class Lease {
  Lease({
    required this.mac,
    required this.ip,
    required this.state,
    required this.grantedAt,
    required this.expiresAt,
    this.hostname,
  });

  final MacAddress mac;
  final Ipv4 ip;
  LeaseState state;
  DateTime grantedAt;

  /// null이면 무제한 (bound일 때만).
  DateTime? expiresAt;
  String? hostname;

  bool isExpired(DateTime now) => expiresAt != null && !now.isBefore(expiresAt!);

  /// 남은 시간. 무제한이면 null.
  Duration? remaining(DateTime now) {
    final end = expiresAt;
    if (end == null) return null;
    final left = end.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

class PoolConfigException implements Exception {
  PoolConfigException(this.message);

  final String message;

  @override
  String toString() => 'PoolConfigException: $message';
}

class LeasePool {
  /// [start]~[end]는 [mask] 서브넷 안의 호스트 주소여야 한다. [excluded]에는 서버 자신과 게이트웨이처럼
  /// 범위 안에 있어도 나눠 주면 안 되는 주소를 넣는다. [leaseTime]이 null이면 무제한.
  LeasePool({
    required this.start,
    required this.end,
    required this.mask,
    this.leaseTime = const Duration(hours: 1),
    Iterable<Ipv4> excluded = const [],
    this.offerHold = const Duration(seconds: 60),
    this.declineQuarantine = const Duration(minutes: 10),
    DateTime Function()? clock,
  })  : excluded = Set.unmodifiable(excluded),
        _clock = clock ?? DateTime.now {
    if (!mask.isValidMask) throw PoolConfigException('Invalid subnet mask $mask');
    if (start > end) throw PoolConfigException('Range start $start is after end $end');
    if (!end.isInSubnet(start, mask)) throw PoolConfigException('$start and $end are not in the same subnet');
    final network = start.networkOf(mask);
    final broadcast = start.broadcastOf(mask);
    if (start == network || end == broadcast) {
      throw PoolConfigException('Range must not include the network address $network or broadcast $broadcast');
    }
  }

  final Ipv4 start;
  final Ipv4 end;
  final Ipv4 mask;
  Duration? leaseTime;
  final Set<Ipv4> excluded;
  final Duration offerHold;
  final Duration declineQuarantine;
  final DateTime Function() _clock;

  final _byMac = <MacAddress, Lease>{};
  final _byIp = <Ipv4, Lease>{};
  final _reservations = <MacAddress, Ipv4>{};
  final _declined = <Ipv4, DateTime>{};

  DateTime get now => _clock();

  /// 풀이 나눠 줄 수 있는 주소 수 (제외 주소 뺀 것).
  int get capacity => end.value - start.value + 1 - excluded.where(_inRange).length;

  List<Lease> get leases => (_byMac.values.toList()..sort((a, b) => a.ip.compareTo(b.ip)));

  int get boundCount => _byMac.values.where((l) => l.state == LeaseState.bound).length;

  Lease? leaseOfMac(MacAddress mac) => _byMac[mac];

  Lease? leaseOfIp(Ipv4 ip) => _byIp[ip];

  Map<MacAddress, Ipv4> get reservations => Map.unmodifiable(_reservations);

  bool _inRange(Ipv4 ip) => ip >= start && ip <= end;

  // ---- 예약 -------------------------------------------------------------------------------------

  /// [mac]에는 항상 [ip]를 준다. [ip]는 서브넷 안의 호스트 주소이고 다른 MAC에 예약돼 있으면 안 된다.
  /// 그 주소를 이미 다른 클라이언트가 쓰고 있으면 그 Lease가 끝나야 적용된다.
  void reserve(MacAddress mac, Ipv4 ip) {
    if (!ip.isInSubnet(start, mask) || ip == start.networkOf(mask) || ip == start.broadcastOf(mask)) {
      throw PoolConfigException('$ip is not a host address of the subnet');
    }
    for (final MapEntry(key: other, value: reserved) in _reservations.entries) {
      if (reserved == ip && other != mac) throw PoolConfigException('$ip is already reserved for $other');
    }
    _reservations[mac] = ip;
  }

  void unreserve(MacAddress mac) => _reservations.remove(mac);

  // ---- DISCOVER / REQUEST ----------------------------------------------------------------------

  /// DISCOVER에 대한 제안. 줄 주소가 없으면 null (OFFER를 보내지 않는다).
  /// 우선순위: 이미 가진 Lease → 예약 → 클라이언트가 요청한 주소 → 비어 있는 첫 주소.
  Lease? offer(MacAddress mac, {Ipv4? requested, String? hostname}) {
    expire();
    final existing = _byMac[mac];
    if (existing != null) {
      existing.hostname = hostname ?? existing.hostname;
      if (existing.state == LeaseState.offered) existing.expiresAt = now.add(offerHold);
      return existing;
    }
    final reserved = _reservations[mac];
    final ip = (reserved != null && _isFree(reserved, mac) ? reserved : null) ??
        (requested != null && _isFree(requested, mac) ? requested : null) ??
        _firstFree(mac);
    if (ip == null) return null;
    return _put(Lease(
      mac: mac,
      ip: ip,
      state: LeaseState.offered,
      grantedAt: now,
      expiresAt: now.add(offerHold),
      hostname: hostname,
    ));
  }

  /// REQUEST(선택, 갱신, 재바인딩, INIT-REBOOT)에 대한 확정. 줄 수 없으면 null (NAK).
  Lease? confirm(MacAddress mac, Ipv4 ip, {String? hostname}) {
    expire();
    final reserved = _reservations[mac];
    if (reserved != null && reserved != ip) return null;
    var lease = _byMac[mac];
    if (lease == null || lease.ip != ip) {
      if (!_isFree(ip, mac)) return null;
      if (lease != null) _remove(lease);
      lease = _put(Lease(
        mac: mac,
        ip: ip,
        state: LeaseState.offered,
        grantedAt: now,
        expiresAt: null,
        hostname: hostname,
      ));
    }
    lease
      ..state = LeaseState.bound
      ..grantedAt = now
      ..expiresAt = leaseTime == null ? null : now.add(leaseTime!)
      ..hostname = hostname ?? lease.hostname;
    return lease;
  }

  // ---- 해제 / 거절 / 만료 -----------------------------------------------------------------------

  /// 해제한 Lease를 돌려준다. 없으면 null.
  Lease? releaseMac(MacAddress mac) {
    final lease = _byMac[mac];
    if (lease != null) _remove(lease);
    return lease;
  }

  Lease? releaseIp(Ipv4 ip) {
    final lease = _byIp[ip];
    if (lease != null) _remove(lease);
    return lease;
  }

  /// 모든 Lease를 해제하고 해제한 목록을 돌려준다. 예약은 그대로 둔다.
  List<Lease> releaseAll() {
    final released = leases;
    _byMac.clear();
    _byIp.clear();
    return released;
  }

  /// DECLINE: 클라이언트가 그 주소가 이미 쓰인다고 알려 왔다. 한동안 나눠 주지 않는다.
  void decline(Ipv4 ip) {
    final lease = _byIp[ip];
    if (lease != null) _remove(lease);
    _declined[ip] = now.add(declineQuarantine);
  }

  /// 만료된 Lease를 지우고 돌려준다. 제안 보류가 끝난 것도 포함한다.
  List<Lease> expire() {
    final t = now;
    final gone = _byMac.values.where((l) => l.isExpired(t)).toList();
    for (final lease in gone) {
      _remove(lease);
    }
    _declined.removeWhere((_, until) => !t.isBefore(until));
    return gone;
  }

  // ---- 내부 ----------------------------------------------------------------------------------

  /// [mac]이 [ip]를 받을 수 있는가: 범위 안, 제외 아님, 격리 중 아님, 다른 MAC의 Lease·예약이 아님.
  bool _isFree(Ipv4 ip, MacAddress mac) {
    if (!_inRange(ip) || excluded.contains(ip) || _declined.containsKey(ip)) return false;
    final holder = _byIp[ip];
    if (holder != null && holder.mac != mac) return false;
    for (final MapEntry(key: other, value: reserved) in _reservations.entries) {
      if (reserved == ip && other != mac) return false;
    }
    return true;
  }

  Ipv4? _firstFree(MacAddress mac) {
    for (var v = start.value; v <= end.value; v++) {
      final ip = Ipv4(v);
      if (_isFree(ip, mac)) return ip;
    }
    return null;
  }

  Lease _put(Lease lease) {
    _byMac[lease.mac] = lease;
    _byIp[lease.ip] = lease;
    return lease;
  }

  void _remove(Lease lease) {
    _byMac.remove(lease.mac);
    _byIp.remove(lease.ip);
  }
}
