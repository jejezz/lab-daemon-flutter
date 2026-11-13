// FTP 화면이 편집하는 값. 계정은 하나(사용자 이름 + 비밀번호 해시)이고 익명 접속과 쓰기 허용은 스위치 하나씩이다.
// 비밀번호는 입력하는 순간 솔트+해시로 바꿔서 저장한다 — 평문은 어디에도 남기지 않는다. 저장 키는 `ftp_<이름>`.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/ftp/config.dart';
import '../core/ipv4.dart';
import 'settings_common.dart';

enum FtpField { bindIp, port, rootDir, username, password, passiveStart, passiveEnd, maxConnections, idleTimeout }

class FtpSettings {
  const FtpSettings({
    this.bindIp = '',
    this.port = '21',
    this.rootDir = '',
    this.username = '',
    this.account,
    this.allowAnonymous = false,
    this.allowWrite = false,
    this.passiveStart = '${FtpConfig.defaultPassiveStart}',
    this.passiveEnd = '${FtpConfig.defaultPassiveEnd}',
    this.maxConnections = '32',
    this.idleTimeout = '300',
    this.logCommands = false,
  });

  final String bindIp;
  final String port;
  final String rootDir;
  final String username;

  /// 비밀번호까지 정한 계정 (해시만 들어 있다). 사용자 이름을 바꾸면 비밀번호를 다시 정해야 한다.
  final FtpAccount? account;
  final bool allowAnonymous;
  final bool allowWrite;
  final String passiveStart;
  final String passiveEnd;
  final String maxConnections;
  final String idleTimeout;
  final bool logCommands;

  static const _prefix = 'ftp_';

  bool get hasPassword => account != null && account!.username == username.trim();

