// HTTP 파일 서버 설정. 값을 검증하고 JSON으로 바꾼다 (Isolate 경계와 저장소를 건넌다).

import 'dart:io';

import '../ipv4.dart';
import '../service.dart';

class HttpConfigException implements Exception {
  HttpConfigException(this.reason, [this.detail]);

  /// `rootMissing`, `invalidPort`, `invalidConnections`, `invalidIdle`.
  final String reason;
  final String? detail;

  @override
  String toString() => 'HttpConfigException($reason${detail == null ? '' : ': $detail'})';
}

class HttpConfig implements ServiceConfig {
  HttpConfig({
    required this.rootDir,
    this.bindAddress,
    this.port = 80,
    this.allowListing = true,
    this.allowWrite = false,
    this.allowOverwrite = false,
    this.maxConnections = 64,
    this.idleTimeoutSeconds = 30,
  });

  /// 내려받을 파일이 있는 폴더. 클라이언트는 이 아래만 볼 수 있다.
  final String rootDir;

  /// 소켓을 묶을 NIC 주소. null이면 모든 NIC (0.0.0.0).
  final Ipv4? bindAddress;

  /// 0이면 OS가 정한다 (시험용).
  final int port;

  /// 폴더 주소를 열면 파일 목록(HTML)을 보여 준다. 꺼져 있으면 `index.html`이 있을 때만 그것을 내주고 없으면 403.
  final bool allowListing;

  /// `PUT`으로 파일을 올릴 수 있는가 (`curl -T 파일 http://…/이름`). 기본은 읽기 전용이다.
  final bool allowWrite;

  /// 이미 있는 파일을 올린 파일로 바꿀 수 있는가 ([allowWrite]가 켜져 있을 때만 뜻이 있다).
  final bool allowOverwrite;

  /// 동시에 처리할 수 있는 요청 수. 넘으면 새 요청은 503으로 거절한다.
  final int maxConnections;

  /// 요청이 없는 연결을 끊기까지의 시간(초).
  final int idleTimeoutSeconds;

  Ipv4 get bindTo => bindAddress ?? Ipv4.any;

  void validate() {
    if (!Directory(rootDir).existsSync()) throw HttpConfigException('rootMissing', rootDir);
    if (port < 0 || port > 65535) throw HttpConfigException('invalidPort');
    if (maxConnections < 1 || maxConnections > 10000) throw HttpConfigException('invalidConnections');
    if (idleTimeoutSeconds < 1 || idleTimeoutSeconds > 3600) throw HttpConfigException('invalidIdle');
  }

  @override
  Map<String, Object?> toJson() => {
        'rootDir': rootDir,
        'bindAddress': bindAddress?.toString(),
        'port': port,
        'allowListing': allowListing,
        'allowWrite': allowWrite,
        'allowOverwrite': allowOverwrite,
        'maxConnections': maxConnections,
        'idleTimeoutSeconds': idleTimeoutSeconds,
      };

  factory HttpConfig.fromJson(Map<String, Object?> json) {
    try {
      final bind = json['bindAddress'] as String?;
      return HttpConfig(
        rootDir: json['rootDir']! as String,
        bindAddress: bind == null ? null : Ipv4.parse(bind),
        port: json['port'] as int? ?? 80,
        allowListing: json['allowListing'] as bool? ?? true,
        allowWrite: json['allowWrite'] as bool? ?? false,
        allowOverwrite: json['allowOverwrite'] as bool? ?? false,
        maxConnections: json['maxConnections'] as int? ?? 64,
        idleTimeoutSeconds: json['idleTimeoutSeconds'] as int? ?? 30,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid HTTP config: $e');
    }
  }
}
