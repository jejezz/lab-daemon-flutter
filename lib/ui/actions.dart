// 여러 화면이 같이 쓰는 동작: 시작하고 결과를 알리기, Lease 해제 확인.

import 'package:flutter/material.dart';

import '../core/ipv4.dart';
import '../core/dhcp/detector.dart';
import '../l10n/app_localizations.dart';
import '../settings/settings_dialog.dart';
import '../state/controller.dart';
import '../theme/app_theme.dart';
import 'widgets/error_snackbar.dart';

/// DHCP 서버를 켠다. 설정이 틀렸으면 설정 열기 액션을 붙여 알리고, 소켓 오류는 원문을 복사할 수 있게 알린다.
Future<void> startDhcpWithFeedback(BuildContext context, {bool skipProbe = false}) async {
  final controller = ControllerScope.read(context);
  final l10n = AppLocalizations.of(context);
  final ok = await controller.startDhcp(skipProbe: skipProbe);
  if (ok || !context.mounted) return;
  if (controller.startError == 'otherServer') {
    final proceed = await _confirmOtherServers(context, controller.detectedServers);
    if (proceed && context.mounted) await startDhcpWithFeedback(context, skipProbe: true);
  } else if (controller.startError == 'invalidSettings') {
    showErrorSnackBar(
      context,
      l10n.startInvalidSettings,
      actionLabel: l10n.openSettings,
      onAction: () => showSettingsDialog(context, initial: SettingsSection.dhcp),
    );
  } else {
    final error = controller.startError ?? '';
    showErrorSnackBar(context, l10n.startFailed(error), copyText: error);
  }
}

Future<void> toggleDhcpWithFeedback(BuildContext context) async {
  final controller = ControllerScope.read(context);
  if (controller.dhcpRunning) {
    await controller.stopDhcp();
  } else {
    await startDhcpWithFeedback(context);
  }
}

void releaseLeaseWithFeedback(BuildContext context, Ipv4 ip) {
  final controller = ControllerScope.read(context);
  if (controller.releaseLease(ip)) {
    showInfoSnackBar(context, AppLocalizations.of(context).leaseReleasedSnack('$ip'));
  }
}

/// 되돌릴 수 없는 작업이라 확인을 받는다. 기본 포커스는 취소에 둔다 (ui-ux.md §6).
Future<void> confirmReleaseAll(BuildContext context) async {
  final controller = ControllerScope.read(context);
  final count = controller.leases.length;
  if (count == 0) return;
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.leaseReleaseAllConfirmTitle),
      content: Text(l10n.leaseReleaseAllConfirmBody(count)),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.leaseReleaseAll),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final released = controller.releaseAllLeases();
  showInfoSnackBar(context, l10n.leaseReleasedAllSnack(released));
}

/// 같은 망에서 DHCP 서버 둘이 응답하면 장비가 엉뚱한 주소를 받을 수 있어서, 켜기 전에 한 번 더 묻는다.
/// 기본 포커스는 취소에 둔다 (ui-ux.md §6).
Future<bool> _confirmOtherServers(BuildContext context, List<DetectedServer> servers) async {
  final l10n = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
      title: Text(l10n.probeConflictTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.probeConflictBody),
            const SizedBox(height: 12),
            for (final server in servers)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l10n.probeServerLine('${server.serverId}', '${server.offeredIp}'), style: AppFonts.mono),
              ),
            const SizedBox(height: 12),
            Text(l10n.probeConflictAdvice, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.probeStartAnyway),
        ),
      ],
    ),
  );
  return result == true;
}
