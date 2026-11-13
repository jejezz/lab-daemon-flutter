// HTTP 파일 서버를 실제 TCP loopback으로 시험한다 (소켓·파일은 가짜가 아니다).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/http/config.dart';
import 'package:lab_daemon/core/http/server.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/service.dart';

Uint8List _bytes(int n, {int seed = 7}) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

class _Reply {
  _Reply(this.status, this.headers, this.body);

  final int status;
  final Map<String, String> headers;
  final List<int> body;

  String get text => utf8.decode(body);
}

void main() {
  group('Range 해석', () {
    test('범위 · 열린 끝 · 접미 범위를 파일 안으로 맞춘다', () {
      HttpRange? r(String? h, [int size = 1000]) => parseHttpRange(h, size);
      expect([r('bytes=0-99')!.start, r('bytes=0-99')!.end, r('bytes=0-99')!.length], [0, 99, 100]);
      expect([r('bytes=500-')!.start, r('bytes=500-')!.end], [500, 999]);
      expect([r('bytes=-100')!.start, r('bytes=-100')!.end], [900, 999], reason: '마지막 100바이트');
      expect([r('bytes=-5000')!.start, r('bytes=-5000')!.end], [0, 999], reason: '접미 범위가 파일보다 크면 전체');
      expect(r('bytes=990-5000')!.end, 999, reason: '끝이 파일 밖이면 끝까지');
      expect(r('BYTES = 1 - 2')!.length, 2, reason: '대소문자·공백을 받아 준다');
    });

    test('범위를 벗어나면 416, 해석할 수 없거나 여러 범위면 무시(전체)', () {
      expect(parseHttpRange('bytes=1000-', 1000)!.unsatisfiable, isTrue);
      expect(parseHttpRange('bytes=5000-6000', 1000)!.unsatisfiable, isTrue);
      expect(parseHttpRange('bytes=-0', 1000)!.unsatisfiable, isTrue);
      expect(parseHttpRange(null, 1000), isNull);
      expect(parseHttpRange('items=0-5', 1000), isNull, reason: '알 수 없는 단위');
      expect(parseHttpRange('bytes=0-5,10-20', 1000), isNull, reason: '여러 범위는 전체를 보낸다');
      expect(parseHttpRange('bytes=9-3', 1000), isNull, reason: '시작이 끝보다 큼');
      expect(parseHttpRange('bytes=abc', 1000), isNull);
      expect(parseHttpRange('bytes=-', 1000), isNull);
      expect(parseHttpRange('bytes=0-5', 0), isNull, reason: '빈 파일');
    });
  });

  test('Content-Type은 확장자로 정하고 모르면 바이너리', () {
    expect(httpContentType('/a/index.html'), 'text/html; charset=utf-8');
    expect(httpContentType('boot.LOG'), 'text/plain; charset=utf-8');
    expect(httpContentType('Image'), 'application/octet-stream');
    expect(httpContentType('rootfs.squashfs'), 'application/octet-stream');
    expect(httpContentType('a.json'), 'application/json; charset=utf-8');
  });

  group('설정', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('http_cfg_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('JSON이 왕복하고 잘못된 값은 거부한다', () {
      final c = HttpConfig(rootDir: root.path, bindAddress: Ipv4.parse('10.0.0.5'), port: 8080, allowWrite: true, allowOverwrite: true, allowListing: false, maxConnections: 5, idleTimeoutSeconds: 9);
      expect(HttpConfig.fromJson(c.toJson()).toJson(), c.toJson());
      expect(HttpConfig.fromJson({'rootDir': root.path}).port, 80, reason: '기본은 HTTP 기본 포트');
      expect(() => HttpConfig(rootDir: '${root.path}/없음').validate(), throwsA(isA<HttpConfigException>()));
      expect(() => HttpConfig(rootDir: root.path, port: 70000).validate(), throwsA(isA<HttpConfigException>()));
      expect(() => HttpConfig(rootDir: root.path, maxConnections: 0).validate(), throwsA(isA<HttpConfigException>()));
      expect(() => HttpConfig(rootDir: root.path, idleTimeoutSeconds: 0).validate(), throwsA(isA<HttpConfigException>()));
      HttpConfig(rootDir: root.path).validate();
    });
  });

  group('서버', () {
    late Directory root;
    late HttpFileServer server;
    late List<LogEvent> logs;
    late List<HttpRequestsEvent> snapshots;
    late HttpClient http;

    HttpConfig config({bool write = false, bool overwrite = false, bool listing = true, int maxConnections = 64, int port = 0}) => HttpConfig(
          rootDir: root.path,
          bindAddress: Ipv4.parse('127.0.0.1'),
          port: port,
          allowWrite: write,
          allowOverwrite: overwrite,
          allowListing: listing,
          maxConnections: maxConnections,
        );

    setUp(() async {
      root = Directory.systemTemp.createTempSync('http_test_');
      server = HttpFileServer(snapshotInterval: Duration.zero);
      logs = [];
      snapshots = [];
      server.events.listen((e) {
        if (e is LogEvent) logs.add(e);
        if (e is HttpRequestsEvent) snapshots.add(e);
      });
      http = HttpClient()..autoUncompress = false;
    });

    tearDown(() async {
      http.close(force: true);
      await server.dispose();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });

    Uri url(String path) => Uri.parse('http://127.0.0.1:${server.boundPort}$path');

    Future<_Reply> request(String method, String path, {Map<String, String> headers = const {}, List<int>? body}) async {
      final req = await http.openUrl(method, url(path));
      headers.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close();
      final bytes = <int>[];
      await for (final c in res) {
        bytes.addAll(c);
      }
      final h = <String, String>{};
      res.headers.forEach((name, values) => h[name] = values.join(', '));
      return _Reply(res.statusCode, h, bytes);
    }

    Future<_Reply> get(String path, {Map<String, String> headers = const {}}) => request('GET', path, headers: headers);

    /// HttpClient가 경로를 고쳐 버리는 요청(`..`)이나 잘못된 요청을 그대로 보낸다.
    Future<String> raw(String requestLine) async {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort!);
      socket.write('$requestLine HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n');
      final text = await utf8.decodeStream(socket.timeout(const Duration(seconds: 5)));
      await socket.close();
      return text;
    }

    Future<void> idle() => Future<void>.delayed(const Duration(milliseconds: 120));

    group('내려받기', () {
      test('파일을 그대로 내주고 머리를 붙인다 (길이·이어받기 가능·ETag·수정 시각·형식)', () async {
        final data = _bytes(100000);
        File('${root.path}/Image').writeAsBytesSync(data);
        await server.start(config());
        final r = await get('/Image');
        expect(r.status, 200);
        expect(r.body, data);
        expect(r.headers['content-length'], '100000');
        expect(r.headers['accept-ranges'], 'bytes');
        expect(r.headers['content-type'], 'application/octet-stream');
        expect(r.headers['etag'], startsWith('W/"'));
        expect(r.headers['last-modified'], isNotNull);
        expect(r.headers['server'], 'LabDaemon');
        expect(r.headers['x-content-type-options'], 'nosniff');
      });

      test('HEAD는 본문 없이 같은 머리만', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(5000));
        await server.start(config());
        final r = await request('HEAD', '/a.bin');
        expect(r.status, 200);
        expect(r.body, isEmpty);
        expect(r.headers['content-length'], '5000');
      });

      test('없는 파일은 404, 하위 폴더와 퍼센트 인코딩된 이름(공백·한글)을 찾는다', () async {
        Directory('${root.path}/boards/rk 3566').createSync(recursive: true);
        File('${root.path}/boards/rk 3566/부팅 이미지.bin').writeAsBytesSync([1, 2, 3]);
        await server.start(config());
        expect((await get('/없는-파일')).status, 404);
        final r = await get('/boards/rk%203566/%EB%B6%80%ED%8C%85%20%EC%9D%B4%EB%AF%B8%EC%A7%80.bin');
        expect(r.status, 200);
        expect(r.body, [1, 2, 3]);
      });

      test('업로드 중인 임시 파일(*.lab-part-*)은 없는 것처럼 404', () async {
        File('${root.path}/fw.bin.lab-part-3').writeAsBytesSync([1]);
        await server.start(config());
        expect((await get('/fw.bin.lab-part-3')).status, 404);
      });

      test('If-None-Match·If-Modified-Since가 맞으면 304', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(1000));
        await server.start(config());
        final first = await get('/a.bin');
        final etag = first.headers['etag']!;
        final modified = first.headers['last-modified']!;
        final byEtag = await get('/a.bin', headers: {'If-None-Match': etag});
        expect([byEtag.status, byEtag.body.length], [304, 0]);
        final byDate = await get('/a.bin', headers: {'If-Modified-Since': modified});
        expect(byDate.status, 304);
        expect((await get('/a.bin', headers: {'If-None-Match': 'W/"other"'})).status, 200);
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(2000));
        expect((await get('/a.bin', headers: {'If-None-Match': etag})).status, 200, reason: '내용이 바뀌면 ETag가 달라진다');
      });
    });

    group('이어받기 (Range)', () {
      late Uint8List data;

      setUp(() async {
        data = _bytes(10000);
        File('${root.path}/fw.bin').writeAsBytesSync(data);
        await server.start(config());
      });

      test('범위 · 열린 끝 · 마지막 N바이트는 206과 Content-Range', () async {
        final a = await get('/fw.bin', headers: {'Range': 'bytes=100-199'});
        expect(a.status, 206);
        expect(a.body, data.sublist(100, 200));
        expect(a.headers['content-range'], 'bytes 100-199/10000');
        expect(a.headers['content-length'], '100');

        final b = await get('/fw.bin', headers: {'Range': 'bytes=9000-'});
        expect([b.status, b.body.length, b.headers['content-range']], [206, 1000, 'bytes 9000-9999/10000']);
        expect(b.body, data.sublist(9000));

        final c = await get('/fw.bin', headers: {'Range': 'bytes=-50'});
        expect(c.body, data.sublist(9950));
        expect(c.headers['content-range'], 'bytes 9950-9999/10000');
      });

      test('파일 밖 범위는 416과 Content-Range: bytes */크기', () async {
        final r = await get('/fw.bin', headers: {'Range': 'bytes=20000-'});
        expect(r.status, 416);
        expect(r.headers['content-range'], 'bytes */10000');
        expect(r.body, isEmpty);
      });

      test('여러 범위나 잘못된 범위는 무시하고 전체를 200으로', () async {
        for (final h in ['bytes=0-5,10-20', 'bytes=abc', 'items=0-5']) {
          final r = await get('/fw.bin', headers: {'Range': h});
          expect([r.status, r.body.length], [200, 10000], reason: h);
        }
      });

      test('끊긴 전송을 이어받는다 (앞부분 + 뒷부분 = 원본)', () async {
        final head = await get('/fw.bin', headers: {'Range': 'bytes=0-3999'});
        final tail = await get('/fw.bin', headers: {'Range': 'bytes=4000-'});
        expect([...head.body, ...tail.body], data);
      });
    });

    group('폴더', () {
      test('끝에 /가 없으면 301로 /를 붙여 보내고, 있으면 파일 목록(폴더 먼저, 임시 파일 숨김, 이스케이프)', () async {
        Directory('${root.path}/boards').createSync();
        File('${root.path}/zimage').writeAsBytesSync(List.filled(2048, 1));
        File('${root.path}/Apple.txt').writeAsBytesSync([1]);
        File('${root.path}/x.bin.lab-part-1').writeAsBytesSync([1]);
        File('${root.path}/a&b.txt').writeAsBytesSync([1]);
        await server.start(config());

        final req = await http.getUrl(url('/boards'))
          ..followRedirects = false;
        final redirect = await req.close();
        await redirect.drain<void>();
        expect(redirect.statusCode, 301);
        expect(redirect.headers.value('location'), endsWith('/boards/'));

        final r = await get('/');
        expect(r.status, 200);
        expect(r.headers['content-type'], 'text/html; charset=utf-8');
        final html = r.text;
        expect(html.indexOf('boards/'), lessThan(html.indexOf('Apple.txt')), reason: '폴더가 먼저');
        expect(html.indexOf('Apple.txt'), lessThan(html.indexOf('zimage')));
        expect(html, contains('2048'));
        expect(html, isNot(contains('lab-part')));
        expect(html, contains('>a&amp;b.txt<'), reason: '파일 이름의 HTML 특수문자(&)는 이스케이프');
        expect(html, contains('href="a&amp;b.txt"'), reason: '링크도 이스케이프');
        expect(html, isNot(contains('>a&b.txt<')));
        expect(html, isNot(contains('../')), reason: '루트에는 상위 폴더 링크가 없다');

        final sub = await get('/boards/');
        expect(sub.text, contains('href="../"'));
      });

      test('index.html이 있으면 목록 대신 그것을, 목록을 끄면 403 (index.html은 계속 내줌)', () async {
        Directory('${root.path}/site').createSync();
        File('${root.path}/site/index.html').writeAsStringSync('<h1>hi</h1>');
        Directory('${root.path}/plain').createSync();
        await server.start(config(listing: false));
        final index = await get('/site/');
        expect([index.status, index.text], [200, '<h1>hi</h1>']);
        expect((await get('/plain/')).status, 403);
        expect((await get('/')).status, 403);
      });
    });

    group('보안: 루트 밖으로 나가지 못한다', () {
      setUp(() async {
        // 루트의 형제 위치에 "비밀" 파일을 둔다.
        File('${root.parent.path}${Platform.pathSeparator}${root.uri.pathSegments.where((s) => s.isNotEmpty).last}_secret.txt').writeAsStringSync('TOP SECRET');
        File('${root.path}/ok.txt').writeAsStringSync('ok');
        await server.start(config());
      });

      tearDown(() {
        try {
          File('${root.parent.path}${Platform.pathSeparator}${root.uri.pathSegments.where((s) => s.isNotEmpty).last}_secret.txt').deleteSync();
        } catch (_) {}
      });

      test('인코딩된 구분자(%2F·%5C)를 낀 .. · 드라이브 문자 · 대체 스트림 · 예약 이름 · NUL은 403이고 내용이 새지 않는다', () async {
        final name = '${root.uri.pathSegments.where((s) => s.isNotEmpty).last}_secret.txt';
        for (final line in [
          'GET /%2E%2E%2F$name',
          'GET /..%5C$name',
          'GET /%2e%2e%2f%2e%2e%2f$name',
          'GET /C:/Windows/win.ini',
          'GET /ok.txt:stream',
          'GET /CON',
          'GET /a%00b',
        ]) {
          final text = await raw(line);
          expect(text, startsWith('HTTP/1.1 403'), reason: line);
          expect(text, isNot(contains('TOP SECRET')), reason: line);
        }
        await idle();
        expect(logs.where((l) => l.key == 'logHttpBlocked').length, 7);
        expect((await get('/ok.txt')).text, 'ok', reason: '정상 요청은 계속 된다');
      });

      test('글자 그대로의 .. 구간(%2e%2e 포함)은 Dart가 경로를 정리하므로 루트 안의 경로가 되어 비밀 파일이 보이지 않는다', () async {
        final name = '${root.uri.pathSegments.where((s) => s.isNotEmpty).last}_secret.txt';
        for (final line in ['GET /../$name', 'GET /sub/../../$name', r'GET /..' + name, 'GET /%2e%2e/$name', 'GET /sub/%2e%2e/%2e%2e/$name']) {
          final text = await raw(line);
          expect(text, isNot(contains('TOP SECRET')), reason: line);
          expect(text, anyOf(startsWith('HTTP/1.1 403'), startsWith('HTTP/1.1 404'), startsWith('HTTP/1.1 400')), reason: line);
        }
      });
    });

    group('메서드', () {
      test('읽기 전용에서 PUT은 405, 모르는 메서드도 405와 Allow, OPTIONS는 허용 목록', () async {
        File('${root.path}/a.bin').writeAsBytesSync([1]);
        await server.start(config());
        final put = await request('PUT', '/new.bin', body: [1, 2]);
        expect(put.status, 405);
        expect(put.headers['allow'], 'GET, HEAD, OPTIONS');
        expect(File('${root.path}/new.bin').existsSync(), isFalse);
        expect((await request('POST', '/a.bin', body: [1])).status, 405);
        expect((await request('DELETE', '/a.bin')).status, 405);
        expect(File('${root.path}/a.bin').existsSync(), isTrue, reason: '지우기는 지원하지 않는다');
        final options = await request('OPTIONS', '/');
        expect([options.status, options.headers['allow']], [204, 'GET, HEAD, OPTIONS']);
      });
    });

    group('올리기 (PUT)', () {
      test('쓰기를 켜면 새 파일은 201이고, 임시 파일은 남지 않는다', () async {
        await server.start(config(write: true));
        final data = _bytes(300000);
        final r = await request('PUT', '/fw-new.bin', body: data);
        expect(r.status, 201);
        expect(File('${root.path}/fw-new.bin').readAsBytesSync(), data);
        expect(root.listSync().map((e) => e.uri.pathSegments.last).where((n) => n.contains('lab-part')), isEmpty);
        await idle();
        expect(snapshots.last.bytesReceived, 300000);
        expect(logs.map((l) => l.key), contains('logHttpRequest'));
      });

      test('이미 있는 파일은 덮어쓰기를 켜야만 바꾸고(204), 아니면 409', () async {
        File('${root.path}/a.bin').writeAsBytesSync([1, 1, 1]);
        await server.start(config(write: true));
        expect((await request('PUT', '/a.bin', body: [9])).status, 409);
        expect(File('${root.path}/a.bin').readAsBytesSync(), [1, 1, 1], reason: '그대로');
        await server.stop();

        await server.start(config(write: true, overwrite: true));
        expect((await request('PUT', '/a.bin', body: [9, 9])).status, 204);
        expect(File('${root.path}/a.bin').readAsBytesSync(), [9, 9]);
      });

      test('부모 폴더가 없거나 폴더·임시 파일 이름이면 거부, 루트 밖 경로는 403', () async {
        Directory('${root.path}/dir').createSync();
        await server.start(config(write: true));
        expect((await request('PUT', '/없는폴더/a.bin', body: [1])).status, 409);
        expect((await request('PUT', '/dir', body: [1])).status, 405);
        expect((await request('PUT', '/dir/', body: [1])).status, 405);
        expect((await request('PUT', '/x.bin.lab-part-9', body: [1])).status, 403);
        expect(await raw('PUT /%2E%2E%2Fevil.txt'), startsWith('HTTP/1.1 403'));
        await raw('PUT /../evil2.txt'); // 글자 그대로의 ..는 정리되어 루트 안의 파일이 된다 (밖에는 만들지 못한다)
        expect(File('${root.parent.path}${Platform.pathSeparator}evil.txt').existsSync(), isFalse);
        expect(File('${root.parent.path}${Platform.pathSeparator}evil2.txt').existsSync(), isFalse);
      });

      test('올리는 도중 연결이 끊기면 임시 파일을 지우고 대상 파일은 만들지 않는다', () async {
        await server.start(config(write: true));
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.boundPort!);
        socket.write('PUT /half.bin HTTP/1.1\r\nHost: x\r\nContent-Length: 1000000\r\n\r\n');
        socket.add(Uint8List(5000));
        await socket.flush();
        await idle();
        socket.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(File('${root.path}/half.bin').existsSync(), isFalse);
        expect(root.listSync(), isEmpty, reason: '임시 파일도 남지 않는다');
        expect(snapshots.last.failed, 1);
      });
    });

    group('상태·로그·스냅샷', () {
      test('요청이 끝나면 한 줄만 남기고, 목록에는 상태 코드·크기·속도가 있다', () async {
        File('${root.path}/a.bin').writeAsBytesSync(_bytes(200000));
        await server.start(config());
        await get('/a.bin');
        await get('/missing');
        await idle();

        final lines = logs.where((l) => l.key == 'logHttpRequest').toList();
        expect(lines, hasLength(2), reason: '요청마다 한 줄');
        expect(lines[0].args['method'], 'GET');
        expect(lines[0].args['path'], '/a.bin');
        expect(lines[0].args['status'], 200);
        expect(lines[0].args['bytes'], 200000);
        expect(lines[0].level, LogLevel.info);
        expect(lines[1].args['status'], 404);
        expect(lines[1].level, LogLevel.warning);

        final snap = snapshots.last;
        expect([snap.completed, snap.failed, snap.bytesSent], [1, 1, 200000]);
        final ok = snap.requests.firstWhere((r) => r.path == '/a.bin');
        expect([ok.state, ok.status, ok.bytes, ok.size], [HttpRequestState.done, 200, 200000, 200000]);
        expect(ok.client, startsWith('127.0.0.1:'));
        expect(snap.requests.firstWhere((r) => r.path == '/missing').state, HttpRequestState.failed);
      });

      test('clearRecent는 끝난 요청 목록을 비운다', () async {
        File('${root.path}/a.bin').writeAsBytesSync([1]);
        await server.start(config());
        await get('/a.bin');
        await idle();
        expect(snapshots.last.requests, isNotEmpty);
        await server.command('clearRecent', const {});
        expect(snapshots.last.requests, isEmpty);
      });

      test('시작·중지 로그를 남기고, 멈추면 연결을 받지 않는다', () async {
        await server.start(config());
        final port = server.boundPort!;
        expect(server.state, ServiceState.running);
        expect(logs.map((l) => l.key), contains('logHttpStarted'));
        await server.stop();
        expect(logs.map((l) => l.key), contains('logHttpStopped'));
        await expectLater(Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 1)), throwsA(isA<SocketException>()));
      });

      test('같은 포트를 두 번 열면 "포트 사용 중" 로그와 함께 실패한다', () async {
        await server.start(config());
        final other = HttpFileServer(snapshotInterval: Duration.zero);
        final otherLogs = <LogEvent>[];
        other.events.listen((e) {
          if (e is LogEvent) otherLogs.add(e);
        });
        await expectLater(other.start(config(port: server.boundPort!)), throwsA(anything));
        expect(otherLogs.map((l) => l.key), contains('logHttpPortInUse'));
        await other.dispose();
      });
    });

    group('연결 관리', () {
      test('abort 명령은 내려받는 중인 연결을 끊고 "중단됨"으로 남긴다', () async {
        File('${root.path}/big.bin').writeAsBytesSync(_bytes(30 * 1024 * 1024));
        await server.start(config());
        final req = await http.getUrl(url('/big.bin'));
        final res = await req.close();
        final sub = res.listen((_) {})..pause(); // 안 읽어서 서버가 보내다 막힌다
        await idle();
        final active = snapshots.last.requests.firstWhere((r) => r.state == HttpRequestState.active);
        expect(await server.command('abort', {'id': active.id}), isTrue);
        sub.resume();
        await sub.asFuture<void>().catchError((Object _) {});
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(logs.map((l) => l.key), contains('logHttpAborted'));
        expect(snapshots.last.requests.firstWhere((r) => r.id == active.id).failure, 'aborted');
        expect(server.activeCount, 0);
      });

      test('동시에 처리할 수 있는 수를 넘으면 503', () async {
        File('${root.path}/big.bin').writeAsBytesSync(_bytes(30 * 1024 * 1024));
        await server.start(config(maxConnections: 1));
        final req = await http.getUrl(url('/big.bin'));
        final res = await req.close();
        final sub = res.listen((_) {})..pause();
        await idle();
        final second = await get('/big.bin');
        expect(second.status, 503);
        expect(second.headers['retry-after'], '1');
        expect(logs.map((l) => l.key), contains('logHttpBusy'));
        sub.resume();
        await sub.cancel();
      });

      test('5개 클라이언트가 동시에 여러 번 받아도 모두 같은 내용을 받는다', () async {
        final files = {for (var i = 0; i < 4; i++) 'f$i.bin': _bytes(800000 + i * 1000, seed: i)};
        files.forEach((name, data) => File('${root.path}/$name').writeAsBytesSync(data));
        await server.start(config());
        final sums = {for (final e in files.entries) e.key: md5.convert(e.value).toString()};
        final results = await Future.wait([
          for (var c = 0; c < 5; c++)
            Future(() async {
              var ok = 0;
              for (var round = 0; round < 6; round++) {
                final name = 'f${(c + round) % 4}.bin';
                final r = await get('/$name');
                if (r.status == 200 && md5.convert(r.body).toString() == sums[name]) ok++;
              }
              return ok;
            }),
        ]);
        expect(results, everyElement(6));
        await idle();
        expect(snapshots.last.completed, 30);
        expect(snapshots.last.failed, 0);
      });

      test('성능: 50MB를 loopback으로 내려받는 속도', () async {
        File('${root.path}/big.bin').writeAsBytesSync(_bytes(50 * 1024 * 1024));
        await server.start(config());
        final sw = Stopwatch()..start();
        var total = 0;
        final res = await (await http.getUrl(url('/big.bin'))).close();
        await for (final c in res) {
          total += c.length;
        }
        sw.stop();
        // ignore: avoid_print
        print('HTTP loopback 50MB: ${sw.elapsedMilliseconds} ms (${(total / 1024 / 1024 / (sw.elapsedMilliseconds / 1000)).toStringAsFixed(1)} MB/s)');
        expect(total, 50 * 1024 * 1024);
        expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
      });
    });
  });
}
