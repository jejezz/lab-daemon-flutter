// 서비스 설정 화면들이 같이 쓰는 검증 도우미와 오류 종류.

import '../core/netutil.dart';
import 'dart:io';

import '../core/ipv4.dart';

enum FieldError {
  required,
  invalidIp,
  invalidMask,
  invalidLeaseTime,
  notInSubnet,
  notHostAddress,
  rangeReversed,
  tooLong,
  invalidPort,
  invalidNumber,
  dirMissing,
}

/// 비어 있으면 "모든 NIC"(null). 올바르지 않은 주소면 오류.
FieldError? checkOptionalIp(String text) => text.trim().isEmpty || Ipv4.tryParse(text) != null ? null : FieldError.invalidIp;

/// 1~65535 (또는 [allowZero]면 0도).
FieldError? checkPort(String text, {bool allowZero = false}) {
  final n = int.tryParse(text.trim());
  if (n == null) return text.trim().isEmpty ? FieldError.required : FieldError.invalidPort;
  return n < (allowZero ? 0 : 1) || n > 65535 ? FieldError.invalidPort : null;
}

/// [low]..[high] 범위의 정수.
FieldError? checkInt(String text, int low, int high) {
  final n = int.tryParse(text.trim());
  if (n == null) return text.trim().isEmpty ? FieldError.required : FieldError.invalidNumber;
  return n < low || n > high ? FieldError.invalidNumber : null;
}

FieldError? checkDirectory(String path) {
  if (path.trim().isEmpty) return FieldError.required;
  return Directory(path.trim()).existsSync() ? null : FieldError.dirMissing;
}

/// 클라이언트가 접속할 `IP[:포트]` 목록. [bindIp]가 비어 있으면(모든 NIC) 루프백이 아닌 NIC마다 하나씩,
/// 포트가 프로토콜 기본값([defaultPort])과 같으면 포트는 쓰지 않는다.
List<String> connectEndpoints(String bindIp, String port, int defaultPort, List<NicInfo> nics) {
  final p = int.tryParse(port) ?? defaultPort;
  final suffix = p == defaultPort ? '' : ':$p';
  final ips = bindIp.trim().isNotEmpty
      ? [bindIp.trim()]
      : [
          for (final n in nics)
            if (!'${n.address}'.startsWith('127.')) '${n.address}',
        ];
  if (ips.isEmpty) return ['0.0.0.0$suffix'];
  return [for (final ip in ips) '$ip$suffix'];
}
