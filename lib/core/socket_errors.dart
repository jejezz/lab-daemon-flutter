// 소켓 바인딩 오류의 원인 판별 (세 서비스가 같이 쓴다).

import 'dart:io';

/// 포트를 이미 쓰고 있다: Windows `WSAEADDRINUSE`(10048), Linux `EADDRINUSE`(98), macOS(48).
/// 같은 프로세스 안에서 같은 주소·포트를 두 번 열면 Dart가 OS까지 가지 않고 코드 -1과 "shared flag" 문구로 막는다.
bool isAddressInUse(Object error) {
  if (error is! SocketException) return false;
  final os = error.osError;
  if (os == null) return false;
  if (const {10048, 98, 48}.contains(os.errorCode)) return true;
  return os.errorCode == -1 && os.message.contains('shared flag');
}

/// 권한 때문에 바인딩이 거부됐다: `WSAEACCES`(10013), `EACCES`(13).
bool isPermissionDenied(Object error) =>
    error is SocketException && const {10013, 13}.contains(error.osError?.errorCode);

/// 로그 키 접미사: `PortInUse`, `PermissionDenied`, `BindFailed`.
String bindFailureKind(Object error) =>
    isAddressInUse(error) ? 'PortInUse' : (isPermissionDenied(error) ? 'PermissionDenied' : 'BindFailed');
