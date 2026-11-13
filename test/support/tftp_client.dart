// 시험용 TFTP 클라이언트: 실제 UDP loopback으로 서버와 대화한다. 옵션 협상, 윈도우 전송, 패킷 유실 흉내를 지원한다.

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lab_daemon/core/tftp/netascii.dart';
import 'package:lab_daemon/core/udp_queue.dart';
import 'package:lab_daemon/core/tftp/packet.dart';

class TftpResult {
  Uint8List? data;
  int? errorCode;
  String? errorMessage;
  Map<String, String> oack = {};
  int dataPackets = 0;
  int duplicatePackets = 0;
  int acks = 0;
  int retransmits = 0;
  int serverPort = 0;
  bool timedOut = false;

  bool get ok => errorCode == null && !timedOut;
}

class _Udp {
  _Udp._(this.socket) : out = UdpSendQueue(socket) {
    socket.listen((e) {
      if (e == RawSocketEvent.write) {
        out.onWritable();
        return;
      }
      if (e != RawSocketEvent.read) return;
      for (var d = socket.receive(); d != null; d = socket.receive()) {
        queue.add(d);
        _wake?.complete();
        _wake = null;
      }
    });
  }

  static Future<_Udp> open() async => _Udp._(await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0));

  final RawDatagramSocket socket;
  final UdpSendQueue out;
  final queue = Queue<Datagram>();
  Completer<void>? _wake;

  Future<Datagram?> next(Duration timeout) async {
    if (queue.isEmpty) {
      final c = Completer<void>();
      _wake = c;
      final t = Timer(timeout, () {
        if (!c.isCompleted) c.complete();
      });
      await c.future;
      t.cancel();
    }
    return queue.isEmpty ? null : queue.removeFirst();
  }

  void send(Uint8List data, int port) => out.send(data, InternetAddress.loopbackIPv4, port);

  void close() => socket.close();
}

/// 서버에서 파일을 받는다. [dropBlocks]에 든 블록 번호는 처음 한 번 못 받은 척한다.
Future<TftpResult> tftpGet({
  required int port,
  required String file,
  String mode = 'octet',
  Map<String, String> options = const {},
  Set<int> dropBlocks = const {},
  Duration timeout = const Duration(seconds: 5),
}) async {
  final udp = await _Udp.open();
  final result = TftpResult();
  final out = BytesBuilder(copy: false);
  final decoder = mode == 'netascii' ? NetasciiDecoder() : null;
  final dropped = <int>{};
  try {
    udp.send(buildRequest(write: false, filename: file, mode: mode, options: options), port);
    var blksize = tftpDefaultBlockSize;
    var window = 1;
    var next = 1;
    var sinceAck = 0;
    int? serverPort;
    while (true) {
      final d = await udp.next(timeout);
      if (d == null) {
        result.timedOut = true;
        break;
      }
      serverPort ??= d.port;
      result.serverPort = serverPort;
      final op = tftpOpcode(d.data);
      if (op == TftpOp.error) {
        final e = parseError(d.data)!;
        result.errorCode = e.$1;
        result.errorMessage = e.$2;
        break;
      }
      if (op == TftpOp.oack) {
        result.oack = parseOack(d.data)!;
        blksize = int.tryParse(result.oack['blksize'] ?? '') ?? blksize;
        window = int.tryParse(result.oack['windowsize'] ?? '') ?? 1;
        udp.send(buildAck(0), serverPort);
        continue;
      }
      if (op != TftpOp.data) continue;
      final block = tftpBlock(d.data);
      if (dropBlocks.contains(next) && !dropped.contains(next) && block == (next & 0xFFFF)) {
        dropped.add(next);
        continue;
      }
      if (block != (next & 0xFFFF)) {
        result.duplicatePackets++;
        udp.send(buildAck(next - 1), serverPort);
        continue;
      }
      result.dataPackets++;
      final payload = Uint8List.sublistView(d.data, 4);
      out.add(decoder == null ? payload : decoder.convert(payload));
      next++;
      sinceAck++;
      final last = payload.length < blksize;
      if (last || sinceAck >= window) {
        udp.send(buildAck(next - 1), serverPort);
        result.acks++;
        sinceAck = 0;
      }
      if (last) {
        if (decoder != null) out.add(decoder.finish());
        result.data = out.takeBytes();
        break;
      }
    }
  } finally {
    udp.close();
  }
  return result;
}

/// 서버로 파일을 올린다. [dropAckOnce]에 든 ACK 번호는 처음 한 번 못 받은 척한다.
Future<TftpResult> tftpPut({
  required int port,
  required String file,
  required Uint8List data,
  String mode = 'octet',
  Map<String, String> options = const {},
  Duration timeout = const Duration(seconds: 2),
  int retries = 5,
  Set<int> dropAckOnce = const {},
}) async {
  final udp = await _Udp.open();
  final result = TftpResult();
  final dropped = <int>{};
  try {
    udp.send(buildRequest(write: true, filename: file, mode: mode, options: options), port);
    var blksize = tftpDefaultBlockSize;
    var window = 1;
    var serverPort = 0;

    // 첫 응답: OACK 또는 ACK 0 또는 ERROR.
    final first = await udp.next(timeout);
    if (first == null) {
      result.timedOut = true;
      return result;
    }
    serverPort = first.port;
    result.serverPort = serverPort;
    final op = tftpOpcode(first.data);
    if (op == TftpOp.error) {
      final e = parseError(first.data)!;
      result.errorCode = e.$1;
      result.errorMessage = e.$2;
      return result;
    }
    if (op == TftpOp.oack) {
      result.oack = parseOack(first.data)!;
      blksize = int.tryParse(result.oack['blksize'] ?? '') ?? blksize;
      window = int.tryParse(result.oack['windowsize'] ?? '') ?? 1;
    }

    final payload = mode == 'netascii' ? NetasciiEncoder().convert(data) : data;
    final totalBlocks = payload.length ~/ blksize + 1;
    Uint8List blockAt(int seq) => Uint8List.sublistView(payload, (seq - 1) * blksize, math.min(seq * blksize, payload.length));

    var base = 1;
    var attempts = 0;
    while (base <= totalBlocks) {
      final end = math.min(base + window - 1, totalBlocks);
      for (var seq = base; seq <= end; seq++) {
        udp.send(buildData(seq, blockAt(seq)), serverPort);
        result.dataPackets++;
      }
      final d = await udp.next(timeout);
      if (d == null) {
        if (++attempts > retries) {
          result.timedOut = true;
          return result;
        }
        result.retransmits++;
        continue;
      }
      final o = tftpOpcode(d.data);
      if (o == TftpOp.error) {
        final e = parseError(d.data)!;
        result.errorCode = e.$1;
        result.errorMessage = e.$2;
        return result;
      }
      if (o != TftpOp.ack) continue;
      final acked = tftpBlock(d.data);
      if (dropAckOnce.contains(acked) && !dropped.contains(acked)) {
        dropped.add(acked);
        continue;
      }
      result.acks++;
      // 하위 16비트가 같은 순번 중 base 이후 것.
      for (var seq = end; seq >= base; seq--) {
        if ((seq & 0xFFFF) == acked) {
          base = seq + 1;
          attempts = 0;
          break;
        }
      }
    }
    result.data = data;
  } finally {
    udp.close();
  }
  return result;
}
