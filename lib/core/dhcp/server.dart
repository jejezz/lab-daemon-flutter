// DHCP 서버: 전송 계층에서 패킷을 받아 [DhcpEngine]에 넘기고 응답을 보낸다. 상태·로그·이벤트는
// [BaseNetService]가 맡고, 이 클래스는 소켓 수명과 Lease 만료 타이머, 화면용 스냅샷을 다룬다.
//
// 성능: 패킷마다 하는 일은 엔진 호출과 응답 전송, 그리고 "표가 바뀜" 표시뿐이다. Lease 표와 통계의
// 스냅샷은 [BaseNetService.scheduleSnapshot]이 일정 간격에 한 번만 만든다.

import 'dart:async';
import 'dart:typed_data';

import '../host.dart';
import '../ipv4.dart';
import '../lease_time.dart';
import '../service.dart';
import 'config.dart';
import 'engine.dart';
import 'packet.dart';
import 'pool.dart';
import 'transport.dart';

/// 화면에 보여 줄 Lease 한 줄 (복사본이라 서버 상태가 바뀌어도 변하지 않는다).
class LeaseInfo {
  const LeaseInfo({
    required this.ip,
    required this.mac,
    required this.hostname,
    required this.state,
    required this.grantedAt,
    required this.expiresAt,
  });

  factory LeaseInfo.of(Lease lease) => LeaseInfo(
        ip: lease.ip,
        mac: lease.mac,
        hostname: lease.hostname,
        state: lease.state,
        grantedAt: lease.grantedAt,
        expiresAt: lease.expiresAt,
      );

  final Ipv4 ip;
  final MacAddress mac;
  final String? hostname;
  final LeaseState state;
  final DateTime grantedAt;

  /// null이면 무제한.
  final DateTime? expiresAt;
}

/// Lease 표가 바뀌면 전체 스냅샷을 내보낸다 (표는 작아서 차분보다 단순하다).
final class DhcpLeasesEvent extends ServiceEvent {
  DhcpLeasesEvent(super.service, this.leases, {required this.capacity, super.time});

  final List<LeaseInfo> leases;

  /// 풀이 나눠 줄 수 있는 주소 수.
  final int capacity;

  int get boundCount => leases.where((l) => l.state == LeaseState.bound).length;
}

final class DhcpStatsEvent extends ServiceEvent {
  DhcpStatsEvent(super.service, this.counts, {super.time});

  final Map<String, int> counts;
}

/// 서비스 Isolate에서 DHCP 서버를 만드는 최상위 함수 ([IsolateHost]에 넘긴다).
NetService<ServiceConfig> createDhcpService() => DhcpServer();

class DhcpServer extends BaseNetService<DhcpConfig> {
  DhcpServer({DhcpTransportFactory? transportFactory, this.clock, super.snapshotInterval})
      : _transportFactory = transportFactory ?? UdpDhcpTransport.bind,
        super('dhcp');

  final DhcpTransportFactory _transportFactory;

  /// 테스트에서 시간을 주입한다. null이면 실제 시계.
  final DateTime Function()? clock;

  DhcpConfig? _config;
  LeasePool? _pool;
  DhcpEngine? _engine;
  DhcpTransport? _transport;
  StreamSubscription<DhcpDatagram>? _subscription;
  Timer? _timer;
  int _publishedVersion = -1;

  /// 실행 중인 설정 (멈췄으면 null).
  DhcpConfig? get config => _config;

  LeasePool? get pool => _pool;

  DhcpStats get stats => _engine?.stats ?? DhcpStats();

  @override
  DhcpConfig decodeConfig(Map<String, Object?> json) => DhcpConfig.fromJson(json);

