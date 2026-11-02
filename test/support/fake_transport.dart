// 화면 테스트용 가짜 UDP 전송 계층: 소켓 없이 패킷을 넣고, 서버가 보낸 응답을 모아 둔다.

import 'dart:async';
import 'dart:typed_data';

import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/dhcp/transport.dart';
import 'package:lab_daemon/core/ipv4.dart';

class FakeTransport implements DhcpTransport {
  final _incoming = StreamController<DhcpDatagram>.broadcast(sync: true);
  final sent = <DhcpPacket>[];

  @override
  Stream<DhcpDatagram> get incoming => _incoming.stream;

  @override
  int get port => 67;

  void receive(DhcpPacket packet) => _incoming.add(DhcpDatagram(packet.toBytes(), Ipv4.any, 68));

  @override
  void send(Uint8List data, Ipv4 address, int port) => sent.add(DhcpPacket.parse(data));

  @override
  Future<void> close() => _incoming.close();

  /// DISCOVER → OFFER → REQUEST → ACK를 한 번에 돌린다.
  void dora(MacAddress mac, {String? hostname}) {
    DhcpPacket client(int type, Map<int, Uint8List> options) => DhcpPacket(
          op: DhcpOp.request,
          xid: 1,
          chaddr: Uint8List.fromList(mac.bytes),
          options: {DhcpOpt.messageType: DhcpValue.u8(type), ...options},
        );
    receive(client(DhcpMessageType.discover, {if (hostname != null) DhcpOpt.hostname: DhcpValue.string(hostname)}));
    final offered = sent.last.yiaddr;
    receive(client(DhcpMessageType.request, {
      DhcpOpt.requestedIp: DhcpValue.ip(offered),
      DhcpOpt.serverId: DhcpValue.ip(Ipv4.parse('192.168.50.1')),
    }));
  }
}
