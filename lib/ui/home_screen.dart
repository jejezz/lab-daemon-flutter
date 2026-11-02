// 메인 화면: 앱 바(설정 | 정보) + 왼쪽 서비스 목록 + 본문(서비스별 뷰) + 아래 공용 로그 패널.
// 로그 패널과 본문 사이의 경계를 끌어서 높이를 바꿀 수 있다.
// 화면 전체 단축키: Ctrl+, 설정 · Ctrl+F 로그 검색 · Ctrl+R/F5 NIC 새로고침.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_identity.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_dialog.dart';
import '../state/controller.dart';
import '../window/focus_tint.dart';
import 'dhcp_view.dart';
import 'log_panel.dart';
import 'sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onAbout});

  final VoidCallback onAbout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchFocus = FocusNode();
  double _logHeight = 220;

  /// 본문이 최소한 이만큼은 남도록 로그 패널 높이를 제한한다.
  static const _minBody = 200.0;
  static const _minLog = 120.0;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  void _refresh() => ControllerScope.read(context).refreshNics();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => showSettingsDialog(context),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): _refresh,
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
      },
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: const FocusTint(),
          title: const Text(AppIdentity.displayName),
          actions: [
            IconButton(
              tooltip: l10n.settingsTooltip,
              icon: const Icon(Icons.settings_rounded),
              onPressed: () => showSettingsDialog(context),
            ),
            IconButton(
              tooltip: l10n.aboutTooltip,
              icon: const Icon(Icons.info_outline_rounded),
              onPressed: widget.onAbout,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxLog = (constraints.maxHeight - _minBody).clamp(_minLog, double.infinity);
            final logHeight = _logHeight.clamp(_minLog, maxLog);
            return Column(
              children: [
                const Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ServiceSidebar(),
                      VerticalDivider(width: 1),
                      Expanded(child: DhcpView()),
                    ],
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeRow,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (d) => setState(() => _logHeight = (logHeight - d.delta.dy).clamp(_minLog, maxLog)),
                    child: const SizedBox(height: 8, child: Divider(height: 8)),
                  ),
                ),
                SizedBox(height: logHeight, child: LogPanel(bus: controller.bus, searchFocus: _searchFocus)),
              ],
            );
          },
        ),
      ),
    );
  }
}
