// DHCP 요청 하나를 받아 응답 하나(또는 없음)를 정하는 순수 로직 (RFC 2131 §4.3).
// 소켓·타이머를 모르므로 패킷만 넣어서 DORA 전체를 테스트할 수 있다.

import 'dart:typed_data';

import '../ipv4.dart';
import '../service.dart';
import 'config.dart';
import 'packet.dart';
import 'pool.dart';

typedef DhcpLog = void Function(LogLevel level, String key, {String? kind, Map<String, Object?> args, String? detail});

/// 보낼 응답과 목적지.
class DhcpReply {
  const DhcpReply(this.packet, this.address, this.port);

  final DhcpPacket packet;
  final Ipv4 address;
  final int port;
}

/// 메시지 종류별 처리 횟수.
class DhcpStats {
  int discover = 0, offer = 0, request = 0, ack = 0, nak = 0, release = 0, decline = 0, inform = 0;

  Map<String, int> toMap() => {
        'discover': discover,
        'offer': offer,
        'request': request,
        'ack': ack,
        'nak': nak,
        'release': release,
        'decline': decline,
        'inform': inform,
      };
}

class DhcpEngine {
  DhcpEngine(this.config, this.pool, this._log);

  final DhcpConfig config;
  final LeasePool pool;
  final DhcpLog _log;
  final stats = DhcpStats();

  /// [request]에 대한 응답. 응답하지 않을 요청이면 null.
  DhcpReply? handle(DhcpPacket request) {
    if (request.op != DhcpOp.request) return _ignore('notRequest');
    if (request.htype != 1 || request.hlen != 6) return _ignore('unsupportedHardware');
    return switch (request.messageType) {
      DhcpMessageType.discover => _discover(request),
      DhcpMessageType.request => _request(request),
      DhcpMessageType.release => _release(request),
      DhcpMessageType.decline => _decline(request),
      DhcpMessageType.inform => _inform(request),
      _ => _ignore('unknownType'),
    };
  }

  // ---- 메시지별 처리 -----------------------------------------------------------------------------

  DhcpReply? _discover(DhcpPacket req) {
    stats.discover++;
    final mac = req.clientMac;
    final hostname = req.stringOption(DhcpOpt.hostname);
    _log(LogLevel.info, 'logDhcpDiscover', kind: 'DISCOVER', args: {'mac': '$mac', 'hostname': hostname});
    final lease = pool.offer(mac, requested: req.ipOption(DhcpOpt.requestedIp), hostname: hostname);
    if (lease == null) {
      _log(LogLevel.warning, 'logDhcpPoolExhausted', kind: 'OFFER', args: {'mac': '$mac'});
      return null;
    }
    stats.offer++;
    _log(LogLevel.info, 'logDhcpOffer', kind: 'OFFER', args: {'mac': '$mac', 'ip': '${lease.ip}'});
    return _leaseReply(req, DhcpMessageType.offer, lease);
  }

  DhcpReply? _request(DhcpPacket req) {
    stats.request++;
    final mac = req.clientMac;
    final serverId = req.ipOption(DhcpOpt.serverId);
    final hostname = req.stringOption(DhcpOpt.hostname);

    // SELECTING 단계에서 다른 서버를 골랐다: 우리 제안은 거둔다.
    if (serverId != null && serverId != config.serverIp) {
      final held = pool.leaseOfMac(mac);
      if (held != null && held.state == LeaseState.offered) pool.releaseMac(mac);
      _log(LogLevel.info, 'logDhcpOtherServer', kind: 'REQUEST', args: {'mac': '$mac', 'server': '$serverId'});
      return null;
    }

    final requested = req.ipOption(DhcpOpt.requestedIp);
    final ip = requested ?? (req.ciaddr != Ipv4.any ? req.ciaddr : null);
    if (ip == null) return _ignore('requestWithoutAddress');
    _log(LogLevel.info, 'logDhcpRequest', kind: 'REQUEST', args: {'mac': '$mac', 'ip': '$ip', 'hostname': hostname});

    // INIT-REBOOT인데 다른 네트워크의 주소를 들고 왔다.
    if (serverId == null && req.ciaddr == Ipv4.any && !ip.isInSubnet(config.rangeStart, config.mask)) {
      return _nak(req, 'wrongNetwork', ip);
    }

    final lease = pool.confirm(mac, ip, hostname: hostname);
    if (lease == null) return _nak(req, 'addressUnavailable', ip);

    stats.ack++;
    _log(LogLevel.info, 'logDhcpAck', kind: 'ACK', args: {
      'mac': '$mac',
      'ip': '${lease.ip}',
      'seconds': config.leaseTime?.inSeconds,
    });
    return _leaseReply(req, DhcpMessageType.ack, lease);
  }

  DhcpReply? _release(DhcpPacket req) {
    stats.release++;
    final mac = req.clientMac;
    final lease = pool.leaseOfIp(req.ciaddr);
    if (lease == null || lease.mac != mac) return _ignore('releaseUnknown');
    pool.releaseIp(req.ciaddr);
    _log(LogLevel.info, 'logDhcpRelease', kind: 'RELEASE', args: {'mac': '$mac', 'ip': '${req.ciaddr}'});
    return null;
  }

  DhcpReply? _decline(DhcpPacket req) {
    stats.decline++;
    final serverId = req.ipOption(DhcpOpt.serverId);
    final ip = req.ipOption(DhcpOpt.requestedIp);
    if (ip == null || (serverId != null && serverId != config.serverIp)) return _ignore('declineNotForUs');
    pool.decline(ip);
    _log(LogLevel.warning, 'logDhcpDecline', kind: 'DECLINE', args: {'mac': '${req.clientMac}', 'ip': '$ip'});
    return null;
  }

