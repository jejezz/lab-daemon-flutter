// FTP 서버를 실제 TCP loopback으로 시험한다 (소켓·파일은 가짜가 아니다).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/ftp/config.dart';
import 'package:lab_daemon/core/ftp/server.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/service.dart';

import '../support/ftp_client.dart';

Uint8List _bytes(int n, {int seed = 7}) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

void main() {
  group('계정', () {
    test('비밀번호는 솔트+해시로만 저장하고 확인한다', () {
      final a = FtpAccount.create('board', 's3cret');
      expect(a.toJson().values, isNot(contains('s3cret')));
      expect(a.salt, hasLength(32));
      expect(a.verify('s3cret'), isTrue);
      expect(a.verify('S3cret'), isFalse);
      expect(a.verify(''), isFalse);
      final b = FtpAccount.create('board', 's3cret');
      expect(b.hash, isNot(a.hash), reason: '솔트가 달라서 같은 비밀번호도 해시가 다르다');
      expect(FtpAccount.fromJson(a.toJson()).verify('s3cret'), isTrue);
    });
  });

  group('설정', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('ftp_cfg_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('JSON이 왕복하고 잘못된 값은 거부한다', () {
      final c = FtpConfig(rootDir: root.path, account: FtpAccount.create('u', 'p'), passivePortStart: 51000, passivePortEnd: 51010);
      expect(FtpConfig.fromJson(c.toJson()).toJson(), c.toJson());
      expect(() => FtpConfig(rootDir: root.path).validate(), throwsA(isA<FtpConfigException>()), reason: '로그인 방법이 없음');
      expect(() => FtpConfig(rootDir: root.path, allowAnonymous: true, passivePortStart: 100).validate(), throwsA(isA<FtpConfigException>()));
      expect(() => FtpConfig(rootDir: '${root.path}/none', allowAnonymous: true).validate(), throwsA(isA<FtpConfigException>()));
      FtpConfig(rootDir: root.path, allowAnonymous: true).validate();
    });
  });

  group('서버', () {
    late Directory root;
    late FtpServer server;
    late List<LogEvent> logs;
    late List<FtpSessionsEvent> snapshots;
    final clients = <FtpTestClient>[];
    // Windows 동적 포트 범위(49152~)는 Hyper-V 등이 예약해서 막혀 있을 수 있다: 그 밖에서 고른다.
    var passiveBase = 41000 + Random().nextInt(4000);

    FtpConfig config({bool anonymous = false, bool write = false, int maxConnections = 32, int idle = 60}) {
      passiveBase += 40;
      return FtpConfig(
        rootDir: root.path,
        bindAddress: Ipv4.parse('127.0.0.1'),
        port: 0,
        passivePortStart: passiveBase,
        passivePortEnd: passiveBase + 30,
        account: FtpAccount.create('board', 'pw'),
        allowAnonymous: anonymous,
        allowWrite: write,
        maxConnections: maxConnections,
        idleTimeoutSeconds: idle,
      );
    }

    Future<FtpTestClient> client() async {
      final c = await FtpTestClient.connect(server.boundPort!);
      clients.add(c);
      return c;
    }

    Future<FtpTestClient> loggedIn(String user, String pw) async {
      final c = await client();
      final r = await c.login(user, pw);
      expect(r.code, 230, reason: '$r');
      return c;
    }

    setUp(() async {
      root = Directory.systemTemp.createTempSync('ftp_test_');
      server = FtpServer(snapshotInterval: Duration.zero);
      logs = [];
      snapshots = [];
      server.events.listen((e) {
        if (e is LogEvent) logs.add(e);
        if (e is FtpSessionsEvent) snapshots.add(e);
      });
    });

    tearDown(() async {
      for (final c in clients) {
        await c.close();
      }
      clients.clear();
      await server.dispose();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 120));

    group('로그인', () {
      test('계정으로 로그인하고, 틀린 비밀번호는 530', () async {
        await server.start(config());
        await loggedIn('board', 'pw');
        final bad = await client();
        expect((await bad.login('board', 'wrong')).code, 530);
        await idle();
        expect(logs.map((l) => l.key), containsAll(['logFtpLogin', 'logFtpLoginFailed']));
        expect(logs.firstWhere((l) => l.key == 'logFtpLogin').args, {'client': isA<String>(), 'user': 'board', 'write': false});
      });

      test('없는 사용자도 같은 530 (사용자가 있는지 알려 주지 않는다)', () async {
        await server.start(config());
        final c = await client();
        await c.reply();
        expect((await c.cmd('USER nobody')).code, 331);
        expect((await c.cmd('PASS x')).code, 530);
      });

      test('익명 + 쓰기 허용이면 익명도 올릴 수 있다', () async {
        await server.start(config(anonymous: true, write: true));
        final a = await loggedIn('anonymous', 'x');
        expect((await a.upload('STOR anon.bin', _bytes(10))).$2.code, 226);
        expect(File('${root.path}/anon.bin').lengthSync(), 10);
      });

      test('계정 없이 익명만 켠 설정도 되고, 비밀번호가 맞아도 다른 사용자 이름은 530', () async {
        final c = config(anonymous: true);
        await server.start(FtpConfig(
          rootDir: root.path,
          bindAddress: Ipv4.parse('127.0.0.1'),
          port: 0,
          allowAnonymous: true,
          passivePortStart: c.passivePortStart,
          passivePortEnd: c.passivePortEnd,
        ));
        expect((await (await client()).login('board', 'pw')).code, 530);
        await loggedIn('ftp', 'guest');
        await server.stop();

        await server.start(config());
        expect((await (await client()).login('someone', 'pw')).code, 530);
      });

      test('세 번 틀리면 연결을 끊는다', () async {
        await server.start(config());
        final c = await client();
        await c.reply();
        for (var i = 0; i < 3; i++) {
          await c.cmd('USER board');
          await c.cmd('PASS nope');
        }
        expect((await c.reply()).code, 421);
        await idle();
        expect(c.closed, isTrue);
      }, timeout: const Timeout(Duration(seconds: 20)));

      test('익명 접속은 기본으로 막혀 있고, 켜면 받을 수 있다 (쓰기 허용이 꺼져 있으면 읽기만)', () async {
        await server.start(config());
        final c = await client();
        expect((await c.login('anonymous', 'me@x')).code, 530);
        await server.stop();

        File('${root.path}/pub.txt').writeAsStringSync('hello');
        await server.start(config(anonymous: true));
        final a = await loggedIn('anonymous', 'me@x');
        final (data, _, end) = await a.download('RETR pub.txt');
        expect(utf8.decode(data!), 'hello');
        expect(end.code, 226);
        final (opening, _) = await a.upload('STOR x.txt', _bytes(10));
        expect(opening.code, 550);
      });

      test('로그인 전에는 파일 명령을 거부한다', () async {
        await server.start(config());
        final c = await client();
        await c.reply();
        for (final cmd in ['PWD', 'LIST', 'RETR a', 'CWD /', 'PASV']) {
          expect((await c.cmd(cmd)).code, 530, reason: cmd);
        }
        expect((await c.cmd('SYST')).code, 215);
        expect((await c.cmd('FEAT')).text, contains('EPSV'));
      });
    });

    group('탐색', () {
      test('PWD·CWD·CDUP: 루트 위로는 올라가지 못한다', () async {
        Directory('${root.path}/a/b').createSync(recursive: true);
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('PWD')).text, contains('"/"'));
        expect((await c.cmd('CWD a/b')).code, 250);
        expect((await c.cmd('PWD')).text, contains('"/a/b"'));
        expect((await c.cmd('CDUP')).code, 250);
        expect((await c.cmd('PWD')).text, contains('"/a"'));
        expect((await c.cmd('CWD ../../../..')).code, 250);
        expect((await c.cmd('PWD')).text, contains('"/"'), reason: '루트에서 멈춘다');
        expect((await c.cmd('CWD nope')).code, 550);
        expect((await c.cmd(r'CWD a\b')).code, 250, reason: '백슬래시도 구분자');
      });

      test('LIST·NLST·MLSD가 루트의 내용만 보여 준다 (올리는 중인 임시 파일은 숨긴다)', () async {
        Directory('${root.path}/dir').createSync();
        File('${root.path}/file.bin').writeAsBytesSync(_bytes(1234));
        File('${root.path}/half.bin.lab-part-1').writeAsBytesSync(_bytes(5));
        await server.start(config());
        final c = await loggedIn('board', 'pw');

        final (list, _, end) = await c.download('LIST -la');
        expect(end.code, 226);
        final text = utf8.decode(list!);
        expect(text, contains('file.bin'));
        expect(text, contains(RegExp(r'^d.* dir\r?$', multiLine: true)));
        expect(text, contains(RegExp(r'^-.*1234 .* file\.bin', multiLine: true)));
        expect(text, isNot(contains('lab-part')));

        final (names, _, _) = await c.download('NLST');
        expect(const LineSplitter().convert(utf8.decode(names!)), ['dir', 'file.bin']);

        final (mlsd, _, _) = await c.download('MLSD', extended: true);
        expect(utf8.decode(mlsd!), contains('type=file;size=1234;'));
        expect(utf8.decode(mlsd), contains('type=dir;'));
      });

      test('SIZE·MDTM', () async {
        File('${root.path}/f.bin').writeAsBytesSync(_bytes(77));
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect(await c.cmd('SIZE f.bin'), isA<FtpReply>().having((r) => '${r.code} ${r.text}', 'reply', '213 77'));
        expect((await c.cmd('MDTM f.bin')).text, matches(RegExp(r'^\d{14}$')));
        expect((await c.cmd('SIZE nope')).code, 550);
      });
    });

    group('받기', () {
      test('RETR가 내용을 그대로 보낸다 (PASV·EPSV)', () async {
        final content = _bytes(300000);
        File('${root.path}/a.bin').writeAsBytesSync(content);
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('TYPE I')).code, 200);
        final (data, opening, end) = await c.download('RETR a.bin');
        expect(opening.code, 150);
        expect(end.code, 226);
        expect(data, content);
        final (again, _, _) = await c.download('RETR /a.bin', extended: true);
        expect(again, content);
        await idle();
        expect(logs.where((l) => l.key == 'logFtpDownload'), hasLength(2));
      });

      test('REST로 이어 받는다', () async {
        final content = _bytes(10000);
        File('${root.path}/a.bin').writeAsBytesSync(content);
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('REST 4000')).code, 350);
        final (data, _, _) = await c.download('RETR a.bin');
        expect(data, content.sublist(4000));
      });

      test('없는 파일·폴더는 550, 데이터 연결 준비 없이 RETR하면 425', () async {
        Directory('${root.path}/d').createSync();
        File('${root.path}/x').writeAsStringSync('x');
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('RETR nope')).code, 550);
        expect((await c.cmd('RETR d')).code, 550);
        expect((await c.cmd('RETR x')).code, 425);
      });

      test('처리량: 50MB를 내려받는다 (성능 점검)', () async {
        final content = _bytes(50 * 1024 * 1024, seed: 9);
        File('${root.path}/big.bin').writeAsBytesSync(content);
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        final sw = Stopwatch()..start();
        final (data, _, end) = await c.download('RETR big.bin');
        sw.stop();
        expect(end.code, 226);
        expect(data!.length, content.length);
        expect(data, content);
        // ignore: avoid_print
        print('FTP loopback 50MB: ${sw.elapsedMilliseconds} ms (${(50 / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} MB/s)');
      }, timeout: const Timeout(Duration(seconds: 120)));
    });

    group('쓰기', () {
      test('쓰기 허용이 꺼져 있으면 쓰기 명령이 모두 550', () async {
        File('${root.path}/a.txt').writeAsStringSync('a');
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.upload('STOR new.bin', _bytes(10))).$1.code, 550);
        for (final cmd in ['DELE a.txt', 'MKD d', 'RMD d', 'RNFR a.txt', 'APPE a.txt']) {
          expect((await c.cmd(cmd)).code, 550, reason: cmd);
        }
        expect(File('${root.path}/new.bin').existsSync(), isFalse);
        await idle();
        expect(logs.where((l) => l.key == 'logFtpDenied').length, greaterThanOrEqualTo(5));
      });

      test('쓰기 허용을 켜면 올리고(임시 파일 없이 남음) 이어 붙이고 이름을 바꾸고 지운다', () async {
        await server.start(config(write: true));
        final c = await loggedIn('board', 'pw');
        final content = _bytes(200000, seed: 4);
        final (opening, end) = await c.upload('STOR up.bin', content);
        expect([opening.code, end.code], [150, 226]);
        expect(File('${root.path}/up.bin').readAsBytesSync(), content);
        expect(root.listSync().where((e) => e.path.contains('lab-part')), isEmpty);

        final more = _bytes(500, seed: 5);
        await c.upload('APPE up.bin', more);
        expect(File('${root.path}/up.bin').lengthSync(), content.length + more.length);

        expect((await c.cmd('MKD sub')).code, 257);
        expect((await c.cmd('RNFR up.bin')).code, 350);
        expect((await c.cmd('RNTO sub/moved.bin')).code, 250);
        expect(File('${root.path}/sub/moved.bin').existsSync(), isTrue);
        expect((await c.cmd('RMD sub')).code, 550, reason: '비어 있지 않은 폴더는 지우지 않는다');
        expect((await c.cmd('DELE sub/moved.bin')).code, 250);
        expect((await c.cmd('RMD sub')).code, 250);
        await idle();
        expect(logs.map((l) => l.key), containsAll(['logFtpUpload', 'logFtpMkdir', 'logFtpRenamed', 'logFtpDeleted', 'logFtpRmdir']));
      });

      test('REST + STOR는 파일 끝에서 이어 올릴 때만 받는다', () async {
        File('${root.path}/p.bin').writeAsBytesSync(_bytes(100));
        await server.start(config(write: true));
        final c = await loggedIn('board', 'pw');
        await c.cmd('REST 50');
        expect((await c.upload('STOR p.bin', _bytes(10))).$1.code, 554);
        await c.cmd('REST 100');
        expect((await c.upload('STOR p.bin', _bytes(10))).$2.code, 226);
        expect(File('${root.path}/p.bin').lengthSync(), 110);
      });

      test('RNTO 대상이 이미 있으면 553, RNFR 없이 RNTO는 503', () async {
        File('${root.path}/a').writeAsStringSync('a');
        File('${root.path}/b').writeAsStringSync('b');
        await server.start(config(write: true));
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('RNTO c')).code, 503);
        await c.cmd('RNFR a');
        expect((await c.cmd('RNTO b')).code, 553);
      });
    });

    group('보안', () {
      test('경로 탈출은 루트 안에 갇힌다', () async {
        final secret = File('${root.parent.path}/ftp_secret_${root.path.hashCode}.txt')..writeAsStringSync('secret');
        addTearDown(() {
          try {
            secret.deleteSync();
          } catch (_) {}
        });
        File('${root.path}/inside.txt').writeAsStringSync('inside');
        await server.start(config(write: true));
        final c = await loggedIn('board', 'pw');
        final name = secret.uri.pathSegments.last;
        for (final evil in ['../$name', '/../$name', r'..\' + name, 'C:$name', secret.path]) {
          final r = await c.cmd('SIZE $evil');
          expect(r.code, 550, reason: evil);
        }
        // `..`은 루트에서 멈추므로 ../inside.txt는 루트의 inside.txt다.
        expect((await c.cmd('SIZE ../inside.txt')).text, '6');
        expect((await c.cmd('DELE ../$name')).code, 550);
        expect(secret.existsSync(), isTrue);
      });

      test('PORT·EPRT는 제어 연결의 주소로만 연결한다 (FTP bounce 방지)', () async {
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('PORT 10,1,2,3,200,10')).code, 500);
        expect((await c.cmd('EPRT |1|10.1.2.3|51234|')).code, 500);
        expect((await c.cmd('PORT 127,0,0,1,0,80')).code, 500, reason: '특권 포트');
        expect((await c.cmd('EPRT |2|::1|51234|')).code, 522);
        expect((await c.cmd('PORT 127,0,0,1,200,10')).code, 200);
      });

      test('액티브 모드(PORT)로 받는다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(5000));
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = listener.port;
        final received = BytesBuilder();
        final got = listener.first.then((s) => s.listen(received.add).asFuture<void>());
        expect((await c.cmd('PORT 127,0,0,1,${port >> 8},${port & 0xFF}')).code, 200);
        expect((await c.cmd('RETR a.bin')).code, 150);
        await got;
        expect((await c.reply()).code, 226);
        expect(received.length, 5000);
        await listener.close();
      });

      test('알 수 없는 명령은 502, TLS는 지원하지 않는다고 답한다', () async {
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        expect((await c.cmd('XYZZY')).code, 502);
        expect((await c.cmd('AUTH TLS')).code, 502);
      });
    });

    group('연결 관리와 상태', () {
      test('동시 연결 한도를 넘으면 421', () async {
        await server.start(config(maxConnections: 2));
        await loggedIn('board', 'pw');
        await loggedIn('board', 'pw');
        final third = await client();
        expect((await third.reply()).code, 421);
        await idle();
        expect(logs.where((l) => l.key == 'logFtpTooMany'), hasLength(1));
      });

      test('명령이 없으면 끊는다 (유휴 시간 초과)', () async {
        await server.start(config(idle: 1));
        final c = await loggedIn('board', 'pw');
        expect((await c.reply(timeout: const Duration(seconds: 3))).code, 421);
        await idle();
        expect(logs.map((l) => l.key), contains('logFtpIdleTimeout'));
      }, timeout: const Timeout(Duration(seconds: 15)));

      test('세션 목록에 사용자·폴더·바이트 수가 나오고 끊으면 최근 목록으로 간다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(4000));
        Directory('${root.path}/sub').createSync();
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        await c.cmd('CWD sub');
        await c.cmd('CWD /');
        await c.download('RETR a.bin');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final open = snapshots.last.sessions.single;
        expect(open.user, 'board');
        expect(open.authenticated, isTrue);
        expect(open.cwd, '/');
        expect(open.bytesOut, 4000);
        expect(open.filesOut, 1);
        expect(open.closed, isFalse);
        expect(snapshots.last.openCount, 1);

        expect((await c.cmd('QUIT')).code, 221);
        await idle();
        final last = snapshots.last;
        expect(last.openCount, 0);
        expect(last.sessions.single.closed, isTrue);
        expect(last.totalConnections, 1);
        expect(last.bytesOut, 4000);
        expect(logs.map((l) => l.key), containsAllInOrder(['logFtpStarted', 'logFtpConnected', 'logFtpLogin', 'logFtpDownload', 'logFtpDisconnected']));
      });

      test('PASS 인자는 세션 표시에서 가린다', () async {
        await server.start(config());
        final c = await client();
        await c.reply();
        await c.cmd('USER board');
        await c.cmd('PASS pw');
        await Future<void>.delayed(const Duration(milliseconds: 400)); // 표는 250ms마다 갱신된다
        expect(snapshots.last.sessions.single.lastCommand, 'PASS ****');
      });

      test('disconnect 명령으로 세션을 끊는다', () async {
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        await idle();
        final id = snapshots.last.sessions.single.id;
        expect(await server.command('disconnect', {'id': id}), isTrue);
        expect((await c.reply()).code, 421);
        await idle();
        expect(server.sessionCount, 0);
      });

      test('여러 클라이언트가 동시에 받는다', () async {
        final content = _bytes(400000, seed: 12);
        File('${root.path}/a.bin').writeAsBytesSync(content);
        await server.start(config());
        final sessions = await Future.wait([for (var i = 0; i < 6; i++) loggedIn('board', 'pw')]);
        final results = await Future.wait([for (final s in sessions) s.download('RETR a.bin')]);
        for (final (data, _, end) in results) {
          expect(end.code, 226);
          expect(data, content);
        }
      });

      test('중지하면 세션에 421을 보내고 닫는다', () async {
        await server.start(config());
        final c = await loggedIn('board', 'pw');
        await server.stop();
        expect((await c.reply()).code, 421);
        expect(server.state, ServiceState.stopped);
      });

      test('같은 포트를 두 번 열면 "포트 사용 중" 로그와 함께 실패한다', () async {
        await server.start(config());
        final second = FtpServer(snapshotInterval: Duration.zero);
        final secondLogs = <LogEvent>[];
        second.events.listen((e) {
          if (e is LogEvent) secondLogs.add(e);
        });
        final c = config();
        await expectLater(
          second.start(FtpConfig(rootDir: root.path, bindAddress: Ipv4.parse('127.0.0.1'), port: server.boundPort!, allowAnonymous: true, passivePortStart: c.passivePortStart, passivePortEnd: c.passivePortEnd)),
          throwsA(isA<SocketException>()),
        );
        expect(secondLogs.map((l) => l.key), contains('logFtpPortInUse'));
        await second.dispose();
      });
    });
  });
}
