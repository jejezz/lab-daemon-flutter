// HTTP 파일 서버: 루트 폴더 안의 파일을 내려주고(GET/HEAD, 이어받기 Range, 폴더 목록), 켜 두면 PUT으로 올리게 한다.
// 보드가 `wget`·`curl`·OTA로 펌웨어를 받는 용도다. TFTP·FTP처럼 루트 폴더 밖으로 나갈 수 없고([FsSandbox]),
// 요청이 몰려도 화면이 막히지 않게 로그는 요청이 끝났을 때 한 줄만 남기고 화면용 목록은 250ms마다 스냅샷으로 보낸다.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import '../fs_sandbox.dart';
import '../service.dart';
import '../socket_errors.dart';
import 'config.dart';

enum HttpRequestState { active, done, failed }

/// 화면에 보여 줄 요청 한 줄 (복사본).
class HttpRequestInfo {
  const HttpRequestInfo({
    required this.id,
    required this.client,
    required this.method,
    required this.path,
    required this.state,
    required this.status,
    required this.bytes,
    required this.size,
    required this.startedAt,
    required this.endedAt,
    required this.rate,
    required this.upload,
    required this.failure,
  });

  final int id;
  final String client;
  final String method;

  /// 클라이언트가 요청한 경로 (디코딩한 것).
  final String path;
  final HttpRequestState state;

  /// 응답 상태 코드 (아직 모르면 null).
  final int? status;

  /// 지금까지 보낸(올리는 요청이면 받은) 바이트.
  final int bytes;

  /// 알려진 전체 크기 (모르면 null).
  final int? size;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// 바이트/초.
  final double rate;
  final bool upload;

  /// 실패한 이유 (`aborted`, `io`, `diskFull`, `blocked`, ... 없으면 null).
  final String? failure;

  double? get progress => size == null || size == 0 ? null : (bytes / size!).clamp(0.0, 1.0);
}

/// 요청 목록이 바뀌면 전체 스냅샷을 내보낸다.
final class HttpRequestsEvent extends ServiceEvent {
  HttpRequestsEvent(
    super.service,
    this.requests, {
    required this.completed,
    required this.failed,
    required this.bytesSent,
    required this.bytesReceived,
    super.time,
  });

  /// 진행 중인 요청이 먼저, 그다음 최근에 끝난 요청 (최대 [HttpFileServer.recentLimit]개).
  final List<HttpRequestInfo> requests;
  final int completed;
  final int failed;
  final int bytesSent;
  final int bytesReceived;

  int get activeCount => requests.where((r) => r.state == HttpRequestState.active).length;
}

/// `Range` 요청 머리를 해석한 결과.
class HttpRange {
  const HttpRange(this.start, this.end) : unsatisfiable = false;
  const HttpRange.unsatisfiable()
      : start = 0,
        end = 0,
        unsatisfiable = true;

  /// 보낼 첫 바이트와 마지막 바이트 (둘 다 포함).
  final int start;
  final int end;

  /// 파일 크기를 넘는 범위라 416으로 답해야 한다.
  final bool unsatisfiable;

  int get length => end - start + 1;
}

/// [header]는 `Range` 머리 값, [size]는 파일 크기. 범위 요청이 아니거나 해석할 수 없거나(RFC 9110: 무시) 여러 범위면 null
/// (전체를 보낸다). 단일 범위는 파일 안으로 맞추고, 시작이 파일 끝을 넘으면 [HttpRange.unsatisfiable].
HttpRange? parseHttpRange(String? header, int size) {
  if (header == null || size <= 0) return null;
  final m = RegExp(r'^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$', caseSensitive: false).firstMatch(header);
  if (m == null) return null; // 여러 범위·알 수 없는 단위·잘못된 형식은 무시
  final a = m.group(1)!;
  final b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;
  if (a.isEmpty) {
    // 접미 범위: 마지막 N바이트
    final n = int.tryParse(b);
    if (n == null) return null;
    if (n == 0) return const HttpRange.unsatisfiable();
    return HttpRange(n >= size ? 0 : size - n, size - 1);
  }
  final start = int.tryParse(a);
  final end = b.isEmpty ? size - 1 : int.tryParse(b);
  if (start == null || end == null || (b.isNotEmpty && end < start)) return null;
  if (start >= size) return const HttpRange.unsatisfiable();
  return HttpRange(start, end >= size ? size - 1 : end);
}

