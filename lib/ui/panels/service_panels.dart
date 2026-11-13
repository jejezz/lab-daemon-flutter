// 서비스별 설정 패널. 설정이 곧 서버의 전부라서 별도 설정 창이 아니라 각 서비스 화면의 왼쪽에 둔다.
// 바꾼 값은 확인 단추 없이 바로 저장된다. 실행 중에는 잠그고(DHCP의 Lease Time만 즉시 적용 가능) 안내를 보인다.

import 'package:flutter/material.dart';

import '../../core/ipv4.dart';
import '../../core/netutil.dart';
import '../../l10n/app_localizations.dart';
import '../../state/dhcp_settings.dart';
import '../../state/ftp_settings.dart';
import '../../state/service_models.dart';
import '../../state/tftp_settings.dart';
import '../../theme/app_theme.dart';
import '../widgets/fields.dart';

class _LockedNote extends StatelessWidget {
  const _LockedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.button),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class DhcpPanel extends StatelessWidget {
  const DhcpPanel({super.key, required this.model, required this.nics, required this.onRefreshNics});

  final DhcpModel model;
  final List<NicInfo> nics;
  final VoidCallback onRefreshNics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = model.settings;
    final errors = model.errors;
    final locked = model.running || model.busy;
    String? e(DhcpField f) => fieldErrorText(l10n, visibleError(errors[f], showRequired: model.showAllErrors));
    void set(DhcpField f, String v) => model.update(model.settings.withValue(f, v));
    Widget text(DhcpField f, String label, {String? hint, bool live = false}) =>
        SettingsTextField(label: label, value: s.valueOf(f), hint: hint, error: e(f), enabled: !locked || live, onChanged: (v) => set(f, v));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locked) _LockedNote(l10n.dhcpRestartNote),
        PanelHeading(l10n.statusServer, first: true),
        NicDropdown(
          value: s.serverIp,
          nics: nics,
          error: e(DhcpField.serverIp),
          enabled: !locked,
          onRefresh: onRefreshNics,
          onChanged: (ip) {
            var next = model.settings.copyWith(serverIp: ip);
            final parsed = Ipv4.tryParse(ip);
            if (parsed != null) next = next.withSuggestionsFor(parsed);
            model.update(next);
          },
        ),
        fieldGap,
        FieldPair(text(DhcpField.rangeStart, l10n.dhcpFieldRangeStart), text(DhcpField.rangeEnd, l10n.dhcpFieldRangeEnd)),
        fieldGap,
        FieldPair(text(DhcpField.mask, l10n.dhcpFieldMask), text(DhcpField.gateway, l10n.dhcpFieldGateway, hint: l10n.dhcpHintOptional)),
        fieldGap,
        text(DhcpField.dns, l10n.dhcpFieldDns, hint: l10n.dhcpHintDns),
        fieldGap,
        text(DhcpField.leaseTime, l10n.dhcpFieldLeaseTime, hint: l10n.dhcpHintLeaseTime, live: true),
        PanelHeading(l10n.dhcpFieldTftp),
        FieldPair(text(DhcpField.tftpServer, l10n.dhcpFieldTftp, hint: l10n.dhcpHintOptional), text(DhcpField.bootFile, l10n.dhcpFieldBootFile, hint: l10n.dhcpHintOptional)),
        fieldGap,
        text(DhcpField.domain, l10n.dhcpFieldDomain, hint: l10n.dhcpHintOptional),
        PanelHeading(l10n.sectionAdvanced),
        SwitchRow(
          title: l10n.dhcpDetectOthers,
          subtitle: l10n.dhcpDetectOthersHint,
          value: s.detectOtherServers,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(detectOtherServers: v)),
        ),
        SwitchRow(
          title: l10n.dhcpDirectedBroadcast,
          subtitle: l10n.dhcpDirectedBroadcastHint,
          value: s.directedBroadcast,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(directedBroadcast: v)),
        ),
        SwitchRow(
          title: l10n.dhcpLogPackets,
          value: s.logPackets,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(logPackets: v)),
        ),
      ],
    );
  }
}

class TftpPanel extends StatelessWidget {
  const TftpPanel({super.key, required this.model, required this.nics, required this.onRefreshNics});

