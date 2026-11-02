import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/config.dart';
import 'package:lab_daemon/core/dhcp/engine.dart';
import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/dhcp/pool.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/service.dart';

Ipv4 ip(String s) => Ipv4.parse(s);
MacAddress mac(int n) => MacAddress([0xaa, 0xbb, 0xcc, 0, 0, n]);

DhcpPacket client(int type, MacAddress m, {Ipv4? ciaddr, Ipv4? giaddr, int flags = 0, Map<int, Uint8List> options = const {}}) {
  final chaddr = Uint8List(16)..setRange(0, 6, m.bytes);
  return DhcpPacket(
    op: DhcpOp.request,
    xid: 0x1234,
    flags: flags,
    ciaddr: ciaddr ?? Ipv4.any,
    giaddr: giaddr ?? Ipv4.any,
    chaddr: chaddr,
    options: {DhcpOpt.messageType: DhcpValue.u8(type), ...options},
  );
}

DhcpConfig _config({Duration? leaseTime = const Duration(hours: 1), bool directed = false, String? tftp, String? boot}) => DhcpConfig(
      serverIp: ip('192.168.50.1'),
      rangeStart: ip('192.168.50.100'),
      rangeEnd: ip('192.168.50.102'),
      mask: ip('255.255.255.0'),
      gateway: ip('192.168.50.1'),
      dnsServers: [ip('8.8.8.8'), ip('8.8.4.4')],
      domainName: 'lab.local',
      leaseTime: leaseTime,
      tftpServer: tftp,
      bootFile: boot,
      directedBroadcast: directed,
    );

class _Harness {
  _Harness(this.config) {
    pool = config.createPool(clock: () => now);
    engine = DhcpEngine(config, pool, (level, key, {kind, args = const {}, detail}) => logs.add(key));
  }

  final DhcpConfig config;
  late final LeasePool pool;
  late final DhcpEngine engine;
  final logs = <String>[];
  DateTime now = DateTime.utc(2026, 11, 2, 12);

  /// DISCOVER → OFFER → REQUEST → ACK 한 바퀴.
  DhcpReply dora(MacAddress m, {Map<int, Uint8List> discoverOptions = const {}}) {
    final offer = engine.handle(client(DhcpMessageType.discover, m, options: discoverOptions))!;
    return engine.handle(client(DhcpMessageType.request, m, options: {
      DhcpOpt.requestedIp: DhcpValue.ip(offer.packet.yiaddr),
      DhcpOpt.serverId: DhcpValue.ip(config.serverIp),
    }))!;
  }
}

