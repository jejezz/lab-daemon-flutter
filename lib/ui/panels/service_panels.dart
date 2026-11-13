// 서비스별 설정 패널. 설정이 곧 서버의 전부라서 별도 설정 창이 아니라 각 서비스 화면의 왼쪽에 둔다.
// 바꾼 값은 확인 단추 없이 바로 저장된다. 실행 중에는 잠그고(DHCP의 Lease Time만 즉시 적용 가능) 안내를 보인다.

import 'package:flutter/material.dart';

import '../../core/ipv4.dart';
import '../../core/netutil.dart';
import '../../l10n/app_localizations.dart';
import '../../state/dhcp_settings.dart';
import '../../state/ftp_settings.dart';
import '../../state/service_model.dart';
import '../../state/service_models.dart';
import '../../state/tftp_settings.dart';
import '../../theme/app_theme.dart';
import '../open_folder.dart';
import '../widgets/error_snackbar.dart';
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
        PanelHeading(l10n.dhcpReservations),
        _ReservationsSection(model: model, error: errors[DhcpField.reservations]),
        PanelHeading(l10n.sectionAdvanced),
        _LogFileRow(model: model),
        SwitchRow(
          title: l10n.dhcpPersistLeases,
          subtitle: l10n.dhcpPersistLeasesHint,
          value: s.persistLeases,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(persistLeases: v)),
        ),
        SwitchRow(
          title: l10n.dhcpConflictCheck,
          subtitle: l10n.dhcpConflictCheckHint,
          value: s.conflictCheck,
          enabled: !locked,
          onChanged: (v) => model.update(model.settings.copyWith(conflictCheck: v)),
        ),
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

/// 서비스 로그를 파일에도 저장하는 스위치와 [로그 폴더 열기]. 파일 저장 기능이 없는 모델(시험)에서는 아무것도 그리지 않는다.
class _LogFileRow extends StatelessWidget {
  const _LogFileRow({required this.model});

  final ServiceModel model;

  @override
  Widget build(BuildContext context) {
    final dir = model.logDirectory;
    if (dir == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchRow(
        title: l10n.logToFile,
        subtitle: l10n.logToFileHint,
        value: model.logToFile,
        onChanged: (v) => model.setLogToFile(v),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => openInExplorer(dir, create: true),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(l10n.logOpenFolder),
        ),
      ),
    ]);
  }
}

/// 고정 주소 예약 목록과 추가 칸. 서비스가 켜져 있어도 바꿀 수 있다.
class _ReservationsSection extends StatefulWidget {
  const _ReservationsSection({required this.model, required this.error});

  final DhcpModel model;
  final FieldError? error;

  @override
  State<_ReservationsSection> createState() => _ReservationsSectionState();
}

class _ReservationsSectionState extends State<_ReservationsSection> {
  final _mac = TextEditingController();
  final _ip = TextEditingController();
  FieldError? _error;

  @override
  void dispose() {
    _mac.dispose();
    _ip.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    final error = widget.model.checkReservation(_mac.text, _ip.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    try {
      await widget.model.addReservation(_mac.text, _ip.text);
      if (!mounted) return;
      setState(() => _error = null);
      _mac.clear();
      _ip.clear();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, l10n.reserveFailed('$e'), copyText: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reservations = widget.model.settings.reservations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.dhcpReservationsHint, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        if (reservations.isEmpty)
          Text(l10n.dhcpReservationNone, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        for (final (m, ip) in reservations)
          Row(children: [
            Expanded(child: Text('$m  →  $ip', style: AppFonts.mono.copyWith(fontSize: 13), overflow: TextOverflow.ellipsis)),
            IconButton(
              tooltip: l10n.dhcpReserveRemove,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                final mac = MacAddress.tryParse(m);
                if (mac != null) {
                  widget.model.removeReservation(mac);
                } else {
                  widget.model.update(widget.model.settings.copyWith(reservations: [
                    for (final r in reservations)
                      if (r.$1 != m || r.$2 != ip) r,
                  ]));
                }
              },
            ),
          ]),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(fieldErrorText(l10n, widget.error) ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _mac,
          decoration: InputDecoration(isDense: true, labelText: l10n.dhcpReserveMac, hintText: 'aa:bb:cc:00:11:22', border: const OutlineInputBorder()),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _ip,
              decoration: InputDecoration(
                isDense: true,
                labelText: l10n.dhcpReserveIp,
                errorText: fieldErrorText(l10n, _error),
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(onPressed: _add, child: Text(l10n.dhcpReserveAdd)),
        ]),
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
        text(TftpField.port, l10n.fieldPortDefault(69)),
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
        _LogFileRow(model: model),
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
        text(FtpField.port, l10n.fieldPortDefault(21)),
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
        _LogFileRow(model: model),
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
