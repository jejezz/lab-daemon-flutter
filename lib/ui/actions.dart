// 여러 화면이 같이 쓰는 동작: 서비스 시작(설정 검증 → 시작 전 점검 → 확인 → 시작)과 결과 알림, Lease 해제.

import 'package:flutter/material.dart';

import '../core/dhcp/server.dart';
import '../core/ipv4.dart';
import '../core/netcheck.dart';
import '../core/service.dart';
import '../l10n/app_localizations.dart';
import '../state/settings_common.dart';
import '../state/service_model.dart';
import '../state/service_models.dart';
import 'firewall_help.dart';
import 'widgets/error_snackbar.dart';
import 'widgets/fields.dart';
import 'widgets/status_pill.dart';

String serviceName(AppLocalizations l10n, String id) => switch (id) {
      'dhcp' => l10n.serviceDhcp,
      'tftp' => l10n.serviceTftp,
      'ftp' => l10n.serviceFtp,
      'http' => l10n.serviceHttp,
      _ => id,
    };

String serviceStatusLabel(AppLocalizations l10n, ServiceModel m) => m.checking
    ? l10n.stateChecking
    : switch (m.state) {
        ServiceState.stopped => l10n.stateStopped,
        ServiceState.starting => l10n.stateStarting,
        ServiceState.running => l10n.stateRunning,
        ServiceState.stopping => l10n.stateStopping,
        ServiceState.error => l10n.stateError,
      };

PillTone serviceStatusTone(ServiceModel m) => m.checking
    ? PillTone.warning
    : switch (m.state) {
        ServiceState.running => PillTone.success,
        ServiceState.starting || ServiceState.stopping => PillTone.warning,
        ServiceState.error => PillTone.danger,
        ServiceState.stopped => PillTone.neutral,
      };

String issueText(AppLocalizations l10n, PreStartIssue issue) {
  final a = issue.args;
  String list(String key) => (a[key] as List?)?.join(', ') ?? '';
  return switch (issue.kind) {
    IssueKind.portInUse => l10n.checkPortInUse('${a['protocol']}', a['port'] as int? ?? 0, '${a['process'] ?? '?'}', a['pid'] as int? ?? 0),
    IssueKind.firewallBlocked => l10n.checkFirewall(list('profiles'), list('ports')),
    IssueKind.otherDhcpServer => l10n.checkOtherDhcp([
        for (var i = 0; i < (a['servers'] as List).length; i++) l10n.probeServerLine('${(a['servers'] as List)[i]}', '${(a['offers'] as List?)?[i] ?? '?'}'),
      ].join(', ')),
    IssueKind.portsReserved => l10n.checkPortsReserved('${a['range']}', list('reserved'), a['free'] as int? ?? 0),
  };
}

enum _Choice { cancel, proceed, addRule }

/// 서비스를 켠다. 설정이 틀렸거나, 시작 전 점검에서 문제가 나오거나, 소켓을 못 열면 알린다.
Future<void> startServiceWithFeedback(BuildContext context, ServiceModel model, {bool skipWarnings = false}) async {
  final l10n = AppLocalizations.of(context);
  final result = await model.start(skipWarnings: skipWarnings);
  if (!context.mounted) return;
  switch (result) {
    case StartResult.started:
      return;
    case StartResult.invalid:
      showErrorSnackBar(context, l10n.startInvalidSettingsFor(serviceName(l10n, model.id)));
    case StartResult.blocked:
    case StartResult.needsConfirmation:
      final choice = await _showIssues(context, model);
      if (!context.mounted) return;
      if (choice == _Choice.proceed) {
        await startServiceWithFeedback(context, model, skipWarnings: true);
      } else if (choice == _Choice.addRule) {
        final ok = await model.addFirewallRule();
        if (!context.mounted) return;
        if (ok) {
          showInfoSnackBar(context, l10n.checkRuleAdded);
          await startServiceWithFeedback(context, model);
        }
      }
    case StartResult.failed:
      final error = model.startError ?? '';
      showErrorSnackBar(context, l10n.startFailed(error), copyText: error);
  }
}

/// 방화벽 안내를 열고, 거기서 [방화벽 규칙 추가]를 고르면 규칙을 넣는다 (서비스 화면 위쪽 [방화벽 안내]).
Future<void> openFirewallHelp(BuildContext context, ServiceModel model) async {
  final issue = model.firewallIssue;
  if (issue == null) return;
  final l10n = AppLocalizations.of(context);
  if (!await showFirewallHelp(context, issue: issue, program: model.programPath)) return;
  final ok = await model.addFirewallRule();
  if (!context.mounted) return;
  if (ok) {
    showInfoSnackBar(context, l10n.checkRuleAdded);
  } else {
    showErrorSnackBar(context, l10n.logCheckRuleFailed);
  }
}

Future<void> toggleServiceWithFeedback(BuildContext context, ServiceModel model) async {
  if (model.running) {
    await model.stop();
  } else if (!model.busy) {
    await startServiceWithFeedback(context, model);
  }
}

