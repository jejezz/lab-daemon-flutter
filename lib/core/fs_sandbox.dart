// 루트 폴더 밖으로 나가지 못하게 막는 경로 검사. TFTP와 FTP가 같이 쓴다.
//
// 막는 것: `..` 구간, 절대 경로, 드라이브 문자와 대체 데이터 스트림(`:`), NUL, Windows 예약 장치 이름,
// 그리고 심볼릭 링크·정션을 통해 루트 밖을 가리키는 경로 (실제 경로를 해석해서 다시 확인한다).
// 클라이언트가 보낸 경로 문자열은 항상 신뢰하지 않는다.

import 'dart:io';

class SandboxViolation implements Exception {
  SandboxViolation(this.reason);

  /// `traversal`, `invalidName`, `outsideRoot`.
  final String reason;

  @override
  String toString() => 'SandboxViolation($reason)';
}

class FsSandbox {
  /// [root]는 존재하는 폴더여야 한다. 실제 경로(링크를 푼 것)를 기준으로 삼는다.
  FsSandbox(String root) : root = Directory(root).resolveSymbolicLinksSync();

  final String root;

  static final _reserved = RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$', caseSensitive: false);

  /// 클라이언트 경로를 루트 아래 구간들로 나눈다. `/`와 `\`를 모두 구분자로 보고, 빈 구간과 `.`은 버린다.
  /// 위험한 구간이 있으면 [SandboxViolation].
  static List<String> segments(String requested) {
    if (requested.contains('\u0000')) throw SandboxViolation('invalidName');
    final parts = <String>[];
    for (final raw in requested.split(RegExp(r'[\\/]'))) {
      if (raw.isEmpty || raw == '.') continue;
      if (raw == '..') throw SandboxViolation('traversal');
      if (raw.contains(':') || raw.contains('*') || raw.contains('?') || raw.contains('"') || raw.contains('<') || raw.contains('>') || raw.contains('|')) {
        throw SandboxViolation('invalidName');
      }
      if (raw.endsWith('.') || raw.endsWith(' ') || _reserved.hasMatch(raw)) throw SandboxViolation('invalidName');
      parts.add(raw);
    }
    return parts;
  }

  /// 루트 아래의 경로로 바꾼다 (존재 여부는 보지 않는다). 파일이 아직 없어도 부모가 루트 안인지 확인한다.
  String resolve(String requested) {
    final parts = segments(requested);
    final path = parts.isEmpty ? root : '$root${Platform.pathSeparator}${parts.join(Platform.pathSeparator)}';
    _ensureInside(path);
    return path;
  }

  /// 링크를 풀어 본 실제 경로가 루트 안인지. 없는 파일은 가장 가까운 존재하는 부모로 확인한다.
  void _ensureInside(String path) {
    var probe = path;
    while (true) {
      final type = FileSystemEntity.typeSync(probe, followLinks: false);
      if (type != FileSystemEntityType.notFound) break;
      final parent = File(probe).parent.path;
      if (parent == probe) throw SandboxViolation('outsideRoot');
      probe = parent;
    }
    final String real;
    try {
      real = FileSystemEntity.isDirectorySync(probe) ? Directory(probe).resolveSymbolicLinksSync() : File(probe).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw SandboxViolation('outsideRoot');
    }
    if (!isWithin(root, real)) throw SandboxViolation('outsideRoot');
  }

  /// [path]가 [root] 자신이거나 그 아래인가 (Windows는 대소문자를 구분하지 않는다).
  static bool isWithin(String root, String path) {
    final sep = Platform.pathSeparator;
    String norm(String s) => Platform.isWindows ? s.toLowerCase() : s;
    final r = norm(root.endsWith(sep) ? root.substring(0, root.length - 1) : root);
    final p = norm(path);
    return p == r || p.startsWith('$r$sep');
  }

  /// 루트에서 [path]까지의 상대 경로를 `/` 구분자로 (FTP 표시용).
  String relative(String path) {
    final sep = Platform.pathSeparator;
    if (path.length <= root.length) return '/';
    return path.substring(root.length).replaceAll(sep, '/');
  }
}
