// 서비스 하나의 화면 쪽 상태: 설정, 상태, 시작 전 점검 결과, 그 서비스만의 로그와 클라이언트 표.
// 서비스마다 모델이 따로라서 한 서비스의 갱신이 다른 서비스 화면을 다시 그리지 않는다.
//
// 성능: 서비스 Isolate가 보내는 이벤트 묶음(최대 10번/초)마다 화면을 바로 그리지 않고 [notifyDelay] 안의 변경을
// 한 번으로 합친다. 로그는 고정 크기 버퍼([logs])에 쌓이고, 표는 최신 스냅샷 하나만 들고 있다.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/host.dart';
import '../core/ipv4.dart';
import '../core/netcheck.dart';
import '../core/netutil.dart';
import '../core/service.dart';
import 'log_file.dart';

enum StartResult { started, invalid, blocked, needsConfirmation, failed }

abstract class ServiceModel extends ChangeNotifier {
  ServiceModel({
    required this.id,
    required this.host,
    required this.prefs,
    required this.checker,
    this.logSink,
    this.notifyDelay = const Duration(milliseconds: 50),
  }) {
    final saved = prefs.getInt('${id}_log_capacity');
    if (saved != null && LogBus.capacityChoices.contains(saved)) logs.capacity = saved;
    _subscription = host.events.listen(_onEvent);
    if (logToFile) logSink?.attach(logs);
  }

  /// 로그를 파일에 쓰는 도구 (없으면 파일 저장 기능이 없다).
  final LogFileSink? logSink;

  /// 로그를 파일에도 저장하는가 (서비스마다 따로, 기본 꺼짐).
  bool get logToFile => prefs.getBool('${id}_log_file') ?? false;

  /// 로그 파일 폴더. 저장 기능이 없으면 null.
  String? get logDirectory => logSink?.directory;

  /// 모인 로그를 바로 파일에 쓴다 (앱을 끝낼 때).
  Future<void> flushLogs() async => logSink?.flush();

  Future<void> setLogToFile(bool value) async {
    final sink = logSink;
    if (sink == null) return;
    await prefs.setBool('${id}_log_file', value);
    if (value) {
      sink.attach(logs);
    } else {
      await sink.detach();
    }
    notifyNow();
  }

  final String id;
  final ServiceHost host;
  final SharedPreferences prefs;
  final PreStartChecker checker;
  final Duration notifyDelay;

  /// 이 서비스만의 로그. 보관 줄 수는 서비스마다 고른다 (기본 1000줄).
  final logs = LogBus();

  /// 로그 보관 줄 수를 바꾸고 저장한다.
  void setLogCapacity(int value) {
    logs.capacity = value;
    prefs.setInt('${id}_log_capacity', value);
  }

  late final StreamSubscription<ServiceEvent> _subscription;
  Timer? _notifyTimer;

  /// 시작 전 점검 중인가.
  bool checking = false;

  /// 마지막 시작 시도가 실패한 이유. `invalidSettings`, `blocked`(포트 충돌 등), `needsConfirmation`(경고를 보고
  /// 켤지 물어야 함)은 화면이 알아보는 표식이고, 그 밖에는 오류 원문이다.
  String? startError;

  /// 마지막 시작 전 점검에서 찾은 문제.
  List<PreStartIssue> issues = const [];

  /// 마지막 점검에서 나온 방화벽 경고. [그래도 시작]으로 넘어간 뒤에도 화면 위쪽 [방화벽 안내]가 이것을 연다.
  PreStartIssue? firewallIssue;

  /// 방화벽 규칙을 넣을 프로그램 경로.
  String get programPath => checker.exePath;

  /// 시작이 거부된 뒤에는 빈 칸의 "필요" 오류도 보여 준다.
  bool showAllErrors = false;

  DateTime? startedAt;

  ServiceState get state => host.state;

  bool get running => state == ServiceState.running;

  /// 클라이언트가 접속할 주소(`IP` 또는 `IP:포트`, 프로토콜 기본 포트면 포트는 생략). 모든 NIC에 열었으면 NIC마다 하나씩.
  List<String> endpoints(List<NicInfo> nics) => const [];

  bool get busy => checking || state == ServiceState.starting || state == ServiceState.stopping;

  // ---- 서비스마다 채우는 것 -----------------------------------------------------------------------

  bool get settingsValid;

  /// [settingsValid]일 때만 부른다.
  Map<String, Object?> buildConfig();