  @override
  Future<void> onStart(DhcpConfig config) async {
    config.validate();
    final pool = config.createPool(clock: clock);
    final engine = DhcpEngine(config, pool, _engineLog);
    try {
      _transport = await _transportFactory(config.bindTo, config.serverPort);
    } catch (e) {
      log(LogLevel.error, isAddressInUse(e) ? 'logDhcpPortInUse' : (isPermissionDenied(e) ? 'logDhcpPermissionDenied' : 'logDhcpBindFailed'),
          args: {'address': '${config.bindTo}', 'port': config.serverPort, 'error': '$e'});
      rethrow;
    }
    _config = config;
    _pool = pool;
    _engine = engine;
    _publishedVersion = -1;
    _subscription = _transport!.incoming.listen(_onDatagram);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => expireNow());
    log(LogLevel.info, 'logDhcpStarted', args: {
      'address': '${config.bindTo}',
      'start': '${config.rangeStart}',
      'end': '${config.rangeEnd}',
      'mask': '${config.mask}',
    });
    _publishLeases();
    _publishStats();
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    final hadTransport = _transport != null;
    await _transport?.close();
    _transport = null;
    _engine = null;
    _pool = null;
    _config = null;
    if (hadTransport) log(LogLevel.info, 'logDhcpStopped');
  }

  @override
  Future<Object?> handleCommand(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'releaseIp':
        return releaseIp(Ipv4.parse(args['ip']! as String)) != null;
      case 'releaseMac':
        return releaseMac(MacAddress.parse(args['mac']! as String)) != null;
      case 'releaseAll':
        return releaseAll();
      case 'setLeaseTime':
        final text = args['leaseTime'] as String?;
        setLeaseTime(text == null ? null : parseLeaseTime(text));
        return null;
      case 'reserve':
        reserve(MacAddress.parse(args['mac']! as String), Ipv4.parse(args['ip']! as String));
        return null;
      case 'unreserve':
        unreserve(MacAddress.parse(args['mac']! as String));
        return null;
    }
    return super.handleCommand(name, args);
  }

  // ---- 조작 -------------------------------------------------------------------------------------

  /// 만료된 Lease를 지운다. 1초마다 불리고, 테스트에서는 직접 부른다.
  void expireNow() {
    final pool = _pool;
    if (pool == null) return;
    final gone = pool.expire();
    for (final lease in gone) {
      // 제안(offered)이 시간 초과로 사라진 것은 Lease가 아니라서 조용히 둔다.
      if (lease.state == LeaseState.bound) {
        log(LogLevel.info, 'logDhcpExpired', kind: 'EXPIRE', args: {'mac': '${lease.mac}', 'ip': '${lease.ip}'});
      }
    }
    _publishLeases();
  }

  Lease? releaseIp(Ipv4 ip) => _release(_requirePool().releaseIp(ip));

  Lease? releaseMac(MacAddress mac) => _release(_requirePool().releaseMac(mac));

  /// 모든 Lease를 해제하고 해제한 수를 돌려준다. 예약은 유지한다.
  int releaseAll() {
    final released = _requirePool().releaseAll();
    for (final lease in released) {
      log(LogLevel.info, 'logDhcpManualRelease', kind: 'RELEASE', args: {'mac': '${lease.mac}', 'ip': '${lease.ip}'});
    }
    _publishLeases();
    return released.length;
  }

  void reserve(MacAddress mac, Ipv4 ip) {
    _requirePool().reserve(mac, ip);
    log(LogLevel.info, 'logDhcpReserved', args: {'mac': '$mac', 'ip': '$ip'});
  }

  void unreserve(MacAddress mac) {
    _requirePool().unreserve(mac);
    log(LogLevel.info, 'logDhcpUnreserved', args: {'mac': '$mac'});
  }

  /// 실행 중에 새 Lease Time을 적용한다. 이미 받은 Lease는 갱신될 때부터 새 값을 따른다.
  void setLeaseTime(Duration? time) {
    _requirePool().leaseTime = time;
  }

  // ---- 내부 ----------------------------------------------------------------------------------

  LeasePool _requirePool() => _pool ?? (throw StateError('DHCP server is not running'));

  Lease? _release(Lease? lease) {
    if (lease != null) {
      log(LogLevel.info, 'logDhcpManualRelease', kind: 'RELEASE', args: {'mac': '${lease.mac}', 'ip': '${lease.ip}'});
      _publishLeases();
    }
    return lease;
  }

  void _engineLog(LogLevel level, String key, {String? kind, Map<String, Object?> args = const {}, String? detail}) =>
      log(level, key, kind: kind, args: args, detail: detail);

  void _onDatagram(DhcpDatagram datagram) {
    final engine = _engine;
    final transport = _transport;
    if (engine == null || transport == null) return;
    final DhcpPacket request;
    try {
      request = DhcpPacket.parse(datagram.data);
    } on DhcpFormatException catch (e) {
      log(LogLevel.warning, 'logDhcpMalformed', args: {'from': '${datagram.from}', 'error': e.message});
      return;
    }
    final logPackets = _config?.logPackets ?? false;
    if (logPackets) {
      log(LogLevel.debug, 'logDhcpPacketIn', kind: DhcpMessageType.name(request.messageType),
          args: {'from': '${datagram.from}'}, detail: DhcpPacket.hexDump(datagram.data));
    }
    final reply = engine.handle(request);
    if (reply != null) {
      final Uint8List bytes = reply.packet.toBytes();
      try {
        transport.send(bytes, reply.address, reply.port);
        if (logPackets) {
          log(LogLevel.debug, 'logDhcpPacketOut', kind: DhcpMessageType.name(reply.packet.messageType),
              args: {'to': '${reply.address}', 'port': reply.port}, detail: DhcpPacket.hexDump(bytes));
        }
      } catch (e) {
        log(LogLevel.error, 'logDhcpSendFailed', args: {'to': '${reply.address}', 'error': '$e'});
      }
    }
    _publishLeases();
    _publishStats();
  }

  /// 풀이 바뀌었을 때만 스냅샷을 예약한다 (표 크기와 무관한 O(1) 비교).
  void _publishLeases() {
    final pool = _pool;
    if (pool == null || pool.version == _publishedVersion) return;
    _publishedVersion = pool.version;
    scheduleSnapshot('leases', () {
      final p = _pool;
      return DhcpLeasesEvent(id, [if (p != null) for (final l in p.leases) LeaseInfo.of(l)], capacity: p?.capacity ?? 0);
    });
  }

  void _publishStats() {
    scheduleSnapshot('stats', () => DhcpStatsEvent(id, _engine?.stats.toMap() ?? const {}));
  }
}
