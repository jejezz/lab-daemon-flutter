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
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/netcheck.dart';
import 'package:lab_daemon/core/netutil.dart';
import 'package:lab_daemon/core/tftp/server.dart';
import 'package:lab_daemon/l10n/app_localizations.dart';
import 'package:lab_daemon/settings/app_settings.dart';
import 'package:lab_daemon/state/controller.dart';
import 'package:lab_daemon/state/service_models.dart';
import 'package:lab_daemon/theme/app_theme.dart';
import 'package:lab_daemon/ui/home_screen.dart';
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
    _testApp('사이드바에 서비스 세 개가 있고, 서비스마다 자기 설정 패널을 보인다', (tester, app) async {
      for (final name in ['DHCP', 'TFTP', 'FTP']) {
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
    });

    _testApp('앱 설정 창에는 외형만 있다 (서비스 설정은 각 서비스 화면에)', (tester, app) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Appearance'), findsWidgets);
      expect(find.text('Server interface'), findsNothing);
      expect(find.text('Range start'), findsNWidgets(1), reason: '뒤에 있는 DHCP 패널의 것 하나뿐');
    });

    _testApp('설정 패널을 숨기고 다시 보일 수 있다', (tester, app) async {
      await tester.tap(find.byTooltip('Show or hide settings'));
      await tester.pumpAndSettle();
      expect(find.text('Range start'), findsNothing);
      await tester.tap(find.byTooltip('Show or hide settings'));
      await tester.pumpAndSettle();
      expect(find.text('Range start'), findsOneWidget);
    });
  });

  _testApp('최소 창 크기(960×600)에서도 세 서비스 화면이 넘치지 않는다', (tester, app) async {
    await _startDhcp(tester);
    app.transport.dora(mac(1), hostname: 'a-very-long-hostname-for-the-table');
    await _settle(tester);
    for (final name in ['TFTP', 'FTP', 'DHCP']) {
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
      final field = find.widgetWithText(TextField, 'Port');
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
