// DHCP 본문: 서버가 꺼져 있으면 빈 상태, 켜져 있으면 상태 바 + 도구줄 + Lease 표.
// 단축키: Del 선택 Lease 해제, Ctrl+Shift+Del 전체 해제, Ctrl+Enter 시작/중지.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/dhcp/config.dart';
import '../core/ipv4.dart';
import '../core/service.dart';
import '../l10n/app_localizations.dart';
import '../state/controller.dart';
import '../theme/app_theme.dart';
import 'actions.dart';
import 'lease_table.dart';
import 'widgets/status_pill.dart';

String serviceStateLabel(AppLocalizations l10n, ServiceState state) => switch (state) {
      ServiceState.stopped => l10n.stateStopped,
      ServiceState.starting => l10n.stateStarting,
      ServiceState.running => l10n.stateRunning,
      ServiceState.stopping => l10n.stateStopping,
      ServiceState.error => l10n.stateError,
    };

PillTone serviceStateTone(ServiceState state) => switch (state) {
      ServiceState.running => PillTone.success,
      ServiceState.starting || ServiceState.stopping => PillTone.warning,
      ServiceState.error => PillTone.danger,
      ServiceState.stopped => PillTone.neutral,
    };

/// 확인 중에는 서비스 상태가 아직 stopped이므로 "확인 중"을 따로 보여 준다.
String dhcpStatusLabel(AppLocalizations l10n, LabDaemonController c) =>
    c.checking ? l10n.stateChecking : serviceStateLabel(l10n, c.dhcpState);

PillTone dhcpStatusTone(LabDaemonController c) => c.checking ? PillTone.warning : serviceStateTone(c.dhcpState);

class DhcpView extends StatefulWidget {
  const DhcpView({super.key});

  @override
  State<DhcpView> createState() => _DhcpViewState();
}

class _DhcpViewState extends State<DhcpView> {
  Ipv4? _selected;

  void _releaseSelected() {
    final ip = _selected;
    if (ip != null) releaseLeaseWithFeedback(context, ip);
  }

  @override
  Widget build(BuildContext context) {
    final c = ControllerScope.of(context);
    final l10n = AppLocalizations.of(context);
    // 선택한 Lease가 사라졌으면 선택도 푼다.
    if (_selected != null && !c.leases.any((l) => l.ip == _selected)) _selected = null;
    final active = c.dhcpRunning || c.dhcpBusy;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): _releaseSelected,
        const SingleActivator(LogicalKeyboardKey.delete, control: true, shift: true): () => confirmReleaseAll(context),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => toggleDhcpWithFeedback(context),
      },
      child: Focus(
        autofocus: true,
        child: active
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusBar(controller: c),
                  _Toolbar(controller: c, canReleaseSelected: _selected != null, onReleaseSelected: _releaseSelected),
                  const Divider(height: 1),
                  Expanded(
                    child: LeaseTable(
                      leases: c.leases,
                      selected: _selected,
                      onSelect: (ip) => setState(() => _selected = ip),
                      onRelease: (ip) => releaseLeaseWithFeedback(context, ip),
                    ),
                  ),
                ],
              )
            : _EmptyState(controller: c, l10n: l10n),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.controller, required this.l10n});

  final LabDaemonController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = controller.dhcpState == ServiceState.error ? controller.startError : null;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icon/app_icon.png', width: 48, height: 48),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.homeEmptyTitle, style: theme.textTheme.titleMedium),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(error, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: () => startDhcpWithFeedback(context), child: Text(l10n.homeEmptyAction)),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.canReleaseSelected, required this.onReleaseSelected});

  final LabDaemonController controller;
  final bool canReleaseSelected;
  final VoidCallback onReleaseSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final running = controller.dhcpRunning;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: controller.dhcpBusy ? null : () => toggleDhcpWithFeedback(context),
            icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
            label: Text(running ? l10n.serviceStopTooltip : l10n.serviceStartTooltip),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: running && canReleaseSelected ? onReleaseSelected : null,
            icon: const Icon(Icons.link_off_rounded, size: 18),
            label: Text(l10n.leaseRelease),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton.icon(
            onPressed: running && controller.leases.isNotEmpty ? () => confirmReleaseAll(context) : null,
            icon: const Icon(Icons.layers_clear_outlined, size: 18),
            label: Text(l10n.leaseReleaseAll),
          ),
        ],
      ),
    );
  }
}

/// 서버 주소, 범위, 게이트웨이, Lease Time, 사용률, 통계를 한눈에 (PLAN.md §8).
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final LabDaemonController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final DhcpConfig? config = controller.dhcp.config;
    final stats = controller.dhcpStats;
    final started = controller.dhcpStartedAt;
    final mono = AppFonts.mono.copyWith(fontSize: theme.textTheme.bodyMedium?.fontSize);

    Widget item(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            Text(value, style: mono),
          ],
        );

    final used = controller.leases.length;
    final prefix = config?.mask.prefixLength;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.xl,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              StatusPill(label: dhcpStatusLabel(l10n, controller), tone: dhcpStatusTone(controller)),
              if (config != null) ...[
                item(l10n.statusServer, '${config.bindTo}'),
                item(l10n.statusPool, '${config.rangeStart} ~ ${config.rangeEnd}${prefix == null ? '' : ' /$prefix'}'),
                if (config.gateway != null) item(l10n.statusGateway, '${config.gateway}'),
                item(l10n.statusLeaseTime, config.leaseTime == null ? l10n.leaseUnlimited : _leaseText(controller)),
                Text(l10n.statusUsage(used, controller.leaseCapacity), style: mono),
              ],
              if (started != null) _Uptime(since: started, style: mono),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.statsLine(stats['discover'] ?? 0, stats['offer'] ?? 0, stats['request'] ?? 0, stats['ack'] ?? 0, stats['nak'] ?? 0),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _leaseText(LabDaemonController c) => c.dhcpSettings.leaseTime;
}

/// 가동 시간. 1초마다 스스로 다시 그린다.
class _Uptime extends StatefulWidget {
  const _Uptime({required this.since, required this.style});

  final DateTime since;
  final TextStyle style;

  @override
  State<_Uptime> createState() => _UptimeState();
}

class _UptimeState extends State<_Uptime> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = DateTime.now().difference(widget.since);
    final text = '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Text(AppLocalizations.of(context).statusUptime(text), style: widget.style);
  }
}
