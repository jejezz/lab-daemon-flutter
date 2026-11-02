// 메인 화면 흐름 테스트: 시작 → (다른 서버 확인) → DORA → Lease 표 → 해제 → 로그, 설정 창 DHCP 구역.
// 소켓 대신 가짜 전송 계층과 가짜 감지기를 쓰므로 실제 네트워크를 건드리지 않는다.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/dhcp/detector.dart';
import 'package:lab_daemon/core/dhcp/packet.dart';
import 'package:lab_daemon/core/dhcp/server.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/netutil.dart';
import 'package:lab_daemon/core/service.dart';
import 'package:lab_daemon/l10n/app_localizations.dart';
import 'package:lab_daemon/settings/app_settings.dart';
import 'package:lab_daemon/state/controller.dart';
import 'package:lab_daemon/theme/app_theme.dart';
import 'package:lab_daemon/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_transport.dart';

const _validPrefs = <String, Object>{
  'dhcp_server_ip': '192.168.50.1',
  'dhcp_range_start': '192.168.50.100',
  'dhcp_range_end': '192.168.50.110',
  'dhcp_mask': '255.255.255.0',
  'dhcp_gateway': '192.168.50.1',
  'dhcp_lease_time': '1h',
};

MacAddress mac(int n) => MacAddress([0xaa, 0xbb, 0xcc, 0, 0, n]);

class _TestApp {
  _TestApp(this.controller, this.transport);

  final LabDaemonController controller;
  final FakeTransport transport;

  /// 다른 DHCP 서버가 있다고 가정할 때 채운다. 비어 있으면 감지기는 "없음"을 돌려준다.
  List<DetectedServer> otherServers = [];
  int probes = 0;

  /// 타이머가 남지 않도록 화면을 내리고 서버를 멈춘다. 테스트 본문 끝에서 불러야 한다
  /// (addTearDown은 프레임워크의 남은 타이머 검사보다 늦게 돈다).
  Future<void> shutdown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => controller.dhcp.stop());
    controller.dispose();
  }
}

