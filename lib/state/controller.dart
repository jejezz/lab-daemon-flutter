// 화면이 보는 앱 상태: 서비스 하나하나의 상태, Lease 표, 통계, 설정. 서비스(lib/core)는 Flutter를 모르고,
// 이 클래스가 그 이벤트를 받아 ChangeNotifier로 화면에 전한다. 로그는 [LogBus]를 화면이 직접 구독한다.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dhcp/detector.dart';
import '../core/dhcp/server.dart';
import '../core/ipv4.dart';
import '../core/netutil.dart';
import '../core/service.dart';
import 'dhcp_settings.dart';

/// 서버를 켜기 전에 [interfaceIp]가 속한 망에 다른 DHCP 서버가 있는지 확인한다. 테스트에서 바꿔 끼운다.
typedef DhcpProber = Future<DhcpProbeResult> Function(Ipv4 interfaceIp);

class LabDaemonController extends ChangeNotifier {
  LabDaemonController({
    required SharedPreferences prefs,
    LogBus? bus,
    DhcpServer? dhcp,
    Future<List<NicInfo>> Function()? nicLister,
    DhcpProber? prober,
  })  : _prefs = prefs,
        _nicLister = nicLister ?? listNics,
        _prober = prober ?? ((ip) => detectOtherDhcpServers(interfaceIp: ip)),
        bus = bus ?? LogBus(),
        dhcpSettings = DhcpSettings.load(prefs) {
    this.dhcp = dhcp ?? DhcpServer(this.bus);
    _subscription = this.dhcp.events.listen(_onEvent);
  }

  final SharedPreferences _prefs;
  final Future<List<NicInfo>> Function() _nicLister;
  final DhcpProber _prober;
  final LogBus bus;
  late final DhcpServer dhcp;
  late final StreamSubscription<ServiceEvent> _subscription;

  DhcpSettings dhcpSettings;
  List<NicInfo> nics = const [];

  List<LeaseInfo> leases = const [];
  int leaseCapacity = 0;
  Map<String, int> dhcpStats = const {};
  DateTime? dhcpStartedAt;

  /// 마지막 시작 시도가 실패한 이유 (원문). 시작에 성공하면 지워진다.
  /// 'invalidSettings'(설정 오류)와 'otherServer'(다른 DHCP 서버 감지)는 화면이 알아보는 표식이다.
  String? startError;

  /// 시작 전에 다른 DHCP 서버를 확인하는 중인가.
  bool checking = false;

  /// 마지막 확인에서 찾은 다른 서버들.
  List<DetectedServer> detectedServers = const [];

  /// 서비스 시작 요청이 설정 오류로 거부됐을 때 그 오류들. 비었으면 설정은 올바르다.
  Map<DhcpField, FieldError> get dhcpErrors => dhcpSettings.validate();

  ServiceState get dhcpState => dhcp.state;

  bool get dhcpRunning => dhcp.state == ServiceState.running;

  bool get dhcpBusy => checking || dhcp.state == ServiceState.starting || dhcp.state == ServiceState.stopping;

  Future<void> refreshNics() async {
    nics = await _nicLister();
    notifyListeners();
  }

  /// 설정을 바꾸고 바로 저장한다. 실행 중이면 Lease Time만 즉시 적용하고, 나머지는 다시 시작할 때 적용된다.
  void updateDhcp(DhcpSettings next) {
    final leaseChanged = next.leaseTime != dhcpSettings.leaseTime;
    dhcpSettings = next;
    unawaited(next.save(_prefs));
    if (leaseChanged && dhcpRunning && next.validate()[DhcpField.leaseTime] == null) {
      dhcp.setLeaseTime(next.toConfig().leaseTime);
    }
    notifyListeners();
  }

  /// 서버를 켠다. 설정이 틀렸거나, 다른 DHCP 서버가 감지됐거나, 소켓을 못 열면 false이고 이유는
  /// [startError]와 로그에 남는다. [skipProbe]는 사용자가 경고를 보고도 켜겠다고 했을 때 쓴다.
  Future<bool> startDhcp({bool skipProbe = false}) async {
    if (dhcpRunning || dhcpBusy) return dhcpRunning;
    startError = null;
    detectedServers = const [];
    if (dhcpSettings.validate().isNotEmpty) {
      startError = 'invalidSettings';
      notifyListeners();
      return false;
    }
    if (dhcpSettings.detectOtherServers && !skipProbe && !await _noOtherServers()) {
      startError = 'otherServer';
      notifyListeners();
      return false;
    }
    try {
      await dhcp.start(dhcpSettings.toConfig());
      return true;
    } catch (e) {
      startError = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 같은 망에 다른 DHCP 서버가 없으면 true. 확인 자체가 실패하면 막지 않고 경고만 남긴다
  /// (예: 포트를 못 열었을 때 서버를 못 켜게 하면 오히려 불편하다).
  Future<bool> _noOtherServers() async {
    final ip = Ipv4.parse(dhcpSettings.serverIp);
    checking = true;
    notifyListeners();
    _log(LogLevel.info, 'logDhcpProbeStart', args: {'address': '$ip'});
    try {
      final result = await _prober(ip);
      if (result.inconclusive) {
        _log(LogLevel.warning, 'logDhcpProbeFailed', args: {'error': result.error});
        return true;
      }
      if (result.found) {
        detectedServers = result.servers;
        for (final server in result.servers) {
          _log(LogLevel.warning, 'logDhcpProbeFound', args: {'server': '${server.serverId}', 'ip': '${server.offeredIp}'});
        }
        return false;
      }
      _log(LogLevel.info, 'logDhcpProbeNone');
      return true;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  void _log(LogLevel level, String key, {Map<String, Object?> args = const {}}) =>
      bus.add(LogEvent('dhcp', level, key, kind: 'PROBE', args: args));

  Future<void> stopDhcp() => dhcp.stop();

  Future<bool> toggleDhcp() async {
    if (dhcpRunning) {
      await stopDhcp();
      return false;
    }
    return startDhcp();
  }

  bool releaseLease(Ipv4 ip) => dhcpRunning && dhcp.releaseIp(ip) != null;

  int releaseAllLeases() => dhcpRunning ? dhcp.releaseAll() : 0;

  void _onEvent(ServiceEvent event) {
    switch (event) {
      case DhcpLeasesEvent():
        leases = event.leases;
        leaseCapacity = event.capacity;
      case DhcpStatsEvent():
        dhcpStats = event.counts;
      case StateEvent():
        if (event.state == ServiceState.running) {
          dhcpStartedAt = event.time;
          startError = null;
        } else if (event.state == ServiceState.stopped || event.state == ServiceState.error) {
          dhcpStartedAt = null;
          leases = const [];
          leaseCapacity = 0;
          if (event.state == ServiceState.error) startError = event.error;
        }
      default:
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(dhcp.dispose());
    super.dispose();
  }
}

/// `ControllerScope.of(context)`로 컨트롤러를 읽고, 바뀌면 다시 그린다.
class ControllerScope extends InheritedNotifier<LabDaemonController> {
  const ControllerScope({super.key, required LabDaemonController controller, required super.child})
      : super(notifier: controller);

  static LabDaemonController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControllerScope>()!.notifier!;

  /// 다시 그리지 않고 한 번만 읽을 때 (이벤트 핸들러).
  static LabDaemonController read(BuildContext context) =>
      (context.getInheritedWidgetOfExactType<ControllerScope>()!).notifier!;
}
