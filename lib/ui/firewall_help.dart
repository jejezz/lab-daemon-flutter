// 방화벽 허용 방법 안내: 자동 추가(UAC), OS 버전별 직접 허용 단계, 관리자 터미널용 명령.
// 시작 전 점검 대화상자와 서비스 화면 위쪽의 [방화벽 안내]에서 연다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/netcheck.dart';
import '../core/os_info.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'widgets/error_snackbar.dart';

/// Windows의 "허용된 앱" 창을 연다 (설정이 아니라 제어판 화면, 일반 권한으로 열린다).
Future<void> openAllowedApps() async {
  if (!Platform.isWindows) return;
  try {
    await Process.start('control', ['/name', 'Microsoft.WindowsFirewall', '/page', 'pageConfigureApps'], mode: ProcessStartMode.detached);
  } catch (_) {}
}

/// 안내를 보여 준다. 사용자가 [방화벽 규칙 추가]를 고르면 true.
Future<bool> showFirewallHelp(
  BuildContext context, {
  required PreStartIssue issue,
  required String program,
  bool canAddRule = true,
  HostOs? os,
}) async {
  final l10n = AppLocalizations.of(context);
  final hostOs = os ?? currentHostOs;
  final (osName, steps) = switch (hostOs) {
    HostOs.windows11 => ('Windows 11', l10n.firewallStepsWin11),
    HostOs.windows10 => ('Windows 10', l10n.firewallStepsWin10),
    _ => ('Windows', l10n.firewallStepsWin11),
  };
  String list(String key) => (issue.args[key] as List?)?.join(', ') ?? '';
  final command = PreStartChecker.ruleCommand(program);

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final mono = AppFonts.mono.copyWith(fontSize: 12);
      Widget heading(String text) => Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
            child: Text(text, style: theme.textTheme.titleSmall),
          );
      Widget box(Widget child) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: child,
          );
      return AlertDialog(
        icon: const Icon(Icons.shield_outlined),
        title: Text(l10n.firewallHelpTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.firewallHelpWhy(list('ports'), list('profiles'))),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.firewallHelpProgram, style: theme.textTheme.labelMedium),
                box(SelectableText(program, style: mono)),
                if (canAddRule) ...[
                  heading(l10n.firewallHelpAutoTitle),
                  Text(l10n.firewallHelpAutoBody, style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                    label: Text(l10n.checkAddRule),
                  ),
                ],
                heading(l10n.firewallHelpManualTitle(osName)),
                for (final (i, step) in steps.split('\n').indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 20, child: Text('${i + 1}.', style: theme.textTheme.bodySmall)),
                      Expanded(child: Text(step, style: theme.textTheme.bodySmall)),
                    ]),
                  ),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton.icon(
                  onPressed: openAllowedApps,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(l10n.firewallOpenAllowedApps),
                ),
                heading(l10n.firewallHelpCommandTitle),
                box(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: SelectableText(command, style: mono)),
                  IconButton(
                    tooltip: l10n.errorCopy,
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: command));
                      if (context.mounted) showInfoSnackBar(context, l10n.commandCopied);
                    },
                  ),
                ])),
                const SizedBox(height: AppSpacing.md),
                Text(l10n.firewallHelpInstallerNote, style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.firewallHelpPolicyNote, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonClose))],
      );
    },
  );
  return result ?? false;
}
