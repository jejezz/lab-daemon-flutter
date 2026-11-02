// DHCP 패킷 파싱과 생성 (RFC 2131, 2132). 소켓에 의존하지 않는다.
//
// 고정 헤더 236바이트 + 매직 쿠키 4바이트 + 옵션(TLV). 옵션은 값을 그대로 바이트로 들고 있고,
// 자주 쓰는 해석(메시지 종류, IP 하나/여러 개, 문자열)은 접근자로 제공한다.

import 'dart:convert';
import 'dart:typed_data';

import '../ipv4.dart';

abstract final class DhcpOp {
  static const request = 1; // 클라이언트 → 서버 (BOOTREQUEST)
  static const reply = 2; // 서버 → 클라이언트 (BOOTREPLY)
}

abstract final class DhcpMessageType {
  static const discover = 1;
  static const offer = 2;
  static const request = 3;
  static const decline = 4;
  static const ack = 5;
  static const nak = 6;
  static const release = 7;
  static const inform = 8;

  static String name(int? type) => switch (type) {
        discover => 'DISCOVER',
        offer => 'OFFER',
        request => 'REQUEST',
        decline => 'DECLINE',
        ack => 'ACK',
        nak => 'NAK',
        release => 'RELEASE',
        inform => 'INFORM',
        _ => 'UNKNOWN',
      };
}

abstract final class DhcpOpt {
  static const pad = 0;
  static const subnetMask = 1;
  static const router = 3;
  static const dnsServers = 6;
  static const hostname = 12;
  static const domainName = 15;
  static const ntpServers = 42;
  static const requestedIp = 50;
  static const leaseTime = 51;
  static const messageType = 53;
  static const serverId = 54;
  static const parameterRequestList = 55;
  static const message = 56;
  static const renewalTime = 58;
  static const rebindingTime = 59;
  static const vendorClass = 60;
  static const clientId = 61;
  static const tftpServerName = 66;
  static const bootfileName = 67;
  static const end = 255;
}

class DhcpFormatException implements FormatException {
  DhcpFormatException(this.message);

  @override
  final String message;

  @override
  dynamic get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => 'DhcpFormatException: $message';
}

/// 옵션 값을 만드는 도우미.
abstract final class DhcpValue {
  static Uint8List u8(int v) => Uint8List.fromList([v & 0xFF]);

  static Uint8List u32(int v) => Uint8List.fromList([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);

  static Uint8List ip(Ipv4 v) => v.toBytes();

  static Uint8List ips(Iterable<Ipv4> v) => Uint8List.fromList([for (final ip in v) ...ip.toBytes()]);

  static Uint8List string(String v) => Uint8List.fromList(utf8.encode(v));
}

class DhcpPacket {
  DhcpPacket({
    required this.op,
    this.htype = 1,
    this.hlen = 6,
    this.hops = 0,
    required this.xid,
    this.secs = 0,
    this.flags = 0,
    this.ciaddr = Ipv4.any,
    this.yiaddr = Ipv4.any,
    this.siaddr = Ipv4.any,
    this.giaddr = Ipv4.any,
    required Uint8List chaddr,
    this.sname = '',
    this.file = '',
    Map<int, Uint8List>? options,
  })  : chaddr = _padChaddr(chaddr),
        options = options ?? <int, Uint8List>{};

  static const headerLength = 236;
  static const magicCookie = [0x63, 0x82, 0x53, 0x63];

  /// 일부 오래된 BOOTP 클라이언트가 이보다 짧은 패킷을 거부하므로 300바이트까지 0으로 채워 보낸다.
  static const minimumLength = 300;

  static const broadcastFlag = 0x8000;

  final int op;
  final int htype;
  final int hlen;
  final int hops;
  final int xid;
  final int secs;
  final int flags;
  final Ipv4 ciaddr;
  final Ipv4 yiaddr;
  final Ipv4 siaddr;
  final Ipv4 giaddr;

  /// 항상 16바이트.
  final Uint8List chaddr;
  final String sname;
  final String file;

  /// 옵션 코드 → 값. 넣은 순서대로 보낸다 (메시지 종류가 맨 앞에 오게 하는 것을 권장).
  final Map<int, Uint8List> options;

  static Uint8List _padChaddr(Uint8List value) {
    final padded = Uint8List(16);
    padded.setRange(0, value.length < 16 ? value.length : 16, value);
    return padded;
  }

  bool get wantsBroadcast => (flags & broadcastFlag) != 0;

  MacAddress get clientMac => MacAddress(chaddr.sublist(0, hlen.clamp(0, 16)));

  int? get messageType {
    final v = options[DhcpOpt.messageType];
    return v != null && v.length == 1 ? v[0] : null;
  }

  Ipv4? ipOption(int code) {
    final v = options[code];
    return v != null && v.length == 4 ? Ipv4.fromBytes(v) : null;
  }

  List<Ipv4> ipListOption(int code) {
    final v = options[code];
    if (v == null) return const [];
    return [for (var i = 0; i + 4 <= v.length; i += 4) Ipv4.fromBytes(v, i)];
  }

  String? stringOption(int code) {
    final v = options[code];
    return v == null ? null : utf8.decode(v, allowMalformed: true);
  }

  int? u32Option(int code) {
    final v = options[code];
    if (v == null || v.length != 4) return null;
    return (v[0] << 24) | (v[1] << 16) | (v[2] << 8) | v[3];
  }

