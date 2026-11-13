import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/main.dart';
import 'package:lab_daemon/settings/app_settings.dart';
import 'package:lab_daemon/state/controller.dart';
import 'package:lab_daemon/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('설정에서 색 구성을 바꾸면 앱 전체의 주색이 바뀐다', (tester) async {
    // window_manager 플러그인 호출은 받아 두기만 한다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('window_manager'), null));
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final prefs = await SharedPreferences.getInstance();
    final settings = await AppSettings.load();
    final controller = LabDaemonController.create(prefs);
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(App(settings: settings, controller: controller));
    await tester.pump();
    Color primary() => Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme.primary;
    expect(primary(), AccentPalette.saturn.darkPrimary);

    await settings.setAccentPalette(AccentPalette.rose);
    await tester.pumpAndSettle();
    expect(primary(), AccentPalette.rose.darkPrimary, reason: '색 구성을 고르면 테마가 따라간다');

    double scaled() => MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first)).scale(10);
    expect(scaled(), 10);
    await settings.setTextScale(1.3);
    await tester.pumpAndSettle();
    expect(scaled(), closeTo(13, 0.001), reason: '글자 크기 배율이 앱 전체에 적용된다');

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(controller.stopAll);
  });
}
