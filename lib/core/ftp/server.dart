// FTP 서버: TCP 21(기본)에서 제어 연결을 받아 연결마다 [FtpSession]을 만든다. 세션 목록은 250ms마다(바뀐
// 경우에만) 스냅샷으로 내보낸다 — 연결과 전송이 많아도 화면 쪽으로 가는 양은 늘지 않는다.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../fs_sandbox.dart';
import '../service.dart';
import '../socket_errors.dart';
import 'config.dart';
import 'session.dart';

/// 화면에 보여 줄 세션 한 줄 (복사본).
class FtpSessionInfo {
  const FtpSessionInfo({
    required this.id,
    required this.client,
    required this.user,
    required this.authenticated,
    required this.canWrite,
    required this.cwd,
    required this.connectedAt,
    required this.lastCommand,
    required this.bytesIn,
    required this.bytesOut,
    required this.filesIn,
    required this.filesOut,
    required this.transferFile,
    required this.transferUpload,
    required this.transferBytes,
    required this.transferSize,
    required this.transferRate,
    required this.closed,
  });

  factory FtpSessionInfo.of(FtpSession s) {
    final t = s.transfer;
    return FtpSessionInfo(
      id: s.id,
      client: s.client,
      user: s.user,
      authenticated: s.authenticated,
      canWrite: s.canWrite,
      cwd: s.cwd,
      connectedAt: s.connectedAt,
      lastCommand: s.lastCommand,
      bytesIn: s.bytesIn,
      bytesOut: s.bytesOut,
      filesIn: s.filesIn,
      filesOut: s.filesOut,
      transferFile: t?.file,
      transferUpload: t?.upload ?? false,
      transferBytes: t?.bytes ?? 0,
      transferSize: t?.size,
      transferRate: t?.rate ?? 0,
      closed: s.closed,
    );
  }

  final int id;
  final String client;
  final String? user;
  final bool authenticated;
  final bool canWrite;
  final String cwd;
  final DateTime connectedAt;
  final String lastCommand;
  final int bytesIn;
  final int bytesOut;
  final int filesIn;
  final int filesOut;

  /// 진행 중인 전송 (없으면 null).
  final String? transferFile;
  final bool transferUpload;
  final int transferBytes;
  final int? transferSize;
  final double transferRate;
  final bool closed;
}

final class FtpSessionsEvent extends ServiceEvent {
  FtpSessionsEvent(super.service, this.sessions, {required this.totalConnections, required this.bytesIn, required this.bytesOut, super.time});

  /// 연결된 세션이 먼저, 그다음 최근에 끊긴 세션 (최대 [FtpServer.recentLimit]개).
  final List<FtpSessionInfo> sessions;
  final int totalConnections;
  final int bytesIn;
  final int bytesOut;

  int get openCount => sessions.where((s) => !s.closed).length;
}

NetService<ServiceConfig> createFtpService() => FtpServer();

class FtpServer extends BaseNetService<FtpConfig> {
  FtpServer({super.snapshotInterval}) : super('ftp');

  static const recentLimit = 50;

  FtpConfig? _config;
  FsSandbox? _sandbox;
  ServerSocket? _listener;
  StreamSubscription<Socket>? _subscription;
  Timer? _timer;
  final _sessions = <int, FtpSession>{};
  final _recent = Queue<FtpSessionInfo>();
  var _nextId = 1;
  var _nextPassive = 0;
  var _total = 0;
  var _closedIn = 0;
  var _closedOut = 0;
  var _dirty = false;

  int? get boundPort => _listener?.port;

  int get sessionCount => _sessions.length;

  @override
  FtpConfig decodeConfig(Map<String, Object?> json) => FtpConfig.fromJson(json);

  @override
  Future<void> onStart(FtpConfig config) async {
    config.validate();
    final sandbox = FsSandbox(config.rootDir);
    final ServerSocket listener;
    try {
      listener = await ServerSocket.bind(InternetAddress(config.bindTo.toString()), config.port, shared: false);
    } on SocketException catch (e) {
      log(LogLevel.error, 'logFtp${bindFailureKind(e)}', args: {'address': '${config.bindTo}', 'port': config.port, 'error': '$e'});
      rethrow;
    }
    _config = config;
    _sandbox = sandbox;
    _listener = listener;
    _total = _closedIn = _closedOut = 0;
    _recent.clear();
    _nextPassive = 0;
    _subscription = listener.listen(_onConnection);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    log(LogLevel.info, 'logFtpStarted', args: {
      'address': '${config.bindTo}',
      'port': listener.port,
      'root': sandbox.root,
      'passive': '${config.passivePortStart}-${config.passivePortEnd}',
    });
    _publish();
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    for (final s in _sessions.values.toList()) {
      await s.close('Service shutting down');
    }
    _sessions.clear();
    final had = _listener != null;
    await _listener?.close();
    _listener = null;
    _config = null;
    _sandbox = null;
    if (had) log(LogLevel.info, 'logFtpStopped');
  }