/// 파일 확장자로 정하는 `Content-Type`. 모르는 것은 내려받기용 바이너리로 둔다.
String httpContentType(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'html' || 'htm' => 'text/html; charset=utf-8',
    'txt' || 'log' || 'md' || 'cfg' || 'conf' || 'ini' || 'sh' || 'csv' => 'text/plain; charset=utf-8',
    'json' => 'application/json; charset=utf-8',
    'xml' => 'application/xml; charset=utf-8',
    'css' => 'text/css; charset=utf-8',
    'js' => 'text/javascript; charset=utf-8',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'svg' => 'image/svg+xml',
    'ico' => 'image/x-icon',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'gz' || 'tgz' => 'application/gzip',
    'tar' => 'application/x-tar',
    _ => 'application/octet-stream',
  };
}

/// 업로드하는 동안 임시로 쓰는 파일의 표식. 목록과 요청에서 숨긴다 (TFTP·FTP와 같다).
const _partMarker = '.lab-part-';

NetService<ServiceConfig> createHttpService() => HttpFileServer();

/// 진행 중인 요청 하나의 가변 상태.
class _Req {
  _Req(this.id, this.client, this.method, this.path) : startedAt = DateTime.now();

  final int id;
  final String client;
  final String method;
  final String path;
  final DateTime startedAt;
  DateTime? endedAt;
  HttpRequestState state = HttpRequestState.active;
  int? status;
  int bytes = 0;
  int? size;
  bool upload = false;
  double rate = 0;
  String? failure;
  HttpResponse? response;
  bool aborted = false;
  int _lastBytes = 0;
  DateTime _lastTick = DateTime.now();

  void updateRate(DateTime now) {
    final dt = now.difference(_lastTick).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final instant = (bytes - _lastBytes) / dt;
    rate = rate == 0 ? instant : rate * 0.5 + instant * 0.5;
    _lastBytes = bytes;
    _lastTick = now;
  }

  HttpRequestInfo info() => HttpRequestInfo(
        id: id,
        client: client,
        method: method,
        path: path,
        state: state,
        status: status,
        bytes: bytes,
        size: size,
        startedAt: startedAt,
        endedAt: endedAt,
        rate: rate,
        upload: upload,
        failure: failure,
      );
}

class HttpFileServer extends BaseNetService<HttpConfig> {
  HttpFileServer({super.snapshotInterval}) : super('http');

  /// 화면에 남겨 두는, 끝난 요청의 수.
  static const recentLimit = 100;

  HttpConfig? _config;
  FsSandbox? _sandbox;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  Timer? _timer;

  final _active = <int, _Req>{};
  final _recent = Queue<HttpRequestInfo>();
  final _writes = <String>{};
  var _nextId = 1;
  var _completed = 0;
  var _failed = 0;
  var _bytesSent = 0;
  var _bytesReceived = 0;
  var _dirty = false;

  /// 요청을 받는 실제 포트 (설정이 0이었다면 OS가 정한 값).
  int? get boundPort => _server?.port;

  int get activeCount => _active.length;

  @override
  HttpConfig decodeConfig(Map<String, Object?> json) => HttpConfig.fromJson(json);

