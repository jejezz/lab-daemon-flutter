import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/ui/boot_file_picker.dart';
import 'package:lab_daemon/ui/widgets/fields.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('boot_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('루트 아래 파일을 상대 경로(/ 구분)와 크기로, 경로순으로 돌려준다', () async {
    File('${root.path}/u-boot.bin').writeAsBytesSync(List.filled(10, 1));
    Directory('${root.path}/boards/rk3566').createSync(recursive: true);
    File('${root.path}/boards/rk3566/Image').writeAsBytesSync(List.filled(30, 1));
    File('${root.path}/Zimage').writeAsBytesSync(const []);

    final found = await listBootCandidates(root.path);
    expect(found.map((f) => f.path), ['boards/rk3566/Image', 'u-boot.bin', 'Zimage']);
    expect(found.map((f) => f.size), [30, 10, 0]);
  });

  test('폴더가 없거나 비어 있으면 빈 목록, 많으면 limit까지', () async {
    expect(await listBootCandidates('${root.path}/없는-폴더'), isEmpty);
    expect(await listBootCandidates(''), isEmpty);
    for (var i = 0; i < 5; i++) {
      File('${root.path}/f$i.bin').writeAsBytesSync(const [1]);
    }
    expect(await listBootCandidates(root.path, limit: 3), hasLength(3));
  });

  test('folderFromDroppedPaths: 폴더가 있으면 그 폴더, 파일뿐이면 그 파일이 든 폴더, 없으면 null', () {
    final dir = Directory('${root.path}/images')..createSync();
    final file = File('${root.path}/zImage')..writeAsBytesSync([1]);
    expect(folderFromDroppedPaths([dir.path]), dir.path);
    expect(folderFromDroppedPaths([file.path, dir.path]), dir.path, reason: '폴더가 있으면 폴더가 먼저');
    expect(folderFromDroppedPaths([file.path]), root.path);
    expect(folderFromDroppedPaths(['${root.path}/없는-경로', '']), isNull);
    expect(folderFromDroppedPaths(const []), isNull);
  });
}
