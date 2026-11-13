// 실제 앱처럼 서비스를 별도 Isolate(IsolateHost)에서 돌린다: 설정 JSON이 건너가고, 소켓이 서비스 Isolate에서 열리고,
// 전송·세션 스냅샷과 로그가 화면 쪽으로 돌아오는지 확인한다.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/server.dart';
import 'package:lab_daemon/core/ftp/config.dart';
import 'package:lab_daemon/core/ftp/server.dart';
import 'package:lab_daemon/core/host.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/service.dart';
import 'package:lab_daemon/core/tftp/config.dart';
import 'package:lab_daemon/core/tftp/server.dart';
import 'package:lab_daemon/core/tftp/transfer.dart';

import '../support/ftp_client.dart';
import '../support/tftp_client.dart';

Future<int> _freeUdp() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  s.close();
  return p;
}

Future<int> _freeTcp() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  await s.close();
  return p;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('iso_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('TFTP를 서비스 Isolate에서 돌리고 전송 목록과 로그를 받는다', () async {
    final content = Uint8List.fromList(List.generate(100000, (i) => i % 253));
    File('${root.path}/a.bin').writeAsBytesSync(content);
    final port = await _freeUdp();
    final host = IsolateHost('tftp', createTftpService);
    addTearDown(host.dispose);
    final events = <ServiceEvent>[];
    host.events.listen(events.add);

    await host.start(TftpConfig(rootDir: root.path, bindAddress: Ipv4.parse('127.0.0.1'), port: port).toJson());
    expect(host.state, ServiceState.running);
    final r = await tftpGet(port: port, file: 'a.bin', options: {'blksize': '1468', 'windowsize': '8'});
    expect(r.data, content);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final snapshot = events.whereType<TftpTransfersEvent>().last;
    expect(snapshot.completed, 1);
    expect(snapshot.transfers.single.state, TransferState.done);
    expect(snapshot.transfers.single.bytes, content.length);
    expect(events.whereType<LogEvent>().map((e) => e.key), containsAll(['logTftpStarted', 'logTftpRrq', 'logTftpSent']));
    expect(await host.command('abort', {'id': 999}), isFalse);
    await host.stop();
    expect(host.state, ServiceState.stopped);
  });

  test('FTP를 서비스 Isolate에서 돌리고 세션 목록을 받는다', () async {
    final port = await _freeTcp();
    final host = IsolateHost('ftp', createFtpService);
    addTearDown(host.dispose);
    final events = <ServiceEvent>[];
    host.events.listen(events.add);

    await host.start(FtpConfig(
      rootDir: root.path,
      bindAddress: Ipv4.parse('127.0.0.1'),
      port: port,
      account: FtpAccount.create('board', 'pw'),
      passivePortStart: 43000,
      passivePortEnd: 43050,
    ).toJson());
    final c = await FtpTestClient.connect(port);
    expect((await c.login('board', 'pw')).code, 230);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final sessions = events.whereType<FtpSessionsEvent>().last;
    expect(sessions.sessions.single.user, 'board');
    await c.close();
    await host.stop();
  });

  test('DHCP 설정 JSON이 서비스 Isolate로 건너가고 잘못된 설정은 시작 실패로 돌아온다', () async {
    final host = IsolateHost('dhcp', createDhcpService);
    addTearDown(host.dispose);
    await expectLater(
      host.start({'serverIp': '10.0.0.1', 'rangeStart': '192.168.50.100', 'rangeEnd': '192.168.50.110', 'mask': '255.255.255.0'}),
      throwsA(isA<ServiceStartException>()),
    );
    expect(host.state, ServiceState.error);
  });
}
