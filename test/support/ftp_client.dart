// 시험용 FTP 클라이언트: 실제 TCP loopback으로 제어·데이터 연결을 연다.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FtpReply {
  const FtpReply(this.code, this.text);

  final int code;
  final String text;

  @override
  String toString() => '$code $text';
}

class FtpTestClient {
  FtpTestClient._(this._socket) {
    _socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
      (line) {
        _lines.add(line);
        _wake?.complete();
        _wake = null;
      },
      onDone: () {
        closed = true;
        _wake?.complete();
        _wake = null;
      },
      onError: (_) {},
    );
  }

  static Future<FtpTestClient> connect(int port) async => FtpTestClient._(await Socket.connect(InternetAddress.loopbackIPv4, port));

  final Socket _socket;
  final _lines = Queue<String>();
  Completer<void>? _wake;
  bool closed = false;

  Future<String?> _line(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_lines.isEmpty) {
      if (closed) return null;
      final c = Completer<void>();
      _wake = c;
      final left = deadline.difference(DateTime.now());
      if (left.isNegative) return null;
      final t = Timer(left, () {
        if (!c.isCompleted) c.complete();
      });
      await c.future;
      t.cancel();
    }
    return _lines.removeFirst();
  }

  /// 다음 응답 (여러 줄 응답은 합친다). 시간 안에 없으면 code 0.
  Future<FtpReply> reply({Duration timeout = const Duration(seconds: 5)}) async {
    final first = await _line(timeout);
    if (first == null || first.length < 3) return const FtpReply(0, '');
    final code = int.tryParse(first.substring(0, 3)) ?? 0;
    if (first.length > 3 && first[3] == '-') {
      final lines = [first.substring(4)];
      while (true) {
        final l = await _line(timeout);
        if (l == null) break;
        if (l.startsWith('$code ')) {
          lines.add(l.substring(4));
          break;
        }
        lines.add(l.trim());
      }
      return FtpReply(code, lines.join('\n'));
    }
    return FtpReply(code, first.length > 4 ? first.substring(4) : '');
  }

  Future<FtpReply> cmd(String line) async {
    _socket.write('$line\r\n');
    return reply();
  }

  /// 220 인사를 받고 로그인한다. 마지막 응답을 돌려준다.
  Future<FtpReply> login(String user, String password) async {
    await reply();
    final u = await cmd('USER $user');
    if (u.code != 331) return u;
    return cmd('PASS $password');
  }

  /// PASV(또는 EPSV)로 데이터 포트를 얻는다.
  Future<int> passive({bool extended = false}) async {
    final r = await cmd(extended ? 'EPSV' : 'PASV');
    if (extended) {
      final m = RegExp(r'\|\|\|(\d+)\|').firstMatch(r.text) ?? (throw StateError('EPSV reply: $r'));
      return int.parse(m.group(1)!);
    }
    final m = RegExp(r'\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)').firstMatch(r.text) ?? (throw StateError('PASV reply: $r'));
    return int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
  }

  /// 데이터 명령(LIST, RETR 등)을 보내고 데이터와 마지막 응답을 받는다.
  Future<(Uint8List?, FtpReply, FtpReply)> download(String command, {bool extended = false}) async {
    final port = await passive(extended: extended);
    final data = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final bytes = BytesBuilder(copy: false);
    final done = data.listen(bytes.add).asFuture<void>();
    final opening = await cmd(command);
    if (opening.code != 150) {
      data.destroy();
      return (null, opening, opening);
    }
    await done;
    final end = await reply(timeout: const Duration(seconds: 60));
    return (bytes.takeBytes(), opening, end);
  }

  /// STOR/APPE로 [payload]를 올린다.
  Future<(FtpReply, FtpReply)> upload(String command, Uint8List payload) async {
    final port = await passive();
    final data = await Socket.connect(InternetAddress.loopbackIPv4, port);
    final opening = await cmd(command);
    if (opening.code != 150) {
      data.destroy();
      return (opening, opening);
    }
    data.add(payload);
    await data.flush();
    await data.close();
    final end = await reply(timeout: const Duration(seconds: 60));
    return (opening, end);
  }

  Future<void> close() async {
    _socket.destroy();
  }
}
