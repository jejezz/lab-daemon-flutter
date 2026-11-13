// 설정 창 테스트 (conventions/settings.md "테스트"): 도킹 크기에서 넘치지 않는지,
// 각 선택지가 값을 바꾸고 저장하는지.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/l10n/app_localizations.dart';
import 'package:lab_daemon/settings/app_settings.dart';
import 'package:lab_daemon/settings/settings_dialog.dart';
import 'package:lab_daemon/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppSettings> _pump(WidgetTester tester, {Size size = const Size(1200, 720)}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = await AppSettings.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppSettingsScope(
    settings: settings,
    child: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showSettingsDialog(context), child: const Text('open')),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets('외형 구역에 모드 · 색 구성 · 언어가 이 순서로 있다', (tester) async {
    await _pump(tester);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Mode'), lessThan(y('Color scheme')));
    expect(y('Color scheme'), lessThan(y('Language')));
  });

  testWidgets('모드·색 구성·언어를 바꾸면 바로 적용되고 저장된다', (tester) async {
    final settings = await _pump(tester);
    final prefs = await SharedPreferences.getInstance();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(settings.themeMode, ThemeMode.dark);
    expect(prefs.getString('theme_mode'), 'dark');

    await tester.tap(find.text('Teal'));
    await tester.pumpAndSettle();
    expect(settings.accentPalette, AccentPalette.teal);
    expect(prefs.getString('accent_palette'), 'teal');

    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    expect(settings.locale, const Locale('ko'));
    expect(prefs.getString('app_locale'), 'ko');
  });

  testWidgets('글자 크기 슬라이더가 언어 아래에 있고, 움직이면 퍼센트가 바뀌고 저장된다', (tester) async {
    final settings = await _pump(tester);
    expect(find.text('Text size'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Text size')).dy, greaterThan(tester.getTopLeft(find.text('Language')).dy));
    expect(find.text('100%'), findsOneWidget);

    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    await tester.drag(slider, const Offset(400, 0)); // 가운데(100%)의 손잡이를 오른쪽 끝으로
    await tester.pumpAndSettle();
    expect(settings.textScale, 1.5);
    expect(find.text('${(settings.textScale * 100).round()}%'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset to default'));
    await tester.pumpAndSettle();
    expect(settings.textScale, 1.0);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('도킹 크기(480×480)에서도 넘치지 않고 구역을 위쪽 칩으로 보인다', (tester) async {
    await _pump(tester, size: const Size(480, 480));
    expect(tester.takeException(), isNull);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text('Appearance'), findsOneWidget);
  });
}