  @override
  Future<void> onStart(HttpConfig config) async {
    config.validate();
    final sandbox = FsSandbox(config.rootDir);
    final HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress(config.bindTo.toString()), config.port);
    } on SocketException catch (e) {
      log(LogLevel.error, 'logHttp${bindFailureKind(e)}', args: {'address': '${config.bindTo}', 'port': config.port, 'error': '$e'});
      rethrow;
    }
    server.idleTimeout = Duration(seconds: config.idleTimeoutSeconds);
    server.autoCompress = false; // 파일은 그대로 보낸다 (이어받기 범위와 어긋나지 않게)
    _config = config;
    _sandbox = sandbox;
    _server = server;
    _completed = _failed = _bytesSent = _bytesReceived = 0;
    _recent.clear();
    _subscription = server.listen(_onRequest, onError: (Object e) => log(LogLevel.warning, 'logHttpConnectionError', args: {'error': '$e'}));
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    log(LogLevel.info, 'logHttpStarted', args: {'address': '${config.bindTo}', 'port': server.port, 'root': sandbox.root, 'write': config.allowWrite});
    _publish();
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    final had = _server != null;
    for (final r in _active.values.toList()) {
      _abortRequest(r);
    }
    await _server?.close(force: true);
    _server = null;
    _config = null;
    _sandbox = null;
    _active.clear();
    _writes.clear();
    if (had) log(LogLevel.info, 'logHttpStopped');
  }

  @override
  Future<Object?> handleCommand(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'abort':
        final r = _active[args['id']! as int];
        if (r == null) return false;
        _abortRequest(r);
        return true;
      case 'abortAll':
        final all = _active.values.toList();
        for (final r in all) {
          _abortRequest(r);
        }
        return all.length;
      case 'clearRecent':
        _recent.clear();
        _publish();
        return null;
    }
    return super.handleCommand(name, args);
  }

  /// 연결을 바로 끊는다. 보내던 응답은 실패('aborted')로 정리된다.
  void _abortRequest(_Req r) {
    r.aborted = true;
    final response = r.response;
    if (response == null) return;
    try {
      unawaited(response.detachSocket(writeHeaders: false).then((socket) => socket.destroy()).catchError((Object _) {}));
    } catch (_) {
      // 이미 끝난 응답이다.
    }
  }

  // ---- 요청 처리 -------------------------------------------------------------------------------

  void _onRequest(HttpRequest request) {
    final config = _config;
    if (config == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      unawaited(request.response.close());
      return;
    }
    final info = request.connectionInfo;
    final client = info == null ? '?' : '${info.remoteAddress.address}:${info.remotePort}';
    if (_active.length >= config.maxConnections) {
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.set(HttpHeaders.retryAfterHeader, '1');
      unawaited(request.response.close().catchError((Object _) {}));
      log(LogLevel.warning, 'logHttpBusy', args: {'client': client, 'limit': config.maxConnections});
      return;
    }
    final req = _Req(_nextId++, client, request.method.toUpperCase(), _displayPath(request.uri));
    req.response = request.response;
    _active[req.id] = req;
    _dirty = true;
    _publish();
    unawaited(_run(request, req, config));
  }

  /// 화면과 로그에 보일 경로: 디코딩하고, 폴더 주소의 끝 `/`는 유지한다.
  static String _displayPath(Uri uri) {
    final decoded = uri.pathSegments.join('/');
    final path = '/$decoded';
    return uri.path.endsWith('/') && !path.endsWith('/') ? '$path/' : path;
  }

  Future<void> _run(HttpRequest request, _Req r, HttpConfig config) async {
    try {
      await _handle(request, r, config);
      if (r.aborted && r.state == HttpRequestState.active) r.failure = 'aborted';
    } on SandboxViolation catch (e) {
      r.failure = 'blocked';
      log(LogLevel.warning, 'logHttpBlocked', kind: 'BLOCK', args: {'client': r.client, 'path': r.path, 'reason': e.reason});
      await _respond(request, r, HttpStatus.forbidden, 'Forbidden');
    } on _ClientGone {
      r.failure = 'aborted';
    } on FileSystemException catch (e) {
      r.failure ??= _isDiskFull(e) ? 'diskFull' : 'io';
      await _respond(request, r, _isDiskFull(e) ? HttpStatus.insufficientStorage : HttpStatus.internalServerError, 'Server error');
    } catch (e) {
      // 연결이 끊긴 경우(SocketException·HttpException)가 대부분이다.
      r.failure ??= r.aborted || e is SocketException || e is HttpException ? 'aborted' : 'io';
      if (r.failure == 'io') await _respond(request, r, HttpStatus.internalServerError, 'Server error');
    } finally {
      await _finish(request, r);
    }
  }

  static bool _isDiskFull(FileSystemException e) => (e.osError?.errorCode == 112 /* ERROR_DISK_FULL */) || (e.osError?.errorCode == 28 /* ENOSPC */);

  Future<void> _handle(HttpRequest request, _Req r, HttpConfig config) async {
    final res = request.response;
    res.headers
      ..set(HttpHeaders.serverHeader, 'LabDaemon')
      ..set('X-Content-Type-Options', 'nosniff');
    switch (r.method) {
      case 'GET' || 'HEAD':
        await _serve(request, r, config, head: r.method == 'HEAD');
      case 'PUT':
        if (!config.allowWrite) {
          res.headers.set(HttpHeaders.allowHeader, 'GET, HEAD, OPTIONS');
          await _respond(request, r, HttpStatus.methodNotAllowed, 'Read-only server');
        } else {
          await _upload(request, r, config);
        }
      case 'OPTIONS':
        res.headers.set(HttpHeaders.allowHeader, config.allowWrite ? 'GET, HEAD, PUT, OPTIONS' : 'GET, HEAD, OPTIONS');
        res.headers.set(HttpHeaders.contentLengthHeader, '0');
        r.status = HttpStatus.noContent;
        res.statusCode = HttpStatus.noContent;
        await res.close();
      default:
        res.headers.set(HttpHeaders.allowHeader, config.allowWrite ? 'GET, HEAD, PUT, OPTIONS' : 'GET, HEAD, OPTIONS');
        await _respond(request, r, HttpStatus.methodNotAllowed, 'Method not allowed');
    }
  }

  /// 짧은 글자 본문으로 답한다. 이미 보낸 응답이면 조용히 넘어간다.
  Future<void> _respond(HttpRequest request, _Req r, int status, String message) async {
    final res = request.response;
    try {
      if (r.status != null) return; // 이미 응답을 시작했다
      r.status = status;
      res.statusCode = status;
      res.headers.contentType = ContentType.text;
      final body = utf8.encode('$status $message\n');
      res.headers.set(HttpHeaders.contentLengthHeader, '${body.length}');
      res.add(body);
      await res.close();
    } catch (_) {
      // 머리를 이미 보냈거나 연결이 끊겼다.
    }
  }

  // ---- GET / HEAD ------------------------------------------------------------------------------

  Future<void> _serve(HttpRequest request, _Req r, HttpConfig config, {required bool head}) async {
    final sandbox = _sandbox!;
    final res = request.response;
    final fsPath = sandbox.resolve(request.uri.pathSegments.join('/'));
    if (File(fsPath).uri.pathSegments.last.contains(_partMarker) && !FileSystemEntity.isDirectorySync(fsPath)) {
      await _respond(request, r, HttpStatus.notFound, 'Not found');
      return;
    }
    final type = FileSystemEntity.typeSync(fsPath);
    if (type == FileSystemEntityType.notFound) {
      await _respond(request, r, HttpStatus.notFound, 'Not found');
      return;
    }
    if (type == FileSystemEntityType.directory) {
      if (!request.uri.path.endsWith('/')) {
        // 폴더는 끝에 /를 붙여서 다시 요청하게 한다 (목록 안의 상대 링크가 맞도록).
        r.status = HttpStatus.movedPermanently;
        res.statusCode = HttpStatus.movedPermanently;
        res.headers.set(HttpHeaders.locationHeader, request.uri.replace(path: '${request.uri.path}/').toString());
        res.headers.set(HttpHeaders.contentLengthHeader, '0');
        await res.close();
        return;
      }
      final index = File('$fsPath${Platform.pathSeparator}index.html');
      if (index.existsSync()) {
        await _sendFile(request, r, index, head: head);
        return;
      }
      if (!config.allowListing) {
        await _respond(request, r, HttpStatus.forbidden, 'Directory listing is off');
        return;
      }
      await _sendListing(request, r, Directory(fsPath), head: head);
      return;
    }
    await _sendFile(request, r, File(fsPath), head: head);
  }

  Future<void> _sendFile(HttpRequest request, _Req r, File file, {required bool head}) async {
    final res = request.response;
    final stat = file.statSync();
    final size = stat.size;
    // 수정 시각은 초 단위로 맞춘다 (HTTP 날짜는 초 단위다).
    final modified = DateTime.fromMillisecondsSinceEpoch(stat.modified.millisecondsSinceEpoch ~/ 1000 * 1000, isUtc: true);
    final etag = 'W/"${size.toRadixString(16)}-${modified.millisecondsSinceEpoch.toRadixString(16)}"';
    res.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(modified))
      ..set(HttpHeaders.etagHeader, etag)
      ..set(HttpHeaders.contentTypeHeader, httpContentType(file.path));

    final noneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
    final since = request.headers.ifModifiedSince;
    final notModified = noneMatch != null ? (noneMatch == '*' || noneMatch.split(',').map((e) => e.trim()).contains(etag)) : (since != null && !modified.isAfter(since));
    if (notModified) {
      r.status = HttpStatus.notModified;
      res.statusCode = HttpStatus.notModified;
      await res.close();
      return;
    }

    final range = parseHttpRange(request.headers.value(HttpHeaders.rangeHeader), size);
    if (range != null && range.unsatisfiable) {
      r.status = HttpStatus.requestedRangeNotSatisfiable;
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
      res.headers.set(HttpHeaders.contentLengthHeader, '0');
      await res.close();
      return;
    }
    final start = range?.start ?? 0;
    final length = range?.length ?? size;
    r.size = length;
    r.status = range == null ? HttpStatus.ok : HttpStatus.partialContent;
    res.statusCode = r.status!;
    if (range != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes ${range.start}-${range.end}/$size');
    res.headers.set(HttpHeaders.contentLengthHeader, '$length');
    if (head || length == 0) {
      await res.close();
      return;
    }
    // 보내는 대로 바이트를 센다 (화면의 진행률·속도). 연결이 끊기면 addStream이 오류로 끝난다.
    final stream = file.openRead(start, start + length).map((chunk) {
      r.bytes += chunk.length;
      return chunk;
    });
    await res.addStream(stream);
    await res.close();
  }

  // ---- 폴더 목록 -------------------------------------------------------------------------------

  Future<void> _sendListing(HttpRequest request, _Req r, Directory dir, {required bool head}) async {
    final res = request.response;
    final entries = <({String name, bool isDir, int size, DateTime modified})>[];
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.contains(_partMarker)) continue;
      final isDir = e is Directory;
      FileStat? s;
      try {
        s = e.statSync();
      } catch (_) {}
      entries.add((name: name, isDir: isDir, size: isDir ? 0 : (s?.size ?? 0), modified: s?.modified ?? DateTime.fromMillisecondsSinceEpoch(0)));
    }
    entries.sort((a, b) => a.isDir != b.isDir ? (a.isDir ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final shownPath = r.path;
    final html = StringBuffer()
      ..writeln('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
      ..writeln('<title>Index of ${_esc(shownPath)}</title>')
      ..writeln('<style>:root{color-scheme:light dark}body{font:15px system-ui,sans-serif;margin:24px}table{border-collapse:collapse}'
          'td,th{padding:4px 18px 4px 0;text-align:left}td.n{text-align:right;font-variant-numeric:tabular-nums}a{text-decoration:none}</style>')
      ..writeln('</head><body><h1>Index of ${_esc(shownPath)}</h1><table><tr><th>Name</th><th>Size</th><th>Modified</th></tr>');
    if (shownPath != '/') html.writeln('<tr><td><a href="../">../</a></td><td></td><td></td></tr>');
    for (final e in entries.take(10000)) {
      final href = Uri(pathSegments: [e.name]).toString();
      final name = e.isDir ? '${e.name}/' : e.name;
      html.writeln('<tr><td><a href="${_esc(href)}${e.isDir ? '/' : ''}">${_esc(name)}</a></td><td class="n">${e.isDir ? '-' : e.size}</td>'
          '<td>${_stamp(e.modified)}</td></tr>');
    }
    html.writeln('</table></body></html>');
    final body = utf8.encode(html.toString());
    r.status = HttpStatus.ok;
    r.size = body.length;
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/html; charset=utf-8')
      ..set(HttpHeaders.contentLengthHeader, '${body.length}')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (!head) {
      res.add(body);
      r.bytes += body.length;
    }
    await res.close();
  }

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final l = t.toLocal();
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  // ---- PUT (올리기) ----------------------------------------------------------------------------

  Future<void> _upload(HttpRequest request, _Req r, HttpConfig config) async {
    final sandbox = _sandbox!;
    final path = sandbox.resolve(request.uri.pathSegments.join('/'));
    r.upload = true;
    if (path == sandbox.root || request.uri.path.endsWith('/') || FileSystemEntity.isDirectorySync(path)) {
      await _respond(request, r, HttpStatus.methodNotAllowed, 'Not a file');
      return;
    }
    final name = File(path).uri.pathSegments.last;
    if (name.contains(_partMarker)) {
      await _respond(request, r, HttpStatus.forbidden, 'Forbidden');
      return;
    }
    if (!FileSystemEntity.isDirectorySync(File(path).parent.path)) {
      await _respond(request, r, HttpStatus.conflict, 'Parent folder does not exist');
      return;
    }
    final existed = FileSystemEntity.isFileSync(path);
    if (existed && !config.allowOverwrite) {
      await _respond(request, r, HttpStatus.conflict, 'File exists');
      return;
    }
    if (!_writes.add(path)) {
      await _respond(request, r, HttpStatus.conflict, 'Another upload to this file is in progress');
      return;
    }
    final temp = File('$path$_partMarker${r.id}');
    try {
      r.size = request.contentLength >= 0 ? request.contentLength : null;
      final sink = temp.openWrite();
      try {
        await for (final chunk in request) {
          r.bytes += chunk.length;
          sink.add(chunk);
        }
        await sink.close();
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {}
        rethrow;
      }
      if (r.aborted) throw const _ClientGone();
      await temp.rename(path);
      await _respond(request, r, existed ? HttpStatus.noContent : HttpStatus.created, existed ? 'Replaced' : 'Created');
    } catch (_) {
      try {
        if (temp.existsSync()) temp.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      _writes.remove(path);
    }
  }

  // ---- 마무리 ----------------------------------------------------------------------------------

  Future<void> _finish(HttpRequest request, _Req r) async {
    r.endedAt = DateTime.now();
    final status = r.status;
    final ok = r.failure == null && status != null && status < 400;
    r.state = ok ? HttpRequestState.done : HttpRequestState.failed;
    if (r.failure == null && status != null && status >= 400) r.failure = 'status';
    if (ok) {
      _completed++;
    } else {
      _failed++;
    }
    if (r.upload) {
      _bytesReceived += r.bytes;
    } else {
      _bytesSent += r.bytes;
    }
    final seconds = r.endedAt!.difference(r.startedAt).inMilliseconds / 1000;
    final args = {
      'client': r.client,
      'method': r.method,
      'path': r.path,
      'status': status ?? 0,
      'bytes': r.bytes,
      'seconds': seconds.toStringAsFixed(2),
      'rate': seconds <= 0 ? 0 : (r.bytes / seconds).round(),
    };
    if (r.failure == 'aborted') {
      log(LogLevel.warning, 'logHttpAborted', kind: r.method, args: args);
    } else if (r.failure == 'blocked') {
      // 차단은 logHttpBlocked로 이미 남겼다.
    } else {
      final level = status == null || status >= 500 ? LogLevel.error : (status >= 400 ? LogLevel.warning : LogLevel.info);
      log(level, 'logHttpRequest', kind: r.method, args: args);
    }
    _active.remove(r.id);
    _recent.addFirst(r.info());
    while (_recent.length > recentLimit) {
      _recent.removeLast();
    }
    _dirty = true;
    _publish();
  }

  /// 250ms마다: 진행 중인 요청의 속도를 갱신하고, 바뀐 것이 있으면 스냅샷을 예약한다.
  void _tick() {
    if (_active.isEmpty && !_dirty) return;
    final now = DateTime.now();
    for (final r in _active.values) {
      r.updateRate(now);
    }
    _publish();
    _dirty = _active.isNotEmpty;
  }

  void _publish() {
    scheduleSnapshot('requests', () {
      final active = [for (final r in _active.values) r.info()]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return HttpRequestsEvent(
        id,
        [...active, ..._recent],
        completed: _completed,
        failed: _failed,
        bytesSent: _bytesSent + _liveBytes(upload: false),
        bytesReceived: _bytesReceived + _liveBytes(upload: true),
      );
    });
  }

  int _liveBytes({required bool upload}) {
    var sum = 0;
    for (final r in _active.values) {
      if (r.upload == upload) sum += r.bytes;
    }
    return sum;
  }
}

/// 중단 명령으로 연결을 끊어서 응답을 끝낼 수 없다.
class _ClientGone implements Exception {
  const _ClientGone();
}
