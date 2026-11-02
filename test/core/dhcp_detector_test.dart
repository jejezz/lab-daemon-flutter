import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/detector.dart';
import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/dhcp/transport.dart';
import 'package:lab_daemon/core/ipv4.dart';

Ipv4 ip(String s) => Ipv4.parse(s);

/// 프로브가 보낸 DISCOVER를 보고 [answer]가 정한 응답을 돌려주는 가짜 전송 계층.
class _ProbeTransport implements DhcpTransport {
  _ProbeTransport(this.answer);

  /// DISCOVER를 받아 응답할 패킷들(없으면 침묵).
  final List<Uint8List> Function(DhcpPacket discover) answer;

  final _incoming = StreamController<DhcpDatagram>.broadcast(sync: true);
  final sent = <({DhcpPacket packet, Ipv4 address, int port})>[];
  bool closed = false;

  @override
  Stream<DhcpDatagram> get incoming => _incoming.stream;

  @override
  int get port => 68;

  @override
  void send(Uint8List data, Ipv4 address, int port) {
    final packet = DhcpPacket.parse(data);
    sent.add((packet: packet, address: address, port: port));
    for (final reply in answer(packet)) {
      _incoming.add(DhcpDatagram(reply, ip('192.168.50.254'), 67));
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    await _incoming.close();
  }
}

Uint8List _offer(DhcpPacket discover, {Ipv4? serverId, String offered = '192.168.50.77', int? xid}) {
  return DhcpPacket(
    op: DhcpOp.reply,
    xid: xid ?? discover.xid,
    chaddr: discover.chaddr,
    yiaddr: ip(offered),
    options: {
      DhcpOpt.messageType: DhcpValue.u8(DhcpMessageType.offer),
      if (serverId != null) DhcpOpt.serverId: DhcpValue.ip(serverId),
    },
  ).toBytes();
}

Future<DhcpProbeResult> _probe(_ProbeTransport transport) => detectOtherDhcpServers(
      interfaceIp: ip('192.168.50.1'),
      timeout: const Duration(milliseconds: 20),
      transportFactory: (a, p) async => transport,
      random: Random(1),
    );

void main() {
  test('아무도 응답하지 않으면 서버 없음이고, DISCOVER를 브로드캐스트로 두 번 보낸다', () async {
    final transport = _ProbeTransport((_) => []);
    final result = await _probe(transport);

    expect(result.found, isFalse);
    expect(result.inconclusive, isFalse);
    expect(transport.sent, hasLength(2));
    final first = transport.sent.first;
    expect(first.address, Ipv4.broadcast);
    expect(first.port, 67);
    expect(first.packet.messageType, DhcpMessageType.discover);
    expect(first.packet.wantsBroadcast, isTrue, reason: '주소 없는 클라이언트라서 응답을 브로드캐스트로 받는다');
    expect(first.packet.chaddr[0] & 0x02, 0x02, reason: '로컬 관리 MAC이라 실제 장비와 겹치지 않는다');
    expect(transport.closed, isTrue);
  });

  test('OFFER를 보낸 서버를 서버 식별자로 찾아낸다 (두 번 보내도 한 번만)', () async {
    final transport = _ProbeTransport((d) => [_offer(d, serverId: ip('192.168.50.254'))]);
    final result = await _probe(transport);

    expect(result.found, isTrue);
    expect(result.servers.single.serverId, ip('192.168.50.254'));
    expect(result.servers.single.offeredIp, ip('192.168.50.77'));
  });

  test('서버 식별자가 없으면 보낸 주소를 서버로 본다', () async {
    final result = await _probe(_ProbeTransport((d) => [_offer(d)]));
    expect(result.servers.single.serverId, ip('192.168.50.254'));
  });

  test('서버가 둘이면 둘 다 모은다', () async {
    final result = await _probe(_ProbeTransport((d) => [
          _offer(d, serverId: ip('192.168.50.254')),
          _offer(d, serverId: ip('192.168.50.253'), offered: '192.168.50.88'),
        ]));
    expect(result.servers.map((s) => '${s.serverId}'), unorderedEquals(['192.168.50.254', '192.168.50.253']));
  });

  test('xid가 다르거나 OFFER가 아니거나 깨진 패킷은 무시한다', () async {
    final result = await _probe(_ProbeTransport((d) => [
          _offer(d, xid: d.xid + 1, serverId: ip('192.168.50.250')),
          DhcpPacket(
            op: DhcpOp.reply,
            xid: d.xid,
            chaddr: d.chaddr,
            options: {DhcpOpt.messageType: DhcpValue.u8(DhcpMessageType.ack), DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.251'))},
          ).toBytes(),
          Uint8List(40),
        ]));
    expect(result.found, isFalse);
  });

  test('다른 클라이언트(MAC)에게 간 OFFER는 무시한다', () async {
    final result = await _probe(_ProbeTransport((d) {
      final other = Uint8List.fromList(d.chaddr)..[5] ^= 0xFF;
      return [
        DhcpPacket(
          op: DhcpOp.reply,
          xid: d.xid,
          chaddr: other,
          options: {DhcpOpt.messageType: DhcpValue.u8(DhcpMessageType.offer), DhcpOpt.serverId: DhcpValue.ip(ip('192.168.50.254'))},
        ).toBytes()
      ];
    }));
    expect(result.found, isFalse);
  });

  test('소켓을 열 수 없으면 "알 수 없음"으로 돌려주고 예외를 던지지 않는다', () async {
    final result = await detectOtherDhcpServers(
      interfaceIp: ip('192.168.50.1'),
      timeout: const Duration(milliseconds: 20),
      transportFactory: (a, p) async => throw StateError('port 68 busy'),
    );
    expect(result.inconclusive, isTrue);
    expect(result.found, isFalse);
    expect(result.error, contains('port 68 busy'));
  });

  test('프로브는 선택한 NIC 주소의 클라이언트 포트에 묶는다', () async {
    Ipv4? boundAddress;
    int? boundPort;
    await detectOtherDhcpServers(
      interfaceIp: ip('192.168.50.1'),
      timeout: const Duration(milliseconds: 20),
      transportFactory: (a, p) async {
        boundAddress = a;
        boundPort = p;
        return _ProbeTransport((_) => []);
      },
    );
    expect(boundAddress, ip('192.168.50.1'));
    expect(boundPort, 68);
  });
}
