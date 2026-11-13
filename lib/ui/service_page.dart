// 서비스 한 화면: 머리(이름·상태·요약·시작/중지) + 왼쪽 설정 패널 + 오른쪽 클라이언트 표 + 아래 그 서비스의 로그.
// 서비스마다 화면이 따로고(설정도 서비스마다 따로), 한 서비스의 갱신은 그 서비스 화면만 다시 그린다.
// 단축키: Ctrl+Enter 시작/중지 · Ctrl+B 설정 패널 접기/펴기 · Ctrl+F 로그 검색 · (DHCP) Del 선택 Lease 해제, Ctrl+Shift+Del 전체 해제.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/ipv4.dart';
import '../l10n/app_localizations.dart';
import '../state/controller.dart';
import '../state/service_model.dart';
import '../state/service_models.dart';
import '../theme/app_theme.dart';
import 'actions.dart';
import 'clients/client_tables.dart';
import 'format.dart';
import 'log_panel.dart';
import 'panels/service_panels.dart';
import 'widgets/status_pill.dart';

class ServicePage extends StatefulWidget {
  const ServicePage({super.key, required this.model});

  final ServiceModel model;

  @override
  State<ServicePage> createState() => _ServicePageState();
}

class _ServicePageState extends State<ServicePage> {
  final _searchFocus = FocusNode();
  double _logHeight = 240;
  double _dragStartY = 0;
  double _dragStartHeight = 240;
  late bool _panelOpen = widget.model.prefs.getBool('${widget.model.id}_panel_open') ?? true;
  Ipv4? _selectedLease;

  static const _minBody = 160.0;
  static const _minLog = 120.0;
  static const _panelWidth = 340.0;

  ServiceModel get model => widget.model;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  /// 설정 패널을 접고 펴고, 서비스마다 기억한다.
  void _togglePanel() {
    setState(() => _panelOpen = !_panelOpen);
    unawaited(model.prefs.setBool('${model.id}_panel_open', _panelOpen));
  }

