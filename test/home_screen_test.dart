// 메인 화면 흐름: 서비스별 화면(각자의 설정·클라이언트 표·로그), 시작 전 점검 대화상자, DHCP Lease, TFTP 전송, FTP 세션.
// DHCP는 가짜 전송 계층을 쓰고, TFTP·FTP는 실제 loopback 소켓을 쓴다 (실제 I/O는 tester.runAsync 안에서).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/detector.dart';
import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/dhcp/server.dart';
import 'package:lab_daemon/core/ftp/server.dart';
import 'package:lab_daemon/core/host.dart';
import 'package:lab_daemon/core/http/server.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/netcheck.dart';
import 'package:lab_daemon/core/netutil.dart';
import 'package:lab_daemon/core/tftp/server.dart';
import 'package:lab_daemon/l10n/app_localizations.dart';
import 'package:lab_daemon/settings/app_settings.dart';
import 'package:lab_daemon/state/controller.dart';
import 'package:lab_daemon/state/service_models.dart';
import 'package:lab_daemon/theme/app_theme.dart';
import 'package:lab_daemon/ui/log_panel.dart';
import 'package:lab_daemon/ui/clients/client_tables.dart';
import 'package:lab_daemon/ui/home_screen.dart';
import 'package:lab_daemon/ui/widgets/fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';
import 'support/ftp_client.dart';
import 'support/tftp_client.dart';

const _dhcpPrefs = <String, Object>{
  'dhcp_server_ip': '192.168.50.1',
  'dhcp_range_start': '192.168.50.100',
  'dhcp_range_end': '192.168.50.110',
  'dhcp_mask': '255.255.255.0',
  'dhcp_gateway': '192.168.50.1',
  'dhcp_lease_time': '1h',
  // 가짜 전송 계층의 dora()가 응답을 바로(동기로) 읽으므로 ping 확인은 끈다.
  'dhcp_conflict_check': false,
  'dhcp_persist_leases': false,
};

MacAddress mac(int n) => MacAddress([0xaa, 0xbb, 0xcc, 0, 0, n]);

class _FakeChecker extends PreStartChecker {
  _FakeChecker() : super(isWindows: false, exePath: r'C:\lab\lab_daemon.exe');

  List<PreStartIssue> next = [];
  int checks = 0;
  int ruleCalls = 0;
  bool ruleResult = true;

  @override
  Future<List<PreStartIssue>> check({required Ipv4 bindAddress, required List<PreStartPort> ports, (int, int)? tcpRange}) async {
    checks++;
    return next;
  }

  @override
  Future<bool> requestFirewallRule() async {
    ruleCalls++;
    if (ruleResult) next = [];
    return ruleResult;
  }
}

class _App {
  _App(this.controller, this.transport, this.checker, this.root);

  final LabDaemonController controller;
  final FakeTransport transport;
  final _FakeChecker checker;
  final Directory root;
  List<DetectedServer> otherDhcp = [];

  DhcpModel get dhcp => controller.dhcp;
  TftpModel get tftp => controller.tftp;
  FtpModel get ftp => controller.ftp;
  HttpModel get http => controller.http;

  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await controller.stopAll();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    controller.dispose();
  }
}

/// TCP 포트 하나 (HTTP 서버용).
Future<int> _freePort2() => _freePort(tcp: true);

Future<int> _freePort({bool tcp = false}) async {
  if (tcp) {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final p = s.port;
  s.close();
  return p;
}

void _testApp(String name, Future<void> Function(WidgetTester tester, _App app) body,
    {Map<String, Object> prefs = _dhcpPrefs, Size size = const Size(1280, 800)}) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final settings = await AppSettings.load();
    final transport = FakeTransport();
    final checker = _FakeChecker();
    final root = (await tester.runAsync(() async => Directory.systemTemp.createTempSync('ui_test_')))!;
    late final _App app;
    final controller = LabDaemonController(
      prefs: sp,
      dhcp: DhcpModel(
        host: InProcessHost(DhcpServer(transportFactory: (a, p) async => transport, snapshotInterval: Duration.zero)),
        prefs: sp,
        checker: checker,
        prober: (ip) async => DhcpProbeResult(app.otherDhcp),
        notifyDelay: Duration.zero,
      ),
      tftp: TftpModel(host: InProcessHost(TftpServer(snapshotInterval: Duration.zero)), prefs: sp, checker: checker, notifyDelay: Duration.zero),
      ftp: FtpModel(host: InProcessHost(FtpServer(snapshotInterval: Duration.zero)), prefs: sp, checker: checker, notifyDelay: Duration.zero),
      http: HttpModel(host: InProcessHost(HttpFileServer(snapshotInterval: Duration.zero)), prefs: sp, checker: checker, notifyDelay: Duration.zero),
      nicLister: () async => [NicInfo('Ethernet 2', Ipv4.parse('192.168.50.1')), NicInfo('Loopback', Ipv4.parse('127.0.0.1'))],
    );
    app = _App(controller, transport, checker, root);
    await controller.refreshNics();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ControllerScope(
      controller: controller,
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(onAbout: () {}),
        ),
      ),
    ));
    await tester.pump();
    try {
      await body(tester, app);
    } finally {
      await app.shutdown(tester);
    }
  });
}

