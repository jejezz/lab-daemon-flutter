// 설정 창의 DHCP 구역이 편집하는 값. 입력 중인 글자 그대로(문자열) 저장해 두고, 서비스를 켤 때
// [DhcpSettings.toConfig]가 [DhcpConfig]로 바꾼다. 저장 키는 `dhcp_<이름>`이다 (localization.md §5).

import 'package:shared_preferences/shared_preferences.dart';

import '../core/dhcp/config.dart';
import '../core/ipv4.dart';
import '../core/lease_time.dart';

enum DhcpField { serverIp, rangeStart, rangeEnd, mask, gateway, dns, leaseTime, domain, tftpServer, bootFile }

enum FieldError { required, invalidIp, invalidMask, invalidLeaseTime, notInSubnet, notHostAddress, rangeReversed, tooLong }

class DhcpSettings {
  const DhcpSettings({
    this.serverIp = '',
    this.rangeStart = '',
    this.rangeEnd = '',
    this.mask = '255.255.255.0',
    this.gateway = '',
    this.dns = '',
    this.leaseTime = '1h',
    this.domain = '',
    this.tftpServer = '',
    this.bootFile = '',
    this.directedBroadcast = false,
    this.logPackets = false,
    this.detectOtherServers = true,
  });

  final String serverIp;
  final String rangeStart;
  final String rangeEnd;
  final String mask;
  final String gateway;

  /// 쉼표나 공백으로 구분한 DNS 서버 주소.
  final String dns;
  final String leaseTime;
  final String domain;
  final String tftpServer;
  final String bootFile;
  final bool directedBroadcast;
  final bool logPackets;

  /// 서버를 켜기 전에 같은 망의 다른 DHCP 서버를 찾아 경고한다.
  final bool detectOtherServers;

  static const _keys = {
    DhcpField.serverIp: 'dhcp_server_ip',
    DhcpField.rangeStart: 'dhcp_range_start',
    DhcpField.rangeEnd: 'dhcp_range_end',
    DhcpField.mask: 'dhcp_mask',
    DhcpField.gateway: 'dhcp_gateway',
    DhcpField.dns: 'dhcp_dns',
    DhcpField.leaseTime: 'dhcp_lease_time',
    DhcpField.domain: 'dhcp_domain',
    DhcpField.tftpServer: 'dhcp_tftp_server',
    DhcpField.bootFile: 'dhcp_boot_file',
  };
  static const _directedKey = 'dhcp_directed_broadcast';
  static const _logPacketsKey = 'dhcp_log_packets';
  static const _detectKey = 'dhcp_detect_other_servers';

