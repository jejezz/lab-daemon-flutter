// TFTP 서버 설정. 값을 검증하고 JSON으로 바꾼다 (Isolate 경계와 저장소를 건넌다).

import 'dart:io';

import '../ipv4.dart';
import '../service.dart';

class TftpConfigException implements Exception {
  TftpConfigException(this.reason, [this.detail]);

  /// `rootMissing`, `invalidPort`, `invalidBlockSize`, `invalidWindow`, `invalidTimeout`, `invalidRetries`, `invalidTransfers`.
  final String reason;
  final String? detail;

  @override
  String toString() => 'TftpConfigException($reason${detail == null ? '' : ': $detail'})';
}

class TftpConfig implements ServiceConfig {
  TftpConfig({
    required this.rootDir,
    this.bindAddress,
    this.port = 69,
    this.allowWrite = false,
    this.allowOverwrite = false,
    this.maxBlockSize = 1468,
    this.maxWindowSize = 8,
    this.timeoutMs = 2000,
    this.maxRetries = 5,
    this.maxTransfers = 64,
    this.logPackets = false,
  });

  /// 보내고 받을 파일이 있는 폴더. 클라이언트는 이 아래만 볼 수 있다.
  final String rootDir;

  /// 소켓을 묶을 NIC 주소. null이면 모든 NIC (0.0.0.0).
  final Ipv4? bindAddress;

  /// 0이면 OS가 정한다 (시험용).
  final int port;

  /// 클라이언트가 파일을 올릴 수 있는가. 기본은 읽기 전용이다.
  final bool allowWrite;

  /// 이미 있는 파일을 올린 파일로 바꿀 수 있는가 ([allowWrite]가 켜져 있을 때만 뜻이 있다).
  final bool allowOverwrite;

  /// 클라이언트가 요청해도 이 크기를 넘기지 않는다. 1468은 이더넷 MTU 1500에 들어가는 최대 크기다.
  final int maxBlockSize;

  /// 확인 응답을 기다리지 않고 보낼 수 있는 블록 수의 상한 (RFC 7440). 1이면 고전적인 한 블록씩.
  final int maxWindowSize;

  /// 응답이 없을 때 다시 보내기까지 기다리는 시간. 클라이언트가 `timeout` 옵션을 주면 그 값을 쓴다.
  final int timeoutMs;
  final int maxRetries;

  /// 동시에 진행할 수 있는 전송 수. 넘으면 새 요청은 "바쁨" 오류로 거절한다.
  final int maxTransfers;

  /// 주고받는 패킷의 16진수 덤프를 DEBUG 로그에 남긴다. 켜면 성능이 떨어질 수 있다.
  final bool logPackets;

  Ipv4 get bindTo => bindAddress ?? Ipv4.any;

  void validate() {
    if (!Directory(rootDir).existsSync()) throw TftpConfigException('rootMissing', rootDir);
    if (port < 0 || port > 65535) throw TftpConfigException('invalidPort');
    if (maxBlockSize < 8 || maxBlockSize > 65464) throw TftpConfigException('invalidBlockSize');
    if (maxWindowSize < 1 || maxWindowSize > 65535) throw TftpConfigException('invalidWindow');
    if (timeoutMs < 50 || timeoutMs > 60000) throw TftpConfigException('invalidTimeout');
    if (maxRetries < 1 || maxRetries > 20) throw TftpConfigException('invalidRetries');
    if (maxTransfers < 1 || maxTransfers > 1000) throw TftpConfigException('invalidTransfers');
  }

  @override
  Map<String, Object?> toJson() => {
        'rootDir': rootDir,
        'bindAddress': bindAddress?.toString(),
        'port': port,
        'allowWrite': allowWrite,
        'allowOverwrite': allowOverwrite,
        'maxBlockSize': maxBlockSize,
        'maxWindowSize': maxWindowSize,
        'timeoutMs': timeoutMs,
        'maxRetries': maxRetries,
        'maxTransfers': maxTransfers,
        'logPackets': logPackets,
      };

  factory TftpConfig.fromJson(Map<String, Object?> json) {
    try {
      final bind = json['bindAddress'] as String?;
      return TftpConfig(
        rootDir: json['rootDir']! as String,
        bindAddress: bind == null ? null : Ipv4.parse(bind),
        port: json['port'] as int? ?? 69,
        allowWrite: json['allowWrite'] as bool? ?? false,
        allowOverwrite: json['allowOverwrite'] as bool? ?? false,
        maxBlockSize: json['maxBlockSize'] as int? ?? 1468,
        maxWindowSize: json['maxWindowSize'] as int? ?? 8,
        timeoutMs: json['timeoutMs'] as int? ?? 2000,
        maxRetries: json['maxRetries'] as int? ?? 5,
        maxTransfers: json['maxTransfers'] as int? ?? 64,
        logPackets: json['logPackets'] as bool? ?? false,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid TFTP config: $e');
    }
  }
}
