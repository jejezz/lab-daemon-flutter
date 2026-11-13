// 상태를 알약 모양으로 보여 주는 작은 표시 (conventions/ui-ux.md "Saturn 디자인 언어"의 StatusPill).
// 공통 패키지(zoomon_ui)가 생기면 그쪽으로 옮긴다. 의미 색(성공·경고·위험)은 색 구성과 무관하게 고정이다.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum PillTone { success, warning, danger, neutral }

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = PillTone.neutral, this.dot = true});

  final String label;
  final PillTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final color = switch (tone) {
      PillTone.success => light ? AppColors.successTextLight : AppColors.success,
      PillTone.warning => light ? AppColors.warningTextLight : AppColors.warning,
      PillTone.danger => light ? AppColors.dangerTextLight : AppColors.danger,
      PillTone.neutral => theme.colorScheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: light ? 0.10 : 0.16),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
