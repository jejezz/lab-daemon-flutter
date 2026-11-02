// 네트워크 인터페이스(NIC) 열거. 서버를 켤 NIC를 고르는 화면과 시작 전 점검에 쓴다.

import 'dart:io';

import 'ipv4.dart';

class NicInfo {
  const NicInfo(this.name, this.address);

  /// OS가 보여 주는 이름 (예: `Ethernet 2`).
  final String name;
  final Ipv4 address;

  @override
  String toString() => '$name ($address)';
}

/// IPv4 주소가 있는 NIC를 이름순으로. 루프백(127.x)과 링크 로컬(169.254.x)은 뺀다:
/// 링크 로컬은 DHCP를 받지 못했다는 뜻이라 서버 주소로 쓰면 안 된다.
Future<List<NicInfo>> listNics({bool includeLoopback = false}) async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: includeLoopback);
  final nics = <NicInfo>[];
  for (final nic in interfaces) {
    for (final address in nic.addresses) {
      final ip = Ipv4.tryParse(address.address);
      if (ip == null) continue;
      if (!includeLoopback && ip.value >> 24 == 127) continue;
      if (ip.value >> 16 == 0xA9FE) continue;
      nics.add(NicInfo(nic.name, ip));
    }
  }
  nics.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return nics;
}