  @override
  Future<Object?> handleCommand(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'disconnect':
        final s = _sessions[args['id']! as int];
        if (s == null) return false;
        log(LogLevel.info, 'logFtpKicked', args: {'client': s.client, 'user': s.user});
        await s.close('Disconnected by administrator');
        return true;
      case 'clearRecent':
        _recent.clear();
        _publish();
        return null;
    }
    return super.handleCommand(name, args);
  }

  void _onConnection(Socket socket) {
    final config = _config;
    final sandbox = _sandbox;
    if (config == null || sandbox == null) {
      socket.destroy();
      return;
    }
    final client = '${socket.remoteAddress.address}:${socket.remotePort}';
    if (_sessions.length >= config.maxConnections) {
      log(LogLevel.warning, 'logFtpTooMany', args: {'client': client, 'limit': config.maxConnections});
      socket.write('421 Too many connections, try again later\r\n');
      unawaited(socket.flush().then((_) => socket.destroy(), onError: (_) => socket.destroy()));
      return;
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final session = FtpSession(
      id: _nextId++,
      control: socket,
      config: config,
      sandbox: sandbox,
      log: (level, key, {kind, args = const {}}) => log(level, key, kind: kind, args: args),
      openPassive: _openPassive,
      onClosed: _onClosed,
      onChanged: () => _dirty = true,
    );
    _sessions[session.id] = session;
    _total++;
    log(LogLevel.info, 'logFtpConnected', kind: 'CONNECT', args: {'client': client});
    _dirty = true;
    _publish();
    unawaited(session.run());
  }

  void _onClosed(FtpSession s) {
    if (_sessions.remove(s.id) == null) return;
    _closedIn += s.bytesIn;
    _closedOut += s.bytesOut;
    _recent.addFirst(FtpSessionInfo.of(s));
    while (_recent.length > recentLimit) {
      _recent.removeLast();
    }
    log(LogLevel.info, 'logFtpDisconnected', kind: 'CLOSE', args: {
      'client': s.client,
      'user': s.user,
      'seconds': DateTime.now().difference(s.connectedAt).inSeconds,
    });
    _dirty = true;
    _publish();
  }

  /// 패시브 포트 범위를 돌아가며 빈 포트를 찾는다 (같은 포트를 바로 다시 쓰지 않도록 커서를 옮긴다).
  Future<ServerSocket?> _openPassive(InternetAddress address) async {
    final config = _config;
    if (config == null) return null;
    final span = config.passivePortEnd - config.passivePortStart + 1;
    for (var i = 0; i < span; i++) {
      final port = config.passivePortStart + (_nextPassive + i) % span;
      try {
        final socket = await ServerSocket.bind(address, port, shared: false);
        _nextPassive = (_nextPassive + i + 1) % span;
        return socket;
      } on SocketException {
        continue;
      }
    }
    log(LogLevel.warning, 'logFtpNoPassivePort', args: {'range': '${config.passivePortStart}-${config.passivePortEnd}'});
    return null;
  }

  void _tick() {
    final busy = _sessions.values.any((s) => s.transfer != null);
    if (!busy && !_dirty) return;
    final now = DateTime.now();
    for (final s in _sessions.values) {
      s.transfer?.updateRate(now);
    }
    _publish();
    _dirty = busy;
  }

  void _publish() {
    scheduleSnapshot('sessions', () {
      final open = [for (final s in _sessions.values) FtpSessionInfo.of(s)]..sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
      var bytesIn = _closedIn;
      var bytesOut = _closedOut;
      for (final s in _sessions.values) {
        bytesIn += s.bytesIn;
        bytesOut += s.bytesOut;
      }
      return FtpSessionsEvent(id, [...open, ..._recent], totalConnections: _total, bytesIn: bytesIn, bytesOut: bytesOut);
    });
  }
}