/// 시작 전 점검 결과. 막는 문제가 있으면 닫기만, 경고뿐이면 [취소] [방화벽 규칙 추가] [그래도 시작]. 기본 포커스는 취소.
Future<_Choice> _showIssues(BuildContext context, ServiceModel model) async {
  final l10n = AppLocalizations.of(context);
  final blocking = model.issues.any((i) => i.blocking);
  final firewall = model.issues.any((i) => i.kind == IssueKind.firewallBlocked);
  final reserved = model.issues.any((i) => i.kind == IssueKind.portsReserved);
  final dhcp = model.issues.any((i) => i.kind == IssueKind.otherDhcpServer);
  final result = await showDialog<_Choice>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        icon: Icon(blocking ? Icons.block_rounded : Icons.warning_amber_rounded, color: theme.colorScheme.error),
        title: Text(blocking ? l10n.checkTitleBlocked : (dhcp ? l10n.probeConflictTitle : l10n.checkTitleWarning)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final issue in model.issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(issue.blocking ? Icons.error_outline_rounded : Icons.info_outline_rounded, size: 18, color: issue.blocking ? theme.colorScheme.error : null),
                    const SizedBox(width: 8),
                    Expanded(child: Text(issueText(l10n, issue))),
                  ]),
                ),
              if (dhcp) ...[const SizedBox(height: 4), Text(l10n.probeConflictAdvice, style: theme.textTheme.bodySmall)],
              if (reserved) ...[const SizedBox(height: 4), SelectableText(l10n.checkPortsReservedAdvice, style: theme.textTheme.bodySmall)],
              if (firewall && !blocking) ...[const SizedBox(height: 4), Text(l10n.checkAddRuleHint, style: theme.textTheme.bodySmall)],
            ],
          ),
        ),
        actions: blocking
            ? [
                if (firewall) _helpButton(context, model, l10n),
                FilledButton(autofocus: true, onPressed: () => Navigator.pop(context, _Choice.cancel), child: Text(l10n.commonClose)),
              ]
            : [
                if (firewall) _helpButton(context, model, l10n),
                TextButton(autofocus: true, onPressed: () => Navigator.pop(context, _Choice.cancel), child: Text(l10n.commonCancel)),
                if (firewall) OutlinedButton(onPressed: () => Navigator.pop(context, _Choice.addRule), child: Text(l10n.checkAddRule)),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                  onPressed: () => Navigator.pop(context, _Choice.proceed),
                  child: Text(l10n.probeStartAnyway),
                ),
              ],
      );
    },
  );
  return result ?? _Choice.cancel;
}

/// 점검 대화상자의 [해결 방법]. 안내에서 [방화벽 규칙 추가]를 고르면 점검 대화상자도 그 선택으로 닫는다.
Widget _helpButton(BuildContext context, ServiceModel model, AppLocalizations l10n) {
  final issue = model.issues.firstWhere((i) => i.kind == IssueKind.firewallBlocked);
  return TextButton.icon(
    onPressed: () async {
      final add = await showFirewallHelp(context, issue: issue, program: model.programPath);
      if (add && context.mounted) Navigator.pop(context, _Choice.addRule);
    },
    icon: const Icon(Icons.help_outline_rounded, size: 18),
    label: Text(l10n.firewallHelpButton),
  );
}

/// 이 Lease의 MAC에 지금 주소를 고정 예약한다. 이미 예약됐거나 맞지 않으면 이유를 알린다.
Future<void> reserveLeaseWithFeedback(BuildContext context, DhcpModel model, LeaseInfo lease) async {
  final l10n = AppLocalizations.of(context);
  try {
    await model.addReservation('${lease.mac}', '${lease.ip}');
    if (context.mounted) showInfoSnackBar(context, l10n.leaseReserveDone('${lease.mac}', '${lease.ip}'));
  } catch (e) {
    if (!context.mounted) return;
    final text = e is FormatException ? (fieldErrorText(l10n, FieldError.values.asNameMap()[e.message]) ?? e.message) : '$e';
    showErrorSnackBar(context, l10n.reserveFailed(text), copyText: text);
  }
}

Future<void> releaseLeaseWithFeedback(BuildContext context, DhcpModel model, Ipv4 ip) async {
  final l10n = AppLocalizations.of(context);
  if (await model.releaseLease(ip) && context.mounted) showInfoSnackBar(context, l10n.leaseReleasedSnack('$ip'));
}

/// 되돌릴 수 없는 작업이라 확인을 받는다. 기본 포커스는 취소에 둔다 (ui-ux.md §6).
Future<void> confirmReleaseAll(BuildContext context, DhcpModel model) async {
  final count = model.leases.length;
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
  final released = await model.releaseAll();
  if (context.mounted) showInfoSnackBar(context, l10n.leaseReleasedAllSnack(released));
}
