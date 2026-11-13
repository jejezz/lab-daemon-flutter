// TFTP 서버: UDP 69(기본)에서 읽기·쓰기 요청을 받아 전송마다 [TftpTransfer]를 만든다.
// 로그는 요청·완료·실패 같은 사건에만 남기고, 진행 상황은 숫자 필드만 갱신한다. 화면용 전송 목록은
// 250ms마다(바뀐 경우에만) 스냅샷으로 내보낸다 — 전송이 많아져도 패킷 처리 비용이 늘지 않는다.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import '../fs_sandbox.dart';
import '../udp_queue.dart';
import '../service.dart';
import '../socket_errors.dart';
import 'config.dart';
import 'packet.dart';
import 'transfer.dart';

/// 화면에 보여 줄 전송 한 줄 (복사본).
class TftpTransferInfo {
  const TftpTransferInfo({
    required this.id,
    required this.client,
    required this.file,
    required this.upload,
    required this.state,
    required this.bytes,
    required this.size,
    required this.startedAt,
    required this.endedAt,
    required this.rate,
    required this.blksize,
    required this.windowsize,
    required this.mode,
    required this.failure,
    required this.failureDetail,
  });

  factory TftpTransferInfo.of(TftpTransfer t) => TftpTransferInfo(
        id: t.id,
        client: t.clientKey,
        file: t.request.filename,
        upload: t.upload,
        state: t.state,
        bytes: t.bytes,
        size: t.size,
        startedAt: t.startedAt,
        endedAt: t.endedAt,
        rate: t.rate,
        blksize: t.blksize,
        windowsize: t.windowsize,
        mode: t.mode,
        failure: t.failure,
        failureDetail: t.failureDetail,
      );

  final int id;
  final String client;
  final String file;
  final bool upload;
  final TransferState state;
  final int bytes;

  /// 알려진 전체 크기 (모르면 null).
  final int? size;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// 바이트/초.
  final double rate;
  final int blksize;
  final int windowsize;
  final String mode;
  final String? failure;
  final String? failureDetail;

  double? get progress => size == null || size == 0 ? null : (bytes / size!).clamp(0.0, 1.0);
}

final class TftpTransfersEvent extends ServiceEvent {
  TftpTransfersEvent(
    super.service,
    this.transfers, {
    required this.completed,
    required this.failed,
    required this.bytesSent,
    required this.bytesReceived,
    super.time,
  });

  /// 진행 중인 전송이 먼저, 그다음 최근에 끝난 전송 (최대 [TftpServer.recentLimit]개).
  final List<TftpTransferInfo> transfers;
  final int completed;
  final int failed;
  final int bytesSent;
  final int bytesReceived;

  int get activeCount => transfers.where((t) => t.state == TransferState.active).length;
}

NetService<ServiceConfig> createTftpService() => TftpServer();

class TftpServer extends BaseNetService<TftpConfig> {
  TftpServer({super.snapshotInterval}) : super('tftp');

  /// 화면에 남겨 두는, 끝난 전송의 수.
  static const recentLimit = 100;

  TftpConfig? _config;
  FsSandbox? _sandbox;
  RawDatagramSocket? _socket;
  UdpSendQueue? _out;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _timer;

  final _active = <int, TftpTransfer>{};
  final _runs = <int, Future<void>>{};
  final _byClient = <String, TftpTransfer>{};
  final _starting = <String>{};
  final _writes = <String>{};
  final _recent = Queue<TftpTransferInfo>();
  var _nextId = 1;
  var _completed = 0;
  var _failed = 0;
  var _bytesSent = 0;
  var _bytesReceived = 0;
  var _dirty = false;

  /// 요청을 받는 실제 포트 (설정이 0이었다면 OS가 정한 값).
  int? get boundPort => _socket?.port;

  int get activeCount => _active.length;

  @override
  TftpConfig decodeConfig(Map<String, Object?> json) => TftpConfig.fromJson(json);

