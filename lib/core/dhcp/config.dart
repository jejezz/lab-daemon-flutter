// DHCP 서버 설정. 값을 검증하고 [LeasePool]을 만든다. 화면의 입력 검증도 [validate]를 그대로 쓴다.

import '../ipv4.dart';
import '../service.dart';
import 'pool.dart';

class DhcpConfig implements ServiceConfig {
  DhcpConfig({
    required this.serverIp,
    required this.rangeStart,
    required this.rangeEnd,
    required this.mask,
    this.gateway,
    this.dnsServers = const [],
    this.leaseTime = const Duration(hours: 1),
    this.domainName,
    this.ntpServers = const [],
    this.tftpServer,
    this.bootFile,
    this.excluded = const [],
    this.reservations = const {},
    this.bindAddress,
    this.serverPort = 67,
    this.clientPort = 68,
    this.directedBroadcast = false,
    this.offerHold = const Duration(seconds: 60),
    this.declineQuarantine = const Duration(minutes: 10),
    this.logPackets = false,
    this.leaseFile,
    this.conflictCheck = false,
  });

  /// 이 서버의 주소 (option 54). 선택한 NIC의 고정 IP여야 한다.
  final Ipv4 serverIp;
  final Ipv4 rangeStart;
  final Ipv4 rangeEnd;
  final Ipv4 mask;
  final Ipv4? gateway;
  final List<Ipv4> dnsServers;

  /// null이면 무제한.
  final Duration? leaseTime;
  final String? domainName;
  final List<Ipv4> ntpServers;

  /// TFTP 서버 (option 66, IP면 `siaddr`에도 넣는다). 보드 부팅용.
  final String? tftpServer;

  /// 부팅 파일 이름 (option 67, `file` 필드).
  final String? bootFile;

  /// 범위 안에 있어도 나눠 주지 않을 주소. 서버와 게이트웨이는 자동으로 빠진다.
  final List<Ipv4> excluded;

  /// MAC → 고정 주소.
  final Map<MacAddress, Ipv4> reservations;

  /// 소켓을 묶을 주소. null이면 [serverIp]. NIC를 하나로 제한하기 위해 기본은 서버 주소다.
  final Ipv4? bindAddress;

  /// 테스트에서만 바꾼다. 실제 DHCP는 서버 67, 클라이언트 68이다.
  final int serverPort;
  final int clientPort;

  /// true면 255.255.255.255 대신 서브넷 브로드캐스트(예: 192.168.50.255)로 보낸다.
  /// 일부 환경에서 제한된 브로드캐스트가 엉뚱한 NIC로 나가는 경우를 위한 옵션이다.
  final bool directedBroadcast;

  final Duration offerHold;
  final Duration declineQuarantine;

  /// true면 주고받은 패킷의 16진수 덤프를 DEBUG 로그에 남긴다.
  final bool logPackets;

  /// Lease를 저장하는 파일 경로. null이면 저장하지 않는다.
  final String? leaseFile;

  /// true면 DISCOVER에 제안하기 전에 그 주소로 ping을 보내 이미 쓰이는지 확인한다.
  final bool conflictCheck;

  /// Isolate 경계와 저장소를 건너는 JSON 형태.
  @override
  Map<String, Object?> toJson() => {
        'serverIp': '$serverIp',
        'rangeStart': '$rangeStart',
        'rangeEnd': '$rangeEnd',
        'mask': '$mask',
        'gateway': gateway?.toString(),
        'dnsServers': [for (final ip in dnsServers) '$ip'],
        'leaseSeconds': leaseTime?.inSeconds,
        'domainName': domainName,
        'ntpServers': [for (final ip in ntpServers) '$ip'],
        'tftpServer': tftpServer,
        'bootFile': bootFile,
        'excluded': [for (final ip in excluded) '$ip'],
        'reservations': [
          for (final MapEntry(key: mac, value: ip) in reservations.entries) ['$mac', '$ip'],
        ],
        'bindAddress': bindAddress?.toString(),
        'serverPort': serverPort,
        'clientPort': clientPort,
        'directedBroadcast': directedBroadcast,
        'offerHoldSeconds': offerHold.inSeconds,
        'declineQuarantineSeconds': declineQuarantine.inSeconds,
        'logPackets': logPackets,
        'leaseFile': leaseFile,
        'conflictCheck': conflictCheck,
      };

