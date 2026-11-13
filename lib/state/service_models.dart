// 서비스별 화면 모델: DHCP(Lease 표), TFTP(전송 목록), FTP(세션 목록).

import 'dart:async';

import '../core/dhcp/detector.dart';
import '../core/dhcp/server.dart';
import '../core/ftp/server.dart';
import '../core/ipv4.dart';
import '../core/netutil.dart';
import '../core/netcheck.dart';
import '../core/service.dart';
import '../core/tftp/server.dart';
import 'dhcp_settings.dart';
import 'ftp_settings.dart';
import 'service_model.dart';
import 'settings_common.dart';
import 'tftp_settings.dart';

/// 서버를 켜기 전에 [interfaceIp]가 속한 망에 다른 DHCP 서버가 있는지 확인한다. 시험에서 바꿔 끼운다.
typedef DhcpProber = Future<DhcpProbeResult> Function(Ipv4 interfaceIp);

class DhcpModel extends ServiceModel {
  DhcpModel({required super.host, required super.prefs, required super.checker, DhcpProber? prober, this.leaseFile, super.logSink, super.notifyDelay})
      : _prober = prober ?? ((ip) => detectOtherDhcpServers(interfaceIp: ip)),
        super(id: 'dhcp') {
    settings = DhcpSettings.load(prefs);
  }

  final DhcpProber _prober;

  /// Lease를 저장하는 파일 경로 (설정이 켜져 있을 때만 쓴다). null이면 저장하지 않는다.
  final String? leaseFile;
  late DhcpSettings settings;
  List<LeaseInfo> leases = const [];
  int capacity = 0;
  Map<String, int> stats = const {};

  Map<DhcpField, FieldError> get errors => settings.validate();

  @override
  bool get settingsValid => errors.isEmpty;

  @override
  Map<String, Object?> buildConfig() => {...settings.toConfig().toJson(), 'leaseFile': settings.persistLeases ? leaseFile : null};

  @override
  Ipv4 get checkAddress => Ipv4.tryParse(settings.serverIp) ?? Ipv4.any;

  @override
  List<PreStartPort> get checkPorts => const [PreStartPort('UDP', 67)];

  /// DHCP는 클라이언트가 서버 주소를 몰라도 방송으로 찾으므로 포트 없이 IP만 보여 준다.
  @override
  List<String> endpoints(List<NicInfo> nics) => [settings.serverIp];

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

  /// 설정에 있는 예약 (MAC → IP).
  List<(MacAddress, Ipv4)> get reservations => settings.parsedReservations;

  FieldError? checkReservation(String mac, String ip) => settings.checkNewReservation(mac, ip);

  /// 예약을 더한다. 실행 중이면 서버에도 바로 적용하고, 서버가 거부하면 예외를 던진다(설정은 되돌린다).
  Future<void> addReservation(String macText, String ipText) async {
    final error = checkReservation(macText, ipText);
    if (error != null) throw FormatException(error.name);
    final mac = MacAddress.parse(macText);
    final ip = Ipv4.parse(ipText);
    final before = settings;
    update(settings.copyWith(reservations: [...settings.reservations, ('$mac', '$ip')]));
    if (!running) return;
    try {
      await command('reserve', {'mac': '$mac', 'ip': '$ip'});
    } catch (_) {
      update(before);
      rethrow;
    }
  }

  Future<void> removeReservation(MacAddress mac) async {
    update(settings.copyWith(reservations: [
      for (final r in settings.reservations)
        if (MacAddress.tryParse(r.$1) != mac) r,
    ]));
    if (running) await command('unreserve', {'mac': '$mac'});
  }

  Future<bool> releaseLease(Ipv4 ip) async => running && (await command('releaseIp', {'ip': '$ip'})) == true;

  Future<int> releaseAll() async => running ? (await command('releaseAll')) as int : 0;
}

class TftpModel extends ServiceModel {
  TftpModel({required super.host, required super.prefs, required super.checker, super.logSink, super.notifyDelay}) : super(id: 'tftp') {
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
  List<String> endpoints(List<NicInfo> nics) => connectEndpoints(settings.bindIp, settings.port, 69, nics);

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
  FtpModel({required super.host, required super.prefs, required super.checker, super.logSink, super.notifyDelay}) : super(id: 'ftp') {
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
  List<String> endpoints(List<NicInfo> nics) => connectEndpoints(settings.bindIp, settings.port, 21, nics);

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