  void _releaseSelected() {
    final m = model;
    final ip = _selectedLease;
    if (m is DhcpModel && ip != null) unawaited(releaseLeaseWithFeedback(context, m, ip));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ControllerScope.of(context);
    final m = model;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => toggleServiceWithFeedback(context, m),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): _togglePanel,
        if (m is DhcpModel) ...{
          const SingleActivator(LogicalKeyboardKey.delete): _releaseSelected,
          const SingleActivator(LogicalKeyboardKey.delete, control: true, shift: true): () => confirmReleaseAll(context, m),
        },
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: m,
              builder: (context, _) => _Header(model: m),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final maxLog = (constraints.maxHeight - _minBody).clamp(_minLog, double.infinity);
                      final logHeight = _logHeight.clamp(_minLog, maxLog);
                      return Column(
                        children: [
                          Expanded(child: ListenableBuilder(listenable: m, builder: (context, _) => _clients(context, m))),
                          MouseRegion(
                            cursor: SystemMouseCursors.resizeRow,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: (d) {
                                _dragStartY = d.globalPosition.dy;
                                _dragStartHeight = logHeight;
                              },
                              // 움직인 양을 더하지 않고 시작 위치와 지금 위치의 차로 높이를 정한다 (한계에서 멈췄다 돌아와도 손잡이가 마우스를 따라간다).
                              onVerticalDragUpdate: (d) => setState(() => _logHeight = (_dragStartHeight - (d.globalPosition.dy - _dragStartY)).clamp(_minLog, maxLog)),
                              child: const SizedBox(height: 8, child: Divider(height: 8)),
                            ),
                          ),
                          // 로그 패널은 모델이 아니라 그 서비스의 로그 버퍼를 직접 구독한다 (표 갱신과 따로 그린다).
                          SizedBox(height: logHeight, child: LogPanel(bus: m.logs, searchFocus: _searchFocus, onCapacity: m.setLogCapacity)),
                        ],
                      );
                    }),
                  ),
                  _PanelRail(open: _panelOpen, onToggle: _togglePanel),
                  // 접히는 설정 패널(오른쪽 dock): 너비 340 <-> 0으로 부드럽게 바뀌고, 완전히 접히면 트리에서 빠진다 (숨은 칸에 포커스가 가지 않는다).
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _panelOpen ? _panelWidth : 0),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, width, _) => width < 1
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: width,
                            child: ClipRect(
                              child: OverflowBox(
                                alignment: Alignment.centerRight,
                                minWidth: _panelWidth,
                                maxWidth: _panelWidth,
                                child: ListenableBuilder(
                                  listenable: m,
                                  builder: (context, _) => SingleChildScrollView(
                                    padding: const EdgeInsets.all(AppSpacing.lg),
                                    child: switch (m) {
                                      DhcpModel() => DhcpPanel(model: m, nics: controller.nics, onRefreshNics: controller.refreshNics),
                                      TftpModel() => TftpPanel(model: m, nics: controller.nics, onRefreshNics: controller.refreshNics),
                                      FtpModel() => FtpPanel(model: m, nics: controller.nics, onRefreshNics: controller.refreshNics),
                                      _ => const SizedBox.shrink(),
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clients(BuildContext context, ServiceModel m) {
    final l10n = AppLocalizations.of(context);
    if (!m.running && !m.busy) return _Stopped(model: m);
    switch (m) {
      case DhcpModel():
        if (_selectedLease != null && !m.leases.any((l) => l.ip == _selectedLease)) _selectedLease = null;
        return Column(children: [
          _Toolbar(children: [
            TextButton.icon(
              onPressed: _selectedLease == null ? null : _releaseSelected,
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(l10n.leaseRelease),
            ),
            TextButton.icon(
              onPressed: m.leases.isEmpty ? null : () => confirmReleaseAll(context, m),
              icon: const Icon(Icons.layers_clear_outlined, size: 18),
              label: Text(l10n.leaseReleaseAll),
            ),
          ]),
          Expanded(
            child: LeaseTable(
              leases: m.leases,
              selected: _selectedLease,
              onSelect: (ip) => setState(() => _selectedLease = ip),
              onRelease: (ip) => releaseLeaseWithFeedback(context, m, ip),
            ),
          ),
        ]);
      case TftpModel():
        final transfers = m.transfers?.transfers ?? const [];
        return Column(children: [
          _Toolbar(children: [
            _openRootButton(l10n, m.settings.rootDir),
            TextButton.icon(
              onPressed: transfers.any((t) => t.endedAt != null) ? m.clearRecent : null,
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: Text(l10n.tftpClearRecent),
            ),
          ]),
          Expanded(child: TftpTransferTable(transfers: transfers, onAbort: m.abort)),
        ]);
      case FtpModel():
        return Column(children: [
          _Toolbar(children: [_openRootButton(l10n, m.settings.rootDir)]),
          Expanded(child: FtpSessionTable(sessions: m.sessions?.sessions ?? const [], onDisconnect: m.disconnect)),
        ]);
    }
    return const SizedBox.shrink();
  }
}

/// 서비스가 켜져 있는 동안 루트 폴더를 탐색기로 열어 어떤 파일이 있는지 본다.
Widget _openRootButton(AppLocalizations l10n, String dir) => TextButton.icon(
      onPressed: dir.isEmpty ? null : () => Process.start('explorer.exe', [dir.replaceAll('/', r'\')], mode: ProcessStartMode.detached).ignore(),
      icon: const Icon(Icons.folder_open_outlined, size: 18),
      label: Text(l10n.openRootFolder),
    );

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: children),
      );
}

class _Stopped extends StatelessWidget {
  const _Stopped({required this.model});

  final ServiceModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = model.startError;
    final showError = error != null && !const {'invalidSettings', 'blocked', 'needsConfirmation'}.contains(error);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icon/app_icon.png', width: 48, height: 48),
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.homeEmptyTitle, style: theme.textTheme.titleMedium),
          if (showError) ...[
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(error, textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: () => startServiceWithFeedback(context, model), child: Text(l10n.homeEmptyAction)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.model});

  final ServiceModel model;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final running = model.running;
    final summary = _summary(l10n, model);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Text(serviceName(l10n, model.id), style: theme.textTheme.titleLarge),
          const SizedBox(width: AppSpacing.md),
          StatusPill(label: serviceStatusLabel(l10n, model), tone: serviceStatusTone(model)),
          if (model.startedAt != null) ...[
            const SizedBox(width: AppSpacing.md),
            _Uptime(since: model.startedAt!),
          ],
          if (model.firewallIssue != null) ...[
            const SizedBox(width: AppSpacing.md),
            ActionChip(
              avatar: Icon(Icons.shield_outlined, size: 16, color: theme.colorScheme.error),
              label: Text(l10n.firewallHintChip),
              visualDensity: VisualDensity.compact,
              onPressed: () => openFirewallHelp(context, model),
            ),
          ],
          const SizedBox(width: AppSpacing.lg),
          Expanded(child: Text(summary, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
          const SizedBox(width: AppSpacing.md),
          running
              ? OutlinedButton.icon(
                  onPressed: model.busy ? null : () => toggleServiceWithFeedback(context, model),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(l10n.serviceStopTooltip),
                )
              : FilledButton.icon(
                  onPressed: model.busy ? null : () => startServiceWithFeedback(context, model),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(l10n.serviceStartTooltip),
                ),
        ],
      ),
    );
  }

  static String _summary(AppLocalizations l10n, ServiceModel m) {
    if (!m.running) return '';
    switch (m) {
      case DhcpModel():
        final s = m.settings;
        final st = m.stats;
        return '${s.serverIp} · ${s.rangeStart} ~ ${s.rangeEnd} · ${l10n.statusUsage(m.leases.length, m.capacity)} · '
            '${l10n.statsLine(st['discover'] ?? 0, st['offer'] ?? 0, st['request'] ?? 0, st['ack'] ?? 0, st['nak'] ?? 0)}';
      case TftpModel():
        final t = m.transfers;
        return '${m.settings.bindIp.isEmpty ? '0.0.0.0' : m.settings.bindIp}:${m.settings.port} · '
            '${l10n.tftpSummary(t?.activeCount ?? 0, t?.completed ?? 0, t?.failed ?? 0, formatBytes(t?.bytesSent ?? 0), formatBytes(t?.bytesReceived ?? 0))}';
      case FtpModel():
        final f = m.sessions;
        return '${m.settings.bindIp.isEmpty ? '0.0.0.0' : m.settings.bindIp}:${m.settings.port} · '
            '${l10n.ftpSummary(f?.openCount ?? 0, f?.totalConnections ?? 0, formatBytes(f?.bytesIn ?? 0), formatBytes(f?.bytesOut ?? 0))}';
    }
    return '';
  }
}

/// 클라이언트 영역과 (오른쪽에 붙은) 설정 패널 사이의 얇은 띠: 누르면 패널을 접고 편다. 접혀 있으면 창 오른쪽 끝에 남고 세로 글씨 "설정"이 보인다.
class _PanelRail extends StatelessWidget {
  const _PanelRail({required this.open, required this.onToggle});

  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(children: [
      const VerticalDivider(width: 1),
      Tooltip(
        message: open ? l10n.panelCollapseTooltip : l10n.panelExpandTooltip,
        child: InkWell(
          onTap: onToggle,
          child: SizedBox(
            width: 28,
            child: Column(children: [
              const SizedBox(height: AppSpacing.sm),
              // 오른쪽에 붙은 패널: 접을 때는 오른쪽(>), 펼 때는 왼쪽(<)으로 향한다.
              Icon(open ? Icons.chevron_right_rounded : Icons.chevron_left_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
              if (!open) ...[
                const SizedBox(height: AppSpacing.md),
                RotatedBox(quarterTurns: 1, child: Text(l10n.panelRailLabel, style: theme.textTheme.titleSmall)),
              ],
            ]),
          ),
        ),
      ),
      if (open) const VerticalDivider(width: 1),
    ]);
  }
}

/// 가동 시간. 1초마다 스스로 다시 그린다.
class _Uptime extends StatefulWidget {
  const _Uptime({required this.since});

  final DateTime since;

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
  Widget build(BuildContext context) => Text(
        AppLocalizations.of(context).statusUptime(formatElapsed(DateTime.now().difference(widget.since))),
        style: AppFonts.mono.copyWith(fontSize: Theme.of(context).textTheme.bodySmall?.fontSize),
      );
}
