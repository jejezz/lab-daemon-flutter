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
