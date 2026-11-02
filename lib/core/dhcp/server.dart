// DHCP 서버: 전송 계층에서 패킷을 받아 [DhcpEngine]에 넘기고 응답을 보낸다. 상태·로그·이벤트는
// [BaseNetService]가 맡고, 이 클래스는 소켓 수명과 Lease 만료 타이머, 화면용 이벤트를 다룬다.

import 'dart:async';
import 'dart:typed_data';

import '../ipv4.dart';
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

/// Lease 표가 바뀔 때마다 전체 스냅샷을 내보낸다 (표는 작아서 차분보다 단순하다).
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

class DhcpServer extends BaseNetService<DhcpConfig> {
  DhcpServer(LogBus bus, {DhcpTransportFactory? transportFactory, this.clock})
      : _transportFactory = transportFactory ?? UdpDhcpTransport.bind,
        super('dhcp', bus);

  final DhcpTransportFactory _transportFactory;
  /// 테스트에서 시간을 주입한다. null이면 실제 시계.
  final DateTime Function()? clock;

  DhcpConfig? _config;
  LeasePool? _pool;
  DhcpEngine? _engine;
  DhcpTransport? _transport;
  StreamSubscription<DhcpDatagram>? _subscription;
  Timer? _timer;

  /// 실행 중인 설정 (멈췄으면 null). 화면은 편집 중인 값이 아니라 이것을 보여 준다.
  DhcpConfig? get config => _config;

  LeasePool? get pool => _pool;
  DhcpStats get stats => _engine?.stats ?? DhcpStats();

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
    _subscription = _transport!.incoming.listen(_onDatagram);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => expireNow());
    log(LogLevel.info, 'logDhcpStarted', args: {
      'address': '${config.bindTo}',
      'start': '${config.rangeStart}',
      'end': '${config.rangeEnd}',
      'mask': '${config.mask}',
    });
    _emitLeases();
    _emitStats();
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

  // ---- 화면에서 부르는 조작 -----------------------------------------------------------------------

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
    if (gone.isNotEmpty) _emitLeases();
  }

  Lease? releaseIp(Ipv4 ip) => _release(_requirePool().releaseIp(ip));

  Lease? releaseMac(MacAddress mac) => _release(_requirePool().releaseMac(mac));

  /// 모든 Lease를 해제하고 해제한 수를 돌려준다. 예약은 유지한다.
  int releaseAll() {
    final released = _requirePool().releaseAll();
    for (final lease in released) {
      log(LogLevel.info, 'logDhcpManualRelease', kind: 'RELEASE', args: {'mac': '${lease.mac}', 'ip': '${lease.ip}'});
    }
    _emitLeases();
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
      _emitLeases();
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
    if (_config?.logPackets ?? false) {
      log(LogLevel.debug, 'logDhcpPacketIn', kind: DhcpMessageType.name(request.messageType),
          args: {'from': '${datagram.from}'}, detail: DhcpPacket.hexDump(datagram.data));
    }
    final before = _snapshotKey();
    final reply = engine.handle(request);
    if (reply != null) {
      final Uint8List bytes = reply.packet.toBytes();
      try {
        transport.send(bytes, reply.address, reply.port);
        if (_config?.logPackets ?? false) {
          log(LogLevel.debug, 'logDhcpPacketOut', kind: DhcpMessageType.name(reply.packet.messageType),
              args: {'to': '${reply.address}', 'port': reply.port}, detail: DhcpPacket.hexDump(bytes));
        }
      } catch (e) {
        log(LogLevel.error, 'logDhcpSendFailed', args: {'to': '${reply.address}', 'error': '$e'});
      }
    }
    if (_snapshotKey() != before) _emitLeases();
    _emitStats();
  }

  /// Lease 표가 바뀌었는지 싸게 알아내는 지문.
  String _snapshotKey() => _pool!.leases.map((l) => '${l.ip}/${l.mac}/${l.state.name}/${l.expiresAt?.millisecondsSinceEpoch}').join(',');

  void _emitLeases() {
    final pool = _pool;
    if (pool == null) return;
    emit(DhcpLeasesEvent(id, [for (final l in pool.leases) LeaseInfo.of(l)], capacity: pool.capacity));
  }

  void _emitStats() {
    final engine = _engine;
    if (engine != null) emit(DhcpStatsEvent(id, engine.stats.toMap()));
  }
}