  factory FtpSettings.load(SharedPreferences prefs) {
    const d = FtpSettings();
    String s(String k, String v) => prefs.getString('$_prefix$k') ?? v;
    bool b(String k, bool v) => prefs.getBool('$_prefix$k') ?? v;
    FtpAccount? account;
    final raw = prefs.getString('${_prefix}account');
    if (raw != null && raw.isNotEmpty) {
      try {
        account = FtpAccount.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    return FtpSettings(
      bindIp: s('bind_ip', d.bindIp),
      port: s('port', d.port),
      rootDir: s('root_dir', d.rootDir),
      username: s('username', d.username),
      account: account,
      allowAnonymous: b('allow_anonymous', d.allowAnonymous),
      allowWrite: b('allow_write', d.allowWrite),
      passiveStart: s('passive_start', d.passiveStart),
      passiveEnd: s('passive_end', d.passiveEnd),
      maxConnections: s('max_connections', d.maxConnections),
      idleTimeout: s('idle_timeout', d.idleTimeout),
      logCommands: b('log_commands', d.logCommands),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('${_prefix}bind_ip', bindIp);
    await prefs.setString('${_prefix}port', port);
    await prefs.setString('${_prefix}root_dir', rootDir);
    await prefs.setString('${_prefix}username', username);
    await prefs.setString('${_prefix}account', account == null ? '' : jsonEncode(account!.toJson()));
    await prefs.setBool('${_prefix}allow_anonymous', allowAnonymous);
    await prefs.setBool('${_prefix}allow_write', allowWrite);
    await prefs.setString('${_prefix}passive_start', passiveStart);
    await prefs.setString('${_prefix}passive_end', passiveEnd);
    await prefs.setString('${_prefix}max_connections', maxConnections);
    await prefs.setString('${_prefix}idle_timeout', idleTimeout);
    await prefs.setBool('${_prefix}log_commands', logCommands);
  }

  String valueOf(FtpField f) => switch (f) {
        FtpField.bindIp => bindIp,
        FtpField.port => port,
        FtpField.rootDir => rootDir,
        FtpField.username => username,
        FtpField.password => '',
        FtpField.passiveStart => passiveStart,
        FtpField.passiveEnd => passiveEnd,
        FtpField.maxConnections => maxConnections,
        FtpField.idleTimeout => idleTimeout,
      };

  FtpSettings withValue(FtpField f, String v) => switch (f) {
        FtpField.password => withPassword(v),
        _ => copyWith(
            bindIp: f == FtpField.bindIp ? v : null,
            port: f == FtpField.port ? v : null,
            rootDir: f == FtpField.rootDir ? v : null,
            username: f == FtpField.username ? v : null,
            passiveStart: f == FtpField.passiveStart ? v : null,
            passiveEnd: f == FtpField.passiveEnd ? v : null,
            maxConnections: f == FtpField.maxConnections ? v : null,
            idleTimeout: f == FtpField.idleTimeout ? v : null,
          ),
      };

  /// 비밀번호를 정한다 (바로 해시로 바꾼다). 빈 값이면 계정을 지운다.
  FtpSettings withPassword(String password) => password.isEmpty || username.trim().isEmpty
      ? FtpSettings(
          bindIp: bindIp,
          port: port,
          rootDir: rootDir,
          username: username,
          account: null,
          allowAnonymous: allowAnonymous,
          allowWrite: allowWrite,
          passiveStart: passiveStart,
          passiveEnd: passiveEnd,
          maxConnections: maxConnections,
          idleTimeout: idleTimeout,
          logCommands: logCommands,
        )
      : copyWith(account: FtpAccount.create(username.trim(), password));

  FtpSettings copyWith({
    String? bindIp,
    String? port,
    String? rootDir,
    String? username,
    FtpAccount? account,
    bool? allowAnonymous,
    bool? allowWrite,
    String? passiveStart,
    String? passiveEnd,
    String? maxConnections,
    String? idleTimeout,
    bool? logCommands,
  }) =>
      FtpSettings(
        bindIp: bindIp ?? this.bindIp,
        port: port ?? this.port,
        rootDir: rootDir ?? this.rootDir,
        username: username ?? this.username,
        account: account ?? this.account,
        allowAnonymous: allowAnonymous ?? this.allowAnonymous,
        allowWrite: allowWrite ?? this.allowWrite,
        passiveStart: passiveStart ?? this.passiveStart,
        passiveEnd: passiveEnd ?? this.passiveEnd,
        maxConnections: maxConnections ?? this.maxConnections,
        idleTimeout: idleTimeout ?? this.idleTimeout,
        logCommands: logCommands ?? this.logCommands,
      );

  Map<FtpField, FieldError> validate() {
    final errors = <FtpField, FieldError>{
      for (final (f, e) in [
        (FtpField.bindIp, checkOptionalIp(bindIp)),
        (FtpField.port, checkPort(port)),
        (FtpField.rootDir, checkDirectory(rootDir)),
        (FtpField.passiveStart, checkInt(passiveStart, 1024, 65535)),
        (FtpField.passiveEnd, checkInt(passiveEnd, 1024, 65535)),
        (FtpField.maxConnections, checkInt(maxConnections, 1, 1000)),
        (FtpField.idleTimeout, checkInt(idleTimeout, 10, 86400)),
      ])
        f: ?e,
    };
    final start = int.tryParse(passiveStart.trim());
    final end = int.tryParse(passiveEnd.trim());
    if (start != null && end != null && start > end && !errors.containsKey(FtpField.passiveEnd)) {
      errors[FtpField.passiveEnd] = FieldError.rangeReversed;
    }
    // 로그인할 방법이 하나는 있어야 한다: 계정(이름+비밀번호) 또는 익명.
    if (!allowAnonymous) {
      if (username.trim().isEmpty) errors[FtpField.username] = FieldError.required;
      if (!hasPassword) errors[FtpField.password] = FieldError.required;
    } else if (username.trim().isNotEmpty && !hasPassword) {
      errors[FtpField.password] = FieldError.required;
    }
    return errors;
  }

  FtpConfig toConfig() => FtpConfig(
        rootDir: rootDir.trim(),
        bindAddress: bindIp.trim().isEmpty ? null : Ipv4.parse(bindIp),
        port: int.parse(port.trim()),
        passivePortStart: int.parse(passiveStart.trim()),
        passivePortEnd: int.parse(passiveEnd.trim()),
        account: hasPassword ? account : null,
        allowAnonymous: allowAnonymous,
        allowWrite: allowWrite,
        maxConnections: int.parse(maxConnections.trim()),
        idleTimeoutSeconds: int.parse(idleTimeout.trim()),
        logCommands: logCommands,
      );
}
