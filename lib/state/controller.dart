// 앱 전체 상태: 서비스 모델 세 개, NIC 목록, 지금 보고 있는 서비스. 서비스마다의 상태는 각 모델이 들고 있고,
// 이 컨트롤러는 목록과 선택만 알린다 (서비스 갱신이 사이드바·다른 화면을 다시 그리지 않게).

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dhcp/server.dart';
import '../core/ftp/server.dart';
import '../core/host.dart';
import '../core/http/server.dart';
import '../core/netcheck.dart';
import '../core/netutil.dart';
import '../core/tftp/server.dart';
import '../core/service.dart';
import 'app_paths.dart';
import 'log_file.dart';
import 'service_model.dart';
import 'service_models.dart';

class LabDaemonController extends ChangeNotifier {
  LabDaemonController({
    required this.prefs,
    required this.dhcp,
    required this.tftp,
    required this.ftp,
    required this.http,
    Future<List<NicInfo>> Function()? nicLister,
  }) : _nicLister = nicLister ?? listNics {
    selectedId = prefs.getString(_selectedKey) ?? 'dhcp';
    if (!services.any((s) => s.id == selectedId)) selectedId = 'dhcp';
  }

  /// 앱용: 서비스마다 자기 Isolate에서 돈다.
  ///
  /// [logText]를 주면 서비스 로그를 파일에 저장하는 기능이 켜진다 (로그 한 줄을 영어 문구로 바꾸는 함수).
  factory LabDaemonController.create(SharedPreferences prefs, {String Function(LogEvent event)? logText}) {
    final checker = PreStartChecker();
    LogFileSink? sink(String id) {
      final dir = appDataDir();
      if (dir == null || logText == null) return null;
      return LogFileSink(directory: '$dir${Platform.pathSeparator}logs', serviceId: id, format: logText);
    }

    return LabDaemonController(
      prefs: prefs,
      dhcp: DhcpModel(host: IsolateHost('dhcp', createDhcpService), prefs: prefs, checker: checker, leaseFile: _dataFile('dhcp_leases.json'), logSink: sink('dhcp')),
      tftp: TftpModel(host: IsolateHost('tftp', createTftpService), prefs: prefs, checker: checker, logSink: sink('tftp')),
      ftp: FtpModel(host: IsolateHost('ftp', createFtpService), prefs: prefs, checker: checker, logSink: sink('ftp')),
      http: HttpModel(host: IsolateHost('http', createHttpService), prefs: prefs, checker: checker, logSink: sink('http')),
    );
  }

  static const _selectedKey = 'ui_selected_service';

  static String? _dataFile(String name) {
    final dir = appDataDir();
    return dir == null ? null : '$dir${Platform.pathSeparator}$name';
  }

  final SharedPreferences prefs;
  final DhcpModel dhcp;
  final TftpModel tftp;
  final FtpModel ftp;
  final HttpModel http;
  final Future<List<NicInfo>> Function() _nicLister;

  late String selectedId;
  List<NicInfo> nics = const [];

  List<ServiceModel> get services => [dhcp, tftp, ftp, http];

  ServiceModel get selected => services.firstWhere((s) => s.id == selectedId);

  void select(String id) {
    if (id == selectedId) return;
    selectedId = id;
    unawaited(prefs.setString(_selectedKey, id));
    notifyListeners();
  }

  Future<void> refreshNics() async {
    nics = await _nicLister();
    notifyListeners();
  }

  /// 앱을 끝낼 때 열려 있는 소켓을 모두 닫는다.
  Future<void> stopAll() async {
    await Future.wait([for (final s in services) s.stop().catchError((_) {})]);
    await Future.wait([for (final s in services) s.flushLogs()]);
  }

  @override
  void dispose() {
    for (final s in services) {
      s.dispose();
    }
    super.dispose();
  }
}

/// `ControllerScope.of(context)`로 컨트롤러를 읽는다 (선택·NIC 목록이 바뀌면 다시 그린다).
class ControllerScope extends InheritedNotifier<LabDaemonController> {
  const ControllerScope({super.key, required LabDaemonController controller, required super.child}) : super(notifier: controller);

  static LabDaemonController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ControllerScope>()!.notifier!;

  /// 다시 그리지 않고 한 번만 읽을 때 (이벤트 처리기).
  static LabDaemonController read(BuildContext context) => context.getInheritedWidgetOfExactType<ControllerScope>()!.notifier!;
}
