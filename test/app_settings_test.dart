// From jejezz/application-release-templates common/ @ conventions-v1.
// 설정 저장 키·기존 키 이전·언어 해석 (localization.md §3·§5).
// lab_daemon를 앱의 pubspec name으로 바꾼다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to system theme and system language', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.locale, isNull);
  });

  test('글자 크기는 text_scale에 0.1 단위로 저장하고 50~150%로 제한한다', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    expect(s.textScale, 1.0);
    await s.setTextScale(1.1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('text_scale'), 1.1);
    await s.setTextScale(9);
    expect(s.textScale, 1.5);
    await s.setTextScale(0.1);
    expect(s.textScale, 0.5);
    await s.setTextScale(1.0999999);
    expect(prefs.getDouble('text_scale'), 1.1, reason: '부동소수 오차는 0.1 단위로 맞춘다');
    SharedPreferences.setMockInitialValues({'text_scale': 3.0});
    expect((await AppSettings.load()).textScale, 1.5, reason: '저장된 값이 범위를 벗어나도 제한한다');
  });

  test('persists under theme_mode / app_locale', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettings.load();
    await s.setThemeMode(ThemeMode.dark);
    await s.setLocale(const Locale('en'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(prefs.getString('app_locale'), 'en');
    await s.setLocale(null);
    expect(prefs.containsKey('app_locale'), isFalse);
  });

  test('moves a legacy key once', () async {
    SharedPreferences.setMockInitialValues({'locale': 'en'});
    final s = await AppSettings.load(legacyKeys: {'locale': AppSettings.localeKey});
    final prefs = await SharedPreferences.getInstance();
    expect(s.locale, const Locale('en'));
    expect(prefs.containsKey('locale'), isFalse);
  });

  test('non-Korean system languages resolve to English', () {
    const supported = [Locale('ko'), Locale('en')];
    expect(AppSettings.resolveLocale(const Locale('ko', 'KR'), supported), const Locale('ko'));
    expect(AppSettings.resolveLocale(const Locale('ja'), supported), const Locale('en'));
    expect(AppSettings.resolveLocale(null, supported), const Locale('en'));
  });
}
