import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/ipv4.dart';

/// 구현과 무관하게 바이트를 직접 조립한 DHCPDISCOVER (xid 0x3903F326, MAC aa:bb:cc:11:22:33,
/// 호스트 이름 rk3568, 요청 옵션 1·3·6, 요청 주소 192.168.50.150).
Uint8List _discover() {
  final b = Uint8List(300);
  b[0] = 1; // BOOTREQUEST
  b[1] = 1; // 이더넷
  b[2] = 6;
  b.setRange(4, 8, [0x39, 0x03, 0xF3, 0x26]);
  b[10] = 0x80; // 브로드캐스트 플래그
  b.setRange(28, 34, [0xaa, 0xbb, 0xcc, 0x11, 0x22, 0x33]);
  b.setRange(236, 240, [0x63, 0x82, 0x53, 0x63]);
  final options = <int>[
    53, 1, 1, //
    12, 6, ...'rk3568'.codeUnits,
    50, 4, 192, 168, 50, 150,
    55, 3, 1, 3, 6,
    0, 0, // PAD
    255,
  ];
  b.setRange(240, 240 + options.length, options);
  return b;
}

void main() {
  group('파싱', () {
    test('DISCOVER의 헤더와 옵션을 읽는다', () {
      final p = DhcpPacket.parse(_discover());
      expect(p.op, DhcpOp.request);
      expect(p.xid, 0x3903F326);
      expect(p.wantsBroadcast, isTrue);
      expect(p.clientMac.toString(), 'aa:bb:cc:11:22:33');
      expect(p.messageType, DhcpMessageType.discover);
      expect(p.stringOption(DhcpOpt.hostname), 'rk3568');
      expect(p.ipOption(DhcpOpt.requestedIp), Ipv4.parse('192.168.50.150'));
      expect(p.parameterRequestList, [1, 3, 6]);
      expect(p.ciaddr, Ipv4.any);
    });

    test('짧은 패킷, 쿠키 없음, 잘린 옵션은 거부한다', () {
      expect(() => DhcpPacket.parse(Uint8List(100)), throwsA(isA<DhcpFormatException>()));

      final noCookie = _discover()..[236] = 0;
      expect(() => DhcpPacket.parse(noCookie), throwsA(isA<DhcpFormatException>()));

      final truncated = Uint8List.fromList(_discover().sublist(0, 244)); // 옵션 12의 길이 바이트가 없음
      expect(() => DhcpPacket.parse(truncated), throwsA(isA<DhcpFormatException>()));

      final badHlen = _discover()..[2] = 17;
      expect(() => DhcpPacket.parse(badHlen), throwsA(isA<DhcpFormatException>()));
    });

    test('END가 없어도 끝까지 읽고, END 뒤는 무시한다', () {
      final data = Uint8List.fromList([..._discover().sublist(0, 240), 53, 1, 1]);
      expect(DhcpPacket.parse(data).messageType, DhcpMessageType.discover);

      final withTrailing = _discover();
      withTrailing.setRange(240 + 25, 240 + 28, [53, 1, 9]); // END(255) 바로 뒤
      expect(DhcpPacket.parse(withTrailing).messageType, DhcpMessageType.discover);
    });
  });

  group('생성', () {
    test('파싱한 패킷을 다시 만들어도 같다', () {
      final original = DhcpPacket.parse(_discover());
      final again = DhcpPacket.parse(original.toBytes());
      expect(again.xid, original.xid);
      expect(again.clientMac, original.clientMac);
      expect(again.options.keys.toList(), original.options.keys.toList());
      expect(again.stringOption(DhcpOpt.hostname), 'rk3568');
      expect(again.flags, original.flags);
    });

    test('최소 300바이트로 채우고 쿠키와 END를 넣는다', () {
      final bytes = DhcpPacket(op: DhcpOp.reply, xid: 1, chaddr: Uint8List(6)).toBytes();
      expect(bytes.length, 300);
      expect(bytes.sublist(236, 240), [0x63, 0x82, 0x53, 0x63]);
      expect(bytes[240], 255);
    });

    test('옵션이 많으면 300바이트를 넘겨도 자르지 않는다', () {
      final p = DhcpPacket(op: DhcpOp.reply, xid: 1, chaddr: Uint8List(6), options: {
        DhcpOpt.bootfileName: DhcpValue.string('a' * 200),
        DhcpOpt.tftpServerName: DhcpValue.string('b' * 200),
      });
      final bytes = p.toBytes();
      expect(bytes.length, greaterThan(300));
      final parsed = DhcpPacket.parse(bytes);
      expect(parsed.stringOption(DhcpOpt.bootfileName), 'a' * 200);
      expect(parsed.stringOption(DhcpOpt.tftpServerName), 'b' * 200);
    });

    test('255바이트가 넘는 옵션은 거부한다', () {
      final p = DhcpPacket(op: DhcpOp.reply, xid: 1, chaddr: Uint8List(6), options: {
        DhcpOpt.message: Uint8List(256),
      });
      expect(p.toBytes, throwsA(isA<DhcpFormatException>()));
    });

    test('sname과 file은 0으로 끝나는 문자열로 쓴다', () {
      final p = DhcpPacket(op: DhcpOp.reply, xid: 1, chaddr: Uint8List(6), sname: '192.168.50.1', file: 'boot/u-boot.bin');
      final parsed = DhcpPacket.parse(p.toBytes());
      expect(parsed.sname, '192.168.50.1');
      expect(parsed.file, 'boot/u-boot.bin');
    });
  });

  group('응답 틀', () {
    test('OFFER는 xid·flags·giaddr·chaddr을 요청에서 가져온다', () {
      final request = DhcpPacket.parse(_discover());
      final offer = DhcpPacket.replyTo(
        request,
        type: DhcpMessageType.offer,
        yiaddr: Ipv4.parse('192.168.50.150'),
        options: {
          DhcpOpt.serverId: DhcpValue.ip(Ipv4.parse('192.168.50.1')),
          DhcpOpt.leaseTime: DhcpValue.u32(3600),
          DhcpOpt.subnetMask: DhcpValue.ip(Ipv4.parse('255.255.255.0')),
          DhcpOpt.dnsServers: DhcpValue.ips([Ipv4.parse('8.8.8.8'), Ipv4.parse('8.8.4.4')]),
        },
      );
      final parsed = DhcpPacket.parse(offer.toBytes());
      expect(parsed.op, DhcpOp.reply);
      expect(parsed.xid, request.xid);
      expect(parsed.flags, request.flags);
      expect(parsed.clientMac, request.clientMac);
      expect(parsed.yiaddr, Ipv4.parse('192.168.50.150'));
      expect(parsed.messageType, DhcpMessageType.offer);
      expect(parsed.options.keys.first, DhcpOpt.messageType); // 메시지 종류가 맨 앞
      expect(parsed.ipOption(DhcpOpt.serverId), Ipv4.parse('192.168.50.1'));
      expect(parsed.u32Option(DhcpOpt.leaseTime), 3600);
      expect(parsed.ipListOption(DhcpOpt.dnsServers), [Ipv4.parse('8.8.8.8'), Ipv4.parse('8.8.4.4')]);
    });

    test('종류 이름', () {
      expect(DhcpMessageType.name(DhcpMessageType.ack), 'ACK');
      expect(DhcpMessageType.name(null), 'UNKNOWN');
    });

    test('16진수 덤프는 16바이트씩 줄을 나눈다', () {
      final dump = DhcpPacket.hexDump(Uint8List.fromList(List.generate(20, (i) => i)));
      expect(dump.split('\n'), ['00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f', '10 11 12 13']);
    });
  });
}
