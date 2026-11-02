// 설정 창 구역들이 같이 쓰는 작은 위젯.

import 'package:flutter/material.dart';

/// 구역 안의 소제목 (`titleSmall` 굵게, settings.md).
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: first ? 4 : 16, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}
