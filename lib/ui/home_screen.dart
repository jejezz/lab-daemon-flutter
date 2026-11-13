// 메인 화면: 앱 바(설정 | 정보) + 왼쪽 서비스 목록 + 고른 서비스의 화면(설정·클라이언트·로그).
// 화면 전체 단축키: Ctrl+, 앱 설정 · Ctrl+1/2/3 서비스 고르기 · Ctrl+R/F5 NIC 새로고침.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_identity.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_dialog.dart';
import '../state/controller.dart';
import '../state/service_model.dart';
import '../theme/app_theme.dart';
import '../window/focus_tint.dart';
import 'actions.dart';
import 'service_page.dart';
import 'widgets/status_pill.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onAbout});

  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ControllerScope.of(context);
    final services = controller.services;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () => showSettingsDialog(context),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): controller.refreshNics,
        const SingleActivator(LogicalKeyboardKey.f5): controller.refreshNics,
        for (var i = 0; i < services.length; i++)
          SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => controller.select(services[i].id),
      },
      child: Scaffold(
        appBar: AppBar(
          flexibleSpace: const FocusTint(),
          title: Row(children: [
            const Text(AppIdentity.displayName),
            const SizedBox(width: AppSpacing.lg),
            Expanded(child: _ActiveEndpoints(controller: controller)),
          ]),
          actions: [
            IconButton(tooltip: l10n.settingsTooltip, icon: const Icon(Icons.settings_rounded), onPressed: () => showSettingsDialog(context)),
            IconButton(tooltip: l10n.aboutTooltip, icon: const Icon(Icons.info_outline_rounded), onPressed: onAbout),
            const SizedBox(width: 8),
          ],
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 200,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                    child: Text(l10n.servicesTitle, style: Theme.of(context).textTheme.labelMedium),
                  ),
                  for (final s in services) _ServiceTile(model: s, selected: s.id == controller.selectedId, onTap: () => controller.select(s.id)),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: ServicePage(key: ValueKey(controller.selectedId), model: controller.selected)),
          ],
        ),
      ),
    );
  }
}

/// 켜져 있는 서비스마다 클라이언트가 접속할 주소를 앱 바에 보인다 (예: `TFTP 192.168.50.1`, `FTP 192.168.50.1:2121`).
/// 모든 NIC에 열었으면 첫 주소와 `+N`만 보이고 전체는 툴팁에 있다.
class _ActiveEndpoints extends StatelessWidget {
  const _ActiveEndpoints({required this.controller});

  final LabDaemonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ...controller.services]),
      builder: (context, _) {
        final items = <Widget>[];
        for (final s in controller.services.where((s) => s.running)) {
          final all = s.endpoints(controller.nics);
          if (all.isEmpty) continue;
          final text = all.length > 1 ? '${all.first} +${all.length - 1}' : all.first;
          items.add(Tooltip(
            message: all.join('\n'),
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${serviceName(l10n, s.id)}  ', style: theme.textTheme.labelLarge),
                  TextSpan(text: text, style: AppFonts.mono.copyWith(fontSize: 13)),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ));
        }
        return Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: items)));
      },
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.model, required this.selected, required this.onTap});

  final ServiceModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 이 타일만 그 서비스의 변화를 따라 다시 그린다.
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) => InkWell(
        onTap: onTap,
        child: Container(
          // 고른 서비스는 배경을 채우지 않고 왼쪽 굵은 선으로 표시한다 (고대비에서도 글자가 읽힌다).
          decoration: BoxDecoration(border: Border(left: BorderSide(width: 3, color: selected ? theme.colorScheme.primary : Colors.transparent))),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(serviceName(l10n, model.id), style: theme.textTheme.titleSmall?.copyWith(color: selected ? theme.colorScheme.primary : null)),
                const SizedBox(height: AppSpacing.xs),
                StatusPill(label: serviceStatusLabel(l10n, model), tone: serviceStatusTone(model)),
              ]),
            ),
            IconButton(
              tooltip: model.running ? l10n.serviceStopTooltip : l10n.serviceStartTooltip,
              icon: Icon(model.running ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
              onPressed: model.busy ? null : () => toggleServiceWithFeedback(context, model),
            ),
          ]),
        ),
      ),
    );
  }
}
