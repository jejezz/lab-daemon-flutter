import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/conflict.dart';
import 'package:lab_daemon/core/ipv4.dart';

void main() {
  // 실제 ping 프로그램을 쓴다 (Windows).
  test('pingIsUsed: 응답하는 주소(자기 자신)는 true, 응답 없는 주소는 false', () async {
    expect(await pingIsUsed(Ipv4.parse('127.0.0.1')), isTrue);
    final sw = Stopwatch()..start();
    expect(await pingIsUsed(Ipv4.parse('192.0.2.1')), isFalse, reason: 'TEST-NET-1은 어디서도 응답하지 않는다');
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
  }, skip: Platform.isWindows ? false : 'Windows ping 출력(TTL=)을 쓴다');
}
