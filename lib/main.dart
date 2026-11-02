// From jejezz/application-release-templates common/ @ conventions-v1.
//
// 새 앱의 시작점. 규약이 요구하는 연결을 한곳에 모았다:
//   창 크기(window_manager) · 추가 라이선스 · 설정 로드 · 라이트/다크 ·
//   언어 해석 · macOS 앱 메뉴 About · 앱 바 [테마 | 언어 | 정보] · 빈 상태.
// 기존 앱에는 통째로 덮어쓰지 말고 필요한 부분만 옮긴다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'about/about_dialog.dart';
import 'about/app_menu_bar.dart';
import 'about/extra_licenses.dart';
import 'app_identity.dart';
import 'l10n/app_localizations.dart';
import 'settings/app_settings.dart';
import 'settings/settings_menus.dart';
import 'theme/app_theme.dart';
import 'update/update_scope.dart';
import 'update/update_service.dart';
import 'window/focus_tint.dart';
import 'window/window_placement.dart';

final bool _isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerExtraLicenses();

  // 창을 실제로 보일 준비(위치·크기 계산)가 끝나면 호출할 함수. 첫 프레임이 그려지기 전에 부르면
  // 테마가 입혀지지 않은 빈 화면이 잠깐 보였다가 바뀌는 깜빡임이 생기므로, 첫 프레임 뒤로 미룬다
  // (window-placement.md §5 — windows/runner/flutter_window.cpp의 자동 show()도 지워야 한다).
  Future<void> Function()? showWindow;
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    showWindow = await _prepareWindow();
  }

  final settings = await AppSettings.load();
  // 데스크톱이 아니거나 UPDATE_SERVER 가 비어 있으면 null — 업데이트 확인 없음.
  final updates = await UpdateService.create();
  // UpdateScope 는 MaterialApp 위에 둔다 — 정보 창이 이것을 읽어 "업데이트 확인" 단추를 붙인다.
  runApp(UpdateScope(service: updates, child: App(settings: settings, updates: updates)));

  if (showWindow != null) {
    final show = showWindow;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(show()));
  }
}

/// 다음 프레임이 그려질 때까지 기다린다. 지금 막 레이아웃이 바뀌어 다시 그려야 할 프레임이
/// 예약돼 있지 않을 수도 있어, 프레임을 하나 더 예약해 둔다.
Future<void> _nextFrame() {
  final completer = Completer<void>();
  WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
  WidgetsBinding.instance.scheduleFrame();
  return completer.future;
}

/// 창 크기·위치를 계산해 둔다. 창을 실제로 보이려면 돌려준 함수를 불러야 한다(첫 프레임이 그려진
/// 뒤에 부르는 것은 호출하는 쪽의 몫). ui-ux.md §5: 최소 크기는 960×600 이하(1366×768 노트북).
/// 위치는 center: true 대신 WindowPlacement — window-placement.md.
Future<Future<void> Function()> _prepareWindow() async {
  const size = Size(1200, 720);
  WindowPlacement? placement;
  if (WindowPlacement.enabled) {
    placement = WindowPlacement(await SharedPreferences.getInstance(), defaultSize: size);
  }
  final options = WindowOptions(
    size: size,
    minimumSize: const Size(960, 600),
    center: placement == null,
    title: AppIdentity.displayName,
  );
  final placed = Completer<void>();
  windowManager.waitUntilReadyToShow(options, () async {
    await placement?.placeInitially();
    placed.complete();
  });
  return () async {
    await placed.future;
    // 배치가 끝난 직후에도 Flutter가 그 크기로 다시 그릴 프레임이 아직 안 나왔을 수 있어, 한
    // 프레임 더 기다렸다가 보여준다 (창 안 내용이 잠깐 엉뚱한 크기로 보였다가 바뀌는 것을 막는다).
    await _nextFrame();
    await windowManager.show();
    await windowManager.focus();
    placement?.attach();
  };
}

class App extends StatefulWidget {
  const App({super.key, required this.settings, this.updates});

  final AppSettings settings;
  final UpdateService? updates;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_syncWindowBrightness);
    _syncWindowBrightness();
    widget.updates?.startAutomaticCheck(_navigatorKey);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_syncWindowBrightness);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 앱에서 다크를 골라도 OS가 라이트면 제목 표시줄은 밝게 남는다 (theming.md §4).
  @override
  void didChangePlatformBrightness() => _syncWindowBrightness();

  void _syncWindowBrightness() {
    if (!_isDesktop || Platform.isLinux) return;
    final brightness = switch (widget.settings.themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    windowManager.setBrightness(brightness);
  }

  void _showAbout() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context);
    showAppAboutDialog(
      context,
      tagline: l10n.aboutTagline,
      description: l10n.aboutDescription,
      onCheckForUpdates: widget.updates == null ? null : () => widget.updates!.checkManually(context),
    );
  }

  void _checkForUpdates() {
    final context = _navigatorKey.currentContext;
    if (context != null) widget.updates?.checkManually(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppSettingsScope(
      settings: widget.settings,
      child: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: AppIdentity.displayName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dense: _isDesktop),
          darkTheme: AppTheme.dark(dense: _isDesktop),
          themeMode: widget.settings.themeMode,
          locale: widget.settings.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          localeResolutionCallback: AppSettings.resolveLocale,
          builder: (context, child) => AppMenuBar(
            onAbout: _showAbout,
            onCheckForUpdates: widget.updates == null ? null : _checkForUpdates,
            child: child!,
          ),
          home: HomeScreen(onAbout: _showAbout),
        ),
      ),
    );
  }
}

/// 기능이 들어오기 전의 자리 표시 화면 — 빈 상태 패턴 (ui-ux.md §6).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onAbout});

  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const FocusTint(),
        title: const Text(AppIdentity.displayName),
        actions: [
          const ThemeMenuButton(),
          const LanguageMenuButton(),
          IconButton(
            tooltip: l10n.aboutTooltip,
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: onAbout,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AppIdentity.iconAsset, width: 48, height: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.homeEmptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            // 기능이 생기면 주 행동을 연결한다. 그 전까지는 비활성.
            FilledButton(onPressed: null, child: Text(l10n.homeEmptyAction)),
          ],
        ),
      ),
    );
  }
}
