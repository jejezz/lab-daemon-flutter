// 설정 창의 "DHCP" 구역. 값을 바꾸면 확인 단추 없이 바로 저장한다 (settings.md).
// 실행 중에는 Lease Time만 즉시 적용되고 나머지는 서비스를 다시 시작할 때 적용된다.

import 'package:flutter/material.dart';

import '../core/ipv4.dart';
import '../l10n/app_localizations.dart';
import '../state/controller.dart';
import '../state/dhcp_settings.dart';
import '../theme/app_theme.dart';
import 'settings_widgets.dart';

class DhcpSettingsSection extends StatefulWidget {
  const DhcpSettingsSection({super.key});

  @override
  State<DhcpSettingsSection> createState() => _DhcpSettingsSectionState();
}

class _DhcpSettingsSectionState extends State<DhcpSettingsSection> {
  final _fields = <DhcpField, TextEditingController>{};
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final controller = ControllerScope.read(context);
    for (final f in DhcpField.values) {
      if (f == DhcpField.serverIp) continue;
      _fields[f] = TextEditingController(text: controller.dhcpSettings.valueOf(f));
    }
    controller.refreshNics();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _error(AppLocalizations l10n, LabDaemonController c, DhcpField f) {
    final error = c.dhcpErrors[f];
    if (error == null) return null;
    // 아직 만지지 않은 빈 칸에 "값이 필요해요"를 미리 띄우지 않는다. 시작이 거부된 뒤에는 보여 준다.
    if (error == FieldError.required && c.startError != 'invalidSettings') return null;
    return switch (error) {
      FieldError.required => l10n.fieldErrRequired,
      FieldError.invalidIp => l10n.fieldErrInvalidIp,
      FieldError.invalidMask => l10n.fieldErrInvalidMask,
      FieldError.invalidLeaseTime => l10n.fieldErrInvalidLeaseTime,
      FieldError.notInSubnet => l10n.fieldErrNotInSubnet,
      FieldError.notHostAddress => l10n.fieldErrNotHost,
      FieldError.rangeReversed => l10n.fieldErrRangeReversed,
      FieldError.tooLong => l10n.fieldErrTooLong,
    };
  }

  Widget _text(LabDaemonController c, AppLocalizations l10n, DhcpField f, String label, {String? hint}) {
    return TextField(
      controller: _fields[f],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        errorText: _error(l10n, c, f),
        errorMaxLines: 2,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.button))),
      ),
      onChanged: (v) => c.updateDhcp(c.dhcpSettings.withValue(f, v.trim())),
    );
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.md),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final l10n = AppLocalizations.of(context);
    final s = c.dhcpSettings;
    final nicItems = <DropdownMenuItem<String>>[
      for (final nic in c.nics) DropdownMenuItem(value: '${nic.address}', child: Text('${nic.name}  ${nic.address}')),
      if (s.serverIp.isNotEmpty && !c.nics.any((n) => '${n.address}' == s.serverIp))
        DropdownMenuItem(value: s.serverIp, child: Text(l10n.dhcpNicMissing(s.serverIp))),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.dhcpRunning)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
            child: Text(l10n.dhcpRestartNote, style: Theme.of(context).textTheme.bodySmall),
          ),
        SettingsHeading(l10n.statusServer, first: !c.dhcpRunning),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('nic-${s.serverIp}-${c.nics.length}'),
                initialValue: nicItems.any((i) => i.value == s.serverIp) ? s.serverIp : null,
                isExpanded: true,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.dhcpFieldServerIp,
                  helperText: c.nics.isEmpty ? l10n.dhcpNicNone : null,
                  errorText: _error(l10n, c, DhcpField.serverIp),
                  border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.button))),
                ),
                items: nicItems,
                onChanged: (ip) {
                  if (ip == null) return;
                  final parsed = Ipv4.tryParse(ip);
                  var next = s.copyWith(serverIp: ip);
                  if (parsed != null) next = next.withSuggestionsFor(parsed);
                  c.updateDhcp(next);
                  // 제안값을 입력칸에도 반영한다.
                  for (final f in [DhcpField.rangeStart, DhcpField.rangeEnd, DhcpField.gateway]) {
                    _fields[f]!.text = next.valueOf(f);
                  }
                },
              ),
            ),
            IconButton(
              tooltip: l10n.dhcpNicRefresh,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: c.refreshNics,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _row([
          _text(c, l10n, DhcpField.rangeStart, l10n.dhcpFieldRangeStart),
          _text(c, l10n, DhcpField.rangeEnd, l10n.dhcpFieldRangeEnd),
        ]),
        _row([
          _text(c, l10n, DhcpField.mask, l10n.dhcpFieldMask),
          _text(c, l10n, DhcpField.gateway, l10n.dhcpFieldGateway, hint: l10n.dhcpHintOptional),
        ]),
        _row([
          _text(c, l10n, DhcpField.dns, l10n.dhcpFieldDns, hint: l10n.dhcpHintDns),
          _text(c, l10n, DhcpField.leaseTime, l10n.dhcpFieldLeaseTime, hint: l10n.dhcpHintLeaseTime),
        ]),
        SettingsHeading(l10n.dhcpFieldTftp),
        _row([
          _text(c, l10n, DhcpField.tftpServer, l10n.dhcpFieldTftp, hint: l10n.dhcpHintOptional),
          _text(c, l10n, DhcpField.bootFile, l10n.dhcpFieldBootFile, hint: l10n.dhcpHintOptional),
        ]),
        _row([_text(c, l10n, DhcpField.domain, l10n.dhcpFieldDomain, hint: l10n.dhcpHintOptional)]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.dhcpDetectOthers),
          subtitle: Text(l10n.dhcpDetectOthersHint),
          value: s.detectOtherServers,
          onChanged: (v) => c.updateDhcp(s.copyWith(detectOtherServers: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.dhcpDirectedBroadcast),
          subtitle: Text(l10n.dhcpDirectedBroadcastHint),
          value: s.directedBroadcast,
          onChanged: (v) => c.updateDhcp(s.copyWith(directedBroadcast: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l10n.dhcpLogPackets),
          value: s.logPackets,
          onChanged: (v) => c.updateDhcp(s.copyWith(logPackets: v)),
        ),
      ],
    );
  }
}
