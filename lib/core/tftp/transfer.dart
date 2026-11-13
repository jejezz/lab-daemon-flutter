// TFTP 전송 하나 (읽기 또는 쓰기). 전송마다 자기 UDP 소켓(= TID)과 수신함을 가지고, 서비스 Isolate 안에서
// 다른 전송과 독립적으로 돈다. 클라이언트가 요청한 옵션을 협상하고, 윈도우 전송(RFC 7440)과 재전송을 처리한다.
//
// 성능: 패킷마다 하는 일은 소켓 송수신과 파일 읽기·쓰기뿐이다. 로그는 전송 시작과 끝에만 남기고(패킷 로깅
// 옵션을 켠 때만 패킷마다), 진행 상황은 숫자 필드만 갱신한다 — 화면용 표는 서버가 일정 간격에 읽어 간다.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../fs_sandbox.dart';
import '../udp_queue.dart';
import 'config.dart';
import 'netascii.dart';
import 'packet.dart';

enum TransferState { active, done, failed }

/// 전송이 실패한 이유. [reason]은 화면이 번역하는 짧은 이름이다.
/// `accessViolation`, `notFound`, `fileExists`, `writeDisabled`, `timeout`, `clientError`, `aborted`,
/// `diskFull`, `io`, `unsupportedMode`.
class TftpFailure implements Exception {
  TftpFailure(this.reason, [this.detail]);

  final String reason;
  final String? detail;

  @override
  String toString() => 'TftpFailure($reason${detail == null ? '' : ': $detail'})';
}

class _Inbox {
  final _queue = Queue<Datagram>();
  Completer<void>? _wake;

  void add(Datagram d) {
    _queue.add(d);
    wake();
  }

  void wake() {
    final c = _wake;
    _wake = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// 다음 패킷. [timeout] 안에 없으면 null. [wake]로 깨우면 빈 채로 돌아온다.
  Future<Datagram?> next(Duration timeout) async {
    if (_queue.isEmpty) {
      final c = Completer<void>();
      _wake = c;
      final timer = Timer(timeout, wake);
      await c.future;
      timer.cancel();
    }
    return _queue.isEmpty ? null : _queue.removeFirst();
  }
}

class TftpTransfer {
  TftpTransfer({
    required this.id,
    required this.request,
    required this.client,
    required this.clientPort,
    required this.socket,
    required this.config,
    required this.sandbox,
    required this.claimWrite,
    required this.releaseWrite,
  }) : startedAt = DateTime.now() {
    timeout = Duration(milliseconds: config.timeoutMs);
    _out = UdpSendQueue(socket, limit: math.max(64, config.maxWindowSize * 4));
  }

  final int id;
  final TftpRequest request;
  final InternetAddress client;
  final int clientPort;
  final RawDatagramSocket socket;
  final TftpConfig config;
  final FsSandbox sandbox;

  /// 같은 파일을 두 곳에서 동시에 올리지 못하게 서버가 관리하는 집합.
  final bool Function(String path) claimWrite;
  final void Function(String path) releaseWrite;

  // 화면이 읽는 진행 상황.
  TransferState state = TransferState.active;
  int bytes = 0;
  int? size;
  int blksize = tftpDefaultBlockSize;
  int windowsize = 1;
  double rate = 0;
  String? failure;
  String? failureDetail;
  final DateTime startedAt;
  DateTime? endedAt;
  String mode = 'octet';

  late Duration timeout;
  late final UdpSendQueue _out;
  bool _aborted = false;
  final _inbox = _Inbox();
  StreamSubscription<RawSocketEvent>? _subscription;
  int _lastBytes = 0;
  DateTime _lastTick = DateTime.now();

  String get clientKey => '${client.address}:$clientPort';

  bool get upload => request.write;

  /// 지난 호출 이후 평균 전송 속도(바이트/초)를 갱신한다. 서버가 일정 간격으로 부른다.
  void updateRate(DateTime now) {
    final dt = now.difference(_lastTick).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final instant = (bytes - _lastBytes) / dt;
    rate = rate == 0 ? instant : rate * 0.5 + instant * 0.5;
    _lastBytes = bytes;
    _lastTick = now;
  }

  /// 전송을 중단한다. [run]이 `aborted`로 끝난다.
  void abort() {
    _aborted = true;
    _inbox.wake();
  }

  void _send(Uint8List packet) => _out.send(packet, client, clientPort);

  void _sendError(int code, String message) {
    try {
      _send(buildError(code, message));
    } catch (_) {}
  }