void main() {
  group('DORA', () {
    test('DISCOVER에 OFFER를 브로드캐스트로 보낸다', () {
      final h = _Harness(_config());
      final reply = h.engine.handle(client(DhcpMessageType.discover, mac(1), options: {
        DhcpOpt.hostname: DhcpValue.string('rk3568'),
        DhcpOpt.clientId: Uint8List.fromList([1, 0xaa, 0xbb, 0xcc, 0, 0, 1]),
      }))!;
      final p = reply.packet;
      expect(p.messageType, DhcpMessageType.offer);
      expect(p.op, DhcpOp.reply);
      expect(p.xid, 0x1234);
      expect(p.yiaddr, ip('192.168.50.100'));
      expect(p.ipOption(DhcpOpt.serverId), ip('192.168.50.1'));
      expect(p.ipOption(DhcpOpt.subnetMask), ip('255.255.255.0'));
      expect(p.ipOption(DhcpOpt.router), ip('192.168.50.1'));
      expect(p.ipListOption(DhcpOpt.dnsServers), [ip('8.8.8.8'), ip('8.8.4.4')]);
      expect(p.stringOption(DhcpOpt.domainName), 'lab.local');
      expect(p.u32Option(DhcpOpt.leaseTime), 3600);
      expect(p.u32Option(DhcpOpt.renewalTime), 1800);
      expect(p.u32Option(DhcpOpt.rebindingTime), 3150);
      expect(p.options[DhcpOpt.clientId], [1, 0xaa, 0xbb, 0xcc, 0, 0, 1], reason: '클라이언트 식별자를 되돌려 준다');
      expect(p.ciaddr, Ipv4.any);
      expect(reply.address, Ipv4.broadcast);
      expect(reply.port, 68);
      expect(h.pool.leaseOfMac(mac(1))!.hostname, 'rk3568');
    });

    test('REQUEST에 ACK를 보내고 Lease가 bound가 된다', () {
      final h = _Harness(_config());
      final ack = h.dora(mac(1));
      expect(ack.packet.messageType, DhcpMessageType.ack);
      expect(ack.packet.yiaddr, ip('192.168.50.100'));
      expect(h.pool.leaseOfMac(mac(1))!.state, LeaseState.bound);
      expect(h.engine.stats.toMap(), containsPair('ack', 1));
    });

    test('서브넷 브로드캐스트 옵션이면 그 주소로 보낸다', () {
      final h = _Harness(_config(directed: true));
      expect(h.dora(mac(1)).address, ip('192.168.50.255'));
    });

    test('무제한 Lease는 0xFFFFFFFF이고 T1·T2를 보내지 않는다', () {
      final h = _Harness(_config(leaseTime: null));
      final p = h.dora(mac(1)).packet;
      expect(p.u32Option(DhcpOpt.leaseTime), 0xFFFFFFFF);
      expect(p.options.containsKey(DhcpOpt.renewalTime), isFalse);
      expect(p.options.containsKey(DhcpOpt.rebindingTime), isFalse);
    });

    test('TFTP 서버와 부팅 파일을 option 66·67과 siaddr·file에 넣는다', () {
      final h = _Harness(_config(tftp: '192.168.50.1', boot: 'u-boot.bin'));
      final p = h.dora(mac(1)).packet;
      expect(p.stringOption(DhcpOpt.tftpServerName), '192.168.50.1');
      expect(p.stringOption(DhcpOpt.bootfileName), 'u-boot.bin');
      expect(p.siaddr, ip('192.168.50.1'));
      expect(p.file, 'u-boot.bin');
      expect(p.sname, '');
    });

    test('TFTP 서버가 호스트 이름이면 sname에 넣고 siaddr는 비운다', () {
      final h = _Harness(_config(tftp: 'tftp.lab', boot: 'pxelinux.0'));
      final p = h.dora(mac(1)).packet;
      expect(p.sname, 'tftp.lab');
      expect(p.siaddr, Ipv4.any);
    });

    test('풀이 차면 응답하지 않는다', () {
      final h = _Harness(_config());
      h.dora(mac(1));
      h.dora(mac(2)); // 게이트웨이(.1)는 범위 밖, 범위는 100~102
      h.dora(mac(3));
      expect(h.engine.handle(client(DhcpMessageType.discover, mac(4))), isNull);
      expect(h.logs, contains('logDhcpPoolExhausted'));
    });
  });

  group('REQUEST 변형', () {
    test('다른 서버를 고르면 우리 제안을 거두고 응답하지 않는다', () {
      final h = _Harness(_config());
      h.engine.handle(client(DhcpMessageType.discover, mac(1)));
      final reply = h.engine.handle(client(DhcpMessageType.request, mac(1), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('192.168.50.100')),
        DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.250')),
      }));
      expect(reply, isNull);
      expect(h.pool.leaseOfMac(mac(1)), isNull);
    });

    test('INIT-REBOOT: 서버 식별자 없이 알던 주소를 요청하면 ACK', () {
      final h = _Harness(_config());
      final reply = h.engine.handle(client(DhcpMessageType.request, mac(1), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('192.168.50.101')),
      }));
      // 101은 게이트웨이 대신 제외된 주소가 아니다(서버·게이트웨이는 .1). 풀 범위 안이라 확정된다.
      expect(reply!.packet.messageType, DhcpMessageType.ack);
    });

    test('INIT-REBOOT: 다른 네트워크 주소는 NAK', () {
      final h = _Harness(_config());
      final reply = h.engine.handle(client(DhcpMessageType.request, mac(1), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('10.0.0.5')),
      }))!;
      expect(reply.packet.messageType, DhcpMessageType.nak);
      expect(reply.address, Ipv4.broadcast);
      expect(reply.packet.stringOption(DhcpOpt.message), 'wrongNetwork');
      expect(reply.packet.yiaddr, Ipv4.any);
    });

    test('다른 클라이언트가 쓰는 주소를 요청하면 NAK', () {
      final h = _Harness(_config());
      h.dora(mac(1));
      final reply = h.engine.handle(client(DhcpMessageType.request, mac(2), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('192.168.50.100')),
        DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.1')),
      }))!;
      expect(reply.packet.messageType, DhcpMessageType.nak);
      expect(reply.packet.stringOption(DhcpOpt.message), 'addressUnavailable');
    });

    test('갱신(RENEW)은 ciaddr로 유니캐스트 ACK', () {
      final h = _Harness(_config());
      h.dora(mac(1));
      h.now = h.now.add(const Duration(minutes: 30));
      final reply = h.engine.handle(client(DhcpMessageType.request, mac(1), ciaddr: ip('192.168.50.100')))!;
      expect(reply.packet.messageType, DhcpMessageType.ack);
      expect(reply.address, ip('192.168.50.100'));
      expect(reply.port, 68);
      expect(h.pool.leaseOfMac(mac(1))!.expiresAt, h.now.add(const Duration(hours: 1)));
    });

    test('주소 정보가 없는 REQUEST는 무시한다', () {
      final h = _Harness(_config());
      expect(h.engine.handle(client(DhcpMessageType.request, mac(1))), isNull);
    });
  });

  group('릴레이', () {
    test('giaddr가 있으면 릴레이의 서버 포트로 보낸다', () {
      final h = _Harness(_config());
      final reply = h.engine.handle(client(DhcpMessageType.discover, mac(1), giaddr: ip('192.168.50.2')))!;
      expect(reply.address, ip('192.168.50.2'));
      expect(reply.port, 67);
      expect(reply.packet.giaddr, ip('192.168.50.2'));
    });

    test('릴레이를 거친 NAK는 브로드캐스트 플래그를 켠다', () {
      final h = _Harness(_config());
      final reply = h.engine.handle(client(DhcpMessageType.request, mac(1), giaddr: ip('192.168.50.2'), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('10.0.0.5')),
      }))!;
      expect(reply.packet.messageType, DhcpMessageType.nak);
      expect(reply.packet.wantsBroadcast, isTrue);
      expect(reply.address, ip('192.168.50.2'));
    });
  });

  group('RELEASE · DECLINE · INFORM', () {
    test('RELEASE는 Lease를 지우고 응답하지 않는다', () {
      final h = _Harness(_config());
      h.dora(mac(1));
      expect(h.engine.handle(client(DhcpMessageType.release, mac(1), ciaddr: ip('192.168.50.100'))), isNull);
      expect(h.pool.leases, isEmpty);
    });

    test('남의 주소에 대한 RELEASE는 무시한다', () {
      final h = _Harness(_config());
      h.dora(mac(1));
      h.engine.handle(client(DhcpMessageType.release, mac(2), ciaddr: ip('192.168.50.100')));
      expect(h.pool.leases, hasLength(1));
    });

    test('DECLINE은 그 주소를 격리한다', () {
      final h = _Harness(_config());
      h.engine.handle(client(DhcpMessageType.discover, mac(1)));
      h.engine.handle(client(DhcpMessageType.decline, mac(1), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('192.168.50.100')),
        DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.1')),
      }));
      final offer = h.engine.handle(client(DhcpMessageType.discover, mac(2)))!;
      expect(offer.packet.yiaddr, ip('192.168.50.101'));
      expect(h.logs, contains('logDhcpDecline'));
    });

    test('다른 서버 앞으로 온 DECLINE은 무시한다', () {
      final h = _Harness(_config());
      h.engine.handle(client(DhcpMessageType.discover, mac(1)));
      h.engine.handle(client(DhcpMessageType.decline, mac(1), options: {
        DhcpOpt.requestedIp: DhcpValue.ip(ip('192.168.50.100')),
        DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.250')),
      }));
      expect(h.pool.leaseOfIp(ip('192.168.50.100')), isNotNull);
    });

    test('INFORM에는 Lease 없이 설정 옵션만 담은 ACK를 ciaddr로 보낸다', () {
      final h = _Harness(_config());
      final reply = h.engine.handle(client(DhcpMessageType.inform, mac(1), ciaddr: ip('192.168.50.77')))!;
      expect(reply.packet.messageType, DhcpMessageType.ack);
      expect(reply.packet.yiaddr, Ipv4.any);
      expect(reply.packet.options.containsKey(DhcpOpt.leaseTime), isFalse);
      expect(reply.packet.ipOption(DhcpOpt.router), ip('192.168.50.1'));
      expect(reply.address, ip('192.168.50.77'));
      expect(h.pool.leases, isEmpty);
    });
  });

  group('걸러내기', () {
    test('응답 패킷·알 수 없는 종류·이더넷이 아닌 하드웨어는 무시한다', () {
      final h = _Harness(_config());
      final offerLike = DhcpPacket(op: DhcpOp.reply, xid: 1, chaddr: Uint8List(16), options: {DhcpOpt.messageType: DhcpValue.u8(2)});
      expect(h.engine.handle(offerLike), isNull);
      expect(h.engine.handle(client(99, mac(1))), isNull);
      final weird = DhcpPacket(op: DhcpOp.request, htype: 6, hlen: 8, xid: 1, chaddr: Uint8List(16), options: {DhcpOpt.messageType: DhcpValue.u8(1)});
      expect(h.engine.handle(weird), isNull);
      expect(h.pool.leases, isEmpty);
    });
  });

  test('로그 키는 모두 logDhcp로 시작한다', () {
    final h = _Harness(_config());
    h.dora(mac(1));
    h.engine.handle(client(DhcpMessageType.release, mac(1), ciaddr: ip('192.168.50.100')));
    expect(h.logs, isNotEmpty);
    expect(h.logs.every((k) => k.startsWith('logDhcp')), isTrue);
    expect(LogLevel.values, contains(LogLevel.debug));
  });
}
