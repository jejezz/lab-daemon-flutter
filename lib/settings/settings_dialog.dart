// 설정 창 (conventions/settings-screen.md, settings.md) — 데스크톱 전용 앱의 `AlertDialog` 구조.
// 구역 목록과 내용을 두고, 바꾼 값은 확인 버튼 없이 바로 적용·저장한다.
// "외형"이 항상 첫 구역이고 항목 순서는 모드 → 색 구성 → 언어로 고정이다. 앱 고유 구역
// (서비스별 설정 등)은 [SettingsSection]에 더한다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'settings_menus.dart';

enum SettingsSection {
  appearance(Icons.palette_outlined);

  const SettingsSection(this.icon);

  final IconData icon;

  String label(AppLocalizations l10n) => switch (this) {
        appearance => l10n.settingsSectionAppearance,
      };
}

Future<void> showSettingsDialog(BuildContext context, {SettingsSection initial = SettingsSection.appearance}) {
  return showDialog<void>(context: context, builder: (_) => SettingsDialog(initial: initial));
}

/// 이 너비(대화상자 안쪽) 이상이면 왼쪽 구역 목록, 미만이면 위쪽 칩 한 줄 (settings.md "크기와 도킹한 창").
const _wideBreakpoint = 560.0;

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, this.initial = SettingsSection.appearance});

  final SettingsSection initial;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsSection _section = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screen = MediaQuery.sizeOf(context);
    // 앱 창보다 커질 수 없다: 바깥 여백 16 + 제목 줄과 닫기 줄(약 150)을 뺀 만큼만 쓴다.
    final width = math.min(640.0, screen.width - 32);
    final height = (screen.height - 32 - 150).clamp(160.0, 380.0);
    final wide = width >= _wideBreakpoint;
    final content = SingleChildScrollView(
      padding: EdgeInsets.only(left: wide ? 16 : 0, bottom: 16),
      child: switch (_section) {
        SettingsSection.appearance => const _AppearanceSection(),
      },
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(l10n.settingsTitle),
      contentPadding: EdgeInsets.fromLTRB(wide ? 0 : 24, 8, 24, 0),
      content: SizedBox(
        width: width,
        height: height,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: ListView(
                      children: [
                        for (final s in SettingsSection.values)
                          _SectionTile(
                            selected: s == _section,
                            icon: s.icon,
                            label: s.label(l10n),
                            onTap: () => setState(() => _section = s),
                          ),
                      ],
                    ),
                  ),
                  const VerticalDivider(),
                  Expanded(child: content),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in SettingsSection.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              selected: s == _section,
                              showCheckmark: false,
                              avatar: Icon(s.icon, size: 16),
                              label: Text(s.label(l10n)),
                              onSelected: (_) => setState(() => _section = s),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(),
                  Expanded(child: content),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose))],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 4 : 16, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

/// 고른 구역은 배경을 채우는 대신 왼쪽에 굵은 선(3px, primary)을 그어 표시한다 — 고대비에서도 글자가 읽힌다.
class _SectionTile extends StatelessWidget {
  const _SectionTile({required this.selected, required this.icon, required this.label, required this.onTap});

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          // 선택 안 된 줄도 같은 폭을 비워 둬서, 고를 때 글자가 옆으로 밀리지 않게 한다.
          border: Border(left: BorderSide(width: 3, color: selected ? scheme.primary : Colors.transparent)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(color: selected ? scheme.onSurface : color))),
          ],
        ),
      ),
    );
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.settingsMode, first: true),
        const ModeSegmentedButton(),
        _Heading(l10n.settingsPalette),
        const AccentPaletteChips(),
        _Heading(l10n.settingsLanguage),
        const LanguageSegmentedButton(),
      ],
    );
  }
}
