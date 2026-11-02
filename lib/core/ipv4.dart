// IPv4 주소와 MAC 주소 값 타입. dart:io의 InternetAddress 대신 쓰는 이유: 32비트 정수라서 범위 비교와
// 풀 순회가 쉽고, 단위 테스트에서 소켓 없이 만들 수 있다.

import 'dart:typed_data';

/// IPv4 주소 (부호 없는 32비트 정수).
final class Ipv4 implements Comparable<Ipv4> {
  const Ipv4(this.value) : assert(value >= 0 && value <= 0xFFFFFFFF);

  static const any = Ipv4(0);
  static const broadcast = Ipv4(0xFFFFFFFF);

  final int value;

  factory Ipv4.fromBytes(List<int> bytes, [int offset = 0]) => Ipv4(
        (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3],
      );

  /// `a.b.c.d` 형식만 받는다. 앞자리 0, 공백, 256 이상은 거부한다.
  static Ipv4? tryParse(String text) {
    final parts = text.trim().split('.');
    if (parts.length != 4) return null;
    var value = 0;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3 || !RegExp(r'^[0-9]+$').hasMatch(part)) return null;
      if (part.length > 1 && part.startsWith('0')) return null;
      final octet = int.parse(part);
      if (octet > 255) return null;
      value = (value << 8) | octet;
    }
    return Ipv4(value);
  }

  factory Ipv4.parse(String text) => tryParse(text) ?? (throw FormatException('Invalid IPv4 address', text));

  Uint8List toBytes() => Uint8List.fromList([(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]);

  Ipv4 operator &(Ipv4 other) => Ipv4(value & other.value);
  Ipv4 operator |(Ipv4 other) => Ipv4(value | other.value);
  Ipv4 operator ~() => Ipv4(~value & 0xFFFFFFFF);

  /// 범위를 벗어나면 [RangeError].
  Ipv4 operator +(int offset) => Ipv4(value + offset);

  bool operator <(Ipv4 other) => value < other.value;
  bool operator <=(Ipv4 other) => value <= other.value;
  bool operator >(Ipv4 other) => value > other.value;
  bool operator >=(Ipv4 other) => value >= other.value;

  /// 1이 연속으로 나오다 0이 연속으로 나오는 유효한 서브넷 마스크인가 (0.0.0.0, 255.255.255.255 제외).
  bool get isValidMask {
    if (value == 0 || value == 0xFFFFFFFF) return false;
    final inverted = ~value & 0xFFFFFFFF;
    return (inverted & (inverted + 1)) == 0;
  }

  /// 마스크의 접두 길이 (255.255.255.0 → 24). 유효한 마스크가 아니면 null.
  int? get prefixLength => isValidMask ? value.toRadixString(2).replaceAll('0', '').length : null;

  /// 마스크 [mask] 기준 네트워크 주소와 브로드캐스트 주소.
  Ipv4 networkOf(Ipv4 mask) => this & mask;
  Ipv4 broadcastOf(Ipv4 mask) => this | ~mask;

  bool isInSubnet(Ipv4 network, Ipv4 mask) => (this & mask) == (network & mask);

  @override
  int compareTo(Ipv4 other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is Ipv4 && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => '${(value >> 24) & 0xFF}.${(value >> 16) & 0xFF}.${(value >> 8) & 0xFF}.${value & 0xFF}';
}

/// 클라이언트 하드웨어 주소 (DHCP `chaddr`의 앞 `hlen`바이트). 이더넷이면 6바이트.
final class MacAddress {
  MacAddress(List<int> bytes) : bytes = Uint8List.fromList(bytes);

  /// `aa:bb:cc:dd:ee:ff` 또는 `aa-bb-cc-dd-ee-ff`, 구분자 없는 12자리 16진수. 6바이트만 받는다.
  static MacAddress? tryParse(String text) {
    final hex = text.trim().replaceAll(RegExp(r'[:-]'), '');
    if (!RegExp(r'^[0-9a-fA-F]{12}$').hasMatch(hex)) return null;
    return MacAddress([for (var i = 0; i < 12; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
  }

  factory MacAddress.parse(String text) => tryParse(text) ?? (throw FormatException('Invalid MAC address', text));

  final Uint8List bytes;

  @override
  bool operator ==(Object other) {
    if (other is! MacAddress || other.bytes.length != bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != other.bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bytes);

  @override
  String toString() => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
}
