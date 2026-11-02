// 오류 알림: 스낵바로 알리고 오류 원문을 복사할 수 있는 "복사" 액션을 붙인다 (ui-ux.md §6).
// 공통 패키지(zoomon_ui)가 생기면 그쪽으로 옮긴다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

/// [actionLabel]과 [onAction]을 주면 "복사" 대신 그 액션을 붙인다 (예: 설정 열기).
void showErrorSnackBar(BuildContext context, String message,
    {String? copyText, String? actionLabel, VoidCallback? onAction}) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 8),
    behavior: SnackBarBehavior.floating,
    showCloseIcon: true,
    action: SnackBarAction(
      label: actionLabel ?? l10n.errorCopy,
      onPressed: onAction ?? () => Clipboard.setData(ClipboardData(text: copyText ?? message)),
    ),
  ));
}

/// 완료 알림. 4초 뒤 저절로 닫힌다 (ui-ux.md §6).
void showInfoSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    duration: const Duration(seconds: 4),
    behavior: SnackBarBehavior.floating,
  ));
}
