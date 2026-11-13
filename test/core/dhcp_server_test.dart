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

DhcpConfig _config({bool logPackets = false, String? leaseFile, bool conflictCheck = false}) => DhcpConfig(
      serverIp: ip('192.168.50.1'),
      rangeStart: ip('192.168.50.100'),
      rangeEnd: ip('192.168.50.110'),
      mask: ip('255.255.255.0'),
      gateway: ip('192.168.50.1'),
      leaseTime: const Duration(minutes: 10),
      logPackets: logPackets,
      leaseFile: leaseFile,
      conflictCheck: conflictCheck,
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

  group('주소 충돌 검사 (ping)', () {
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

    /// [inUse]에 있는 주소는 응답이 있는 것으로 보는 서버. 확인한 주소를 [probed]에 모은다.
    Future<(DhcpServer, _FakeTransport, LogBus, List<Ipv4>)> make(Set<String> inUse) async {
      final t = _FakeTransport();
      final b = LogBus();
      final probed = <Ipv4>[];
      final s = DhcpServer(
        clock: () => now,
        transportFactory: (a, p) async => t,
        prober: (address) async {
          probed.add(address);
          return inUse.contains('$address');
        },
        snapshotInterval: Duration.zero,
      );
      s.events.listen((e) {
        if (e is LogEvent) b.add(e);
      });
      await s.start(_config(conflictCheck: true));
      addTearDown(() async {
        await s.dispose();
        await b.dispose();
      });
      return (s, t, b, probed);
    }

    test('응답이 없는 주소는 그대로 제안한다', () async {
      final (_, t, _, probed) = await make({});
      t.receive(_client(DhcpMessageType.discover, mac(1)));
      await settle();
      expect(t.sent.single.packet.messageType, DhcpMessageType.offer);
      expect(t.sent.single.packet.yiaddr, ip('192.168.50.100'));
      expect(probed, [ip('192.168.50.100')]);
    });

    test('응답이 있는 주소는 건너뛰고 다음 주소를 제안하며, 로그에 남긴다', () async {
      final (s, t, b, probed) = await make({'192.168.50.100', '192.168.50.101'});
      t.receive(_client(DhcpMessageType.discover, mac(1)));
      await settle();
      expect(t.sent.single.packet.yiaddr, ip('192.168.50.102'));
      expect(probed.map((i) => '$i'), ['192.168.50.100', '192.168.50.101', '192.168.50.102']);
      final conflicts = b.history.where((e) => e.key == 'logDhcpConflict').toList();
      expect(conflicts.map((e) => e.args['ip']), ['192.168.50.100', '192.168.50.101']);
      expect(conflicts.first.args['mac'], '${mac(1)}');
      expect(s.pool!.leaseOfMac(mac(1))!.ip, ip('192.168.50.102'));
    });

    test('이미 Lease가 있는 장비가 다시 DISCOVER해도 다시 확인하지 않는다', () async {
      final (_, t, _, probed) = await make({});
      t.receive(_client(DhcpMessageType.discover, mac(1)));
      await settle();
      t.receive(_client(DhcpMessageType.discover, mac(1)));
      await settle();
      expect(t.sent, hasLength(2));
      expect(probed, hasLength(1));
    });

    test('줄 주소가 모두 쓰이는 중이면 제안하지 않고 로그를 남긴다', () async {
      final all = {for (var i = 100; i <= 110; i++) '192.168.50.$i'};
      final (_, t, b, _) = await make(all);
      t.receive(_client(DhcpMessageType.discover, mac(1)));
      await settle();
      expect(t.sent, isEmpty);
      expect(b.history.map((e) => e.key), contains('logDhcpPoolExhausted'));
    });

    test('확인이 꺼져 있으면 바로(동기로) 제안한다', () async {
      await server.start(_config());
      transport.receive(_client(DhcpMessageType.discover, mac(1)));
      expect(transport.sent.single.packet.messageType, DhcpMessageType.offer);
    });
  });

  group('Lease 영속화', () {
    late Directory dir;
    late String file;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('lease_test_');
      file = '${dir.path}${Platform.pathSeparator}leases.json';
    });

    tearDown(() => dir.deleteSync(recursive: true));

    /// 같은 파일을 쓰는 새 서버 (껐다 켠 것)를 만든다.
    Future<(DhcpServer, _FakeTransport, LogBus)> restart({Duration later = Duration.zero}) async {
      final t = _FakeTransport();
      final b = LogBus();
      final s = _make(b, clock: () => now.add(later), transportFactory: (a, p) async => t);
      await s.start(_config(leaseFile: file));
      return (s, t, b);
    }

    test('멈추면 확정된 Lease가 파일에 저장되고, 다시 켜면 같은 주소가 이어진다', () async {
      await server.start(_config(leaseFile: file));
      await dora(mac(1));
      await dora(mac(2));
      final first = server.pool!.leaseOfMac(mac(1))!.ip;
      final second = server.pool!.leaseOfMac(mac(2))!.ip;
      await server.stop();
      expect(File(file).existsSync(), isTrue);

      final (s2, t2, b2) = await restart();
      addTearDown(() async {
        await s2.dispose();
        await b2.dispose();
      });
      expect(s2.pool!.leaseOfMac(mac(1))!.ip, first);
      expect(s2.pool!.leaseOfMac(mac(1))!.state, LeaseState.bound);
      expect(s2.pool!.leaseOfMac(mac(2))!.ip, second);
      final loaded = b2.history.firstWhere((e) => e.key == 'logDhcpLeasesLoaded');
      expect(loaded.args, {'count': 2, 'skipped': 0});

      // 되살린 Lease의 클라이언트가 다시 REQUEST하면 같은 주소로 ACK
      t2.receive(_client(DhcpMessageType.request, mac(1), options: {DhcpOpt.requestedIp: DhcpValue.ip(first)}));
      expect(t2.sent.last.packet.messageType, DhcpMessageType.ack);
      expect(t2.sent.last.packet.yiaddr, first);
    });

    test('다시 켰을 때 이미 만료된 Lease는 버린다', () async {
      await server.start(_config(leaseFile: file));
      await dora(mac(1));
      await server.stop();

      final (s2, t2, b2) = await restart(later: const Duration(minutes: 30)); // Lease Time 10분
      addTearDown(() async {
        await s2.dispose();
        await b2.dispose();
      });
      expect(s2.pool!.leases, isEmpty);
      expect(b2.history.firstWhere((e) => e.key == 'logDhcpLeasesLoaded').args, {'count': 0, 'skipped': 1});
      expect(t2.sent, isEmpty);
    });

    test('파일이 깨졌으면 경고만 남기고 빈 표로 시작한다', () async {
      File(file).writeAsStringSync('이건 JSON이 아니에요');
      final (s2, _, b2) = await restart();
      addTearDown(() async {
        await s2.dispose();
        await b2.dispose();
      });
      expect(s2.state, ServiceState.running);
      expect(s2.pool!.leases, isEmpty);
      expect(b2.history.map((e) => e.key), contains('logDhcpLeaseFileFailed'));
    });

    test('leaseFile이 없으면 파일을 만들지 않는다', () async {
      await server.start(_config());
      await dora(mac(1));
      await server.stop();
      expect(dir.listSync(), isEmpty);
    });

    test('저장하는 중에 꺼져도 예전 파일이 온전하다 (임시 파일 뒤 이름 바꾸기)', () async {
      await server.start(_config(leaseFile: file));
      await dora(mac(1));
      await server.stop();
      expect(File('$file.tmp').existsSync(), isFalse, reason: '임시 파일은 이름을 바꾸고 나서 남지 않는다');
    });
  });

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