  /// 클라이언트가 요청한 옵션 코드 목록 (option 55).
  List<int> get parameterRequestList => options[DhcpOpt.parameterRequestList]?.toList() ?? const [];

  factory DhcpPacket.parse(Uint8List data) {
    if (data.length < headerLength + 4) throw DhcpFormatException('Packet too short (${data.length} bytes)');
    for (var i = 0; i < 4; i++) {
      if (data[headerLength + i] != magicCookie[i]) throw DhcpFormatException('Missing magic cookie');
    }
    final hlen = data[2];
    if (hlen > 16) throw DhcpFormatException('Invalid hardware address length $hlen');

    final options = <int, Uint8List>{};
    var i = headerLength + 4;
    while (i < data.length) {
      final code = data[i++];
      if (code == DhcpOpt.pad) continue;
      if (code == DhcpOpt.end) break;
      if (i >= data.length) throw DhcpFormatException('Option $code has no length');
      final length = data[i++];
      if (i + length > data.length) throw DhcpFormatException('Option $code is truncated');
      options[code] = Uint8List.fromList(data.sublist(i, i + length));
      i += length;
    }

    return DhcpPacket(
      op: data[0],
      htype: data[1],
      hlen: hlen,
      hops: data[3],
      xid: _u32(data, 4),
      secs: (data[8] << 8) | data[9],
      flags: (data[10] << 8) | data[11],
      ciaddr: Ipv4.fromBytes(data, 12),
      yiaddr: Ipv4.fromBytes(data, 16),
      siaddr: Ipv4.fromBytes(data, 20),
      giaddr: Ipv4.fromBytes(data, 24),
      chaddr: Uint8List.fromList(data.sublist(28, 44)),
      sname: _cString(data, 44, 64),
      file: _cString(data, 108, 128),
      options: options,
    );
  }

  /// [request]에 대한 응답 틀. 서버가 채우지 않는 항목은 요청에서 그대로 가져온다:
  /// `xid`, `flags`, `giaddr`, `chaddr` (RFC 2131 표 3).
  factory DhcpPacket.replyTo(
    DhcpPacket request, {
    required int type,
    Ipv4 yiaddr = Ipv4.any,
    Ipv4 siaddr = Ipv4.any,
    String sname = '',
    String file = '',
    Map<int, Uint8List> options = const {},
  }) {
    return DhcpPacket(
      op: DhcpOp.reply,
      htype: request.htype,
      hlen: request.hlen,
      xid: request.xid,
      flags: request.flags,
      giaddr: request.giaddr,
      yiaddr: yiaddr,
      siaddr: siaddr,
      chaddr: request.chaddr,
      sname: sname,
      file: file,
      options: {DhcpOpt.messageType: DhcpValue.u8(type), ...options},
    );
  }

  Uint8List toBytes() {
    final out = BytesBuilder();
    final header = Uint8List(headerLength);
    header[0] = op;
    header[1] = htype;
    header[2] = hlen;
    header[3] = hops;
    _putU32(header, 4, xid);
    header[8] = (secs >> 8) & 0xFF;
    header[9] = secs & 0xFF;
    header[10] = (flags >> 8) & 0xFF;
    header[11] = flags & 0xFF;
    header.setRange(12, 16, ciaddr.toBytes());
    header.setRange(16, 20, yiaddr.toBytes());
    header.setRange(20, 24, siaddr.toBytes());
    header.setRange(24, 28, giaddr.toBytes());
    header.setRange(28, 44, chaddr);
    _putCString(header, 44, 64, sname);
    _putCString(header, 108, 128, file);
    out.add(header);
    out.add(magicCookie);
    for (final MapEntry(key: code, value: value) in options.entries) {
      if (code == DhcpOpt.pad || code == DhcpOpt.end) continue;
      if (value.length > 255) throw DhcpFormatException('Option $code is longer than 255 bytes');
      out.addByte(code);
      out.addByte(value.length);
      out.add(value);
    }
    out.addByte(DhcpOpt.end);
    final bytes = out.toBytes();
    if (bytes.length >= minimumLength) return bytes;
    return Uint8List(minimumLength)..setRange(0, bytes.length, bytes);
  }

  static int _u32(Uint8List d, int o) => (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

  static void _putU32(Uint8List d, int o, int v) {
    d[o] = (v >> 24) & 0xFF;
    d[o + 1] = (v >> 16) & 0xFF;
    d[o + 2] = (v >> 8) & 0xFF;
    d[o + 3] = v & 0xFF;
  }

  static String _cString(Uint8List d, int offset, int max) {
    var end = offset;
    while (end < offset + max && d[end] != 0) {
      end++;
    }
    return utf8.decode(d.sublist(offset, end), allowMalformed: true);
  }

  static void _putCString(Uint8List d, int offset, int max, String value) {
    final bytes = utf8.encode(value);
    // 끝의 0바이트를 위해 한 칸을 비워 둔다.
    final n = bytes.length < max - 1 ? bytes.length : max - 1;
    d.setRange(offset, offset + n, bytes);
  }

  /// 로그 상세에 쓰는 16진수 덤프.
  static String hexDump(Uint8List data) =>
      [for (var i = 0; i < data.length; i += 16) data.sublist(i, i + 16 > data.length ? data.length : i + 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')].join('\n');
}
