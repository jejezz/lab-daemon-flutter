// Lease 표: 한 줄에 Lease 하나. 행을 눌러 고르고, Del이나 우클릭 메뉴, 줄 끝 버튼으로 해제한다.
// 남은 시간은 1초마다 다시 그린다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/dhcp/pool.dart';
import '../core/dhcp/server.dart';
import '../core/ipv4.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'widgets/status_pill.dart';

/// 열 너비 비율: IP, MAC, 호스트 이름, 상태, 남은 시간, 해제 버튼.
const _flex = [3, 4, 4, 2, 3];
const _actionWidth = 44.0;

class LeaseTable extends StatefulWidget {
  const LeaseTable({
    super.key,
    required this.leases,
    required this.selected,
    required this.onSelect,
    required this.onRelease,
    this.now,
  });

  final List<LeaseInfo> leases;
  final Ipv4? selected;
  final ValueChanged<Ipv4?> onSelect;
  final ValueChanged<Ipv4> onRelease;

  /// 테스트에서 시계를 고정한다.
  final DateTime Function()? now;

  @override
  State<LeaseTable> createState() => _LeaseTableState();
}

class _LeaseTableState extends State<LeaseTable> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.leases.any((l) => l.expiresAt != null)) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
    final headers = [l10n.leaseColIp, l10n.leaseColMac, l10n.leaseColHostname, l10n.leaseColState, l10n.leaseColRemaining];

    if (widget.leases.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.leaseEmptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(l10n.leaseEmptyHint, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              for (var i = 0; i < headers.length; i++) Expanded(flex: _flex[i], child: Text(headers[i], style: headerStyle)),
              const SizedBox(width: _actionWidth),
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: ListView.builder(
            itemCount: widget.leases.length,
            itemExtent: 36,
            itemBuilder: (context, i) {
              final lease = widget.leases[i];
              return _LeaseRow(
                lease: lease,
                now: _now,
                selected: lease.ip == widget.selected,
                onTap: () => widget.onSelect(lease.ip),
                onRelease: () => widget.onRelease(lease.ip),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LeaseRow extends StatelessWidget {
  const _LeaseRow({required this.lease, required this.now, required this.selected, required this.onTap, required this.onRelease});

  final LeaseInfo lease;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRelease;

  static String formatRemaining(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  Future<void> _menu(BuildContext context, Offset position) async {
    final l10n = AppLocalizations.of(context);
    onTap();
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(value: true, height: 36, child: Row(children: [
          Expanded(child: Text(l10n.leaseRelease)),
          Text('Del', style: Theme.of(context).textTheme.labelSmall),
        ])),
      ],
    );
    if (choice == true) onRelease();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = AppFonts.mono.copyWith(fontSize: theme.textTheme.bodyMedium?.fontSize);
    final remaining = lease.expiresAt?.difference(now);
    final bound = lease.state == LeaseState.bound;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Expanded(flex: _flex[0], child: Text('${lease.ip}', style: mono)),
              Expanded(flex: _flex[1], child: Text('${lease.mac}', style: mono)),
              Expanded(
                flex: _flex[2],
                child: Text(lease.hostname ?? '', overflow: TextOverflow.ellipsis, style: AppFonts.userContent),
              ),
              Expanded(
                flex: _flex[3],
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(
                    label: bound ? l10n.leaseStateBound : l10n.leaseStateOffered,
                    tone: bound ? PillTone.success : PillTone.warning,
                  ),
                ),
              ),
              Expanded(
                flex: _flex[4],
                child: Text(
                  remaining == null ? l10n.leaseUnlimited : formatRemaining(remaining.isNegative ? Duration.zero : remaining),
                  style: mono,
                ),
              ),
              SizedBox(
                width: _actionWidth,
                child: IconButton(
                  tooltip: l10n.leaseRelease,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.link_off_rounded),
                  onPressed: onRelease,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
