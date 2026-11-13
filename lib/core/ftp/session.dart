// FTP 제어 연결 하나 (RFC 959, 2389 FEAT, 2428 EPSV/EPRT, 3659 SIZE·MDTM·MLSD·REST).
//
// 보안:
//   - 경로는 가상 경로(`/` 기준)로 다루고 `..`은 루트에서 더 올라가지 못한다. 실제 경로는 [FsSandbox]가
//     링크까지 풀어서 루트 안인지 다시 확인한다.
//   - 데이터 연결은 제어 연결과 같은 주소에서 온 것만 받는다 (데이터 연결 가로채기 방지). PORT/EPRT도 제어
//     연결의 주소로만 연결한다 (FTP bounce 방지).
//   - 로그인 실패마다 1초 늦추고 3번 실패하면 끊는다.
//   - 쓰기(STOR·APPE·DELE·MKD·RMD·RNFR/RNTO)는 "쓰기 허용"을 켰을 때만 할 수 있다.
//
// 성능: 파일은 스트림으로 흘려보내고(파일 전체를 메모리에 올리지 않는다) 바이트 수만 센다. 로그는 명령마다가
// 아니라 로그인·전송·변경 같은 사건에만 남긴다 (명령 로깅 옵션을 켠 때만 명령마다).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../fs_sandbox.dart';
import '../service.dart';
import 'config.dart';

typedef FtpLog = void Function(LogLevel level, String key, {String? kind, Map<String, Object?> args});

/// 진행 중인 데이터 전송 하나.
class FtpTransfer {
  FtpTransfer({required this.file, required this.upload, required this.size}) : startedAt = DateTime.now();

  final String file;
  final bool upload;
  final int? size;
  final DateTime startedAt;
  int bytes = 0;
  double rate = 0;
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
}

class FtpSession {
  FtpSession({
    required this.id,
    required this.control,
    required this.config,
    required this.sandbox,
    required this.log,
    required this.openPassive,
    required this.onClosed,
    required this.onChanged,
  })  : client = '${control.remoteAddress.address}:${control.remotePort}',
        connectedAt = DateTime.now();

  final int id;
  final Socket control;
  final FtpConfig config;
  final FsSandbox sandbox;
  final FtpLog log;

  /// 제어 연결이 들어온 NIC 주소에 패시브 포트 범위 중 빈 포트를 연다. 없으면 null.
  final Future<ServerSocket?> Function(InternetAddress address) openPassive;
  final void Function(FtpSession session) onClosed;

  /// 화면에 보이는 상태(사용자·폴더·마지막 명령·바이트 수)가 바뀌었다. 서버는 표시만 해 두고 다음 틱에 표를 만든다.
  final void Function() onChanged;

  final String client;
  final DateTime connectedAt;

  // 화면이 읽는 상태.
  String? user;
  bool authenticated = false;
  bool canWrite = false;
  String lastCommand = '';
  int bytesIn = 0;
  int bytesOut = 0;
  int filesIn = 0;
  int filesOut = 0;
  FtpTransfer? transfer;
  bool closed = false;

  List<String> _cwd = [];
  String? _pendingUser;
  int _failedLogins = 0;
  int _restOffset = 0;
  List<String>? _renameFrom;
  ServerSocket? _passive;
  (InternetAddress, int)? _active;
  Timer? _idle;
  bool _binary = true;

  String get cwd => _display(_cwd);

  static const _preAuth = {'USER', 'PASS', 'QUIT', 'FEAT', 'SYST', 'OPTS', 'NOOP', 'HELP', 'AUTH', 'PBSZ', 'PROT'};

  // ---- 수명 -----------------------------------------------------------------------------------

