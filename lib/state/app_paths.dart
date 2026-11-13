// 앱이 파일을 두는 폴더. shared_preferences가 쓰는 폴더(%APPDATA%/게시자/표시 이름)와 같게 맞춰서
// 설정·Lease·로그가 한곳에 모이게 한다.

import 'dart:io';

import '../app_identity.dart';

/// 앱 데이터 폴더 (없으면 만들지 않는다). Windows가 아니거나 APPDATA를 모르면 null.
String? appDataDir() {
  final base = Platform.environment['APPDATA'];
  if (base == null || base.isEmpty) return null;
  return '$base${Platform.pathSeparator}${AppIdentity.copyrightHolder}${Platform.pathSeparator}${AppIdentity.displayName}';
}
