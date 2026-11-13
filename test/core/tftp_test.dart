// TFTP 서버를 실제 UDP loopback으로 시험한다 (소켓·파일은 가짜가 아니다).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/service.dart';
import 'package:lab_daemon/core/tftp/config.dart';
import 'package:lab_daemon/core/tftp/netascii.dart';
import 'package:lab_daemon/core/tftp/packet.dart';
import 'package:lab_daemon/core/tftp/server.dart';
import 'package:lab_daemon/core/tftp/transfer.dart';

import '../support/tftp_client.dart';

Uint8List _bytes(int n, {int seed = 7}) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  group('패킷', () {
    test('RRQ 옵션을 읽고 소문자로 바꾼다', () {
      final request = parseRequest(buildRequest(write: false, filename: 'boot/u-boot.bin', mode: 'OCTET', options: {'BlkSize': '1428', 'tsize': '0'}))!;
      expect(request.write, isFalse);
      expect(request.filename, 'boot/u-boot.bin');
      expect(request.mode, 'octet');
      expect(request.options, {'blksize': '1428', 'tsize': '0'});
    });

    test('깨진 요청은 null', () {
      expect(parseRequest(Uint8List.fromList([0, 1, 0x61, 0])), isNull, reason: '모드 없음');
      expect(parseRequest(Uint8List.fromList([0, 1, 0x61, 0, 0x6f])), isNull, reason: '\\0으로 끝나지 않음');
      expect(parseRequest(Uint8List.fromList([0, 3, 0, 1, 0x61, 0, 0x6f, 0])), isNull, reason: 'RRQ/WRQ가 아님');
      expect(parseRequest(buildRequest(write: false, filename: '', mode: 'octet')), isNull, reason: '빈 파일 이름');
      expect(parseRequest(Uint8List.fromList([0, 1, 0x61, 0, 0x6f, 0, 0x62, 0])), isNull, reason: '값 없는 옵션');
    });

    test('DATA·ACK·ERROR·OACK를 만들고 읽는다', () {
      final data = buildData(0x1234, Uint8List.fromList([1, 2, 3]));
      expect([tftpOpcode(data), tftpBlock(data)], [TftpOp.data, 0x1234]);
      expect(data.sublist(4), [1, 2, 3]);
      expect(buildData(65536, Uint8List(0))[2], 0, reason: '블록 번호는 2바이트로 돈다');
      expect(buildAck(7), [0, 4, 0, 7]);
      expect(parseError(buildError(TftpError.fileExists, 'File exists')), (6, 'File exists'));
      expect(parseOack(buildOack({'blksize': '1468', 'windowsize': '8'})), {'blksize': '1468', 'windowsize': '8'});
    });
  });

  group('netascii', () {
    test('보내기와 받기가 서로 되돌린다 (블록 경계에서 CR이 갈라져도)', () {
      final original = Uint8List.fromList('a\nb\r\nc\rd\n'.codeUnits);
      final encoded = NetasciiEncoder().convert(original);
      expect(encoded, 'a\r\nb\r\u0000\r\nc\r\u0000d\r\n'.codeUnits);

      for (var cut = 1; cut < encoded.length; cut++) {
        final decoder = NetasciiDecoder();
        final out = BytesBuilder()
          ..add(decoder.convert(Uint8List.sublistView(encoded, 0, cut)))
          ..add(decoder.convert(Uint8List.sublistView(encoded, cut)))
          ..add(decoder.finish());
        expect(out.toBytes(), original, reason: '$cut에서 자름');
      }
    });
  });

  group('서버', () {
    late Directory root;
    late TftpServer server;
    late List<LogEvent> logs;
    late List<TftpTransfersEvent> snapshots;

    TftpConfig config({bool write = false, bool overwrite = false, int maxBlock = 1468, int maxWindow = 8, int maxTransfers = 64, int timeoutMs = 300}) => TftpConfig(
          rootDir: root.path,
          bindAddress: Ipv4.parse('127.0.0.1'),
          port: 0,
          allowWrite: write,
          allowOverwrite: overwrite,
          maxBlockSize: maxBlock,
          maxWindowSize: maxWindow,
          maxTransfers: maxTransfers,
          timeoutMs: timeoutMs,
          maxRetries: 4,
        );

    Future<void> start([TftpConfig? c]) => server.start(c ?? config());

    setUp(() {
      root = Directory.systemTemp.createTempSync('tftp_test_');
      server = TftpServer(snapshotInterval: Duration.zero);
      logs = [];
      snapshots = [];
      server.events.listen((e) {
        if (e is LogEvent) logs.add(e);
        if (e is TftpTransfersEvent) snapshots.add(e);
      });
    });

    tearDown(() async {
      await server.dispose();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 80));

    group('읽기', () {
      test('작은 파일, 정확히 블록 배수인 파일(빈 마지막 블록), 빈 파일', () async {
        File('${root.path}/small.bin').writeAsBytesSync(_bytes(100));
        File('${root.path}/exact.bin').writeAsBytesSync(_bytes(1024));
        File('${root.path}/empty.bin').writeAsBytesSync(Uint8List(0));
        await start();
        for (final name in ['small.bin', 'exact.bin', 'empty.bin']) {
          final r = await tftpGet(port: server.boundPort!, file: name);
          expect(r.ok, isTrue, reason: '$name ${r.errorMessage}');
          expect(r.data, File('${root.path}/$name').readAsBytesSync(), reason: name);
        }
      });

      test('옵션을 협상한다: blksize는 서버 상한으로 줄고 tsize를 알려 준다', () async {
        final content = _bytes(10000);
        File('${root.path}/a.bin').writeAsBytesSync(content);
        await start(config(maxBlock: 1000));
        final r = await tftpGet(port: server.boundPort!, file: 'a.bin', options: {'blksize': '4096', 'tsize': '0'});
        expect(r.oack, {'blksize': '1000', 'tsize': '10000'});
        expect(r.data, content);
        expect(r.dataPackets, 11, reason: '10000 / 1000 = 10블록 + 빈 마지막 블록');
      });

      test('알아듣지 못하는 옵션·범위 밖 값은 협상에서 빼고 기본 512로 보낸다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(1500));
        await start();
        final r = await tftpGet(port: server.boundPort!, file: 'a.bin', options: {'blksize': '4', 'bogus': '1'});
        expect(r.oack, isEmpty);
        expect(r.dataPackets, 3);
        expect(r.ok, isTrue);
      });

      test('윈도우 전송: 같은 내용을 더 적은 ACK로 받는다', () async {
        final content = _bytes(200000, seed: 3);
        File('${root.path}/big.bin').writeAsBytesSync(content);
        await start();
        final single = await tftpGet(port: server.boundPort!, file: 'big.bin', options: {'blksize': '1468'});
        final windowed = await tftpGet(port: server.boundPort!, file: 'big.bin', options: {'blksize': '1468', 'windowsize': '8'});
        expect(single.data, content);
        expect(windowed.data, content);
        expect(windowed.oack['windowsize'], '8');
        expect(windowed.acks, lessThan(single.acks ~/ 4), reason: '윈도우 8이면 ACK가 8분의 1쯤');
      });

      test('윈도우는 서버 상한으로 줄어든다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(20000));
        await start(config(maxWindow: 4));
        final r = await tftpGet(port: server.boundPort!, file: 'a.bin', options: {'windowsize': '64'});
        expect(r.oack['windowsize'], '4');
      });

      test('블록 번호가 65535를 넘어 0으로 돌아도 이어진다 (작은 블록으로 큰 파일)', () async {
        final content = _bytes(70000 * 8 + 5, seed: 11);
        File('${root.path}/wrap.bin').writeAsBytesSync(content);
        await start();
        final r = await tftpGet(port: server.boundPort!, file: 'wrap.bin', options: {'blksize': '8', 'windowsize': '16'}, timeout: const Duration(seconds: 20));
        expect(r.ok, isTrue, reason: '${r.errorMessage} timedOut=${r.timedOut}');
        expect(r.data!.length, content.length);
        expect(r.data, content);
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('netascii로 받으면 줄 끝이 CR LF로 바뀌어 오고 클라이언트가 되돌린다', () async {
        final text = Uint8List.fromList('line1\nline2\r\nline3\n'.codeUnits);
        File('${root.path}/t.txt').writeAsBytesSync(text);
        await start();
        final r = await tftpGet(port: server.boundPort!, file: 't.txt', mode: 'netascii');
        expect(r.data, text);
      });

      test('하위 폴더 파일을 읽고, 백슬래시·앞 슬래시도 받아 준다', () async {
        Directory('${root.path}/sub').createSync();
        File('${root.path}/sub/x.bin').writeAsBytesSync(_bytes(700));
        await start();
        for (final name in ['sub/x.bin', '/sub/x.bin', r'sub\x.bin']) {
          expect((await tftpGet(port: server.boundPort!, file: name)).ok, isTrue, reason: name);
        }
      });

      test('데이터가 유실되면 재전송한다', () async {
        final content = _bytes(5000);
        File('${root.path}/a.bin').writeAsBytesSync(content);
        await start();
        final sw = Stopwatch()..start();
        final r = await tftpGet(port: server.boundPort!, file: 'a.bin', dropBlocks: {3});
        expect(r.data, content);
        expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(250), reason: '못 받은 블록은 재전송 시간(300ms)이 지나서야 다시 온다');
      });

      test('같은 요청이 재전송돼도 전송을 한 번만 만든다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(100));
        await start();
        final sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        final request = buildRequest(write: false, filename: 'a.bin');
        sock.send(request, InternetAddress.loopbackIPv4, server.boundPort!);
        sock.send(request, InternetAddress.loopbackIPv4, server.boundPort!);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(logs.where((l) => l.key == 'logTftpRrq'), hasLength(1));
        sock.close();
      });
    });

    group('접근 제어', () {
      test('없는 파일은 오류 1', () async {
        await start();
        final r = await tftpGet(port: server.boundPort!, file: 'nope.bin');
        expect(r.errorCode, TftpError.notFound);
        await idle();
        expect(logs.where((l) => l.key == 'logTftpFailed').single.args['reason'], 'notFound');
      });

      test('루트 밖으로 나가는 경로는 모두 오류 2이고 비밀 파일은 새지 않는다', () async {
        final secret = File('${root.parent.path}/tftp_secret_${root.path.hashCode}.txt')..writeAsStringSync('secret');
        addTearDown(() {
          try {
            secret.deleteSync();
          } catch (_) {}
        });
        await start();
        final name = secret.uri.pathSegments.last;
        for (final evil in ['../$name', '..\\$name', 'sub/../../$name', '/../$name', '%2e%2e/$name'.replaceAll('%2e', '.'), secret.path, 'C:\\Windows\\win.ini', 'a:b', 'con']) {
          final r = await tftpGet(port: server.boundPort!, file: evil);
          expect(r.errorCode, isIn([TftpError.accessViolation, TftpError.notFound]), reason: '$evil → ${r.errorCode}');
          expect(r.data, isNull, reason: evil);
        }
        // 이름 안의 NUL은 요청 형식 자체가 깨진 것이라 서버가 응답하지 않는다.
        final nul = await tftpGet(port: server.boundPort!, file: 'x\u0000y', timeout: const Duration(milliseconds: 400));
        expect(nul.data, isNull);
      });

      test('폴더를 읽으려 하면 오류', () async {
        Directory('${root.path}/dir').createSync();
        await start();
        expect((await tftpGet(port: server.boundPort!, file: 'dir')).errorCode, TftpError.notFound);
      });

      test('지원하지 않는 모드는 오류 4', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(10));
        await start();
        expect((await tftpGet(port: server.boundPort!, file: 'a.bin', mode: 'mail')).errorCode, TftpError.illegalOperation);
      });

      test('전송 도중 끼어든 다른 출처는 오류 5를 받고 전송은 계속된다', () async {
        final content = _bytes(20000);
        File('${root.path}/a.bin').writeAsBytesSync(content);
        await start();
        final intruder = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        Uint8List? reply;
        intruder.listen((e) {
          if (e == RawSocketEvent.read) reply = intruder.receive()?.data;
        });
        // 전송 소켓의 포트를 알아내려고 직접 RRQ를 보낸다.
        final client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        client.send(buildRequest(write: false, filename: 'a.bin'), InternetAddress.loopbackIPv4, server.boundPort!);
        Datagram? first;
        await for (final e in client) {
          if (e == RawSocketEvent.read) {
            first = client.receive();
            if (first != null) break;
          }
        }
        intruder.send(buildAck(1), InternetAddress.loopbackIPv4, first!.port);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(reply, isNotNull);
        expect(parseError(reply!)!.$1, TftpError.unknownTid);
        intruder.close();
        client.close();
      });

      test('69번 포트로 온 DATA는 오류 5', () async {
        await start();
        final sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        Uint8List? reply;
        sock.listen((e) {
          if (e == RawSocketEvent.read) reply = sock.receive()?.data;
        });
        sock.send(buildData(1, Uint8List(10)), InternetAddress.loopbackIPv4, server.boundPort!);
        await idle();
        expect(parseError(reply!)!.$1, TftpError.unknownTid);
        sock.close();
      });
    });

    group('쓰기', () {
      test('기본은 읽기 전용이라 거절한다 (오류 2)', () async {
        await start();
        final r = await tftpPut(port: server.boundPort!, file: 'up.bin', data: _bytes(100));
        expect(r.errorCode, TftpError.accessViolation);
        expect(File('${root.path}/up.bin').existsSync(), isFalse);
        await idle();
        expect(logs.where((l) => l.key == 'logTftpFailed').single.args['reason'], 'writeDisabled');
      });

      test('쓰기를 켜면 올릴 수 있다 (옵션·윈도우·큰 파일)', () async {
        await start(config(write: true));
        final content = _bytes(300000, seed: 5);
        final r = await tftpPut(port: server.boundPort!, file: 'up.bin', data: content, options: {'blksize': '1468', 'windowsize': '8', 'tsize': '${content.length}'});
        expect(r.ok, isTrue, reason: '${r.errorMessage}');
        expect(r.oack['windowsize'], '8');
        await idle();
        expect(File('${root.path}/up.bin').readAsBytesSync(), content);
        expect(root.listSync().map((e) => e.path.split(Platform.pathSeparator).last), ['up.bin'], reason: '임시 파일이 남지 않는다');
      });

      test('블록 배수 크기와 빈 파일도 올라간다', () async {
        await start(config(write: true));
        for (final n in [0, 512, 1024]) {
          final r = await tftpPut(port: server.boundPort!, file: 'n$n.bin', data: _bytes(n));
          expect(r.ok, isTrue, reason: '$n');
          await idle();
          expect(File('${root.path}/n$n.bin').lengthSync(), n);
        }
      });

      test('이미 있는 파일은 기본으로 덮어쓰지 않고(오류 6), 허용하면 덮어쓴다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(50, seed: 1));
        await start(config(write: true));
        final denied = await tftpPut(port: server.boundPort!, file: 'a.bin', data: _bytes(80, seed: 2));
        expect(denied.errorCode, TftpError.fileExists);
        expect(File('${root.path}/a.bin').lengthSync(), 50);
        await server.stop();

        await start(config(write: true, overwrite: true));
        final replacement = _bytes(80, seed: 2);
        expect((await tftpPut(port: server.boundPort!, file: 'a.bin', data: replacement)).ok, isTrue);
        await idle();
        expect(File('${root.path}/a.bin').readAsBytesSync(), replacement);
      });

      test('루트 밖·없는 폴더로는 올릴 수 없다', () async {
        await start(config(write: true));
        for (final evil in ['../evil.bin', 'nodir/x.bin']) {
          final r = await tftpPut(port: server.boundPort!, file: evil, data: _bytes(10));
          expect(r.errorCode, isNotNull, reason: evil);
        }
        expect(File('${root.parent.path}/evil.bin').existsSync(), isFalse);
      });

      test('ACK가 유실돼도 재전송으로 끝난다', () async {
        await start(config(write: true));
        final content = _bytes(5000);
        final r = await tftpPut(port: server.boundPort!, file: 'up.bin', data: content, timeout: const Duration(milliseconds: 600), dropAckOnce: {2});
        // 서버가 ACK를 다시 보내 주거나(서버 재전송 300ms) 클라이언트가 블록을 다시 보내서 끝난다.
        expect(r.ok, isTrue);
        await idle();
        expect(File('${root.path}/up.bin').readAsBytesSync(), content);
      });

      test('netascii로 올리면 줄 끝이 LF로 저장된다', () async {
        await start(config(write: true));
        final text = Uint8List.fromList('a\nb\r\nc\n'.codeUnits);
        expect((await tftpPut(port: server.boundPort!, file: 't.txt', data: text, mode: 'netascii')).ok, isTrue);
        await idle();
        expect(File('${root.path}/t.txt').readAsBytesSync(), text);
      });

      test('클라이언트가 중간에 사라지면 임시 파일을 지우고 기존 파일을 건드리지 않는다', () async {
        File('${root.path}/keep.bin').writeAsBytesSync(_bytes(30, seed: 9));
        await start(config(write: true, overwrite: true, timeoutMs: 100));
        final sock = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        Datagram? first;
        sock.send(buildRequest(write: true, filename: 'keep.bin'), InternetAddress.loopbackIPv4, server.boundPort!);
        await for (final e in sock) {
          if (e == RawSocketEvent.read) {
            first = sock.receive();
            if (first != null) break;
          }
        }
        sock.send(buildData(1, _bytes(512)), InternetAddress.loopbackIPv4, first!.port); // 첫 블록만 보내고 사라진다
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        sock.close();
        expect(File('${root.path}/keep.bin').lengthSync(), 30);
        expect(root.listSync().where((e) => e.path.contains('lab-part')), isEmpty);
        expect(logs.where((l) => l.key == 'logTftpFailed').last.args['reason'], 'timeout');
      });
    });

    group('동시 전송과 상태', () {
      test('여러 클라이언트가 동시에 받는다', () async {
        final content = _bytes(150000, seed: 21);
        File('${root.path}/big.bin').writeAsBytesSync(content);
        await start();
        final results = await Future.wait([
          for (var i = 0; i < 12; i++) tftpGet(port: server.boundPort!, file: 'big.bin', options: {'blksize': '1468', 'windowsize': '4'}),
        ]);
        for (final r in results) {
          expect(r.data, content);
        }
        await idle();
        expect(snapshots.last.completed, 12);
        expect(snapshots.last.bytesSent, 12 * content.length);
        expect(server.activeCount, 0);
      });

      test('전송 한도를 넘으면 "바쁨" 오류로 거절한다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(100));
        await start(config(maxTransfers: 1));
        // 첫 전송을 열어 둔 채(ACK하지 않음) 두 번째 요청을 보낸다.
        final holder = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        holder.send(buildRequest(write: false, filename: 'a.bin', options: {'blksize': '8'}), InternetAddress.loopbackIPv4, server.boundPort!);
        await idle();
        final r = await tftpGet(port: server.boundPort!, file: 'a.bin');
        expect(r.errorMessage, 'Server busy');
        expect(logs.where((l) => l.key == 'logTftpBusy'), hasLength(1));
        holder.close();
      });

      test('전송 목록과 합계가 스냅샷으로 나온다 (진행 중 → 완료)', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(4096));
        await start();
        expect((await tftpGet(port: server.boundPort!, file: 'a.bin')).ok, isTrue);
        await idle();
        final last = snapshots.last;
        expect(last.transfers, hasLength(1));
        final t = last.transfers.single;
        expect(t.state, TransferState.done);
        expect(t.file, 'a.bin');
        expect(t.upload, isFalse);
        expect(t.bytes, 4096);
        expect(t.size, 4096);
        expect(t.progress, 1.0);
        expect(last.completed, 1);
        expect(last.failed, 0);
        expect(logs.map((l) => l.key), containsAllInOrder(['logTftpStarted', 'logTftpRrq', 'logTftpSent']));
      });

      test('실패한 전송도 목록에 남고 실패 횟수가 늘어난다', () async {
        await start();
        await tftpGet(port: server.boundPort!, file: 'nope.bin');
        await idle();
        expect(snapshots.last.failed, 1);
        expect(snapshots.last.transfers.single.failure, 'notFound');
      });

      test('abort 명령은 진행 중인 전송을 중단한다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(5000));
        await start();
        final holder = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        holder.send(buildRequest(write: false, filename: 'a.bin', options: {'blksize': '8'}), InternetAddress.loopbackIPv4, server.boundPort!);
        await idle();
        expect(server.activeCount, 1);
        final id = snapshots.last.transfers.first.id;
        expect(await server.command('abort', {'id': id}), isTrue);
        await idle();
        expect(server.activeCount, 0);
        expect(logs.where((l) => l.key == 'logTftpFailed').single.args['reason'], 'aborted');
        expect(await server.command('abort', {'id': 999}), isFalse);
        holder.close();
      });

      test('중지하면 진행 중인 전송을 정리하고 소켓을 닫는다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(5000));
        await start();
        final port = server.boundPort!;
        final holder = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        holder.send(buildRequest(write: false, filename: 'a.bin', options: {'blksize': '8'}), InternetAddress.loopbackIPv4, port);
        await idle();
        await server.stop();
        expect(server.state, ServiceState.stopped);
        expect(server.activeCount, 0);
        // 같은 포트를 다시 열 수 있어야 한다.
        final again = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, port);
        again.close();
        holder.close();
      });
    });

    group('시작', () {
      test('루트 폴더가 없으면 시작하지 못한다', () async {
        await expectLater(
          server.start(TftpConfig(rootDir: '${root.path}/missing', bindAddress: Ipv4.parse('127.0.0.1'), port: 0)),
          throwsA(isA<TftpConfigException>()),
        );
        expect(server.state, ServiceState.error);
      });

      test('같은 포트를 두 번 열면 "포트 사용 중" 로그와 함께 실패한다', () async {
        await start();
        final second = TftpServer(snapshotInterval: Duration.zero);
        final secondLogs = <LogEvent>[];
        second.events.listen((e) {
          if (e is LogEvent) secondLogs.add(e);
        });
        await expectLater(second.start(TftpConfig(rootDir: root.path, bindAddress: Ipv4.parse('127.0.0.1'), port: server.boundPort!)), throwsA(isA<SocketException>()));
        expect(secondLogs.map((l) => l.key), contains('logTftpPortInUse'));
        await second.dispose();
      });

      test('설정 JSON이 왕복한다', () {
        final c = config(write: true, overwrite: true, maxBlock: 4096, maxWindow: 16);
        final again = TftpConfig.fromJson(c.toJson());
        expect(again.toJson(), c.toJson());
        expect(() => TftpConfig.fromJson({'rootDir': 3}), throwsFormatException);
        expect(() => TftpConfig(rootDir: root.path, maxBlockSize: 4).validate(), throwsA(isA<TftpConfigException>()));
        expect(() => TftpConfig(rootDir: root.path, maxWindowSize: 0).validate(), throwsA(isA<TftpConfigException>()));
      });
    });

    test('처리량: 20MB를 윈도우 8로 받는다 (성능 점검)', () async {
      final content = _bytes(20 * 1024 * 1024, seed: 33);
      File('${root.path}/20m.bin').writeAsBytesSync(content);
      await start();
      final sw = Stopwatch()..start();
      final r = await tftpGet(port: server.boundPort!, file: '20m.bin', options: {'blksize': '1468', 'windowsize': '8'}, timeout: const Duration(seconds: 20));
      sw.stop();
      expect(r.ok, isTrue, reason: '${r.errorMessage}');
      expect(r.data, content);
      final mbps = content.length / 1024 / 1024 / (sw.elapsedMilliseconds / 1000);
      // ignore: avoid_print
      print('TFTP loopback 20MB: ${sw.elapsedMilliseconds} ms (${mbps.toStringAsFixed(1)} MB/s)');
      expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