  /// 이미 주소를 가진 클라이언트가 설정만 요청한다: Lease 없이 옵션만 돌려준다.
  DhcpReply? _inform(DhcpPacket req) {
    stats.inform++;
    _log(LogLevel.info, 'logDhcpInform', kind: 'INFORM', args: {'mac': '${req.clientMac}', 'ip': '${req.ciaddr}'});
    stats.ack++;
    final packet = _build(req, DhcpMessageType.ack, options: _configOptions());
    return _send(packet, req, DhcpMessageType.ack);
  }

  // ---- 응답 만들기 -----------------------------------------------------------------------------

  DhcpReply _leaseReply(DhcpPacket req, int type, Lease lease) {
    final time = config.leaseTime;
    final options = <int, Uint8List>{};
    if (time == null) {
      options[DhcpOpt.leaseTime] = DhcpValue.u32(0xFFFFFFFF);
    } else {
      final seconds = time.inSeconds;
      options[DhcpOpt.leaseTime] = DhcpValue.u32(seconds);
      options[DhcpOpt.renewalTime] = DhcpValue.u32(seconds ~/ 2);
      options[DhcpOpt.rebindingTime] = DhcpValue.u32(seconds * 7 ~/ 8);
    }
    options.addAll(_configOptions());
    final packet = _build(req, type, yiaddr: lease.ip, options: options);
    return _send(packet, req, type);
  }

  DhcpReply _nak(DhcpPacket req, String reason, Ipv4 ip) {
    stats.nak++;
    _log(LogLevel.warning, 'logDhcpNak', kind: 'NAK', args: {'mac': '${req.clientMac}', 'ip': '$ip', 'reason': reason});
    final packet = DhcpPacket.replyTo(
      req,
      type: DhcpMessageType.nak,
      // 릴레이를 거치면 클라이언트에게 브로드캐스트로 전달되도록 한다 (RFC 2131 §4.3.2).
      flags: req.giaddr != Ipv4.any ? DhcpPacket.broadcastFlag : null,
      options: {
        DhcpOpt.serverId: DhcpValue.ip(config.serverIp),
        DhcpOpt.message: DhcpValue.string(reason),
        ..._echoClientId(req),
      },
    );
    return _send(packet, req, DhcpMessageType.nak);
  }

  DhcpReply _send(DhcpPacket packet, DhcpPacket req, int type) {
    final (address, port) = _destination(req, type);
    return DhcpReply(packet, address, port);
  }

  DhcpPacket _build(DhcpPacket req, int type, {Ipv4 yiaddr = Ipv4.any, required Map<int, Uint8List> options}) {
    final tftp = config.tftpServer;
    final tftpIp = tftp == null ? null : Ipv4.tryParse(tftp);
    return DhcpPacket.replyTo(
      req,
      type: type,
      yiaddr: yiaddr,
      siaddr: tftpIp ?? Ipv4.any,
      sname: tftp != null && tftpIp == null && tftp.length < 64 ? tftp : '',
      file: config.bootFile ?? '',
      options: {
        DhcpOpt.serverId: DhcpValue.ip(config.serverIp),
        ...options,
        ..._echoClientId(req),
      },
    );
  }

  /// 서브넷, 게이트웨이, DNS 같은 설정 옵션. 설정한 것만 넣는다.
  Map<int, Uint8List> _configOptions() => {
        DhcpOpt.subnetMask: DhcpValue.ip(config.mask),
        if (config.gateway != null) DhcpOpt.router: DhcpValue.ip(config.gateway!),
        if (config.dnsServers.isNotEmpty) DhcpOpt.dnsServers: DhcpValue.ips(config.dnsServers),
        if (config.domainName != null) DhcpOpt.domainName: DhcpValue.string(config.domainName!),
        if (config.ntpServers.isNotEmpty) DhcpOpt.ntpServers: DhcpValue.ips(config.ntpServers),
        if (config.tftpServer != null) DhcpOpt.tftpServerName: DhcpValue.string(config.tftpServer!),
        if (config.bootFile != null) DhcpOpt.bootfileName: DhcpValue.string(config.bootFile!),
      };

  /// 클라이언트 식별자는 받은 그대로 돌려준다 (RFC 6842).
  Map<int, Uint8List> _echoClientId(DhcpPacket req) {
    final id = req.options[DhcpOpt.clientId];
    return id == null ? const {} : {DhcpOpt.clientId: id};
  }

  /// 응답을 보낼 곳 (RFC 2131 §4.1).
  /// - 릴레이를 거쳤으면 릴레이(giaddr)의 서버 포트로.
  /// - 클라이언트가 이미 주소(ciaddr)를 가졌으면 그 주소로 유니캐스트.
  /// - 그 밖에는 브로드캐스트. 아직 주소가 없는 클라이언트에게 유니캐스트하려면 ARP 항목을 직접 넣어야 해서,
  ///   브로드캐스트 플래그와 상관없이 항상 브로드캐스트한다.
  (Ipv4, int) _destination(DhcpPacket req, int type) {
    if (req.giaddr != Ipv4.any) return (req.giaddr, config.serverPort);
    if (type != DhcpMessageType.nak && req.ciaddr != Ipv4.any) return (req.ciaddr, config.clientPort);
    return (config.broadcastTarget, config.clientPort);
  }

  Null _ignore(String reason) {
    _log(LogLevel.debug, 'logDhcpIgnored', args: {'reason': reason});
    return null;
  }
}
