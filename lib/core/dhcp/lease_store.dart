// Lease 표를 파일에 저장하고 읽는다 (서버를 껐다 켜도 Lease가 이어지게). 확정(bound)된 Lease만 저장한다.
// 쓸 때는 임시 파일에 쓰고 이름을 바꿔서, 도중에 꺼져도 예전 파일이 온전하게 남는다.

import 'dart:convert';
import 'dart:io';

import '../ipv4.dart';
import 'pool.dart';

/// 파일에 저장된 Lease 한 줄.
class StoredLease {
  StoredLease({required this.mac, required this.ip, required this.hostname, required this.grantedAt, required this.expiresAt});

  final MacAddress mac;
  final Ipv4 ip;
  final String? hostname;
  final DateTime grantedAt;

  /// null이면 무제한.
  final DateTime? expiresAt;
}

class LeaseStore {
  LeaseStore(this.path);

  final String path;

  /// 저장 내용(JSON 문자열). 같은 내용이면 다시 쓰지 않는 데 쓴다. 시각은 빼고 만든다.
  static String encode(Iterable<Lease> leases) {
    final bound = leases.where((l) => l.state == LeaseState.bound).toList()..sort((a, b) => a.ip.compareTo(b.ip));
    return const JsonEncoder.withIndent(' ').convert({
      'version': 1,
      'leases': [
        for (final l in bound)
          {
            'mac': '${l.mac}',
            'ip': '${l.ip}',
            'hostname': l.hostname,
            'grantedAt': l.grantedAt.toUtc().toIso8601String(),
            'expiresAt': l.expiresAt?.toUtc().toIso8601String(),
          },
      ],
    });
  }

  /// 파일이 없으면 빈 목록. 내용이 깨졌으면 [FormatException].
  List<StoredLease> load() {
    final file = File(path);
    if (!file.existsSync()) return const [];
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      return [
        for (final item in json['leases']! as List)
          StoredLease(
            mac: MacAddress.parse((item as Map)['mac'] as String),
            ip: Ipv4.parse(item['ip'] as String),
            hostname: item['hostname'] as String?,
            grantedAt: DateTime.parse(item['grantedAt'] as String),
            expiresAt: item['expiresAt'] == null ? null : DateTime.parse(item['expiresAt'] as String),
          ),
      ];
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid lease file: $e');
    }
  }

  Future<void> saveEncoded(String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(path);
  }
}
