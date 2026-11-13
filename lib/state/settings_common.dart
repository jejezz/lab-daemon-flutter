// 서비스 설정 화면들이 같이 쓰는 검증 도우미와 오류 종류.

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
