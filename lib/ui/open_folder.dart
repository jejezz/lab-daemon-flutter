// 탐색기로 폴더를 연다 (Windows). 폴더가 없으면 만든 뒤 연다.

import 'dart:io';

Future<void> openInExplorer(String path, {bool create = false}) async {
  if (!Platform.isWindows || path.isEmpty) return;
  try {
    if (create) await Directory(path).create(recursive: true);
    await Process.start('explorer.exe', [path.replaceAll('/', r'\')], mode: ProcessStartMode.detached);
  } catch (_) {
    // 열지 못해도 앱 동작에는 영향이 없다.
  }
}
