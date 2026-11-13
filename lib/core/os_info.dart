// 지금 도는 OS 판별. 안내 문구(방화벽 허용 방법 등)를 OS 버전에 맞춰 고르는 데 쓴다.

import 'dart:io';

enum HostOs { windows11, windows10, windows, other }

/// Windows 11은 커널 버전이 10.0으로 같고 빌드 번호(22000 이상)로만 구분된다.
HostOs hostOsFrom(String operatingSystem, String version) {
  if (operatingSystem != 'windows') return HostOs.other;
  final build = int.tryParse(RegExp(r'Build (\d+)').firstMatch(version)?.group(1) ?? '');
  if (build == null) return HostOs.windows;
  return build >= 22000 ? HostOs.windows11 : HostOs.windows10;
}

HostOs get currentHostOs => hostOsFrom(Platform.operatingSystem, Platform.operatingSystemVersion);