/// 로그 패널은 묶음(50ms) 단위로 다시 그린다.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 60));
  await tester.pump();
}

Future<void> _startDhcp(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Start service'));
  await tester.pumpAndSettle();
}

PreStartIssue _firewall() => const PreStartIssue(IssueKind.firewallBlocked, blocking: false, args: {
      'profiles': ['Public'],
      'ports': ['UDP 67'],
      'program': r'C:\lab\lab_daemon.exe',
    });

void main() {
  group('서비스별 화면', () {
    _testApp('사이드바에 서비스 네 개가 있고, 서비스마다 자기 설정 패널을 보인다', (tester, app) async {
      for (final name in ['DHCP', 'TFTP', 'FTP', 'HTTP']) {
        expect(find.text(name), findsWidgets);
      }
      expect(find.text('Range start'), findsOneWidget, reason: 'DHCP 화면의 설정');
      expect(find.text('Root folder'), findsNothing);

      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      expect(find.text('Root folder'), findsOneWidget);
      expect(find.text('Allow uploads'), findsOneWidget);
      expect(find.text('Range start'), findsNothing, reason: '다른 서비스 설정을 한 화면에 섞지 않는다');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(find.text('Username'), findsOneWidget, reason: 'Ctrl+3 → FTP');
      expect(find.text('Allow anonymous login'), findsOneWidget);
      expect(app.controller.selectedId, 'ftp');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(find.text('Port (default 80)'), findsOneWidget, reason: 'Ctrl+4 → HTTP, 포트 칸에 프로토콜 기본 포트');
      expect(find.text('Show folder listings'), findsOneWidget);
      expect(find.text('Allow uploads (PUT)'), findsOneWidget);
      expect(find.text('Username'), findsNothing, reason: 'FTP 설정은 섞이지 않는다');
      expect(app.controller.selectedId, 'http');
    });

    _testApp('앱 설정 창에는 외형만 있다 (서비스 설정은 각 서비스 화면에)', (tester, app) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Server interface'), findsNothing);
      expect(find.text('Range start'), findsNWidgets(1), reason: '뒤에 있는 DHCP 패널의 것 하나뿐');
    });

    _testApp('설정 패널을 접고 펼 수 있고, 접힌 상태는 서비스마다 기억한다', (tester, app) async {
      await tester.tap(find.byTooltip('Collapse settings (Ctrl+B)'));
      await tester.pumpAndSettle();
      expect(find.text('Range start'), findsNothing);
      expect(find.text('Settings'), findsOneWidget, reason: '접히면 띠에 세로 글씨가 남는다');
      expect(app.controller.prefs.getBool('dhcp_panel_open'), isFalse);

      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      expect(find.text('Root folder'), findsOneWidget, reason: '다른 서비스의 패널은 그대로 펴져 있다');

      await tester.tap(find.text('DHCP').first);
      await tester.pumpAndSettle();
      expect(find.text('Range start'), findsNothing, reason: '돌아와도 DHCP는 접혀 있다');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      expect(find.text('Range start'), findsOneWidget, reason: 'Ctrl+B로 다시 편다');
      expect(app.controller.prefs.getBool('dhcp_panel_open'), isTrue);
    });
  });

  _testApp('최소 창 크기(960×600)에서도 세 서비스 화면이 넘치지 않는다', (tester, app) async {
    await _startDhcp(tester);
    app.transport.dora(mac(1), hostname: 'a-very-long-hostname-for-the-table');
    await _settle(tester);
    for (final name in ['TFTP', 'FTP', 'HTTP', 'DHCP']) {
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
    }
  }, size: const Size(960, 600));

  group('DHCP', () {
    _testApp('설정이 비어 있으면 시작을 거부하고 빈 칸의 오류를 보여 준다', (tester, app) async {
      await _startDhcp(tester);
      expect(find.text('The DHCP settings are not valid. Check the settings on the left.'), findsOneWidget);
      expect(find.text('Required'), findsWidgets);
      expect(app.checker.checks, 0, reason: '설정이 틀리면 점검도 하지 않는다');
    }, prefs: const {});

    _testApp('시작하면 상태와 요약이 나오고, 장비가 주소를 받으면 표와 DHCP 로그에 나타난다', (tester, app) async {
      await _startDhcp(tester);
      expect(app.dhcp.running, isTrue);
      expect(find.text('Running'), findsWidgets);
      expect(find.text('No leases yet'), findsOneWidget);

      app.transport.dora(mac(1), hostname: 'rk3568');
      await _settle(tester);
      expect(find.text('aa:bb:cc:00:00:01'), findsOneWidget);
      expect(find.text('rk3568'), findsOneWidget);
      expect(find.text('Bound'), findsOneWidget);
      expect(find.textContaining('In use 1/11'), findsOneWidget);
      expect(find.textContaining('ACK 192.168.50.100 to aa:bb:cc:00:00:01 (lease 1h)'), findsOneWidget);

      // 서비스마다 로그가 따로다: TFTP 화면의 로그에는 DHCP 로그가 없다.
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('ACK 192.168.50.100'), findsNothing);
      expect(app.tftp.logs.length, 0);
    });

    _testApp('고정 주소 예약을 추가·삭제하고, 켜져 있으면 서버에도 바로 적용한다', (tester, app) async {
      await _startDhcp(tester);
      final mac = find.widgetWithText(TextField, 'MAC address');
      final ipField = find.widgetWithText(TextField, 'Reserved IP');
      await tester.ensureVisible(mac);
      await tester.enterText(mac, 'aa:bb:cc:00:99:01');
      await tester.enterText(ipField, '10.0.0.5');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      expect(find.textContaining('subnet'), findsWidgets, reason: '입력 칸 아래에 이유가 나온다');
      expect(app.dhcp.reservations, isEmpty, reason: '맞지 않는 예약은 더하지 않는다');

      await tester.enterText(ipField, '192.168.50.20');
      await tester.runAsync(() async {
        await app.dhcp.addReservation('aa:bb:cc:00:99:01', '192.168.50.20');
      });
      await tester.pumpAndSettle();
      expect(find.text('aa:bb:cc:00:99:01  →  192.168.50.20'), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(app.controller.prefs.getString('dhcp_reservations'), contains('192.168.50.20'));
      final pool = (app.controller.dhcp.host as InProcessHost).service as DhcpServer;
      expect(pool.pool!.reservations.values.map((ip) => '$ip'), ['192.168.50.20'], reason: '실행 중에도 서버에 바로 적용');

      await tester.ensureVisible(find.byTooltip('Remove reservation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove reservation'));
      await tester.pumpAndSettle();
      expect(find.text('aa:bb:cc:00:99:01  →  192.168.50.20'), findsNothing);
      expect(pool.pool!.reservations, isEmpty);
    });

    _testApp('Lease 줄에서 그 주소를 예약하면 핀 표시가 붙고, 같은 MAC은 다시 예약하지 않는다', (tester, app) async {
      await _startDhcp(tester);
      app.transport.dora(mac(1), hostname: 'rk3568');
      await _settle(tester);
      await tester.tap(find.text('aa:bb:cc:00:00:01'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Reserve address'));
      await tester.pumpAndSettle();
      expect(find.text('Reserved 192.168.50.100 for aa:bb:cc:00:00:01'), findsOneWidget);
      expect(app.dhcp.reservations.single.$2, Ipv4.parse('192.168.50.100'));
      expect(find.byTooltip('Reserved address'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Reserve address'));
      await tester.pumpAndSettle();
      expect(app.dhcp.reservations, hasLength(1), reason: '이미 예약한 MAC');
      expect(find.textContaining('Could not reserve'), findsOneWidget);
    });

    _testApp('option 66/67: TFTP 서비스 주소로 채우고, TFTP 루트 폴더에서 부팅 파일을 고른다', (tester, app) async {
      await tester.runAsync(() async {
        File('${app.root.path}/u-boot.bin').writeAsBytesSync(List.filled(2048, 1));
        Directory('${app.root.path}/rk3566').createSync();
        File('${app.root.path}/rk3566/Image').writeAsBytesSync(List.filled(4096, 1));
      });
      app.tftp.update(app.tftp.settings.copyWith(rootDir: app.root.path, bindIp: '192.168.50.7', port: '6969'));
      // 설정은 서비스 화면마다 따로라서, TFTP를 고친 뒤 DHCP 화면으로 돌아온 상황이다.
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DHCP').first);
      await tester.pumpAndSettle();

      // TFTP가 69번이 아니면 보드가 못 찾을 수 있다는 안내가 나온다.
      await tester.ensureVisible(find.byTooltip('Fill in the TFTP service address'));
      expect(find.textContaining('uses port 6969'), findsOneWidget);

      await tester.tap(find.byTooltip('Fill in the TFTP service address'));
      await tester.pump();
      expect(app.dhcp.settings.tftpServer, '192.168.50.7', reason: 'TFTP 서비스가 묶은 주소');

      app.tftp.update(app.tftp.settings.copyWith(bindIp: ''));
      await tester.pump();
      await tester.tap(find.byTooltip('Fill in the TFTP service address'));
      await tester.pump();
      expect(app.dhcp.settings.tftpServer, '192.168.50.1', reason: '모든 NIC에 열었으면 이 DHCP 서버의 주소');

      await tester.ensureVisible(find.byTooltip('Choose from the TFTP root folder'));
      await tester.tap(find.byTooltip('Choose from the TFTP root folder'));
      await tester.pump(); // 대화상자가 열리며 파일 목록 읽기를 시작한다
      // 목록 읽기는 실제 파일 I/O라서, 끝날 때까지 실제 시간으로 기다리며 화면을 한 번씩 그린다 (진행 표시가 계속 돌아서 pumpAndSettle은 못 쓴다).
      for (var i = 0; i < 20 && find.text('rk3566/Image').evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Choose a boot file'), findsOneWidget);
      expect(find.text('rk3566/Image'), findsOneWidget);
      expect(find.text('u-boot.bin'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Search file names'), 'rk35');
      await tester.pumpAndSettle();
      expect(find.text('u-boot.bin'), findsNothing);
      await tester.tap(find.text('rk3566/Image'));
      await tester.pumpAndSettle();
      expect(app.dhcp.settings.bootFile, 'rk3566/Image');
    });

    _testApp('TFTP 루트 폴더를 정하지 않았으면 고르기 대신 안내한다', (tester, app) async {
      await tester.ensureVisible(find.byTooltip('Choose from the TFTP root folder'));
      await tester.tap(find.byTooltip('Choose from the TFTP root folder'));
      await tester.pumpAndSettle();
      expect(find.text('Set the TFTP service root folder first'), findsOneWidget);
      expect(find.text('Choose a boot file'), findsNothing);
    });

    _testApp('줄 끝 단추로 해제하고, 전체 해제는 확인을 받는다', (tester, app) async {
      await _startDhcp(tester);
      app.transport.dora(mac(1));
      app.transport.dora(mac(2));
      await _settle(tester);

      await tester.tap(find.byTooltip('Release').first);
      await tester.pumpAndSettle();
      expect(app.dhcp.leases, hasLength(1));

      await tester.tap(find.widgetWithText(TextButton, 'Release All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.dhcp.leases, hasLength(1));

      await tester.tap(find.widgetWithText(TextButton, 'Release All'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Release All'));
      await tester.pumpAndSettle();
      expect(app.dhcp.leases, isEmpty);
    });

    _testApp('실행 중에는 설정이 잠기고 Lease Time만 바꿀 수 있다', (tester, app) async {
      await _startDhcp(tester);
      expect(find.textContaining('only the lease time applies immediately'), findsOneWidget);
      final rangeStart = tester.widget<TextField>(find.widgetWithText(TextField, 'Range start'));
      final lease = tester.widget<TextField>(find.widgetWithText(TextField, 'Lease time'));
      expect(rangeStart.enabled, isFalse);
      expect(lease.enabled, isTrue);
    });

    _testApp('다른 DHCP 서버가 있으면 경고하고, 그래도 시작을 고르면 켠다', (tester, app) async {
      app.otherDhcp = [DetectedServer(serverId: Ipv4.parse('192.168.50.254'), offeredIp: Ipv4.parse('192.168.50.77'))];
      await _startDhcp(tester);
      expect(find.text('Another DHCP server is on this network'), findsOneWidget);
      expect(find.textContaining('192.168.50.254 (offered 192.168.50.77)'), findsOneWidget);
      expect(app.dhcp.running, isFalse);
      await tester.tap(find.text('Start Anyway'));
      await tester.pumpAndSettle();
      expect(app.dhcp.running, isTrue);
    });
  });

  group('앱 바 접속 주소', () {
    _testApp('켜진 서비스만 접속 주소를 보이고, DHCP는 IP만, 기본 포트는 생략한다', (tester, app) async {
      Finder inAppBar(String text) => find.descendant(of: find.byType(AppBar), matching: find.textContaining(text));
      expect(inAppBar('192.168.50.1'), findsNothing, reason: '꺼져 있으면 아무것도 보이지 않는다');

      await _startDhcp(tester);
      expect(app.dhcp.running, isTrue);
      final appBarText = inAppBar('192.168.50.1');
      expect(appBarText, findsOneWidget, reason: 'DHCP 서버 IP');
      expect(tester.widget<Text>(appBarText).textSpan!.toPlainText(), 'DHCP  192.168.50.1');

      final port = (await tester.runAsync(_freePort))!;
      app.tftp.update(app.tftp.settings.copyWith(bindIp: '127.0.0.1', port: '$port', rootDir: app.root.path));
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await app.tftp.start();
      });
      await tester.pump();
      expect(inAppBar('TFTP  127.0.0.1:$port'), findsOneWidget, reason: '기본 포트(69)가 아니면 포트를 쓴다');
    });
  });

  group('시작 전 점검', () {
    _testApp('방화벽 경고: 취소하면 켜지 않고, 그래도 시작하면 켠다', (tester, app) async {
      app.checker.next = [_firewall()];
      await _startDhcp(tester);
      expect(find.text('Check before starting'), findsOneWidget);
      expect(find.textContaining('Windows Firewall may block incoming UDP 67 on the Public profile'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.dhcp.running, isFalse);
      await _settle(tester);
      expect(find.textContaining('No firewall allow rule: Public profile, UDP 67'), findsOneWidget, reason: '점검 결과는 그 서비스 로그에도 남는다');

      await _startDhcp(tester);
      await tester.tap(find.text('Start Anyway'));
      await tester.pumpAndSettle();
      expect(app.dhcp.running, isTrue);
    });

    _testApp('방화벽 규칙 추가를 고르면 규칙을 넣고 다시 점검해서 켠다', (tester, app) async {
      app.checker.next = [_firewall()];
      await _startDhcp(tester);
      await tester.tap(find.text('Add Firewall Rule'));
      await tester.pumpAndSettle();
      expect(app.checker.ruleCalls, 1);
      expect(app.checker.checks, 2, reason: '규칙을 넣은 뒤 다시 점검한다');
      expect(app.dhcp.running, isTrue);
      expect(find.text('Firewall rule added'), findsOneWidget);
    });

    _testApp('점검 창의 [해결 방법]은 OS별 허용 단계와 복사할 명령을 보이고, 거기서 규칙을 넣을 수 있다', (tester, app) async {
      app.checker.next = [_firewall()];
      await _startDhcp(tester);
      await tester.tap(find.text('How to Fix'));
      await tester.pumpAndSettle();
      expect(find.text('Allow through Windows Firewall'), findsOneWidget);
      expect(find.textContaining('2. Allow it yourself (Windows'), findsOneWidget);
      expect(find.textContaining('Allow an app through firewall'), findsOneWidget);
      expect(find.text('Open Allowed Apps'), findsOneWidget);
      expect(
        find.text(r'netsh advfirewall firewall add rule name="Lab Daemon" dir=in action=allow program="C:\lab\lab_daemon.exe" enable=yes profile=any'),
        findsOneWidget,
      );

      app.checker.next = [];
      await tester.tap(find.widgetWithText(FilledButton, 'Add Firewall Rule'));
      await tester.pumpAndSettle();
      expect(find.text('Allow through Windows Firewall'), findsNothing);
      expect(find.text('Check before starting'), findsNothing, reason: '점검 창도 같이 닫힌다');
      expect(app.checker.ruleCalls, 1);
      expect(app.dhcp.running, isTrue);
    });

    _testApp('그래도 시작한 뒤에도 화면 위쪽 [방화벽 안내]와 로그 안내가 남는다', (tester, app) async {
      app.checker.next = [_firewall()];
      await _startDhcp(tester);
      await tester.tap(find.text('Start Anyway'));
      await tester.pumpAndSettle();
      expect(app.dhcp.running, isTrue);
      await _settle(tester);
      expect(find.textContaining('See [Firewall help] at the top'), findsWidgets, reason: '점검마다 경고 다음 줄에 안내가 붙는다');

      await tester.tap(find.text('Firewall help'));
      await tester.pumpAndSettle();
      expect(find.text('Allow through Windows Firewall'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add Firewall Rule'));
      await tester.pumpAndSettle();
      expect(app.checker.ruleCalls, 1);
      expect(find.text('Firewall help'), findsNothing, reason: '규칙을 넣으면 안내 칩이 사라진다');
    });

    _testApp('방화벽 경고가 없으면 [방화벽 안내] 칩이 없다', (tester, app) async {
      await _startDhcp(tester);
      expect(app.dhcp.running, isTrue);
      expect(find.text('Firewall help'), findsNothing);
    });

    _testApp('포트를 다른 프로그램이 쓰면 시작할 수 없다는 창만 보인다 (그래도 시작 없음)', (tester, app) async {
      app.checker.next = [
        const PreStartIssue(IssueKind.portInUse, blocking: true, args: {'protocol': 'UDP', 'port': 67, 'pid': 1234, 'process': 'svchost.exe', 'address': '0.0.0.0'}),
      ];
      await _startDhcp(tester);
      expect(find.text('The service cannot start'), findsOneWidget);
      expect(find.textContaining('UDP 67 is used by another program: svchost.exe (PID 1234)'), findsOneWidget);
      expect(find.text('Start Anyway'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(app.dhcp.running, isFalse);
    });
  });

  group('TFTP', () {
    _testApp('파일을 받으면 전송 표·요약·TFTP 로그에 나타난다', (tester, app) async {
      final port = (await tester.runAsync(_freePort))!;
      final content = Uint8List.fromList(List.generate(5000, (i) => i % 251));
      await tester.runAsync(() async => File('${app.root.path}/boot.bin').writeAsBytesSync(content));
      app.tftp.update(app.tftp.settings.copyWith(bindIp: '127.0.0.1', port: '$port', rootDir: app.root.path));

      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await app.tftp.start();
      });
      await tester.pump();
      expect(app.tftp.running, isTrue);
      expect(find.text('No transfers yet'), findsOneWidget);

      final result = (await tester.runAsync(() => tftpGet(port: port, file: 'boot.bin')))!;
      expect(result.data, content);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _settle(tester);

      expect(find.text('boot.bin'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Done 1'), findsOneWidget);
      expect(find.textContaining('Sent boot.bin to 127.0.0.1'), findsOneWidget);
    });
  });

  group('폴더 끌어다 놓기', () {
    /// 탐색기에서 [paths]를 [target] 칸 위로 끌어다 놓는 것을 플러그인 채널 이벤트로 흉내 낸다.
    Future<void> dropOn(WidgetTester tester, Finder target, List<String> paths) async {
      final at = tester.getCenter(target);
      Future<void> send(String method, Object args) => tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'desktop_drop',
            const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
            (_) {},
          );
      await send('entered', [at.dx, at.dy]);
      await tester.pump();
      await send('performOperation', paths);
      await tester.pump();
    }

    _testApp('TFTP 루트 폴더 칸에 폴더를 끌어다 놓으면 그 폴더로 바뀐다', (tester, app) async {
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      expect(find.text('You can also drag a folder onto this field'), findsOneWidget);

      await dropOn(tester, find.byType(FolderField), [app.root.path]);
      expect(app.tftp.settings.rootDir, app.root.path);
      expect(find.text(app.root.path), findsOneWidget, reason: '입력 칸에도 바로 보인다');
    });

    _testApp('파일을 놓으면 그 파일이 든 폴더로, 폴더가 섞여 있으면 폴더를 고른다', (tester, app) async {
      final sub = Directory('${app.root.path}/images')..createSync();
      final file = File('${app.root.path}/zImage')..writeAsBytesSync([1]);
      await tester.tap(find.text('FTP').first);
      await tester.pumpAndSettle();

      await dropOn(tester, find.byType(FolderField), [file.path]);
      expect(app.ftp.settings.rootDir, app.root.path);

      await dropOn(tester, find.byType(FolderField), [file.path, sub.path]);
      expect(app.ftp.settings.rootDir, sub.path);
    });

    _testApp('서비스가 켜져 있어 칸이 잠겨 있으면 끌어다 놓아도 바뀌지 않는다', (tester, app) async {
      final port = (await tester.runAsync(_freePort))!;
      app.tftp.update(app.tftp.settings.copyWith(bindIp: '127.0.0.1', port: '$port', rootDir: app.root.path));
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await app.tftp.start();
      });
      await tester.pump();
      final other = Directory('${app.root.path}/other')..createSync();

      await dropOn(tester, find.byType(FolderField), [other.path]);
      expect(app.tftp.settings.rootDir, app.root.path);
    });
  });

  group('HTTP', () {
    _testApp('파일을 받으면 요청 표·요약·앱 바 주소·HTTP 로그에 나타나고, 주소를 복사할 수 있다', (tester, app) async {
      HttpOverrides.global = null; // flutter_test는 모든 HTTP 요청에 400을 돌려주는 가짜 클라이언트를 끼워 둔다: 실제 loopback을 쓰려면 끈다
      final port = (await tester.runAsync(_freePort2))!;
      final content = Uint8List.fromList(List.generate(20000, (i) => i % 251));
      await tester.runAsync(() async => File('${app.root.path}/boot.bin').writeAsBytesSync(content));
      app.http.update(app.http.settings.copyWith(bindIp: '127.0.0.1', port: '$port', rootDir: app.root.path));

      await tester.tap(find.text('HTTP').first);
      await tester.pumpAndSettle();
      expect(find.text('No requests yet'), findsNothing, reason: '꺼져 있으면 시작 화면');
      await tester.runAsync(() async {
        await app.http.start();
      });
      await tester.pump();
      expect(app.http.running, isTrue);
      expect(find.text('No requests yet'), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.textContaining('HTTP  127.0.0.1:$port')), findsOneWidget, reason: '기본 포트(80)가 아니면 포트를 쓴다');

      final received = await tester.runAsync(() async {
        final client = HttpClient();
        final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/boot.bin'))).close();
        final bytes = <int>[];
        await for (final c in res) {
          bytes.addAll(c);
        }
        client.close();
        return (res.statusCode, bytes);
      });
      expect(received!.$1, 200);
      expect(received.$2, content);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await _settle(tester);

      expect(find.descendant(of: find.byType(HttpRequestTable), matching: find.textContaining('/boot.bin', findRichText: true)), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('OK 1'), findsOneWidget);
      expect(find.textContaining('GET /boot.bin → 200'), findsOneWidget);

      // [주소 복사]는 클라이언트가 열 URL을 클립보드에 넣는다.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.tap(find.widgetWithText(TextButton, 'Copy address'));
      await tester.pumpAndSettle();
      expect(copied, 'http://127.0.0.1:$port/');
      expect(find.text('Copied http://127.0.0.1:$port/'), findsOneWidget);
    });

    _testApp('실패한 요청은 응답 코드와 함께 실패로 보이고, 끝난 요청 지우기로 목록을 비운다', (tester, app) async {
      HttpOverrides.global = null;
      final port = (await tester.runAsync(_freePort2))!;
      app.http.update(app.http.settings.copyWith(bindIp: '127.0.0.1', port: '$port', rootDir: app.root.path));
      await tester.tap(find.text('HTTP').first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await app.http.start();
        final client = HttpClient();
        final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/없는-파일'))).close();
        await res.drain<void>();
        client.close();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await _settle(tester);
      expect(find.text('404'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Clear finished'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await _settle(tester);
      expect(find.text('404'), findsNothing);
      expect(find.text('No requests yet'), findsOneWidget);
    });
  });

  group('설정 칸', () {
    _testApp('루트 폴더 칸에 포커스가 있어도 찾아보기로 고른 폴더가 바로 보인다', (tester, app) async {
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Root folder');
      // 칸을 한 번 누른 뒤 [찾아보기]를 쓰면, 폴더 선택 창이 닫힐 때 포커스가 이 칸으로 돌아온다.
      await tester.tap(field);
      await tester.pump();
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

      // FolderField가 폴더를 고른 뒤 하는 일과 같다.
      app.tftp.update(app.tftp.settings.copyWith(rootDir: app.root.path));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, app.root.path);
      expect(find.text('Folder does not exist'), findsNothing);
    });

    _testApp('직접 입력할 때는 앞뒤 공백을 떼어 저장해도 입력 중인 글자를 덮어쓰지 않는다', (tester, app) async {
      await tester.tap(find.text('TFTP').first);
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, 'Port (default 69)');
      await tester.enterText(field, ' 6969 ');
      await tester.pump();
      expect(app.tftp.settings.port, '6969');
      expect(tester.widget<TextField>(field).controller!.text, ' 6969 ');
    });
  });

  group('FTP', () {
    _testApp('계정 하나를 정하면 비밀번호는 해시로만 저장되고, 접속한 클라이언트가 세션 표에 나온다', (tester, app) async {
      final port = (await tester.runAsync(() => _freePort(tcp: true)))!;
      await tester.tap(find.text('FTP').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Username'), 'board');
      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'p@ss');
      await tester.pump();
      app.ftp.update(app.ftp.settings.copyWith(bindIp: '127.0.0.1', port: '$port', rootDir: app.root.path, passiveStart: '42100', passiveEnd: '42199'));
      await tester.pump();
      final stored = (await SharedPreferences.getInstance()).getString('ftp_account')!;
      expect(stored, isNot(contains('p@ss')));
      expect(jsonDecode(stored)['username'], 'board');
      expect(find.textContaining('A password is set'), findsOneWidget);

      await tester.runAsync(() async {
        await app.ftp.start();
      });
      await tester.pump();
      expect(app.ftp.running, isTrue, reason: '${app.ftp.startError}');

      final client = (await tester.runAsync(() async {
        final c = await FtpTestClient.connect(port);
        final r = await c.login('board', 'p@ss');
        expect(r.code, 230);
        await c.cmd('CWD /');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return c;
      }))!;
      await _settle(tester);
      expect(find.text('board'), findsWidgets);
      expect(find.textContaining('Open 1'), findsOneWidget);
      expect(find.textContaining('Logged in board'), findsOneWidget);

      await tester.tap(find.byTooltip('Disconnect'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await _settle(tester);
      expect(find.text('Closed'), findsOneWidget);
      await tester.runAsync(client.close);
    });

    _testApp('계정 없이 익명만 켜도 시작할 수 있고, 둘 다 없으면 시작을 거부한다', (tester, app) async {
      app.ftp.update(app.ftp.settings.copyWith(rootDir: app.root.path));
      expect(app.ftp.settingsValid, isFalse, reason: '로그인 방법이 없다');
      app.ftp.update(app.ftp.settings.copyWith(allowAnonymous: true));
      expect(app.ftp.settingsValid, isTrue);
    });
  });

  group('로그 패널', () {
    _testApp('위 경계를 끌면 로그 높이가 마우스 위치를 그대로 따라가고, 한계를 넘었다 돌아와도 어긋나지 않는다', (tester, app) async {
      final handle = find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeRow);
      double logHeight() => tester.getSize(find.byType(LogPanel)).height;
      final start = logHeight();
      final y0 = tester.getCenter(handle).dy;

      final drag = await tester.startGesture(Offset(tester.getCenter(handle).dx, y0));
      await drag.moveTo(Offset(tester.getCenter(handle).dx, y0 - 100));
      await tester.pump();
      expect(logHeight(), start + 100, reason: '위로 100 끌면 정확히 100 커진다');
      expect(tester.getCenter(handle).dy, closeTo(y0 - 100, 0.5), reason: '손잡이가 마우스 위치에 있다');

      // 화면 위쪽 한계를 한참 넘어 끌었다가 처음 위치 근처로 돌아온다.
      await drag.moveTo(Offset(tester.getCenter(handle).dx, -3000));
      await tester.pump();
      await drag.moveTo(Offset(tester.getCenter(handle).dx, y0 - 40));
      await tester.pump();
      expect(logHeight(), start + 40, reason: '한계에서 멈췄다 돌아와도 시작 위치 기준으로 정확하다');
      await drag.up();
    });

    _testApp('보관 줄 수는 기본 1000줄이고, 고르면 바로 줄어들고 서비스별로 저장된다', (tester, app) async {
      expect(find.byTooltip('Log lines to keep: 1000 lines'), findsOneWidget);
      await _startDhcp(tester);
      for (var i = 0; i < 5; i++) {
        app.transport.dora(mac(i));
      }
      await _settle(tester);
      expect(app.dhcp.logs.length, greaterThan(10));

      await tester.tap(find.byTooltip('Log lines to keep: 1000 lines'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100 lines').last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Log lines to keep: 100 lines'), findsOneWidget);
      expect(app.dhcp.logs.capacity, 100);
      expect(app.controller.prefs.getInt('dhcp_log_capacity'), 100);
      expect(app.tftp.logs.capacity, 1000, reason: '다른 서비스는 그대로');
    });

    _testApp('디버그 로그는 기본으로 숨기고, 검색으로 줄이고, 일시정지하면 개수만 알린다', (tester, app) async {
      await _startDhcp(tester);
      app.transport.receive(DhcpPacket(op: DhcpOp.reply, xid: 1, chaddr: Uint8List(16), options: {DhcpOpt.messageType: DhcpValue.u8(DhcpMessageType.offer)}));
      await _settle(tester);
      expect(find.textContaining('Ignored packet'), findsNothing);
      await tester.tap(find.byTooltip('Minimum level'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Debug').last);
      await tester.pumpAndSettle();
      await _settle(tester);
      expect(find.textContaining('Ignored packet'), findsOneWidget);

      app.transport.dora(mac(1));
      await _settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Search log'), 'ack');
      await _settle(tester);
      expect(find.textContaining('OFFER 192.168.50.100'), findsNothing);
      expect(find.textContaining('ACK 192.168.50.100'), findsOneWidget);

      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      app.transport.dora(mac(2));
      await _settle(tester);
      expect(find.textContaining('Paused · '), findsOneWidget);
      expect(find.textContaining('ACK 192.168.50.101'), findsNothing);
      await tester.tap(find.byTooltip('Resume'));
      await _settle(tester);
      expect(find.textContaining('ACK 192.168.50.101'), findsOneWidget);
    });
  });
}
