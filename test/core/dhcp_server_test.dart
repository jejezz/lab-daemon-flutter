import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/config.dart';
import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/dhcp/pool.dart';
import 'package:lab_daemon/core/dhcp/server.dart';
import 'package:lab_daemon/core/dhcp/transport.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/netutil.dart';
import 'package:lab_daemon/core/service.dart';

Ipv4 ip(String s) => Ipv4.parse(s);
MacAddress mac(int n) => MacAddress([0xaa, 0xbb, 0xcc, 0, 0, n]);

class _SentPacket {
  _SentPacket(this.bytes, this.address, this.port);

  final Uint8List bytes;
  final Ipv4 address;
  final int port;

  DhcpPacket get packet => DhcpPacket.parse(bytes);
}

class _FakeTransport implements DhcpTransport {
  final _incoming = StreamController<DhcpDatagram>.broadcast(sync: true);
  final sent = <_SentPacket>[];
  bool closed = false;
  Object? failSendWith;

  @override
  Stream<DhcpDatagram> get incoming => _incoming.stream;

  @override
  int get port => 67;

  void receive(DhcpPacket p) => _incoming.add(DhcpDatagram(p.toBytes(), Ipv4.any, 68));

  void receiveRaw(Uint8List bytes) => _incoming.add(DhcpDatagram(bytes, ip('192.168.50.9'), 68));

  @override
  void send(Uint8List data, Ipv4 address, int port) {
    if (failSendWith != null) throw failSendWith!;
    sent.add(_SentPacket(data, address, port));
  }

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}

DhcpPacket _client(int type, MacAddress m, {Map<int, Uint8List> options = const {}}) => DhcpPacket(
      op: DhcpOp.request,
      xid: 7,
      chaddr: Uint8List.fromList(m.bytes),
      options: {DhcpOpt.messageType: DhcpValue.u8(type), ...options},
    );

DhcpConfig _config({bool logPackets = false}) => DhcpConfig(
      serverIp: ip('192.168.50.1'),
      rangeStart: ip('192.168.50.100'),
      rangeEnd: ip('192.168.50.110'),
      mask: ip('255.255.255.0'),
      gateway: ip('192.168.50.1'),
      leaseTime: const Duration(minutes: 10),
      logPackets: logPackets,
    );

/// 서비스가 내는 로그를 [bus]에 모은다 (실제 앱에서는 화면 쪽 호스트가 하는 일).
DhcpServer _make(LogBus bus, {DateTime Function()? clock, DhcpTransportFactory? transportFactory}) {
  final server = DhcpServer(clock: clock, transportFactory: transportFactory, snapshotInterval: Duration.zero);
  server.events.listen((e) {
    if (e is LogEvent) bus.add(e);
  });
  return server;
}