  /// [toJson]의 반대. 값이 없거나 형식이 틀리면 [FormatException].
  factory DhcpConfig.fromJson(Map<String, Object?> json) {
    try {
      Ipv4 ip(String key) => Ipv4.parse(json[key]! as String);
      Ipv4? optIp(String key) => json[key] == null ? null : Ipv4.parse(json[key]! as String);
      List<Ipv4> ips(String key) => [for (final s in (json[key] as List? ?? const [])) Ipv4.parse(s as String)];
      final lease = json['leaseSeconds'] as int?;
      return DhcpConfig(
        serverIp: ip('serverIp'),
        rangeStart: ip('rangeStart'),
        rangeEnd: ip('rangeEnd'),
        mask: ip('mask'),
        gateway: optIp('gateway'),
        dnsServers: ips('dnsServers'),
        leaseTime: lease == null ? null : Duration(seconds: lease),
        domainName: json['domainName'] as String?,
        ntpServers: ips('ntpServers'),
        tftpServer: json['tftpServer'] as String?,
        bootFile: json['bootFile'] as String?,
        excluded: ips('excluded'),
        reservations: {
          for (final pair in (json['reservations'] as List? ?? const []))
            MacAddress.parse((pair as List)[0] as String): Ipv4.parse(pair[1] as String),
        },
        bindAddress: optIp('bindAddress'),
        serverPort: json['serverPort'] as int? ?? 67,
        clientPort: json['clientPort'] as int? ?? 68,
        directedBroadcast: json['directedBroadcast'] as bool? ?? false,
        offerHold: Duration(seconds: json['offerHoldSeconds'] as int? ?? 60),
        declineQuarantine: Duration(seconds: json['declineQuarantineSeconds'] as int? ?? 600),
        logPackets: json['logPackets'] as bool? ?? false,
        leaseFile: json['leaseFile'] as String?,
        conflictCheck: json['conflictCheck'] as bool? ?? false,
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Invalid DHCP config: $e');
    }
  }

  Ipv4 get bindTo => bindAddress ?? serverIp;

  Ipv4 get broadcastTarget => directedBroadcast ? serverIp.broadcastOf(mask) : Ipv4.broadcast;

  /// 잘못된 값이면 [PoolConfigException]. 범위·마스크 검증은 [LeasePool]이 한다.
  void validate() {
    if (!mask.isValidMask) throw PoolConfigException('Invalid subnet mask $mask');
    if (!serverIp.isInSubnet(rangeStart, mask)) {
      throw PoolConfigException('Server address $serverIp is not in the pool subnet');
    }
    if (serverIp == serverIp.networkOf(mask) || serverIp == serverIp.broadcastOf(mask)) {
      throw PoolConfigException('Server address $serverIp is not a host address');
    }
    final gw = gateway;
    if (gw != null && !gw.isInSubnet(rangeStart, mask)) {
      throw PoolConfigException('Gateway $gw is not in the pool subnet');
    }
    final time = leaseTime;
    if (time != null && time.inSeconds < 1) throw PoolConfigException('Lease time must be at least 1 second');
    final boot = bootFile;
    if (boot != null && boot.length > 127) throw PoolConfigException('Boot file name is longer than 127 characters');
    createPool();
  }

  LeasePool createPool({DateTime Function()? clock}) {
    final pool = LeasePool(
      start: rangeStart,
      end: rangeEnd,
      mask: mask,
      leaseTime: leaseTime,
      excluded: {serverIp, ?gateway, ...excluded},
      offerHold: offerHold,
      declineQuarantine: declineQuarantine,
      clock: clock,
    );
    for (final MapEntry(key: mac, value: ip) in reservations.entries) {
      pool.reserve(mac, ip);
    }
    return pool;
  }
}