void _testApp(
  String name,
  Future<void> Function(WidgetTester tester, _TestApp app) body, {
  Map<String, Object> prefs = _validPrefs,
}) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    final settings = await AppSettings.load();
    final transport = FakeTransport();
    final bus = LogBus();
    final server = DhcpServer(bus, transportFactory: (a, p) async => transport);
    late final _TestApp app;
    final controller = LabDaemonController(
      prefs: sp,
      bus: bus,
      dhcp: server,
      nicLister: () async => [NicInfo('Ethernet 2', Ipv4.parse('192.168.50.1'))],
      prober: (ip) async {
        app.probes++;
        return DhcpProbeResult(app.otherServers);
      },
    );
    app = _TestApp(controller, transport);

    tester.view.physicalSize = const Size(1200, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ControllerScope(
      controller: controller,
      child: AppSettingsScope(
        settings: settings,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
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

Future<void> _start(WidgetTester tester) async {
  await tester.tap(find.text('Start Service'));
  await tester.pumpAndSettle();
}

void main() {
  _testApp('서비스가 꺼져 있으면 빈 상태와 시작 단추를 보여 준다', (tester, app) async {
    expect(find.text('No services are running'), findsOneWidget);
    expect(find.text('Start Service'), findsOneWidget);
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.text('No leases yet'), findsNothing);
  });

  _testApp('설정이 비어 있으면 시작을 거부하고 설정 열기 액션을 준다', (tester, app) async {
    await _start(tester);
    expect(find.text('The DHCP settings are not valid. Check them in Settings.'), findsOneWidget);
    expect(app.probes, 0, reason: '설정이 틀리면 확인도 하지 않는다');

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Server interface'), findsOneWidget, reason: 'DHCP 구역이 바로 열린다');
    expect(find.text('Required'), findsWidgets, reason: '거부된 뒤에는 빈 칸의 오류를 보여 준다');
  }, prefs: const {});

  _testApp('시작하면 상태 바와 시작 로그가 나온다', (tester, app) async {
    await _start(tester);
    expect(app.controller.dhcpRunning, isTrue);
    expect(find.text('Running'), findsWidgets);
    expect(find.textContaining('192.168.50.100 ~ 192.168.50.110 /24'), findsOneWidget);
    expect(find.textContaining('DHCP server started on 192.168.50.1'), findsOneWidget);
    expect(find.text('No leases yet'), findsOneWidget);
  });

  _testApp('장비가 주소를 받으면 Lease 표와 로그에 나타난다', (tester, app) async {
    await _start(tester);
    app.transport.dora(mac(1), hostname: 'rk3568');
    await tester.pump();

    expect(find.text('192.168.50.100'), findsWidgets);
    expect(find.text('aa:bb:cc:00:00:01'), findsOneWidget);
    expect(find.text('rk3568'), findsOneWidget);
    expect(find.text('Bound'), findsOneWidget);
    expect(find.textContaining('OFFER 192.168.50.100 to aa:bb:cc:00:00:01'), findsOneWidget);
    expect(find.textContaining('ACK 192.168.50.100 to aa:bb:cc:00:00:01 (lease 1h)'), findsOneWidget);
    expect(find.textContaining('In use 1/11'), findsOneWidget);
  });

  _testApp('줄 끝 버튼으로 Lease를 해제한다', (tester, app) async {
    await _start(tester);
    app.transport.dora(mac(1));
    await tester.pump();

    await tester.tap(find.byTooltip('Release'));
    await tester.pumpAndSettle();
    expect(app.controller.leases, isEmpty);
    expect(find.text('aa:bb:cc:00:00:01'), findsNothing);
    expect(find.text('Released 192.168.50.100'), findsOneWidget);
    expect(find.textContaining('Lease released 192.168.50.100'), findsOneWidget);
  });

  _testApp('전체 해제는 확인을 받는다 (기본은 취소)', (tester, app) async {
    await _start(tester);
    app.transport.dora(mac(1));
    app.transport.dora(mac(2));
    await tester.pump();

    await tester.tap(find.text('Release All'));
    await tester.pumpAndSettle();
    expect(find.text('Release all leases?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(app.controller.leases, hasLength(2));

    await tester.tap(find.text('Release All'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Release All'));
    await tester.pumpAndSettle();
    expect(app.controller.leases, isEmpty);
    expect(find.text('Released 2 lease(s)'), findsOneWidget);
  });

  _testApp('중지하면 빈 상태로 돌아온다', (tester, app) async {
    await _start(tester);
    app.transport.dora(mac(1));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Stop service'));
    await tester.pumpAndSettle();
    // 소켓 닫기는 실제 비동기 작업이라 FakeAsync 밖에서 끝나기를 기다린다.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(app.controller.dhcpState, ServiceState.stopped);
    expect(find.text('No services are running'), findsOneWidget);
    expect(find.textContaining('DHCP server stopped'), findsOneWidget);
  });

  group('다른 DHCP 서버 감지', () {
    _testApp('시작 전에 확인하고, 없으면 그대로 시작한다', (tester, app) async {
      await _start(tester);
      expect(app.probes, 1);
      expect(app.controller.dhcpRunning, isTrue);
      expect(find.textContaining('Checking for other DHCP servers (192.168.50.1)'), findsOneWidget);
      expect(find.textContaining('No other DHCP server answered'), findsOneWidget);
    });

    _testApp('다른 서버가 응답하면 경고를 띄우고 시작하지 않는다', (tester, app) async {
      app.otherServers = [DetectedServer(serverId: Ipv4.parse('192.168.50.254'), offeredIp: Ipv4.parse('192.168.50.77'))];
      await _start(tester);

      expect(app.controller.dhcpRunning, isFalse);
      expect(find.text('Another DHCP server is on this network'), findsOneWidget);
      expect(find.text('192.168.50.254 (offered 192.168.50.77)'), findsOneWidget);
      expect(find.textContaining('Another DHCP server found: 192.168.50.254 (offered 192.168.50.77)'), findsOneWidget);
    });

    _testApp('경고에서 취소하면 시작하지 않는다 (기본 포커스는 취소)', (tester, app) async {
      app.otherServers = [DetectedServer(serverId: Ipv4.parse('192.168.50.254'), offeredIp: Ipv4.parse('192.168.50.77'))];
      await _start(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.controller.dhcpRunning, isFalse);
      expect(app.probes, 1);
    });

    _testApp('그래도 시작을 고르면 다시 확인하지 않고 시작한다', (tester, app) async {
      app.otherServers = [DetectedServer(serverId: Ipv4.parse('192.168.50.254'), offeredIp: Ipv4.parse('192.168.50.77'))];
      await _start(tester);
      await tester.tap(find.text('Start Anyway'));
      await tester.pumpAndSettle();
      expect(app.controller.dhcpRunning, isTrue);
      expect(app.probes, 1, reason: '경고를 보고 켜는 것이므로 두 번 확인하지 않는다');
    });

    _testApp('설정에서 끄면 확인하지 않는다', (tester, app) async {
      app.controller.updateDhcp(app.controller.dhcpSettings.copyWith(detectOtherServers: false));
      app.otherServers = [DetectedServer(serverId: Ipv4.parse('192.168.50.254'), offeredIp: Ipv4.parse('192.168.50.77'))];
      await _start(tester);
      expect(app.probes, 0);
      expect(app.controller.dhcpRunning, isTrue);
    });

    _testApp('확인을 끝내지 못해도 시작은 막지 않고 경고 로그만 남긴다', (tester, app) async {
      // 감지기가 소켓을 못 열어 "알 수 없음"을 돌려주는 경우.
      final controller = LabDaemonController(
        prefs: await SharedPreferences.getInstance(),
        dhcp: DhcpServer(LogBus(), transportFactory: (a, p) async => FakeTransport()),
        nicLister: () async => const [],
        prober: (ip) async => const DhcpProbeResult([], error: 'port 68 busy'),
      );
      expect(await tester.runAsync(controller.startDhcp), isTrue);
      expect(controller.bus.history.map((e) => e.key), contains('logDhcpProbeFailed'));
      await tester.runAsync(() => controller.dhcp.stop());
      controller.dispose();
    });
  });

  group('로그 패널', () {
    _testApp('디버그 로그는 기본으로 숨기고, 수준을 낮추면 보여 준다', (tester, app) async {
      await _start(tester);
      // 응답 패킷(op=2)은 엔진이 무시하며 DEBUG 로그만 남긴다.
      app.transport.receive(DhcpPacket(
        op: DhcpOp.reply,
        xid: 1,
        chaddr: Uint8List(16),
        options: {DhcpOpt.messageType: DhcpValue.u8(DhcpMessageType.offer)},
      ));
      await tester.pump();
      expect(find.textContaining('Ignored packet'), findsNothing);

      await tester.tap(find.text('Debug'));
      await tester.pump();
      expect(find.textContaining('Ignored packet'), findsOneWidget);
    });

    _testApp('검색어로 줄이고 지울 수 있다', (tester, app) async {
      await _start(tester);
      app.transport.dora(mac(1));
      await tester.pump();
      expect(find.textContaining('OFFER 192.168.50.100'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ack');
      await tester.pump();
      expect(find.textContaining('OFFER 192.168.50.100'), findsNothing);
      expect(find.textContaining('ACK 192.168.50.100'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(find.text('Nothing to show'), findsOneWidget);
    });

    _testApp('일시정지하면 새 로그를 바로 보여 주지 않고 개수를 알린다', (tester, app) async {
      await _start(tester);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      app.transport.dora(mac(1));
      await tester.pump();
      expect(find.textContaining('OFFER 192.168.50.100'), findsNothing);
      expect(find.textContaining('Paused · '), findsOneWidget);

      await tester.tap(find.byTooltip('Resume'));
      await tester.pump();
      expect(find.textContaining('OFFER 192.168.50.100'), findsOneWidget);
    });
  });

  group('설정 창 DHCP 구역', () {
    Future<void> openDhcpSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DHCP').last);
      await tester.pumpAndSettle();
    }

    _testApp('값을 바꾸면 바로 저장하고, 틀린 값은 오류를 보여 준다', (tester, app) async {
      await openDhcpSettings(tester);
      final lease = find.widgetWithText(TextField, 'Lease time');
      await tester.enterText(lease, '30m');
      await tester.pump();
      expect(app.controller.dhcpSettings.leaseTime, '30m');
      expect((await SharedPreferences.getInstance()).getString('dhcp_lease_time'), '30m');

      await tester.enterText(lease, 'soon');
      await tester.pump();
      expect(find.text('Use 30s, 10m, 12h, 1d or infinite'), findsOneWidget);
      expect(app.controller.dhcpErrors, isNotEmpty);
    });

    _testApp('범위 끝이 시작보다 앞서면 오류', (tester, app) async {
      await openDhcpSettings(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Range end'), '192.168.50.50');
      await tester.pump();
      expect(find.text('Before the range start'), findsOneWidget);
    });

    _testApp('다른 서버 확인 스위치를 끄면 저장된다', (tester, app) async {
      await openDhcpSettings(tester);
      final toggle = find.widgetWithText(SwitchListTile, 'Check for other DHCP servers before starting');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();
      expect(app.controller.dhcpSettings.detectOtherServers, isFalse);
      expect((await SharedPreferences.getInstance()).getBool('dhcp_detect_other_servers'), isFalse);
    });

    _testApp('NIC를 고르면 같은 /24의 범위와 게이트웨이를 채운다', (tester, app) async {
      await openDhcpSettings(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ethernet 2').last);
      await tester.pumpAndSettle();

      expect(app.controller.dhcpSettings.serverIp, '192.168.50.1');
      expect(app.controller.dhcpSettings.rangeStart, '192.168.50.100');
      expect(app.controller.dhcpSettings.rangeEnd, '192.168.50.200');
      expect(app.controller.dhcpSettings.gateway, '192.168.50.1');
      expect(app.controller.dhcpErrors, isEmpty);
    }, prefs: const {});

    _testApp('실행 중에 Lease Time을 바꾸면 다음 Lease부터 적용된다', (tester, app) async {
      await _start(tester);
      await openDhcpSettings(tester);
      expect(find.textContaining('only the lease time applies immediately'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Lease time'), '5m');
      await tester.pump();
      app.transport.dora(mac(1));
      final lease = app.controller.dhcp.pool!.leaseOfMac(mac(1))!;
      expect(lease.expiresAt!.difference(lease.grantedAt), const Duration(minutes: 5));
    });
  });
}