  /// 전송을 끝까지 수행한다. 실패하면 [TftpFailure]를 던진다 (클라이언트에는 ERROR 패킷을 이미 보냈다).
  Future<void> run() async {
    _subscription = socket.listen((event) {
      if (event == RawSocketEvent.write) {
        _out.onWritable();
        return;
      }
      if (event != RawSocketEvent.read) return;
      for (var d = socket.receive(); d != null; d = socket.receive()) {
        if (d.address == client && d.port == clientPort) {
          _inbox.add(d);
        } else {
          // 전송 도중 끼어든 다른 출처: 오류를 돌려주고 우리 전송은 그대로 둔다 (RFC 1350 §4).
          _out.send(buildError(TftpError.unknownTid, 'Unknown transfer ID'), d.address, d.port);
        }
      }
    });
    try {
      mode = request.mode;
      if (mode != 'octet' && mode != 'netascii') {
        _sendError(TftpError.illegalOperation, 'Unsupported transfer mode');
        throw TftpFailure('unsupportedMode', request.mode);
      }
      if (upload) {
        await _runWrite();
      } else {
        await _runRead();
      }
      state = TransferState.done;
    } on TftpFailure catch (e) {
      state = TransferState.failed;
      failure = e.reason;
      failureDetail = e.detail;
      rethrow;
    } finally {
      endedAt = DateTime.now();
      await _subscription?.cancel();
      socket.close();
    }
  }

  // ---- 옵션 협상 (RFC 2347~2349, 7440) --------------------------------------------------------------

  /// 클라이언트가 요청한 옵션 중 받아들인 것. 받아들인 옵션이 하나도 없으면 비어 있고 OACK 없이 바로 시작한다.
  Map<String, String> _negotiate({int? fileSize}) {
    final accepted = <String, String>{};
    final o = request.options;

    final blk = int.tryParse(o['blksize'] ?? '');
    if (blk != null && blk >= 8 && blk <= 65464) {
      blksize = math.min(blk, config.maxBlockSize);
      accepted['blksize'] = '$blksize';
    }
    final to = int.tryParse(o['timeout'] ?? '');
    if (to != null && to >= 1 && to <= 255) {
      timeout = Duration(seconds: to);
      accepted['timeout'] = '$to';
    }
    if (o.containsKey('tsize')) {
      if (upload) {
        final announced = int.tryParse(o['tsize']!);
        if (announced != null && announced >= 0) {
          size = announced;
          accepted['tsize'] = '$announced';
        }
      } else if (fileSize != null && mode == 'octet') {
        // netascii는 변환 뒤 크기가 달라져서 알려 줄 수 없다.
        size = fileSize;
        accepted['tsize'] = '$fileSize';
      }
    }
    final win = int.tryParse(o['windowsize'] ?? '');
    if (win != null && win >= 1 && win <= 65535) {
      windowsize = math.min(win, config.maxWindowSize);
      accepted['windowsize'] = '$windowsize';
    }
    if (!upload) size ??= fileSize;
    return accepted;
  }

  /// 블록 번호 [wire](2바이트)가 가리키는 순번: [low]..[high] 중 하위 16비트가 같은 것. 없으면 -1.
  static int _resolve(int wire, int low, int high) {
    for (var s = high; s >= low; s--) {
      if ((s & 0xFFFF) == wire) return s;
    }
    return -1;
  }

  // ---- 읽기 (서버 → 클라이언트) ----------------------------------------------------------------------

  Future<void> _runRead() async {
    final String path;
    try {
      path = sandbox.resolve(request.filename);
    } on SandboxViolation {
      _sendError(TftpError.accessViolation, 'Access violation');
      throw TftpFailure('accessViolation');
    }
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
      _sendError(TftpError.notFound, 'File not found');
      throw TftpFailure('notFound');
    }