void main() {
  late LogBus bus;
  late _FakeTransport transport;
  late DhcpServer server;
  late DateTime now;
  Ipv4? boundAddress;
  int? boundPort;

  setUp(() {
    bus = LogBus();
    transport = _FakeTransport();
    now = DateTime.utc(2026, 11, 2, 12);
    boundAddress = null;
    boundPort = null;
    server = _make(bus, clock: () => now, transportFactory: (address, port) async {
      boundAddress = address;
      boundPort = port;
      return transport;
    });
  });

  tearDown(() async {
    await server.dispose();
    await bus.dispose();
  });

  Future<void> dora(MacAddress m) async {
    transport.receive(_client(DhcpMessageType.discover, m));
    final offered = transport.sent.last.packet.yiaddr;
    transport.receive(_client(DhcpMessageType.request, m, options: {
      DhcpOpt.requestedIp: DhcpValue.ip(offered),
      DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.1')),
    }));
  }

  test('서버 주소와 포트에 묶고 시작 로그를 남긴다', () async {
    await server.start(_config());
    expect(server.state, ServiceState.running);
    expect(boundAddress, ip('192.168.50.1'));
    expect(boundPort, 67);
    expect(bus.history.map((e) => e.key), contains('logDhcpStarted'));
  });

  test('DISCOVER → OFFER, REQUEST → ACK를 전송 계층으로 주고받는다', () async {
    await server.start(_config());
    await dora(mac(1));

    expect(transport.sent, hasLength(2));
    expect(transport.sent[0].packet.messageType, DhcpMessageType.offer);
    expect(transport.sent[1].packet.messageType, DhcpMessageType.ack);
    expect(transport.sent[1].address, Ipv4.broadcast);
    expect(transport.sent[1].port, 68);
    expect(transport.sent[1].bytes.length, greaterThanOrEqualTo(300));
    expect(server.pool!.leaseOfMac(mac(1))!.state, LeaseState.bound);
  });

  test('Lease 표와 통계가 바뀔 때 이벤트를 내보낸다', () async {
    final leases = <DhcpLeasesEvent>[];
    final stats = <DhcpStatsEvent>[];
    server.events.listen((e) {
      if (e is DhcpLeasesEvent) leases.add(e);
      if (e is DhcpStatsEvent) stats.add(e);
    });
    await server.start(_config());
    expect(leases.single.leases, isEmpty, reason: '시작 직후 빈 표');
    expect(leases.single.capacity, 11, reason: '100~110은 11개이고, 서버·게이트웨이(.1)는 범위 밖이라 빠지지 않는다');

    await dora(mac(1));
    expect(leases.last.leases.single.mac, mac(1));
    expect(leases.last.boundCount, 1);
    expect(stats.last.counts, containsPair('discover', 1));
    expect(stats.last.counts, containsPair('ack', 1));
  });

  test('손상된 패킷은 로그만 남기고 서버는 계속 돈다', () async {
    await server.start(_config());
    transport.receiveRaw(Uint8List(50));
    expect(bus.history.map((e) => e.key), contains('logDhcpMalformed'));
    expect(server.state, ServiceState.running);
    await dora(mac(1));
    expect(transport.sent, hasLength(2));
  });

  test('전송이 실패해도 서버는 계속 돌고 오류를 기록한다', () async {
    await server.start(_config());
    transport.failSendWith = const SocketException('network unreachable');
    transport.receive(_client(DhcpMessageType.discover, mac(1)));
    expect(bus.history.last.key, anyOf('logDhcpSendFailed', 'logDhcpOffer'));
    expect(bus.history.map((e) => e.key), contains('logDhcpSendFailed'));
    expect(server.state, ServiceState.running);
  });

  test('패킷 로깅을 켜면 16진수 덤프를 DEBUG로 남긴다', () async {
    await server.start(_config(logPackets: true));
    transport.receive(_client(DhcpMessageType.discover, mac(1)));
    final packetLogs = bus.history.where((e) => e.key == 'logDhcpPacketIn' || e.key == 'logDhcpPacketOut').toList();
    expect(packetLogs.map((e) => e.key), ['logDhcpPacketIn', 'logDhcpPacketOut']);
    expect(packetLogs.every((e) => e.level == LogLevel.debug && (e.detail ?? '').isNotEmpty), isTrue);
    expect(packetLogs.first.kind, 'DISCOVER');
  });

  group('Lease 조작', () {
    test('개별 해제는 표를 갱신하고 같은 주소를 다시 쓸 수 있다', () async {
      await server.start(_config());
      await dora(mac(1));
      final released = server.releaseIp(ip('192.168.50.100'));
      expect(released!.mac, mac(1));
      expect(server.pool!.leases, isEmpty);
      expect(bus.history.map((e) => e.key), contains('logDhcpManualRelease'));
      await dora(mac(2));
      expect(server.pool!.leaseOfMac(mac(2))!.ip, ip('192.168.50.100'));
    });

    test('전체 해제는 해제한 수를 돌려주고 예약은 남긴다', () async {
      await server.start(_config());
      server.reserve(mac(9), ip('192.168.50.50'));
      await dora(mac(1));
      await dora(mac(2));
      expect(server.releaseAll(), 2);
      expect(server.pool!.leases, isEmpty);
      expect(server.pool!.reservations, hasLength(1));
    });

    test('만료는 expireNow가 정리하고 bound Lease만 로그에 남긴다', () async {
      await server.start(_config());
      await dora(mac(1));
      transport.receive(_client(DhcpMessageType.discover, mac(2))); // 제안만 한 상태
      now = now.add(const Duration(minutes: 11));
      server.expireNow();
      expect(server.pool!.leases, isEmpty);
      final expired = bus.history.where((e) => e.key == 'logDhcpExpired').toList();
      expect(expired, hasLength(1));
      expect(expired.single.args['mac'], '${mac(1)}');
    });

    test('실행 중이 아니면 조작은 StateError', () async {
      expect(() => server.releaseAll(), throwsStateError);
      expect(() => server.reserve(mac(1), ip('192.168.50.50')), throwsStateError);
    });

    test('실행 중 Lease Time을 바꾸면 다음 확정부터 적용된다', () async {
      await server.start(_config());
      await dora(mac(1));
      server.setLeaseTime(const Duration(minutes: 1));
      await dora(mac(2));
      final first = server.pool!.leaseOfMac(mac(1))!.expiresAt!;
      final second = server.pool!.leaseOfMac(mac(2))!.expiresAt!;
      expect(first, now.add(const Duration(minutes: 10)));
      expect(second, now.add(const Duration(minutes: 1)));
    });
  });

  group('시작과 중지', () {
    test('잘못된 설정은 바인딩 전에 거부하고 error 상태가 된다', () async {
      final bad = DhcpConfig(
        serverIp: ip('10.0.0.1'),
        rangeStart: ip('192.168.50.100'),
        rangeEnd: ip('192.168.50.110'),
        mask: ip('255.255.255.0'),
      );
      await expectLater(server.start(bad), throwsA(isA<PoolConfigException>()));
      expect(server.state, ServiceState.error);
      expect(boundAddress, isNull, reason: '소켓을 열지 않았다');
    });

    test('바인딩이 실패하면 원인을 로그로 남기고 error가 된다', () async {
      final failing = _make(bus, transportFactory: (a, p) async => throw const SocketException('in use', osError: OSError('in use', 10048)));
      await expectLater(failing.start(_config()), throwsA(isA<SocketException>()));
      expect(failing.state, ServiceState.error);
      expect(bus.history.map((e) => e.key), contains('logDhcpPortInUse'));
      await failing.dispose();
    });

    test('중지하면 전송 계층을 닫고 Lease를 비운다. 다시 시작하면 새 풀이다', () async {
      await server.start(_config());
      await dora(mac(1));
      await server.stop();
      expect(transport.closed, isTrue);
      expect(server.pool, isNull);
      expect(bus.history.map((e) => e.key), contains('logDhcpStopped'));

      transport = _FakeTransport();
      await server.start(_config());
      expect(server.pool!.leases, isEmpty);
    });
  });

  group('주소 오류 판별', () {
    test('OS 오류 코드로 포트 사용 중·권한 거부를 가른다', () {
      expect(isAddressInUse(const SocketException('x', osError: OSError('x', 10048))), isTrue);
      expect(isAddressInUse(const SocketException('x', osError: OSError('x', 98))), isTrue);
      expect(isAddressInUse(const SocketException('x', osError: OSError('x', 10013))), isFalse);
      expect(isPermissionDenied(const SocketException('x', osError: OSError('x', 10013))), isTrue);
      expect(isAddressInUse(StateError('x')), isFalse);
    });
  });

  group('실제 UDP (loopback)', () {
    test('바인딩하고 받고 보낼 수 있다', () async {
      final udp = await UdpDhcpTransport.bind(ip('127.0.0.1'), 0);
      addTearDown(udp.close);
      expect(udp.port, greaterThan(0));

      final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(client.close);

      final received = udp.incoming.first;
      client.send([1, 2, 3], InternetAddress.loopbackIPv4, udp.port);
      final datagram = await received.timeout(const Duration(seconds: 5));
      expect(datagram.data, [1, 2, 3]);
      expect(datagram.from, ip('127.0.0.1'));

      final echo = Completer<List<int>>();
      client.listen((e) {
        if (e == RawSocketEvent.read) echo.complete(client.receive()!.data);
      });
      udp.send(Uint8List.fromList([9, 8, 7]), ip('127.0.0.1'), client.port);
      expect(await echo.future.timeout(const Duration(seconds: 5)), [9, 8, 7]);
    });

    test('같은 포트를 두 번 묶으면 포트 사용 중으로 판별된다', () async {
      final first = await UdpDhcpTransport.bind(ip('127.0.0.1'), 0);
      addTearDown(first.close);
      Object? error;
      try {
        await UdpDhcpTransport.bind(ip('127.0.0.1'), first.port);
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(isAddressInUse(error!), isTrue, reason: '$error');
    });

    test('실제 소켓으로 서버가 시작하고 멈춘다', () async {
      final real = _make(bus);
      addTearDown(real.dispose);
      final config = DhcpConfig(
        serverIp: ip('127.0.0.1'),
        rangeStart: ip('127.0.0.10'),
        rangeEnd: ip('127.0.0.20'),
        mask: ip('255.0.0.0'),
        serverPort: 0,
      );
      await real.start(config);
      expect(real.state, ServiceState.running);
      await real.stop();
    });
  });

  test('NIC 목록은 링크 로컬과 루프백을 뺀 IPv4만 담는다', () async {
    final nics = await listNics();
    for (final nic in nics) {
      expect(nic.address.value >> 24, isNot(127));
      expect(nic.address.value >> 16, isNot(0xA9FE));
      expect(nic.name, isNotEmpty);
    }
  });
}