  final TftpModel model;
  final List<NicInfo> nics;
  final VoidCallback onRefreshNics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = model.settings;
    final errors = model.errors;
    final locked = model.running || model.busy;
    String? e(TftpField f) => fieldErrorText(l10n, visibleError(errors[f], showRequired: model.showAllErrors));
    Widget text(TftpField f, String label, {String? hint}) => SettingsTextField(
          label: label,
          value: s.valueOf(f),
          hint: hint,
          error: e(f),
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.withValue(f, v)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locked) _LockedNote(l10n.runningLockedNote),
        PanelHeading(l10n.statusServer, first: true),
        NicDropdown(
          value: s.bindIp,
          nics: nics,
          allowAll: true,
          error: e(TftpField.bindIp),
          enabled: !locked,
          onRefresh: onRefreshNics,
          onChanged: (ip) => model.update(model.settings.copyWith(bindIp: ip)),
        ),
        fieldGap,
        text(TftpField.port, l10n.fieldPort),
        fieldGap,
        FolderField(
          value: s.rootDir,
          error: e(TftpField.rootDir),
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(rootDir: v)),
        ),
        fieldGap,
        SwitchRow(
          title: l10n.tftpAllowWrite,
          subtitle: l10n.tftpAllowWriteHint,
          value: s.allowWrite,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(allowWrite: v)),
        ),
        SwitchRow(
          title: l10n.tftpAllowOverwrite,
          value: s.allowOverwrite,
          enabled: !locked && s.allowWrite,
          onChanged: (v) => model.update(model.settings.copyWith(allowOverwrite: v)),
        ),
        PanelHeading(l10n.sectionAdvanced),
        FieldPair(text(TftpField.maxBlockSize, l10n.tftpMaxBlockSize), text(TftpField.maxWindowSize, l10n.tftpMaxWindow)),
        fieldGap,
        FieldPair(text(TftpField.timeoutMs, l10n.tftpTimeout), text(TftpField.maxTransfers, l10n.tftpMaxTransfers)),
        SwitchRow(
          title: l10n.tftpLogPackets,
          value: s.logPackets,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(logPackets: v)),
        ),
      ],
    );
  }
}

class FtpPanel extends StatelessWidget {
  const FtpPanel({super.key, required this.model, required this.nics, required this.onRefreshNics});

  final FtpModel model;
  final List<NicInfo> nics;
  final VoidCallback onRefreshNics;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = model.settings;
    final errors = model.errors;
    final locked = model.running || model.busy;
    String? e(FtpField f) => fieldErrorText(l10n, visibleError(errors[f], showRequired: model.showAllErrors));
    Widget text(FtpField f, String label, {String? hint, String? helper}) => SettingsTextField(
          label: label,
          value: s.valueOf(f),
          hint: hint,
          helper: helper,
          error: e(f),
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.withValue(f, v)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locked) _LockedNote(l10n.runningLockedNote),
        PanelHeading(l10n.statusServer, first: true),
        NicDropdown(
          value: s.bindIp,
          nics: nics,
          allowAll: true,
          error: e(FtpField.bindIp),
          enabled: !locked,
          onRefresh: onRefreshNics,
          onChanged: (ip) => model.update(model.settings.copyWith(bindIp: ip)),
        ),
        fieldGap,
        text(FtpField.port, l10n.fieldPort),
        fieldGap,
        FolderField(
          value: s.rootDir,
          error: e(FtpField.rootDir),
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(rootDir: v)),
        ),
        PanelHeading(l10n.ftpAccount),
        text(FtpField.username, l10n.ftpUsername),
        fieldGap,
        SettingsTextField(
          label: l10n.ftpPassword,
          value: '',
          obscure: true,
          enabled: !locked,
          helper: s.hasPassword ? l10n.ftpPasswordSet : l10n.ftpPasswordHint,
          error: e(FtpField.password),
          onChanged: (v) => model.update(model.settings.withPassword(v)),
        ),
        SwitchRow(
          title: l10n.ftpAllowAnonymous,
          value: s.allowAnonymous,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(allowAnonymous: v)),
        ),
        SwitchRow(
          title: l10n.ftpAllowWrite,
          value: s.allowWrite,
          enabled: !locked,
          warning: s.allowAnonymous ? l10n.ftpAnonymousWriteWarning : null,
          onChanged: (v) => model.update(model.settings.copyWith(allowWrite: v)),
        ),
        PanelHeading(l10n.sectionAdvanced),
        FieldPair(text(FtpField.passiveStart, l10n.ftpPassiveStart, helper: l10n.ftpPassiveHint), text(FtpField.passiveEnd, l10n.ftpPassiveEnd)),
        fieldGap,
        FieldPair(text(FtpField.maxConnections, l10n.ftpMaxConnections), text(FtpField.idleTimeout, l10n.ftpIdleTimeout)),
        SwitchRow(
          title: l10n.ftpLogCommands,
          value: s.logCommands,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(logCommands: v)),
        ),
      ],
    );
  }
}
