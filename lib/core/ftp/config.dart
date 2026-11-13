// FTP 서버 설정. 계정은 하나만 두고(FileZilla처럼 계정·권한을 여럿 관리하지 않는다) 익명 접속을 켤 수 있다.
// 쓰기 권한도 "쓰기 허용" 하나로 모든 로그인에 같이 적용한다. 비밀번호는 평문으로 저장하지 않고 솔트를 붙인
// SHA-256 해시로만 둔다.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../ipv4.dart';
import '../service.dart';

class FtpConfigException implements Exception {
  FtpConfigException(this.reason, [this.detail]);

  /// `rootMissing`, `invalidPort`, `invalidPassiveRange`, `invalidConnections`, `invalidTimeout`, `noLogin`.
  final String reason;
  final String? detail;

  @override
  String toString() => 'FtpConfigException($reason${detail == null ? '' : ': $detail'})';
}

class FtpAccount {
  const FtpAccount({required this.username, required this.salt, required this.hash});

  /// 새 계정. 솔트는 무작위 16바이트다.
  factory FtpAccount.create(String username, String password, {Random? random}) {
    final rnd = random ?? Random.secure();
    final salt = [for (var i = 0; i < 16; i++) rnd.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    return FtpAccount(username: username, salt: salt, hash: hashPassword(salt, password));
  }

  final String username;
  final String salt;
  final String hash;

  static String hashPassword(String salt, String password) => sha256.convert(utf8.encode('$salt:$password')).toString();

  /// 비밀번호가 맞는가. 길이가 같은 비교를 끝까지 해서 시간 차이로 정보를 흘리지 않는다.
  bool verify(String password) {
    final candidate = hashPassword(salt, password);
    if (candidate.length != hash.length) return false;
    var diff = 0;
    for (var i = 0; i < hash.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  }

  Map<String, Object?> toJson() => {'username': username, 'salt': salt, 'hash': hash};

  factory FtpAccount.fromJson(Map<String, Object?> json) => FtpAccount(
        username: json['username']! as String,
        salt: json['salt']! as String,
        hash: json['hash']! as String,
      );
}

class FtpConfig implements ServiceConfig {
  FtpConfig({
    required this.rootDir,
    this.bindAddress,
    this.port = 21,
    this.passivePortStart = defaultPassiveStart,
    this.passivePortEnd = defaultPassiveEnd,
    this.passiveAddress,
    this.account,
    this.allowAnonymous = false,
    this.allowWrite = false,
    this.maxConnections = 32,
    this.idleTimeoutSeconds = 300,
    this.logCommands = false,
  });

  /// 클라이언트가 볼 수 있는 최상위 폴더. 모든 계정이 같은 루트를 쓴다.
  final String rootDir;

  /// 소켓을 묶을 NIC 주소. null이면 모든 NIC (0.0.0.0).
  final Ipv4? bindAddress;

  /// 0이면 OS가 정한다 (시험용).
  final int port;

  /// 기본 패시브 범위는 Windows 동적 포트 범위(49152~) 밖에 둔다. Hyper-V·WSL 등이 그 범위에서 포트를 100개씩
  /// 예약해서(`netsh int ipv4 show excludedportrange`) 흔히 쓰는 50000번대가 통째로 막히는 일이 있다.
  static const defaultPassiveStart = 40000;
  static const defaultPassiveEnd = 40199;

  /// 패시브 모드 데이터 연결에 쓸 포트 범위. 방화벽에 이 범위도 열려 있어야 한다.
  final int passivePortStart;
  final int passivePortEnd;

  /// PASV 응답에 알려 줄 주소. null이면 제어 연결을 받은 NIC 주소.
  final Ipv4? passiveAddress;

  /// 로그인 계정 하나. 없으면 익명 접속만 된다.
  final FtpAccount? account;

  /// `anonymous`/`ftp` 사용자를 비밀번호 없이 받는다. 기본은 꺼짐.
  final bool allowAnonymous;

  /// 로그인한 사용자(익명 포함)가 올리기·지우기·이름 바꾸기·폴더 만들기를 할 수 있는가. 기본은 읽기 전용.
  final bool allowWrite;

  final int maxConnections;

  /// 이 시간 동안 명령이 없으면 연결을 끊는다.
  final int idleTimeoutSeconds;

  /// 모든 명령을 DEBUG 로그에 남긴다 (PASS 인자는 가린다).
  final bool logCommands;

  Ipv4 get bindTo => bindAddress ?? Ipv4.any;

  static bool isAnonymousName(String name) => name.toLowerCase() == 'anonymous' || name.toLowerCase() == 'ftp';

  void validate() {
    if (!Directory(rootDir).existsSync()) throw FtpConfigException('rootMissing', rootDir);
    if (port < 0 || port > 65535) throw FtpConfigException('invalidPort');
    if (passivePortStart < 1024 || passivePortEnd > 65535 || passivePortStart > passivePortEnd) {
      throw FtpConfigException('invalidPassiveRange');
    }
    if (maxConnections < 1 || maxConnections > 1000) throw FtpConfigException('invalidConnections');
    if (idleTimeoutSeconds < 1 || idleTimeoutSeconds > 86400) throw FtpConfigException('invalidTimeout');
    if (account == null && !allowAnonymous) throw FtpConfigException('noLogin');
  }

  @override
  Map<String, Object?> toJson() => {
        'rootDir': rootDir,
        'bindAddress': bindAddress?.toString(),
        'port': port,
        'passivePortStart': passivePortStart,
        'passivePortEnd': passivePortEnd,
        'passiveAddress': passiveAddress?.toString(),
        'account': account?.toJson(),
        'allowAnonymous': allowAnonymous,
        'allowWrite': allowWrite,
        'maxConnections': maxConnections,
        'idleTimeoutSeconds': idleTimeoutSeconds,
        'logCommands': logCommands,
      };

  factory FtpConfig.fromJson(Map<String, Object?> json) {
    try {
      Ipv4? ip(String key) => json[key] == null ? null : Ipv4.parse(json[key]! as String);
      return FtpConfig(
        rootDir: json['rootDir']! as String,
        bindAddress: ip('bindAddress'),
        port: json['port'] as int? ?? 21,
        passivePortStart: json['passivePortStart'] as int? ?? defaultPassiveStart,
        passivePortEnd: json['passivePortEnd'] as int? ?? defaultPassiveEnd,
        passiveAddress: ip('passiveAddress'),
        account: json['account'] == null ? null : FtpAccount.fromJson(Map<String, Object?>.from(json['account']! as Map)),
        allowAnonymous: json['allowAnonymous'] as bool? ?? false,
        allowWrite: json['allowWrite'] as bool? ?? false,
        maxConnections: json['maxConnections'] as int? ?? 32,
        idleTimeoutSeconds: json['idleTimeoutSeconds'] as int? ?? 300,
        logCommands: json['logCommands'] as bool? ?? false,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid FTP config: $e');
    }
  }
}