    RandomAccessFile file;
    int fileSize;
    try {
      file = await File(path).open();
      fileSize = await file.length();
    } on FileSystemException catch (e) {
      _sendError(TftpError.accessViolation, 'Access violation');
      throw TftpFailure('accessViolation', e.osError?.message);
    }
    try {
      final accepted = _negotiate(fileSize: fileSize);
      final source = _BufferedSource(file, () => blksize, mode == 'netascii' ? NetasciiEncoder().convert : null);

      if (accepted.isNotEmpty) {
        // 옵션이 있으면 OACK를 보내고 클라이언트의 ACK 0을 기다린다.
        await _awaitAck0(buildOack(accepted));
      }

      final inflight = <int, Uint8List>{};
      var base = 1;
      var next = 1;
      int? lastSeq;
      var retries = 0;
      // 진전이 없는 동안 중복 ACK로 다시 보낸 적이 있는가 (중복 ACK마다 다시 보내면 패킷이 불어난다).
      var fastResent = false;

      while (true) {
        if (_aborted) throw TftpFailure('aborted');
        // 창이 찰 때까지 읽어서 보낸다.
        while (lastSeq == null && next < base + windowsize) {
          final block = await source.next();
          if (_aborted) throw TftpFailure('aborted');
          inflight[next] = block;
          if (block.length < blksize) lastSeq = next;
          _send(buildData(next, block));
          next++;
        }
        if (inflight.isEmpty) break;

        final packet = await _inbox.next(timeout);
        if (_aborted) throw TftpFailure('aborted');
        if (packet == null) {
          if (++retries > config.maxRetries) {
            _sendError(TftpError.undefined, 'Timeout');
            throw TftpFailure('timeout');
          }
          for (final seq in (inflight.keys.toList()..sort())) {
            _send(buildData(seq, inflight[seq]!));
          }
          continue;
        }
        final data = packet.data;
        final op = tftpOpcode(data);
        if (op == TftpOp.error) {
          throw TftpFailure('clientError', parseError(data)?.$2);
        }
        if (op != TftpOp.ack) {
          _sendError(TftpError.illegalOperation, 'Illegal TFTP operation');
          continue;
        }
        final acked = _resolve(tftpBlock(data), base - 1, next - 1);
        if (acked < base) {
          // 이미 처리한 블록의 ACK. 윈도우 전송에서 base-1의 ACK는 "그다음 블록을 못 받았다"는 뜻이라
          // 시간 초과를 기다리지 않고 한 번만 다시 보낸다 (RFC 7440 §4). 한 블록씩 보낼 때는 다시 보내지 않는다
          // (Sorcerer's Apprentice 방지).
          if (acked == base - 1 && windowsize > 1 && !fastResent) {
            fastResent = true;
            for (final seq in (inflight.keys.toList()..sort())) {
              _send(buildData(seq, inflight[seq]!));
            }
          }
          continue;
        }
        for (var seq = base; seq <= acked; seq++) {
          final len = inflight.remove(seq)?.length ?? 0;
          bytes += len;
        }
        base = acked + 1;
        retries = 0;
        fastResent = false;
      }
    } on FileSystemException catch (e) {
      _sendError(TftpError.undefined, 'Read error');
      throw TftpFailure('io', e.osError?.message ?? e.message);
    } finally {
      await file.close();
    }
  }

  /// OACK를 보내고 ACK 0을 기다린다. 응답이 없으면 다시 보낸다.
  Future<void> _awaitAck0(Uint8List oack) async {
    var retries = 0;
    _send(oack);
    while (true) {
      final packet = await _inbox.next(timeout);
      if (_aborted) throw TftpFailure('aborted');
      if (packet == null) {
        if (++retries > config.maxRetries) {
          _sendError(TftpError.undefined, 'Timeout');
          throw TftpFailure('timeout');
        }
        _send(oack);
        continue;
      }
      final op = tftpOpcode(packet.data);
      if (op == TftpOp.error) {
        // 클라이언트가 옵션을 거부했다 (RFC 2347: 오류 8).
        throw TftpFailure('clientError', parseError(packet.data)?.$2);
      }
      if (op == TftpOp.ack && tftpBlock(packet.data) == 0) return;
    }
  }

  // ---- 쓰기 (클라이언트 → 서버) ----------------------------------------------------------------------

  Future<void> _runWrite() async {
    if (!config.allowWrite) {
      _sendError(TftpError.accessViolation, 'Write not allowed');
      throw TftpFailure('writeDisabled');
    }
    final String path;
    try {
      path = sandbox.resolve(request.filename);
    } on SandboxViolation {
      _sendError(TftpError.accessViolation, 'Access violation');
      throw TftpFailure('accessViolation');
    }
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      _sendError(TftpError.accessViolation, 'Access violation');
      throw TftpFailure('accessViolation');
    }
    if (type == FileSystemEntityType.file && !config.allowOverwrite) {
      _sendError(TftpError.fileExists, 'File already exists');
      throw TftpFailure('fileExists');
    }
    if (!Directory(File(path).parent.path).existsSync()) {
      _sendError(TftpError.notFound, 'Directory not found');
      throw TftpFailure('notFound');
    }
    if (!claimWrite(path)) {
      _sendError(TftpError.accessViolation, 'File is being written by another client');
      throw TftpFailure('accessViolation', 'busy');
    }

