// 왼쪽 서비스 목록: 서비스마다 이름, 상태 표시, 시작/중지 버튼. 지금은 DHCP 하나이고,
// TFTP·FTP가 생기면 같은 타일을 더한다.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/controller.dart';
import '../theme/app_theme.dart';
import 'actions.dart';
import 'dhcp_view.dart';
import 'widgets/status_pill.dart';

class ServiceSidebar extends StatelessWidget {
  const ServiceSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final running = c.dhcpRunning;

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text(l10n.servicesTitle, style: theme.textTheme.labelMedium),
          ),
          // 선택한 서비스는 배경을 채우지 않고 왼쪽 굵은 선으로 표시한다 (고대비에서도 글자가 읽힌다).
          Container(
            decoration: BoxDecoration(border: Border(left: BorderSide(width: 3, color: theme.colorScheme.primary))),
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.serviceDhcp, style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      StatusPill(label: dhcpStatusLabel(l10n, c), tone: dhcpStatusTone(c)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: running ? l10n.serviceStopTooltip : l10n.serviceStartTooltip,
                  icon: Icon(running ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
                  onPressed: c.dhcpBusy ? null : () => toggleDhcpWithFeedback(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