  Future<void> run() async {
    _reply(220, 'Lab Daemon FTP ready');
    _touch();
    try {
      final lines = control.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter());
      await for (final raw in lines) {
        if (closed) break;
        final line = raw.replaceAll(RegExp(r'[\u0000-\u001fÿ]'), '').trim();
        if (line.isEmpty) continue;
        if (line.length > 4096) {
          _reply(500, 'Line too long');
          continue;
        }
        _idle?.cancel();
        await _dispatch(line);
        onChanged();
        if (closed) break;
        _touch();
      }
    } catch (_) {
      // 연결이 끊어진 것으로 본다.
    } finally {
      await _cleanup();
    }
  }

  /// 서버가 끝내라고 할 때 (서비스 중지 등).
  Future<void> close(String message) async {
    if (closed) return;
    _reply(421, message);
    await _cleanup();
  }

  void _touch() {
    _idle?.cancel();
    _idle = Timer(Duration(seconds: config.idleTimeoutSeconds), () {
      log(LogLevel.info, 'logFtpIdleTimeout', args: {'client': client, 'user': user});
      unawaited(close('Idle timeout, closing control connection'));
    });
  }

  Future<void> _cleanup() async {
    if (closed) return;
    closed = true;
    _idle?.cancel();
    await _closePassive();
    try {
      await control.flush();
    } catch (_) {}
    control.destroy();
    onClosed(this);
  }

  Future<void> _closePassive() async {
    final p = _passive;
    _passive = null;
    try {
      await p?.close();
    } catch (_) {}
  }

  // ---- 응답 -----------------------------------------------------------------------------------

  void _reply(int code, String text) {
    if (closed) return;
    try {
      control.write('$code $text\r\n');
    } catch (_) {}
  }

  void _replyLines(int code, List<String> lines, String last) {
    if (closed) return;
    final b = StringBuffer('$code-${lines.first}\r\n');
    for (final l in lines.skip(1)) {
      b.write(' $l\r\n');
    }
    b.write('$code $last\r\n');
    try {
      control.write(b.toString());
    } catch (_) {}
  }

  // ---- 경로 -----------------------------------------------------------------------------------

  /// 가상 경로 해석: 절대 경로는 루트부터, 상대 경로는 현재 폴더부터. `..`은 루트에서 멈춘다.
  List<String> _virtual(String arg) {
    final result = arg.startsWith('/') || arg.startsWith(r'\') ? <String>[] : [..._cwd];
    for (final part in arg.split(RegExp(r'[\\/]'))) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (result.isNotEmpty) result.removeLast();
        continue;
      }
      FsSandbox.segments(part); // 이름 검사 (드라이브 문자·예약 이름·와일드카드 등)
      result.add(part);
    }
    return result;
  }

  String _real(List<String> segments) => sandbox.resolve(segments.join('/'));

  static String _display(List<String> segments) => '/${segments.join('/')}';

  /// [arg]를 실제 경로로. 실패하면 550을 보내고 null.
  (List<String>, String)? _path(String arg) {
    try {
      final v = _virtual(arg);
      return (v, _real(v));
    } on SandboxViolation {
      _reply(550, 'Permission denied');
      return null;
    }
  }

  bool _requireWrite(String command, String arg) {
    if (canWrite) return true;
    log(LogLevel.warning, 'logFtpDenied', args: {'client': client, 'user': user, 'command': command, 'path': arg});
    _reply(550, 'Permission denied');
    return false;
  }

  // ---- 명령 -----------------------------------------------------------------------------------

  Future<void> _dispatch(String line) async {
    final space = line.indexOf(' ');
    final cmd = (space < 0 ? line : line.substring(0, space)).toUpperCase();
    final arg = space < 0 ? '' : line.substring(space + 1);
    lastCommand = cmd == 'PASS' ? 'PASS ****' : line;
    if (config.logCommands) {
      log(LogLevel.debug, 'logFtpCommand', kind: cmd, args: {'client': client, 'command': lastCommand});
    }
    if (!authenticated && !_preAuth.contains(cmd)) {
      _reply(530, 'Please login with USER and PASS');
      return;
    }
    switch (cmd) {
      case 'USER':
        _user(arg);
      case 'PASS':
        await _pass(arg);
      case 'QUIT':
        _reply(221, 'Goodbye');
        await _cleanup();
      case 'SYST':
        _reply(215, 'UNIX Type: L8');
      case 'FEAT':
        _replyLines(211, ['Features:', 'EPSV', 'EPRT', 'PASV', 'SIZE', 'MDTM', 'MLSD', 'REST STREAM', 'UTF8'], 'End');
      case 'OPTS':
        _reply(arg.toUpperCase().startsWith('UTF8') ? 200 : 501, arg.toUpperCase().startsWith('UTF8') ? 'UTF8 mode enabled' : 'Option not understood');
      case 'NOOP':
        _reply(200, 'OK');
      case 'HELP':
        _reply(214, 'See RFC 959');
      case 'AUTH':
      case 'PBSZ':
      case 'PROT':
        _reply(502, 'TLS is not supported');
      case 'PWD':
      case 'XPWD':
        _reply(257, '"${cwd.replaceAll('"', '""')}" is the current directory');
      case 'CWD':
      case 'XCWD':
        _cwdTo(arg);
      case 'CDUP':
      case 'XCUP':
        _cwdTo('..');
      case 'TYPE':
        final t = arg.toUpperCase();
        if (t.startsWith('A') || t.startsWith('I') || t.startsWith('L')) {
          _binary = !t.startsWith('A');
          _reply(200, 'Type set to ${_binary ? 'I' : 'A'}');
        } else {
          _reply(504, 'Type not supported');
        }
      case 'MODE':
        _reply(arg.toUpperCase() == 'S' ? 200 : 504, arg.toUpperCase() == 'S' ? 'Mode set to S' : 'Only stream mode is supported');
      case 'STRU':
        _reply(arg.toUpperCase() == 'F' ? 200 : 504, arg.toUpperCase() == 'F' ? 'Structure set to F' : 'Only file structure is supported');
      case 'PASV':
        await _pasv(extended: false);
      case 'EPSV':
        if (arg.toUpperCase() == 'ALL') {
          _reply(200, 'EPSV ALL ok');
        } else {
          await _pasv(extended: true);
        }
      case 'PORT':
        _port(arg);
      case 'EPRT':
        _eprt(arg);
      case 'LIST':
      case 'NLST':
      case 'MLSD':
        await _list(cmd, arg);
      case 'RETR':
        await _retr(arg);
      case 'STOR':
        await _stor(arg, append: false);
      case 'APPE':
        await _stor(arg, append: true);
      case 'REST':
        final n = int.tryParse(arg);
        if (n == null || n < 0) {
          _reply(501, 'Invalid restart position');
        } else {
          _restOffset = n;
          _reply(350, 'Restarting at $n');
        }
      case 'SIZE':
        _size(arg);
      case 'MDTM':
        _mdtm(arg);
      case 'DELE':
        await _dele(arg);
      case 'MKD':
      case 'XMKD':
        await _mkd(arg);
      case 'RMD':
      case 'XRMD':
        await _rmd(arg);
      case 'RNFR':
        _rnfr(arg);
      case 'RNTO':
        await _rnto(arg);
      case 'ABOR':
        _reply(226, 'No transfer to abort');
      case 'STAT':
        _replyLines(211, ['Lab Daemon FTP status', 'Logged in as ${user ?? '-'}', 'Current directory $cwd'], 'End of status');
      case 'ALLO':
        _reply(202, 'No storage allocation necessary');
      case 'ACCT':
        _reply(202, 'Account not necessary');
      default:
        _reply(502, 'Command not implemented');
    }
    if (cmd != 'REST' && cmd != 'RETR' && cmd != 'STOR' && cmd != 'APPE') {
      // REST는 바로 다음 전송 명령에만 적용된다.
      if (cmd != 'TYPE' && cmd != 'PASV' && cmd != 'EPSV' && cmd != 'PORT' && cmd != 'EPRT') _restOffset = 0;
    }
  }

  // ---- 로그인 ---------------------------------------------------------------------------------

  void _user(String name) {
    if (authenticated) {
      _reply(530, 'Already logged in');
      return;
    }
    _pendingUser = name;
    final anonymous = FtpConfig.isAnonymousName(name);
    _reply(331, anonymous && config.allowAnonymous ? 'Anonymous login ok, send your email as password' : 'Password required');
  }

  Future<void> _pass(String password) async {
    final name = _pendingUser;
    if (authenticated) {
      _reply(503, 'Already logged in');
      return;
    }
    if (name == null) {
      _reply(503, 'Login with USER first');
      return;
    }
    final anonymous = FtpConfig.isAnonymousName(name);
    final account = config.account;
    final ok = (anonymous && config.allowAnonymous) || (!anonymous && account != null && account.username == name && account.verify(password));
    canWrite = ok && config.allowWrite;
    if (ok) {
      authenticated = true;
      user = anonymous ? 'anonymous' : name;
      log(LogLevel.info, 'logFtpLogin', kind: 'LOGIN', args: {'client': client, 'user': user, 'write': canWrite});
      _reply(230, 'Login successful');
      return;
    }
    _failedLogins++;
    log(LogLevel.warning, 'logFtpLoginFailed', kind: 'LOGIN', args: {'client': client, 'user': name});
    // 무차별 대입을 늦춘다.
    await Future<void>.delayed(const Duration(seconds: 1));
    _reply(530, 'Login incorrect');
    _pendingUser = null;
    if (_failedLogins >= 3) {
      _reply(421, 'Too many failed logins');
      await _cleanup();
    }
  }

  // ---- 폴더 이동 ------------------------------------------------------------------------------

  void _cwdTo(String arg) {
    final p = _path(arg.isEmpty ? '/' : arg);
    if (p == null) return;
    if (FileSystemEntity.isDirectorySync(p.$2)) {
      _cwd = p.$1;
      _reply(250, 'Directory changed to ${_display(p.$1)}');
    } else {
      _reply(550, 'No such directory');
    }
  }

  // ---- 데이터 연결 -----------------------------------------------------------------------------

  Future<void> _pasv({required bool extended}) async {
    await _closePassive();
    _active = null;
    final listener = await openPassive(control.address);
    if (listener == null) {
      _reply(425, 'No passive port available');
      return;
    }
    _passive = listener;
    final port = listener.port;
    if (extended) {
      _reply(229, 'Entering Extended Passive Mode (|||$port|)');
      return;
    }
    final announce = (config.passiveAddress?.toString() ?? control.address.address).split('.');
    _reply(227, 'Entering Passive Mode (${announce.join(',')},${port >> 8},${port & 0xFF})');
  }

  void _port(String arg) {
    final parts = arg.split(',').map((s) => int.tryParse(s.trim())).toList();
    if (parts.length != 6 || parts.any((p) => p == null || p < 0 || p > 255)) {
      _reply(501, 'Invalid PORT argument');
      return;
    }
    final address = InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.${parts[3]}');
    _setActive(address, (parts[4]! << 8) | parts[5]!);
  }

  void _eprt(String arg) {
    if (arg.length < 4) {
      _reply(501, 'Invalid EPRT argument');
      return;
    }
    final fields = arg.split(arg[0]);
    // |1|addr|port| → ['', '1', addr, port, '']
    if (fields.length < 5 || fields[1] != '1') {
      _reply(522, 'Only IPv4 is supported, use (1)');
      return;
    }
    final port = int.tryParse(fields[3]);
    final address = InternetAddress.tryParse(fields[2]);
    if (port == null || address == null || port < 1 || port > 65535) {
      _reply(501, 'Invalid EPRT argument');
      return;
    }
    _setActive(address, port);
  }

  void _setActive(InternetAddress address, int port) {
    if (address.address != control.remoteAddress.address) {
      // 다른 호스트로 데이터를 보내게 하는 FTP bounce 공격을 막는다.
      log(LogLevel.warning, 'logFtpDenied', args: {'client': client, 'user': user, 'command': 'PORT', 'path': '${address.address}:$port'});
      _reply(500, 'Illegal PORT command');
      return;
    }
    if (port < 1024) {
      _reply(500, 'Illegal PORT command');
      return;
    }
    unawaited(_closePassive());
    _active = (address, port);
    _reply(200, 'PORT command successful');
  }

  /// PASV/PORT로 준비한 데이터 연결을 연다. 실패하면 425를 보내고 null.
  Future<Socket?> _openData() async {
    final passive = _passive;
    final active = _active;
    _active = null;
    if (passive != null) {
      _passive = null;
      try {
        final socket = await passive.first.timeout(const Duration(seconds: 30));
        if (socket.remoteAddress.address != control.remoteAddress.address) {
          // 제어 연결과 다른 곳에서 들어온 데이터 연결은 받지 않는다.
          socket.destroy();
          log(LogLevel.warning, 'logFtpDenied', args: {'client': client, 'user': user, 'command': 'DATA', 'path': socket.remoteAddress.address});
          _reply(425, 'Data connection from a different address refused');
          return null;
        }
        return socket;
      } catch (_) {
        _reply(425, 'Cannot open data connection');
        return null;
      } finally {
        try {
          await passive.close();
        } catch (_) {}
      }
    }
    if (active != null) {
      try {
        return await Socket.connect(active.$1, active.$2, sourceAddress: control.address, timeout: const Duration(seconds: 15));
      } catch (_) {
        _reply(425, 'Cannot open data connection');
        return null;
      }
    }
    _reply(425, 'Use PASV or PORT first');
    return null;
  }

  // ---- 목록 -----------------------------------------------------------------------------------

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _listLine(String name, FileStat stat) {
    final dir = stat.type == FileSystemEntityType.directory;
    final m = stat.modified;
    final now = DateTime.now();
    final recent = now.difference(m).inDays.abs() < 180;
    final when = recent ? '${_two(m.hour)}:${_two(m.minute)}' : ' ${m.year}';
    final size = (dir ? 0 : stat.size).toString().padLeft(12);
    return '${dir ? 'd' : '-'}rw${dir ? 'x' : '-'}r-${dir ? 'x' : '-'}r-${dir ? 'x' : '-'} 1 ftp ftp $size ${_months[m.month - 1]} ${m.day.toString().padLeft(2)} ${when.padLeft(5)} $name';
  }

  static String _mlsdLine(String name, FileStat stat) {
    final m = stat.modified.toUtc();
    final modify = '${m.year}${_two(m.month)}${_two(m.day)}${_two(m.hour)}${_two(m.minute)}${_two(m.second)}';
    return stat.type == FileSystemEntityType.directory ? 'type=dir;modify=$modify; $name' : 'type=file;size=${stat.size};modify=$modify; $name';
  }

  Future<void> _list(String cmd, String arg) async {
    // `LIST -la`처럼 옵션을 붙이는 클라이언트가 많다: 옵션은 무시한다.
    final target = arg.split(' ').where((s) => s.isNotEmpty && !s.startsWith('-')).join(' ');
    final p = _path(target.isEmpty ? '.' : target);
    if (p == null) return;
    final type = FileSystemEntity.typeSync(p.$2);
    if (type == FileSystemEntityType.notFound) {
      _reply(550, 'No such file or directory');
      return;
    }
    final lines = <String>[];
    if (type == FileSystemEntityType.directory) {
      final entries = await Directory(p.$2).list(followLinks: false).toList();
      entries.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      for (final e in entries) {
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.contains('.lab-part')) continue; // 올리는 중인 임시 파일은 보이지 않는다
        if (cmd == 'NLST') {
          lines.add(name);
          continue;
        }
        final stat = await e.stat();
        lines.add(cmd == 'MLSD' ? _mlsdLine(name, stat) : _listLine(name, stat));
      }
    } else {
      final stat = await File(p.$2).stat();
      final name = p.$1.last;
      lines.add(cmd == 'NLST' ? name : (cmd == 'MLSD' ? _mlsdLine(name, stat) : _listLine(name, stat)));
    }
    final data = await _openData();
    if (data == null) return;
    _reply(150, 'Here comes the directory listing');
    try {
      final text = lines.isEmpty ? '' : '${lines.join('\r\n')}\r\n';
      final bytes = utf8.encode(text);
      data.add(bytes);
      await data.flush();
      bytesOut += bytes.length;
      await data.close();
      _reply(226, 'Directory send OK');
    } catch (_) {
      _reply(426, 'Connection closed; transfer aborted');
    } finally {
      data.destroy();
    }
  }

  // ---- 파일 정보 -------------------------------------------------------------------------------

  void _size(String arg) {
    final p = _path(arg);
    if (p == null) return;
    if (FileSystemEntity.typeSync(p.$2) != FileSystemEntityType.file) {
      _reply(550, 'Could not get file size');
      return;
    }
    _reply(213, '${File(p.$2).lengthSync()}');
  }

  void _mdtm(String arg) {
    final p = _path(arg);
    if (p == null) return;
    if (FileSystemEntity.typeSync(p.$2) != FileSystemEntityType.file) {
      _reply(550, 'Could not get modification time');
      return;
    }
    final m = File(p.$2).lastModifiedSync().toUtc();
    _reply(213, '${m.year}${_two(m.month)}${_two(m.day)}${_two(m.hour)}${_two(m.minute)}${_two(m.second)}');
  }

  // ---- 받기 -----------------------------------------------------------------------------------

  Future<void> _retr(String arg) async {
    final offset = _restOffset;
    _restOffset = 0;
    final p = _path(arg);
    if (p == null) return;
    if (FileSystemEntity.typeSync(p.$2) != FileSystemEntityType.file) {
      _reply(550, 'File not found');
      return;
    }
    final file = File(p.$2);
    final size = await file.length();
    if (offset > size) {
      _reply(554, 'Restart position beyond end of file');
      return;
    }
    final data = await _openData();
    if (data == null) return;
    final display = _display(p.$1);
    final t = FtpTransfer(file: display, upload: false, size: size);
    transfer = t;
    t.bytes = offset;
    _reply(150, 'Opening ${_binary ? 'BINARY' : 'ASCII'} mode data connection for $display ($size bytes)');
    try {
      await data.addStream(file.openRead(offset).map((chunk) {
        t.bytes += chunk.length;
        bytesOut += chunk.length;
        return chunk;
      }));
      await data.flush();
      await data.close();
      filesOut++;
      _reply(226, 'Transfer complete');
      _logTransfer('logFtpDownload', t);
    } catch (e) {
      _reply(426, 'Connection closed; transfer aborted');
      log(LogLevel.warning, 'logFtpTransferFailed', kind: 'ERROR', args: {'client': client, 'user': user, 'file': display, 'error': '$e'});
    } finally {
      data.destroy();
      transfer = null;
    }
  }

  // ---- 올리기 ---------------------------------------------------------------------------------

  Future<void> _stor(String arg, {required bool append}) async {
    final offset = _restOffset;
    _restOffset = 0;
    if (!_requireWrite(append ? 'APPE' : 'STOR', arg)) return;
    final p = _path(arg);
    if (p == null) return;
    if (p.$1.isEmpty || FileSystemEntity.isDirectorySync(p.$2)) {
      _reply(553, 'Not a file name');
      return;
    }
    if (!Directory(File(p.$2).parent.path).existsSync()) {
      _reply(553, 'Directory does not exist');
      return;
    }
    final exists = FileSystemEntity.typeSync(p.$2) == FileSystemEntityType.file;
    var appendMode = append;
    if (offset > 0) {
      // 이어 올리기는 지금 파일 크기에서 이어 붙이는 경우만 받는다.
      if (!exists || File(p.$2).lengthSync() != offset) {
        _reply(554, 'Restart is only supported at the end of the file');
        return;
      }
      appendMode = true;
    }
    final data = await _openData();
    if (data == null) return;
    final display = _display(p.$1);
    final t = FtpTransfer(file: display, upload: true, size: null);
    transfer = t;
    _reply(150, 'Ok to send data');
    // 새로 올릴 때는 임시 파일에 받다가 끝나면 이름을 바꾼다: 중간에 끊겨도 기존 파일이 깨지지 않는다.
    final target = appendMode ? p.$2 : '${p.$2}.lab-part-$id';
    IOSink? sink;
    var completed = false;
    try {
      sink = File(target).openWrite(mode: appendMode ? FileMode.append : FileMode.write);
      await for (final chunk in data) {
        t.bytes += chunk.length;
        bytesIn += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (!appendMode) await File(target).rename(p.$2);
      completed = true;
      filesIn++;
      _reply(226, 'Transfer complete');
      _logTransfer('logFtpUpload', t);
    } catch (e) {
      _reply(e is FileSystemException ? 452 : 426, e is FileSystemException ? 'Cannot write file' : 'Connection closed; transfer aborted');
      log(LogLevel.warning, 'logFtpTransferFailed', kind: 'ERROR', args: {'client': client, 'user': user, 'file': display, 'error': '$e'});
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (!completed && !appendMode) {
        try {
          await File(target).delete();
        } catch (_) {}
      }
      data.destroy();
      transfer = null;
    }
  }

  void _logTransfer(String key, FtpTransfer t) {
    final seconds = DateTime.now().difference(t.startedAt).inMilliseconds / 1000;
    log(LogLevel.info, key, kind: 'DONE', args: {
      'client': client,
      'user': user,
      'file': t.file,
      'bytes': t.bytes,
      'seconds': seconds.toStringAsFixed(2),
      'rate': seconds <= 0 ? 0 : (t.bytes / seconds).round(),
    });
  }

  // ---- 바꾸기 ---------------------------------------------------------------------------------

  Future<void> _dele(String arg) async {
    if (!_requireWrite('DELE', arg)) return;
    final p = _path(arg);
    if (p == null) return;
    if (FileSystemEntity.typeSync(p.$2) != FileSystemEntityType.file) {
      _reply(550, 'File not found');
      return;
    }
    try {
      await File(p.$2).delete();
      log(LogLevel.info, 'logFtpDeleted', args: {'client': client, 'user': user, 'path': _display(p.$1)});
      _reply(250, 'File deleted');
    } on FileSystemException {
      _reply(550, 'Delete failed');
    }
  }

  Future<void> _mkd(String arg) async {
    if (!_requireWrite('MKD', arg)) return;
    final p = _path(arg);
    if (p == null) return;
    if (p.$1.isEmpty || FileSystemEntity.typeSync(p.$2) != FileSystemEntityType.notFound) {
      _reply(550, 'Create directory operation failed');
      return;
    }
    try {
      await Directory(p.$2).create();
      log(LogLevel.info, 'logFtpMkdir', args: {'client': client, 'user': user, 'path': _display(p.$1)});
      _reply(257, '"${_display(p.$1).replaceAll('"', '""')}" created');
    } on FileSystemException {
      _reply(550, 'Create directory operation failed');
    }
  }

  Future<void> _rmd(String arg) async {
    if (!_requireWrite('RMD', arg)) return;
    final p = _path(arg);
    if (p == null) return;
    if (p.$1.isEmpty || !FileSystemEntity.isDirectorySync(p.$2)) {
      _reply(550, 'Remove directory operation failed');
      return;
    }
    try {
      await Directory(p.$2).delete(); // 비어 있지 않으면 실패한다 (통째로 지우지 않는다)
      if (_cwd.length >= p.$1.length && _display(_cwd.sublist(0, p.$1.length)) == _display(p.$1)) _cwd = p.$1.sublist(0, p.$1.length - 1);
      log(LogLevel.info, 'logFtpRmdir', args: {'client': client, 'user': user, 'path': _display(p.$1)});
      _reply(250, 'Remove directory operation successful');
    } on FileSystemException {
      _reply(550, 'Remove directory operation failed');
    }
  }

  void _rnfr(String arg) {
    if (!_requireWrite('RNFR', arg)) return;
    final p = _path(arg);
    if (p == null) return;
    if (p.$1.isEmpty || FileSystemEntity.typeSync(p.$2) == FileSystemEntityType.notFound) {
      _reply(550, 'File not found');
      return;
    }
    _renameFrom = p.$1;
    _reply(350, 'Ready for RNTO');
  }

  Future<void> _rnto(String arg) async {
    final from = _renameFrom;
    _renameFrom = null;
    if (from == null) {
      _reply(503, 'RNFR required first');
      return;
    }
    if (!_requireWrite('RNTO', arg)) return;
    final p = _path(arg);
    if (p == null) return;
    if (p.$1.isEmpty || FileSystemEntity.typeSync(p.$2) != FileSystemEntityType.notFound) {
      _reply(553, 'Target already exists');
      return;
    }
    try {
      final source = _real(from);
      if (FileSystemEntity.isDirectorySync(source)) {
        await Directory(source).rename(p.$2);
      } else {
        await File(source).rename(p.$2);
      }
      log(LogLevel.info, 'logFtpRenamed', args: {'client': client, 'user': user, 'from': _display(from), 'to': _display(p.$1)});
      _reply(250, 'Rename successful');
    } on FileSystemException {
      _reply(553, 'Rename failed');
    } on SandboxViolation {
      _reply(550, 'Permission denied');
    }
  }

}
