// 같은 망에 다른 DHCP 서버가 있는지 알아낸다. 서버를 켜기 전에 선택한 NIC로 DHCPDISCOVER를 한 번
// 브로드캐스트하고, 몇 초 안에 DHCPOFFER가 오면 그 보낸 서버를 모은다. OFFER만 받고 REQUEST는 보내지
// 않으므로 상대 서버에 Lease가 확정되지 않는다 (상대는 제안을 잠시 잡아 두었다가 푼다).
//
// 한계: 이 방법은 "이 NIC가 닿는 같은 브로드캐스트 영역"에서 새 클라이언트에게 응답하는 서버만 찾는다.
// 릴레이 너머의 서버, MAC 허용 목록으로 낯선 클라이언트를 무시하는 서버, 응답이 느린 서버는 놓칠 수 있다.
// 그래서 결과가 "없음"이어도 다른 서버가 없다고 보장하지는 않는다.

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../ipv4.dart';
import 'packet.dart';
import 'transport.dart';

class DetectedServer {
  const DetectedServer({required this.serverId, required this.offeredIp});

  /// OFFER의 서버 식별자(option 54). 없으면 패킷을 보낸 주소.
  final Ipv4 serverId;

  /// 그 서버가 우리 프로브에 제안한 주소.
  final Ipv4 offeredIp;

  @override
  bool operator ==(Object other) => other is DetectedServer && other.serverId == serverId;

  @override
  int get hashCode => serverId.hashCode;
}

class DhcpProbeResult {
  const DhcpProbeResult(this.servers, {this.error});

  /// 응답한 서버들 (서버 식별자 기준 중복 제거).
  final List<DetectedServer> servers;

  /// 확인을 끝내지 못한 이유 (소켓을 열지 못함 등). 이때 [servers]는 비어 있고 결과는 "알 수 없음"이다.
  final String? error;

  bool get found => servers.isNotEmpty;

  bool get inconclusive => error != null;
}

/// 프로브용 전송 계층을 만든다. Windows의 DHCP 클라이언트 서비스가 이미 68번을 쓸 수 있어서
/// 주소 재사용(reuseAddress)을 켠다.
Future<DhcpTransport> _bindProbe(Ipv4 address, int port) => UdpDhcpTransport.bind(address, port, reuseAddress: true);

/// [interfaceIp]가 속한 망에 다른 DHCP 서버가 있는지 [timeout] 동안 기다려 본다.
/// DISCOVER는 시작 때와 [timeout]의 절반쯤에 한 번씩, 모두 두 번 보낸다 (패킷 유실 대비).
Future<DhcpProbeResult> detectOtherDhcpServers({
  required Ipv4 interfaceIp,
  Duration timeout = const Duration(seconds: 3),
  int serverPort = 67,
  int clientPort = 68,
  DhcpTransportFactory? transportFactory,
  Random? random,
}) async {
  final rnd = random ?? Random.secure();
  final DhcpTransport transport;
  try {
    transport = await (transportFactory ?? _bindProbe)(interfaceIp, clientPort);
  } catch (e) {
    return DhcpProbeResult(const [], error: '$e');
  }

  final xid = rnd.nextInt(0x7FFFFFFF);
  // 로컬 관리 비트(0x02)를 켠 임의 MAC: 실제 장비와 겹치지 않는다.
  final mac = Uint8List.fromList([0x02, ...List.generate(5, (_) => rnd.nextInt(256))]);
  final discover = DhcpPacket(
    op: DhcpOp.request,
    xid: xid,
    flags: DhcpPacket.broadcastFlag, // 주소 없는 클라이언트라서 응답을 브로드캐스트로 받는다.
    chaddr: mac,
    options: {
      DhcpOpt.messageType: DhcpValue.u8(DhcpMessageType.discover),
      DhcpOpt.clientId: Uint8List.fromList([1, ...mac]),
      DhcpOpt.parameterRequestList: Uint8List.fromList([DhcpOpt.subnetMask, DhcpOpt.router, DhcpOpt.dnsServers]),
    },
  ).toBytes();

  final found = <Ipv4, DetectedServer>{};
  final subscription = transport.incoming.listen((datagram) {
    try {
      final p = DhcpPacket.parse(datagram.data);
      if (p.op != DhcpOp.reply || p.xid != xid || p.messageType != DhcpMessageType.offer) return;
      if (!_sameMac(p.chaddr, mac)) return;
      final id = p.ipOption(DhcpOpt.serverId) ?? datagram.from;
      found.putIfAbsent(id, () => DetectedServer(serverId: id, offeredIp: p.yiaddr));
    } on DhcpFormatException {
      // 다른 프로그램의 잡음은 무시한다.
    }
  });

  try {
    transport.send(discover, Ipv4.broadcast, serverPort);
    await Future<void>.delayed(timeout ~/ 2);
    transport.send(discover, Ipv4.broadcast, serverPort);
    await Future<void>.delayed(timeout - timeout ~/ 2);
  } catch (e) {
    return DhcpProbeResult(found.values.toList(), error: found.isEmpty ? '$e' : null);
  } finally {
    await subscription.cancel();
    await transport.close();
  }
  return DhcpProbeResult(found.values.toList());
}

bool _sameMac(Uint8List chaddr, Uint8List mac) {
  for (var i = 0; i < mac.length; i++) {
    if (chaddr[i] != mac[i]) return false;
  }
  return true;
}
