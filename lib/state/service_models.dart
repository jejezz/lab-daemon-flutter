// 서비스별 화면 모델: DHCP(Lease 표), TFTP(전송 목록), FTP(세션 목록).

import 'dart:async';

import '../core/dhcp/detector.dart';
import '../core/dhcp/server.dart';
import '../core/ftp/server.dart';
import '../core/ipv4.dart';
import '../core/netcheck.dart';
import '../core/service.dart';
import '../core/tftp/server.dart';
import 'dhcp_settings.dart';
import 'ftp_settings.dart';
import 'service_model.dart';
import 'tftp_settings.dart';

/// 서버를 켜기 전에 [interfaceIp]가 속한 망에 다른 DHCP 서버가 있는지 확인한다. 시험에서 바꿔 끼운다.
typedef DhcpProber = Future<DhcpProbeResult> Function(Ipv4 interfaceIp);

class DhcpModel extends ServiceModel {
  DhcpModel({required super.host, required super.prefs, required super.checker, DhcpProber? prober, super.notifyDelay})
      : _prober = prober ?? ((ip) => detectOtherDhcpServers(interfaceIp: ip)),
        super(id: 'dhcp') {
    settings = DhcpSettings.load(prefs);
  }

  final DhcpProber _prober;
  late DhcpSettings settings;
  List<LeaseInfo> leases = const [];
  int capacity = 0;
  Map<String, int> stats = const {};

  Map<DhcpField, FieldError> get errors => settings.validate();

  @override
  bool get settingsValid => errors.isEmpty;

  @override
  Map<String, Object?> buildConfig() => settings.toConfig().toJson();

  @override
  Ipv4 get checkAddress => Ipv4.tryParse(settings.serverIp) ?? Ipv4.any;

  @override
  List<PreStartPort> get checkPorts => const [PreStartPort('UDP', 67)];

  @override
  Future<List<PreStartIssue>> extraChecks() async {
    if (!settings.detectOtherServers) return const [];
    final ip = Ipv4.parse(settings.serverIp);
    logs.add(LogEvent(id, LogLevel.info, 'logDhcpProbeStart', kind: 'PROBE', args: {'address': '$ip'}));
    final result = await _prober(ip);
    if (result.inconclusive) {
      logs.add(LogEvent(id, LogLevel.warning, 'logDhcpProbeFailed', kind: 'PROBE', args: {'error': result.error}));
      return const [];
    }
    if (!result.found) {
      logs.add(LogEvent(id, LogLevel.info, 'logDhcpProbeNone', kind: 'PROBE'));
      return const [];
    }
    return [
      PreStartIssue(IssueKind.otherDhcpServer, blocking: false, args: {
        'servers': [for (final s in result.servers) '${s.serverId}'],
        'offers': [for (final s in result.servers) '${s.offeredIp}'],
      }),
    ];
  }

  @override
  void handleEvent(ServiceEvent event) {
    if (event is DhcpLeasesEvent) {
      leases = event.leases;
      capacity = event.capacity;
    } else if (event is DhcpStatsEvent) {
      stats = event.counts;
    }
  }

  @override
  void clearClients() {
    leases = const [];
    capacity = 0;
  }

  /// 설정을 바꾸고 바로 저장한다. 실행 중이면 Lease Time만 즉시 적용된다.
  void update(DhcpSettings next) {
    final leaseChanged = next.leaseTime != settings.leaseTime;
    settings = next;
    unawaited(next.save(prefs));
    if (leaseChanged && running && next.validate()[DhcpField.leaseTime] == null) {
      final time = next.leaseTime.trim().toLowerCase();
      unawaited(command('setLeaseTime', {'leaseTime': time == 'infinite' || time == 'inf' ? null : time}).catchError((_) => null));
    }
    notifyNow();
  }

  Future<bool> releaseLease(Ipv4 ip) async => running && (await command('releaseIp', {'ip': '$ip'})) == true;

  Future<int> releaseAll() async => running ? (await command('releaseAll')) as int : 0;
}

class TftpModel extends ServiceModel {
  TftpModel({required super.host, required super.prefs, required super.checker, super.notifyDelay}) : super(id: 'tftp') {
    settings = TftpSettings.load(prefs);
  }

  late TftpSettings settings;
  TftpTransfersEvent? transfers;

  Map<TftpField, FieldError> get errors => settings.validate();

  @override
  bool get settingsValid => errors.isEmpty;

  @override
  Map<String, Object?> buildConfig() => settings.toConfig().toJson();

  @override
  Ipv4 get checkAddress => Ipv4.tryParse(settings.bindIp) ?? Ipv4.any;

  @override
  List<PreStartPort> get checkPorts => [PreStartPort('UDP', int.tryParse(settings.port) ?? 69)];

  @override
  void handleEvent(ServiceEvent event) {
    if (event is TftpTransfersEvent) transfers = event;
  }

  @override
  void clearClients() => transfers = null;

  void update(TftpSettings next) {
    settings = next;
    unawaited(next.save(prefs));
    notifyNow();
  }

  Future<bool> abort(int id) async => running && (await command('abort', {'id': id})) == true;

  Future<void> clearRecent() async {
    if (running) await command('clearRecent');
  }
}

class FtpModel extends ServiceModel {
  FtpModel({required super.host, required super.prefs, required super.checker, super.notifyDelay}) : super(id: 'ftp') {
    settings = FtpSettings.load(prefs);
  }

  late FtpSettings settings;
  FtpSessionsEvent? sessions;

  Map<FtpField, FieldError> get errors => settings.validate();

  @override
  bool get settingsValid => errors.isEmpty;

  @override
  Map<String, Object?> buildConfig() => settings.toConfig().toJson();

  @override
  Ipv4 get checkAddress => Ipv4.tryParse(settings.bindIp) ?? Ipv4.any;

  @override
  List<PreStartPort> get checkPorts => [PreStartPort('TCP', int.tryParse(settings.port) ?? 21)];

  @override
  (int, int)? get checkTcpRange {
    final s = int.tryParse(settings.passiveStart);
    final e = int.tryParse(settings.passiveEnd);
    return s == null || e == null ? null : (s, e);
  }

  @override
  void handleEvent(ServiceEvent event) {
    if (event is FtpSessionsEvent) sessions = event;
  }

  @override
  void clearClients() => sessions = null;

  void update(FtpSettings next) {
    settings = next;
    unawaited(next.save(prefs));
    notifyNow();
  }

  Future<bool> disconnect(int id) async => running && (await command('disconnect', {'id': id})) == true;
}
