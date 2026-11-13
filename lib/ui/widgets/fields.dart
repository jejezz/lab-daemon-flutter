// 서비스 설정 패널이 같이 쓰는 입력 위젯: 글자 칸, NIC 선택, 폴더 선택, 스위치, 소제목.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/netutil.dart';
import '../../l10n/app_localizations.dart';
import '../../state/settings_common.dart';
import '../../theme/app_theme.dart';

String? fieldErrorText(AppLocalizations l10n, FieldError? error) => switch (error) {
      null => null,
      FieldError.required => l10n.fieldErrRequired,
      FieldError.invalidIp => l10n.fieldErrInvalidIp,
      FieldError.invalidMask => l10n.fieldErrInvalidMask,
      FieldError.invalidLeaseTime => l10n.fieldErrInvalidLeaseTime,
      FieldError.notInSubnet => l10n.fieldErrNotInSubnet,
      FieldError.notHostAddress => l10n.fieldErrNotHost,
      FieldError.rangeReversed => l10n.fieldErrRangeReversed,
      FieldError.tooLong => l10n.fieldErrTooLong,
      FieldError.invalidPort => l10n.fieldErrInvalidPort,
      FieldError.invalidNumber => l10n.fieldErrInvalidNumber,
      FieldError.dirMissing => l10n.fieldErrDirMissing,
    };

/// 아직 만지지 않은 빈 칸에 "값이 필요해요"를 미리 띄우지 않는다 ([showRequired]는 시작이 거부된 뒤 true).
FieldError? visibleError(FieldError? error, {required bool showRequired}) =>
    error == FieldError.required && !showRequired ? null : error;

InputDecoration _decoration({required String label, String? hint, String? error, String? helper, Widget? suffix}) => InputDecoration(
      isDense: true,
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      errorText: error,
      errorMaxLines: 2,
      suffixIcon: suffix,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.button))),
    );

/// 값이 밖에서 바뀌면(예: NIC를 골라 범위를 채움) 입력 중이 아닐 때 화면에도 반영한다.
class SettingsTextField extends StatefulWidget {
  const SettingsTextField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.helper,
    this.error,
    this.enabled = true,
    this.obscure = false,
    this.suffix,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? helper;
  final String? error;
  final bool enabled;
  final bool obscure;
  final Widget? suffix;

  @override
  State<SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<SettingsTextField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  /// 이 칸에서 마지막으로 입력해 보낸 값. 돌아온 값이 이것과 같으면 내가 친 글자이므로 덮어쓰지 않는다.
  String? _typed;

  @override
  void didUpdateWidget(SettingsTextField old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value || widget.value == _controller.text) return;
    // 포커스가 있어도 바깥에서 바뀐 값(찾아보기로 고른 폴더, NIC를 골라 채운 범위)은 보여 준다.
    // 폴더 선택 창이 닫히면 포커스가 이 칸으로 돌아오므로 포커스 여부로 판단하면 안 된다.
    if (widget.value != _typed) {
      _controller.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        obscureText: widget.obscure,
        decoration: _decoration(label: widget.label, hint: widget.hint, error: widget.error, helper: widget.helper, suffix: widget.suffix),
        onChanged: (v) {
          final sent = widget.obscure ? v : v.trim();
          _typed = sent;
          widget.onChanged(sent);
        },
      );
}

/// NIC 고르기. [allowAll]이면 "모든 NIC" 항목을 넣고 값 ''가 그것이다.
class NicDropdown extends StatelessWidget {
  const NicDropdown({
    super.key,
    required this.value,
    required this.nics,
    required this.onChanged,
    required this.onRefresh,
    this.allowAll = false,
    this.error,
    this.enabled = true,
  });

  final String value;
  final List<NicInfo> nics;
  final ValueChanged<String> onChanged;
  final VoidCallback onRefresh;
  final bool allowAll;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <DropdownMenuItem<String>>[
      if (allowAll) DropdownMenuItem(value: '', child: Text(l10n.fieldAllNics)),
      for (final nic in nics) DropdownMenuItem(value: '${nic.address}', child: Text('${nic.name}  ${nic.address}', overflow: TextOverflow.ellipsis)),
      if (value.isNotEmpty && !nics.any((n) => '${n.address}' == value)) DropdownMenuItem(value: value, child: Text(l10n.dhcpNicMissing(value))),
    ];
    final selected = items.any((i) => i.value == value) ? value : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('nic-$value-${nics.length}-$enabled'),
            initialValue: selected,
            isExpanded: true,
            decoration: _decoration(
              label: l10n.fieldBindNic,
              error: error,
              helper: nics.isEmpty ? l10n.dhcpNicNone : (allowAll && value.isEmpty ? l10n.fieldAllNicsWarning : null),
            ),
            items: items,
            onChanged: enabled ? (v) => onChanged(v ?? '') : null,
          ),
        ),
        IconButton(tooltip: l10n.dhcpNicRefresh, icon: const Icon(Icons.refresh_rounded), onPressed: onRefresh),
      ],
    );
  }
}

/// 폴더 경로 칸 + [찾아보기] (Windows 폴더 선택 창).
class FolderField extends StatelessWidget {
  const FolderField({super.key, required this.value, required this.onChanged, this.error, this.enabled = true});

  final String value;
  final ValueChanged<String> onChanged;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SettingsTextField(
      label: l10n.fieldRootDir,
      value: value,
      error: error,
      enabled: enabled,
      onChanged: onChanged,
      suffix: IconButton(
        tooltip: l10n.fieldBrowse,
        icon: const Icon(Icons.folder_open_outlined, size: 20),
        onPressed: !enabled
            ? null
            : () async {
                final picked = await getDirectoryPath(initialDirectory: value.isEmpty ? null : value);
                if (picked != null) onChanged(picked);
              },
      ),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.enabled = true, this.warning});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  /// 켜져 있을 때 보여 줄 주의 문구.
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: (value && warning != null) || subtitle != null
          ? Text(value && warning != null ? warning! : subtitle!, style: value && warning != null ? TextStyle(color: theme.colorScheme.error) : null)
          : null,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 0 : AppSpacing.lg, bottom: AppSpacing.sm),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}

/// 두 칸을 나란히.
class FieldPair extends StatelessWidget {
  const FieldPair(this.left, this.right, {super.key});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: left), const SizedBox(width: AppSpacing.sm), Expanded(child: right)],
      );
}

/// 칸 사이 간격.
const fieldGap = SizedBox(height: AppSpacing.md);
