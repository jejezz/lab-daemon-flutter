// From jejezz/application-release-templates common/ @ conventions-v2.
//
// 테마·언어·색 구성 전환 UI (conventions/settings-screen.md, theming.md §3,
// localization.md §4). 모두 설정 화면 "외형" 구역 안에만 둔다 — 앱 바에는
// 테마/언어 아이콘 대신 설정 아이콘 하나(⌘,/Ctrl+,)만 둔다.
//   ModeSegmentedButton / AccentPaletteChips / LanguageSegmentedButton:
//     설정 창(settings_dialog.dart) "외형" 구역에 이 순서로 넣는다.

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'app_settings.dart';

/// 언어 이름은 그 언어로 쓴다 — 잘못 골라도 읽고 되돌아올 수 있게.
const _languages = [(Locale('ko'), '한국어'), (Locale('en'), 'English')];

IconData _themeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };

/// 설정 화면 "외형" 구역의 모드(시스템/라이트/다크) 단추 (settings-screen.md §3).
class ModeSegmentedButton extends StatelessWidget {
  const ModeSegmentedButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(_themeIcon(ThemeMode.system), size: 16),
          label: Text(l10n.settingsModeSystem),
        ),
        ButtonSegment(value: ThemeMode.light, icon: Icon(_themeIcon(ThemeMode.light), size: 16), label: Text(l10n.themeLight)),
        ButtonSegment(value: ThemeMode.dark, icon: Icon(_themeIcon(ThemeMode.dark), size: 16), label: Text(l10n.themeDark)),
      ],
      selected: {settings.themeMode},
      onSelectionChanged: (s) => settings.setThemeMode(s.first),
    );
  }
}

/// 설정 화면 "외형" 구역의 색 구성 선택 (settings-screen.md §4). 고대비는 색 원 대신
/// 아이콘(contrast)으로 구분한다 — 주색 하나가 아니라 전체 대비를 바꾸는 항목이라서다.
class AccentPaletteChips extends StatelessWidget {
  const AccentPaletteChips({super.key});

  static String _label(AppLocalizations l10n, AccentPalette p) => switch (p) {
        AccentPalette.saturn => l10n.settingsPaletteSaturn,
        AccentPalette.teal => l10n.settingsPaletteTeal,
        AccentPalette.amber => l10n.settingsPaletteAmber,
        AccentPalette.rose => l10n.settingsPaletteRose,
        AccentPalette.slate => l10n.settingsPaletteSlate,
        AccentPalette.highContrast => l10n.settingsPaletteHighContrast,
      };

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in AccentPalette.values)
          ChoiceChip(
            selected: settings.accentPalette == p,
            showCheckmark: false,
            avatar: p == AccentPalette.highContrast
                ? Icon(Icons.contrast_rounded, size: 14, color: Theme.of(context).colorScheme.onSurface)
                : Icon(Icons.circle, size: 14, color: p.primaryFor(brightness)),
            label: Text(_label(l10n, p)),
            onSelected: (_) => settings.setAccentPalette(p),
          ),
      ],
    );
  }
}

/// 모바일 설정 화면용.
class LanguageSegmentedButton extends StatelessWidget {
  const LanguageSegmentedButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<String>(
      segments: [
        ButtonSegment(value: '', label: Text(l10n.languageSystemShort)),
        for (final (locale, name) in _languages) ButtonSegment(value: locale.languageCode, label: Text(name)),
      ],
      selected: {settings.locale?.languageCode ?? ''},
      onSelectionChanged: (s) => settings.setLocale(s.single.isEmpty ? null : Locale(s.single)),
    );
  }
}