  /// 포트 충돌을 볼 주소 (모든 NIC면 0.0.0.0).
  Ipv4 get checkAddress;

  List<PreStartPort> get checkPorts;

  /// FTP 패시브 범위처럼 예약 여부를 볼 TCP 포트 범위.
  (int, int)? get checkTcpRange => null;

  /// 서비스 고유 점검 (DHCP의 다른 서버 찾기).
  Future<List<PreStartIssue>> extraChecks() async => const [];

  /// 로그·상태가 아닌 이벤트 (표 스냅샷).
  void handleEvent(ServiceEvent event) {}

  /// 서비스가 멈췄을 때 표를 비운다.
  void clearClients() {}

  // ---- 시작과 중지 --------------------------------------------------------------------------------

  /// 설정 검증 → 포트·방화벽 점검(+서비스 고유 점검) → 시작. [skipWarnings]는 사용자가 경고를 보고도 켜겠다고 한 경우.
  Future<StartResult> start({bool skipWarnings = false}) async {
    if (running) return StartResult.started;
    if (busy) return StartResult.failed;
    startError = null;
    issues = const [];
    if (!settingsValid) {
      startError = 'invalidSettings';
      showAllErrors = true;
      notifyNow();
      return StartResult.invalid;
    }
    checking = true;
    notifyNow();
    final List<PreStartIssue> found;
    try {
      found = [
        ...await checker.check(bindAddress: checkAddress, ports: checkPorts, tcpRange: checkTcpRange),
        if (!skipWarnings) ...await extraChecks(),
      ];
    } finally {
      checking = false;
    }
    for (final issue in found) {
      logs.add(LogEvent(id, issue.blocking ? LogLevel.error : LogLevel.warning, 'logCheck${_kindKey(issue.kind)}', kind: 'CHECK', args: issue.args));
    }
    firewallIssue = found.where((i) => i.kind == IssueKind.firewallBlocked).firstOrNull;
    if (firewallIssue != null) {
      logs.add(LogEvent(id, LogLevel.info, 'logCheckFirewallHint', kind: 'CHECK'));
    }
    if (found.any((i) => i.blocking)) {
      issues = found;
      startError = 'blocked';
      notifyNow();
      return StartResult.blocked;
    }
    if (found.isNotEmpty && !skipWarnings) {
      issues = found;
      startError = 'needsConfirmation';
      notifyNow();
      return StartResult.needsConfirmation;
    }
    try {
      await host.start(buildConfig());
      showAllErrors = false;
      return StartResult.started;
    } catch (e) {
      startError = '$e';
      notifyNow();
      return StartResult.failed;
    }
  }

  Future<void> stop() => host.stop();

  Future<Object?> command(String name, [Map<String, Object?> args = const {}]) => host.command(name, args);

  /// 이 프로그램의 방화벽 허용 규칙을 추가한다 (UAC). 성공하면 true.
  Future<bool> addFirewallRule() async {
    final ok = await checker.requestFirewallRule();
    if (ok) firewallIssue = null;
    logs.add(LogEvent(id, ok ? LogLevel.info : LogLevel.warning, ok ? 'logCheckRuleAdded' : 'logCheckRuleFailed'));
    notifyNow();
    return ok;
  }

  static String _kindKey(IssueKind kind) => switch (kind) {
        IssueKind.portInUse => 'PortInUse',
        IssueKind.firewallBlocked => 'FirewallBlocked',
        IssueKind.otherDhcpServer => 'OtherDhcpServer',
        IssueKind.portsReserved => 'PortsReserved',
      };

  // ---- 이벤트 ---------------------------------------------------------------------------------

  void _onEvent(ServiceEvent event) {
    switch (event) {
      case LogEvent():
        logs.add(event);
      case StateEvent():
        if (event.state == ServiceState.running) {
          startedAt = event.time;
          startError = null;
        } else if (event.state == ServiceState.stopped || event.state == ServiceState.error) {
          startedAt = null;
          clearClients();
          if (event.state == ServiceState.error) startError = event.error;
        }
        notifyNow();
        return;
      default:
        handleEvent(event);
    }
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (notifyDelay == Duration.zero) {
      notifyListeners();
      return;
    }
    _notifyTimer ??= Timer(notifyDelay, () {
      _notifyTimer = null;
      notifyListeners();
    });
  }

  @protected
  void notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    unawaited(_subscription.cancel());
    unawaited(host.dispose());
    super.dispose();
  }
}