  factory DhcpSettings.load(SharedPreferences prefs) {
    const defaults = DhcpSettings();
    String read(DhcpField f) => prefs.getString(_keys[f]!) ?? defaults.valueOf(f);
    return DhcpSettings(
      serverIp: read(DhcpField.serverIp),
      rangeStart: read(DhcpField.rangeStart),
      rangeEnd: read(DhcpField.rangeEnd),
      mask: read(DhcpField.mask),
      gateway: read(DhcpField.gateway),
      dns: read(DhcpField.dns),
      leaseTime: read(DhcpField.leaseTime),
      domain: read(DhcpField.domain),
      tftpServer: read(DhcpField.tftpServer),
      bootFile: read(DhcpField.bootFile),
      directedBroadcast: prefs.getBool(_directedKey) ?? false,
      logPackets: prefs.getBool(_logPacketsKey) ?? false,
      detectOtherServers: prefs.getBool(_detectKey) ?? true,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    for (final f in DhcpField.values) {
      await prefs.setString(_keys[f]!, valueOf(f));
    }
    await prefs.setBool(_directedKey, directedBroadcast);
    await prefs.setBool(_logPacketsKey, logPackets);
    await prefs.setBool(_detectKey, detectOtherServers);
  }

  String valueOf(DhcpField f) => switch (f) {
        DhcpField.serverIp => serverIp,
        DhcpField.rangeStart => rangeStart,
        DhcpField.rangeEnd => rangeEnd,
        DhcpField.mask => mask,
        DhcpField.gateway => gateway,
        DhcpField.dns => dns,
        DhcpField.leaseTime => leaseTime,
        DhcpField.domain => domain,
        DhcpField.tftpServer => tftpServer,
        DhcpField.bootFile => bootFile,
      };

  DhcpSettings withValue(DhcpField f, String value) => copyWith(
        serverIp: f == DhcpField.serverIp ? value : null,
        rangeStart: f == DhcpField.rangeStart ? value : null,
        rangeEnd: f == DhcpField.rangeEnd ? value : null,
        mask: f == DhcpField.mask ? value : null,
        gateway: f == DhcpField.gateway ? value : null,
        dns: f == DhcpField.dns ? value : null,
        leaseTime: f == DhcpField.leaseTime ? value : null,
        domain: f == DhcpField.domain ? value : null,
        tftpServer: f == DhcpField.tftpServer ? value : null,
        bootFile: f == DhcpField.bootFile ? value : null,
      );

  DhcpSettings copyWith({
    String? serverIp,
    String? rangeStart,
    String? rangeEnd,
    String? mask,
    String? gateway,
    String? dns,
    String? leaseTime,
    String? domain,
    String? tftpServer,
    String? bootFile,
    bool? directedBroadcast,
    bool? logPackets,
    bool? detectOtherServers,
  }) =>
      DhcpSettings(
        serverIp: serverIp ?? this.serverIp,
        rangeStart: rangeStart ?? this.rangeStart,
        rangeEnd: rangeEnd ?? this.rangeEnd,
        mask: mask ?? this.mask,
        gateway: gateway ?? this.gateway,
        dns: dns ?? this.dns,
        leaseTime: leaseTime ?? this.leaseTime,
        domain: domain ?? this.domain,
        tftpServer: tftpServer ?? this.tftpServer,
        bootFile: bootFile ?? this.bootFile,
        directedBroadcast: directedBroadcast ?? this.directedBroadcast,
        logPackets: logPackets ?? this.logPackets,
        detectOtherServers: detectOtherServers ?? this.detectOtherServers,
      );

  /// 같은 서브넷(/24)에서 쓸 만한 기본값을 채운다. 비어 있는 칸만 건드린다.
  DhcpSettings withSuggestionsFor(Ipv4 server) {
    final base = server.value & 0xFFFFFF00;
    return copyWith(
      rangeStart: rangeStart.isEmpty ? Ipv4(base | 100).toString() : null,
      rangeEnd: rangeEnd.isEmpty ? Ipv4(base | 200).toString() : null,
      gateway: gateway.isEmpty ? server.toString() : null,
    );
  }

  List<Ipv4>? _parseList(String text) {
    final parts = text.split(RegExp(r'[,; ]+')).where((s) => s.isNotEmpty).toList();
    final result = <Ipv4>[];
    for (final p in parts) {
      final ip = Ipv4.tryParse(p);
      if (ip == null) return null;
      result.add(ip);
    }
    return result;
  }

  /// 필드별 오류. 비어 있으면 서비스를 켤 수 있다.
  Map<DhcpField, FieldError> validate() {
    final errors = <DhcpField, FieldError>{};
    final server = Ipv4.tryParse(serverIp);
    final maskIp = Ipv4.tryParse(mask);
    final start = Ipv4.tryParse(rangeStart);
    final end = Ipv4.tryParse(rangeEnd);

    if (serverIp.trim().isEmpty) {
      errors[DhcpField.serverIp] = FieldError.required;
    } else if (server == null) {
      errors[DhcpField.serverIp] = FieldError.invalidIp;
    }
    if (mask.trim().isEmpty) {
      errors[DhcpField.mask] = FieldError.required;
    } else if (maskIp == null || !maskIp.isValidMask) {
      errors[DhcpField.mask] = FieldError.invalidMask;
    }
    for (final (field, text, ip) in [
      (DhcpField.rangeStart, rangeStart, start),
      (DhcpField.rangeEnd, rangeEnd, end),
    ]) {
      if (text.trim().isEmpty) {
        errors[field] = FieldError.required;
      } else if (ip == null) {
        errors[field] = FieldError.invalidIp;
      }
    }
    if (gateway.trim().isNotEmpty && Ipv4.tryParse(gateway) == null) errors[DhcpField.gateway] = FieldError.invalidIp;
    if (_parseList(dns) == null) errors[DhcpField.dns] = FieldError.invalidIp;
    try {
      parseLeaseTime(leaseTime);
    } on FormatException {
      errors[DhcpField.leaseTime] = FieldError.invalidLeaseTime;
    }
    if (bootFile.length > 127) errors[DhcpField.bootFile] = FieldError.tooLong;

    // 서브넷 관계는 필요한 값이 모두 올바를 때만 따진다.
    if (maskIp != null && maskIp.isValidMask) {
      final network = start?.networkOf(maskIp) ?? server?.networkOf(maskIp);
      if (network != null) {
        for (final (field, ip) in [
          (DhcpField.serverIp, server),
          (DhcpField.rangeStart, start),
          (DhcpField.rangeEnd, end),
          (DhcpField.gateway, Ipv4.tryParse(gateway)),
        ]) {
          if (ip != null && !errors.containsKey(field) && !ip.isInSubnet(network, maskIp)) {
            errors[field] = FieldError.notInSubnet;
          }
        }
        for (final (field, ip) in [(DhcpField.serverIp, server), (DhcpField.rangeStart, start), (DhcpField.rangeEnd, end)]) {
          if (ip != null && !errors.containsKey(field) && (ip == ip.networkOf(maskIp) || ip == ip.broadcastOf(maskIp))) {
            errors[field] = FieldError.notHostAddress;
          }
        }
      }
    }
    if (start != null && end != null && start > end && !errors.containsKey(DhcpField.rangeEnd)) {
      errors[DhcpField.rangeEnd] = FieldError.rangeReversed;
    }
    return errors;
  }

  /// [validate]가 비어 있을 때만 부른다.
  DhcpConfig toConfig() {
    assert(validate().isEmpty);
    final gw = gateway.trim();
    return DhcpConfig(
      serverIp: Ipv4.parse(serverIp),
      rangeStart: Ipv4.parse(rangeStart),
      rangeEnd: Ipv4.parse(rangeEnd),
      mask: Ipv4.parse(mask),
      gateway: gw.isEmpty ? null : Ipv4.parse(gw),
      dnsServers: _parseList(dns) ?? const [],
      leaseTime: parseLeaseTime(leaseTime),
      domainName: domain.trim().isEmpty ? null : domain.trim(),
      tftpServer: tftpServer.trim().isEmpty ? null : tftpServer.trim(),
      bootFile: bootFile.trim().isEmpty ? null : bootFile.trim(),
      directedBroadcast: directedBroadcast,
      logPackets: logPackets,
    );
  }
}
