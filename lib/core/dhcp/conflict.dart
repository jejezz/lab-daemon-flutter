// 주소를 나눠 주기 전에 그 주소가 이미 쓰이는지 ping으로 확인한다 (RFC 2131 §3.1: 서버는 제안 전에 확인해야 한다).
// 고정 IP로 설정된 장비가 풀 안의 주소를 쓰고 있을 때 같은 주소를 또 나눠 주는 일을 막는다.
// 한계: ICMP를 막는 장비(방화벽이 켜진 PC 등)는 응답하지 않아서 찾지 못한다.

import 'dart:io';

import '../ipv4.dart';

/// [ip]에서 응답이 있으면 true (이미 쓰이는 주소).
typedef IpProbe = Future<bool> Function(Ipv4 ip);

/// 응답을 기다리는 시간. 쓰이지 않는 주소는 이 시간만큼 기다린 뒤에 제안이 나간다.
const probeTimeout = Duration(milliseconds: 300);

/// Windows `ping`: 응답이 오면 출력에 `TTL=`이 있다. (`Destination host unreachable`도 종료 코드는 0이라 출력으로 가른다.)
Future<bool> pingIsUsed(Ipv4 ip) async {
  try {
    final result = await Process.run(
      'ping',
      Platform.isWindows ? ['-n', '1', '-w', '${probeTimeout.inMilliseconds}', '$ip'] : ['-c', '1', '-W', '1', '$ip'],
    ).timeout(const Duration(seconds: 3));
    return '${result.stdout}'.toUpperCase().contains('TTL=');
  } catch (_) {
    return false; // ping을 못 돌리면 확인하지 못한 것이다: 막지 않는다
  }
}