    // 임시 파일에 받다가 끝나면 이름을 바꾼다: 중간에 끊겨도 기존 파일이 깨지지 않는다.
    final temp = '$path.lab-part-$id';
    RandomAccessFile? sink;
    var completed = false;
    try {
      final s = sink = await File(temp).open(mode: FileMode.write);
      final accepted = _negotiate();
      final decoder = mode == 'netascii' ? NetasciiDecoder() : null;

      Uint8List lastReply = accepted.isNotEmpty ? buildOack(accepted) : buildAck(0);
      _send(lastReply);
      var expected = 1;
      var sinceAck = 0;
      var retries = 0;

      while (true) {
        if (_aborted) throw TftpFailure('aborted');
        final packet = await _inbox.next(timeout);
        if (_aborted) throw TftpFailure('aborted');
        if (packet == null) {
          if (++retries > config.maxRetries) {
            _sendError(TftpError.undefined, 'Timeout');
            throw TftpFailure('timeout');
          }
          _send(lastReply);
          continue;
        }
        final data = packet.data;
        final op = tftpOpcode(data);
        if (op == TftpOp.error) throw TftpFailure('clientError', parseError(data)?.$2);
        if (op != TftpOp.data || data.length < 4) {
          _sendError(TftpError.illegalOperation, 'Illegal TFTP operation');
          continue;
        }
        if (tftpBlock(data) != (expected & 0xFFFF)) {
          // 순서가 틀린 블록이나 중복: 마지막으로 제대로 받은 블록을 다시 확인해 준다.
          _send(lastReply);
          continue;
        }
        retries = 0;
        final payload = Uint8List.sublistView(data, 4);
        final out = decoder == null ? payload : decoder.convert(payload);
        final last = payload.length < blksize;
        try {
          if (out.isNotEmpty) await s.writeFrom(out);
          if (last && decoder != null) {
            final tail = decoder.finish();
            if (tail.isNotEmpty) await s.writeFrom(tail);
          }
        } on FileSystemException catch (e) {
          _sendError(TftpError.diskFull, 'Disk full or allocation exceeded');
          throw TftpFailure('diskFull', e.osError?.message ?? e.message);
        }
        bytes += payload.length;
        expected++;
        sinceAck++;
        if (last || sinceAck >= windowsize) {
          lastReply = buildAck(expected - 1);
          _send(lastReply);
          sinceAck = 0;
        }
        if (last) {
          await s.flush();
          await s.close();
          sink = null;
          await File(temp).rename(path);
          completed = true;
          await _dally(lastReply);
          return;
        }
      }
    } on FileSystemException catch (e) {
      _sendError(TftpError.undefined, 'Write error');
      throw TftpFailure('io', e.osError?.message ?? e.message);
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (!completed) {
        try {
          await File(temp).delete();
        } catch (_) {}
      }
      releaseWrite(path);
    }
  }

  /// 마지막 ACK가 유실돼서 클라이언트가 마지막 DATA를 다시 보내면 ACK를 다시 보내 준다.
  Future<void> _dally(Uint8List lastAck) async {
    final wait = Duration(milliseconds: math.min(timeout.inMilliseconds, 500));
    while (true) {
      final packet = await _inbox.next(wait);
      if (packet == null || _aborted) return;
      if (tftpOpcode(packet.data) == TftpOp.data) _send(lastAck);
    }
  }
}

// ---- 읽기용 블록 공급자 -----------------------------------------------------------------------------

abstract class _BlockSource {
  /// 다음 블록. 블록 크기보다 짧으면(비어 있어도) 마지막 블록이다.
  Future<Uint8List> next();
}

/// 파일을 큰 덩어리(기본 64KB)로 읽어 두고 블록 크기만큼씩 잘라 준다. 블록마다 비동기 읽기를 하면
/// 작은 블록에서 읽기 호출 수가 패킷 수만큼 늘어나 느려진다. [_transform]이 있으면 읽은 덩어리에 적용한다 (netascii).
class _BufferedSource implements _BlockSource {
  _BufferedSource(this._file, this._blksize, [this._transform]);

  final RandomAccessFile _file;
  final int Function() _blksize;
  final Uint8List Function(Uint8List chunk)? _transform;

  var _buffer = Uint8List(0);
  var _position = 0;
  var _eof = false;

  @override
  Future<Uint8List> next() async {
    final want = _blksize();
    while (_buffer.length - _position < want && !_eof) {
      final chunk = await _file.read(math.max(65536, want * 16));
      if (chunk.isEmpty) {
        _eof = true;
        break;
      }
      final converted = _transform == null ? chunk : _transform(chunk);
      if (_position >= _buffer.length) {
        _buffer = converted;
      } else {
        _buffer = (BytesBuilder(copy: false)
              ..add(Uint8List.sublistView(_buffer, _position))
              ..add(converted))
            .takeBytes();
      }
      _position = 0;
    }
    final take = math.min(want, _buffer.length - _position);
    // 복사본을 돌려준다: 확인 응답을 기다리는 동안 inflight에 남아 있어야 한다.
    final block = Uint8List.fromList(Uint8List.sublistView(_buffer, _position, _position + take));
    _position += take;
    return block;
  }
}