  @override
  Future<void> onStart(TftpConfig config) async {
    config.validate();
    final sandbox = FsSandbox(config.rootDir);
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress(config.bindTo.toString()), config.port, reuseAddress: false);
    } on SocketException catch (e) {
      log(LogLevel.error, 'logTftp${bindFailureKind(e)}', args: {'address': '${config.bindTo}', 'port': config.port, 'error': '$e'});
      rethrow;
    }
    _config = config;
    _sandbox = sandbox;
    _socket = socket;
    _out = UdpSendQueue(socket, limit: 256);
    _completed = _failed = _bytesSent = _bytesReceived = 0;
    _recent.clear();
    _subscription = socket.listen((event) {
      if (event == RawSocketEvent.write) {
        _out?.onWritable();
        return;
      }
      if (event != RawSocketEvent.read) return;
      for (var d = socket.receive(); d != null; d = socket.receive()) {
        _onRequest(d);
      }
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    log(LogLevel.info, 'logTftpStarted', args: {'address': '${config.bindTo}', 'port': socket.port, 'root': sandbox.root, 'write': config.allowWrite});
    _publish();
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    final runs = _runs.values.toList();
    for (final t in _active.values.toList()) {
      t.abort();
    }
    // 진행 중인 전송이 정리될 시간을 잠깐 준다.
    await Future.wait(runs).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    final had = _socket != null;
    _socket?.close();
    _socket = null;
    _out = null;
    _config = null;
    _sandbox = null;
    _active.clear();
    _byClient.clear();
    _starting.clear();
    _runs.clear();
    if (had) log(LogLevel.info, 'logTftpStopped');
  }

  @override
  Future<Object?> handleCommand(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'abort':
        final t = _active[args['id']! as int];
        if (t == null) return false;
        t.abort();
        return true;
      case 'abortAll':
        final all = _active.values.toList();
        for (final t in all) {
          t.abort();
        }
        return all.length;
      case 'clearRecent':
        _recent.clear();
        _publish();
        return null;
    }
    return super.handleCommand(name, args);
  }

  // ---- 요청 처리 -------------------------------------------------------------------------------

  void _onRequest(Datagram d) {
    final config = _config;
    final socket = _socket;
    if (config == null || socket == null) return;
    final request = parseRequest(d.data);
    if (request == null) {
      final op = tftpOpcode(d.data);
      if (op == TftpOp.data || op == TftpOp.ack) {
        // 69번 포트로 온 DATA/ACK: 이 포트는 전송 중인 포트가 아니다.
        _reply(socket, d, TftpError.unknownTid, 'Unknown transfer ID');
      } else if (op != TftpOp.error) {
        log(LogLevel.debug, 'logTftpMalformed', args: {'from': '${d.address.address}:${d.port}'});
      }
      return;
    }
    final key = '${d.address.address}:${d.port}';
    if (_byClient.containsKey(key) || _starting.contains(key)) return; // 재전송된 같은 요청
    if (_active.length + _starting.length >= config.maxTransfers) {
      _reply(socket, d, TftpError.undefined, 'Server busy');
      log(LogLevel.warning, 'logTftpBusy', args: {'client': key, 'file': request.filename, 'limit': config.maxTransfers});
      return;
    }
    if (config.logPackets) {
      log(LogLevel.debug, 'logTftpPacketIn', args: {'client': key}, detail: _hexDump(d.data));
    }
    _starting.add(key);
    unawaited(_start(request, d, key, config));
  }

  Future<void> _start(TftpRequest request, Datagram d, String key, TftpConfig config) async {
    final RawDatagramSocket transferSocket;
    try {
      transferSocket = await RawDatagramSocket.bind(InternetAddress(config.bindTo.toString()), 0);
    } on SocketException catch (e) {
      _starting.remove(key);
      final main = _socket;
      if (main != null) _reply(main, d, TftpError.undefined, 'Cannot allocate transfer port');
      log(LogLevel.error, 'logTftpBindFailed', args: {'address': '${config.bindTo}', 'port': 0, 'error': '$e'});
      return;
    }
    final transfer = TftpTransfer(
      id: _nextId++,
      request: request,
      client: d.address,
      clientPort: d.port,
      socket: transferSocket,
      config: config,
      sandbox: _sandbox!,
      claimWrite: _writes.add,
      releaseWrite: _writes.remove,
    );
    _starting.remove(key);
    _active[transfer.id] = transfer;
    _byClient[key] = transfer;
    log(LogLevel.info, request.write ? 'logTftpWrq' : 'logTftpRrq', kind: request.write ? 'WRQ' : 'RRQ', args: {
      'client': key,
      'file': request.filename,
      'mode': request.mode,
    });
    _dirty = true;
    _runs[transfer.id] = _run(transfer, key);
    _publish();
  }

  Future<void> _run(TftpTransfer t, String key) async {
    try {
      await t.run();
      final seconds = (t.endedAt ?? DateTime.now()).difference(t.startedAt).inMilliseconds / 1000;
      _completed++;
      if (t.upload) {
        _bytesReceived += t.bytes;
      } else {
        _bytesSent += t.bytes;
      }
      log(LogLevel.info, t.upload ? 'logTftpReceived' : 'logTftpSent', kind: 'DONE', args: {
        'client': key,
        'file': t.request.filename,
        'bytes': t.bytes,
        'seconds': seconds.toStringAsFixed(2),
        'rate': seconds <= 0 ? 0 : (t.bytes / seconds).round(),
      });
    } on TftpFailure catch (e) {
      _failed++;
      if (t.upload) {
        _bytesReceived += t.bytes;
      } else {
        _bytesSent += t.bytes;
      }
      final serious = e.reason == 'io' || e.reason == 'diskFull';
      log(serious ? LogLevel.error : LogLevel.warning, 'logTftpFailed', kind: 'ERROR', args: {
        'client': key,
        'file': t.request.filename,
        'reason': e.reason,
        'detail': e.detail,
      });
    } catch (e) {
      _failed++;
      t.state = TransferState.failed;
      t.failure = 'io';
      t.failureDetail = '$e';
      log(LogLevel.error, 'logTftpFailed', kind: 'ERROR', args: {'client': key, 'file': t.request.filename, 'reason': 'io', 'detail': '$e'});
    } finally {
      _active.remove(t.id);
      _runs.remove(t.id);
      _byClient.remove(key);
      _recent.addFirst(TftpTransferInfo.of(t));
      while (_recent.length > recentLimit) {
        _recent.removeLast();
      }
      _dirty = true;
      _publish();
    }
  }

  void _reply(RawDatagramSocket socket, Datagram to, int code, String message) {
    try {
      (_out ?? UdpSendQueue(socket)).send(buildError(code, message), to.address, to.port);
    } catch (_) {}
  }

  /// 250ms마다: 진행 중인 전송의 속도를 갱신하고, 바뀐 것이 있으면 스냅샷을 예약한다.
  void _tick() {
    if (_active.isEmpty && !_dirty) return;
    final now = DateTime.now();
    for (final t in _active.values) {
      t.updateRate(now);
    }
    _publish();
    _dirty = _active.isNotEmpty;
  }

  void _publish() {
    scheduleSnapshot('transfers', () {
      final active = [for (final t in _active.values) TftpTransferInfo.of(t)]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return TftpTransfersEvent(
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
    for (final t in _active.values) {
      if (t.upload == upload) sum += t.bytes;
    }
    return sum;
  }

  static String _hexDump(Uint8List data) {
    final limit = data.length > 64 ? 64 : data.length;
    return [for (var i = 0; i < limit; i++) data[i].toRadixString(16).padLeft(2, '0')].join(' ') + (data.length > limit ? ' …' : '');
  }
}
