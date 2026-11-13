// 서비스별 "지금 서비스 중인 클라이언트" 표: DHCP Lease, TFTP 전송, FTP 세션.
// 표는 서비스가 보낸 최신 스냅샷만 그린다 (스냅샷은 최대 4~5번/초). 보이는 행만 만들고(고정 행 높이),
// 시간 표시는 1초 간격 타이머 하나로 갱신한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/dhcp/pool.dart';
import '../../core/dhcp/server.dart';
import '../../core/ftp/server.dart';
import '../../core/ipv4.dart';
import '../../core/tftp/server.dart';
import '../../core/tftp/transfer.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../format.dart';
import '../log_format.dart';
import '../widgets/status_pill.dart';

/// 머리글 + 행 목록 + 빈 상태. [flex]는 열 너비 비율, 마지막 [actionWidth]는 줄 끝 단추 자리.
class _Table extends StatelessWidget {
  const _Table({
    required this.headers,
    required this.flex,
    required this.rowCount,
    required this.rowBuilder,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
  });

  final List<String> headers;
  final List<int> flex;
  final int rowCount;
  final Widget Function(BuildContext context, int index) rowBuilder;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  static const actionWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (rowCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(emptyIcon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text(emptyTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(emptyHint, style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }
    final headerStyle = theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(children: [
            for (var i = 0; i < headers.length; i++) Expanded(flex: flex[i], child: Text(headers[i], style: headerStyle)),
            SizedBox(width: actionWidth),
          ]),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(child: ListView.builder(itemCount: rowCount, itemExtent: 38, itemBuilder: rowBuilder)),
      ],
    );
  }
}

TextStyle _mono(BuildContext context) => AppFonts.mono.copyWith(fontSize: Theme.of(context).textTheme.bodyMedium?.fontSize);

/// 1초마다 다시 그려서 남은 시간·접속 시간을 갱신한다 (보일 행이 있을 때만).
mixin _Ticking<T extends StatefulWidget> on State<T> {
  Timer? _ticker;

  bool get needsTick;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && needsTick) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

// ---- DHCP -------------------------------------------------------------------------------------

class LeaseTable extends StatefulWidget {
  const LeaseTable({super.key, required this.leases, required this.selected, required this.onSelect, required this.onRelease, this.now});

  final List<LeaseInfo> leases;
  final Ipv4? selected;
  final ValueChanged<Ipv4?> onSelect;
  final ValueChanged<Ipv4> onRelease;
  final DateTime Function()? now;

  @override
  State<LeaseTable> createState() => _LeaseTableState();
}

class _LeaseTableState extends State<LeaseTable> with _Ticking {
  @override
  bool get needsTick => widget.leases.any((l) => l.expiresAt != null);

  Future<void> _menu(BuildContext context, Offset position, LeaseInfo lease) async {
    final l10n = AppLocalizations.of(context);
    widget.onSelect(lease.ip);
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: true,
          height: 36,
          child: Row(children: [Expanded(child: Text(l10n.leaseRelease)), Text('Del', style: Theme.of(context).textTheme.labelSmall)]),
        ),
      ],
    );
    if (choice == true) widget.onRelease(lease.ip);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = (widget.now ?? DateTime.now)();
    final mono = _mono(context);
    final scheme = Theme.of(context).colorScheme;
    const flex = [3, 4, 4, 2, 3];
    return _Table(
      headers: [l10n.leaseColIp, l10n.leaseColMac, l10n.leaseColHostname, l10n.leaseColState, l10n.leaseColRemaining],
      flex: flex,
      rowCount: widget.leases.length,
      emptyIcon: Icons.devices_other_outlined,
      emptyTitle: l10n.leaseEmptyTitle,
      emptyHint: l10n.leaseEmptyHint,
      rowBuilder: (context, i) {
        final lease = widget.leases[i];
        final remaining = lease.expiresAt?.difference(now);
        final bound = lease.state == LeaseState.bound;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (d) => _menu(context, d.globalPosition, lease),
          child: InkWell(
            onTap: () => widget.onSelect(lease.ip),
            splashFactory: NoSplash.splashFactory,
            child: Container(
              color: lease.ip == widget.selected ? scheme.primary.withValues(alpha: 0.12) : null,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(children: [
                Expanded(flex: flex[0], child: Text('${lease.ip}', style: mono)),
                Expanded(flex: flex[1], child: Text('${lease.mac}', style: mono)),
                Expanded(flex: flex[2], child: Text(lease.hostname ?? '', overflow: TextOverflow.ellipsis, style: AppFonts.userContent)),
                Expanded(
                  flex: flex[3],
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(label: bound ? l10n.leaseStateBound : l10n.leaseStateOffered, tone: bound ? PillTone.success : PillTone.warning),
                  ),
                ),
                Expanded(
                  flex: flex[4],
                  child: Text(remaining == null ? l10n.leaseUnlimited : formatElapsed(remaining.isNegative ? Duration.zero : remaining), style: mono),
                ),
                SizedBox(
                  width: 44,
                  child: IconButton(
                    tooltip: l10n.leaseRelease,
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.link_off_rounded),
                    onPressed: () => widget.onRelease(lease.ip),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ---- TFTP -------------------------------------------------------------------------------------

class TftpTransferTable extends StatelessWidget {
  const TftpTransferTable({super.key, required this.transfers, required this.onAbort});

  final List<TftpTransferInfo> transfers;
  final ValueChanged<int> onAbort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mono = _mono(context);
    const flex = [3, 4, 2, 4, 2, 2];
    return _Table(
      headers: [l10n.tftpColClient, l10n.tftpColFile, l10n.tftpColDirection, l10n.tftpColProgress, l10n.tftpColRate, l10n.tftpColState],
      flex: flex,
      rowCount: transfers.length,
      emptyIcon: Icons.swap_vert_rounded,
      emptyTitle: l10n.tftpEmptyTitle,
      emptyHint: l10n.tftpEmptyHint,
      rowBuilder: (context, i) {
        final t = transfers[i];
        final active = t.state == TransferState.active;
        final (label, tone) = switch (t.state) {
          TransferState.active => (l10n.tftpStateActive, PillTone.warning),
          TransferState.done => (l10n.tftpStateDone, PillTone.success),
          TransferState.failed => (l10n.tftpStateFailed, PillTone.danger),
        };
        final size = t.size;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(children: [
            Expanded(flex: flex[0], child: Text(t.client, style: mono, overflow: TextOverflow.ellipsis)),
            Expanded(flex: flex[1], child: Text(t.file, overflow: TextOverflow.ellipsis, style: AppFonts.userContent)),
            Expanded(
              flex: flex[2],
              child: Row(children: [
                Icon(t.upload ? Icons.south_rounded : Icons.north_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(child: Text(t.upload ? l10n.tftpUpload : l10n.tftpDownload, overflow: TextOverflow.ellipsis)),
              ]),
            ),
            Expanded(
              flex: flex[3],
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(size == null ? formatBytes(t.bytes) : '${formatBytes(t.bytes)} / ${formatBytes(size)}', style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                    if (active) LinearProgressIndicator(value: t.progress, minHeight: 3),
                  ],
                ),
              ),
            ),
            Expanded(flex: flex[4], child: Text(active ? formatRate(t.rate) : '', style: theme.textTheme.bodySmall)),
            Expanded(
              flex: flex[5],
              child: Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message: t.failure == null ? '' : '${tftpReason(l10n, t.failure)}${t.failureDetail == null ? '' : ' — ${t.failureDetail}'}',
                  child: StatusPill(label: label, tone: tone),
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: active
                  ? IconButton(
                      tooltip: l10n.tftpAbort,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => onAbort(t.id),
                    )
                  : null,
            ),
          ]),
        );
      },
    );
  }
}

// ---- FTP --------------------------------------------------------------------------------------

class FtpSessionTable extends StatefulWidget {
  const FtpSessionTable({super.key, required this.sessions, required this.onDisconnect});

  final List<FtpSessionInfo> sessions;
  final ValueChanged<int> onDisconnect;

  @override
  State<FtpSessionTable> createState() => _FtpSessionTableState();
}

class _FtpSessionTableState extends State<FtpSessionTable> with _Ticking {
  @override
  bool get needsTick => widget.sessions.any((s) => !s.closed);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mono = _mono(context);
    final now = DateTime.now();
    const flex = [3, 2, 3, 5, 3, 2];
    return _Table(
      headers: [l10n.ftpColClient, l10n.ftpColUser, l10n.ftpColDir, l10n.ftpColActivity, l10n.ftpColTraffic, l10n.ftpColConnected],
      flex: flex,
      rowCount: widget.sessions.length,
      emptyIcon: Icons.lan_outlined,
      emptyTitle: l10n.ftpEmptyTitle,
      emptyHint: l10n.ftpEmptyHint,
      rowBuilder: (context, i) {
        final s = widget.sessions[i];
        final dim = s.closed ? theme.colorScheme.onSurfaceVariant : null;
        final file = s.transferFile;
        final activity = file == null
            ? s.lastCommand
            : '${s.transferUpload ? l10n.ftpUploading(file) : l10n.ftpDownloading(file)} · ${formatBytes(s.transferBytes)} · ${formatRate(s.transferRate)}';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(children: [
            Expanded(flex: flex[0], child: Text(s.client, style: mono.copyWith(color: dim), overflow: TextOverflow.ellipsis)),
            Expanded(
              flex: flex[1],
              child: Text(s.authenticated ? (s.user ?? '') : l10n.ftpNotLoggedIn, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim)),
            ),
            Expanded(flex: flex[2], child: Text(s.cwd, overflow: TextOverflow.ellipsis, style: AppFonts.userContent.copyWith(color: dim))),
            Expanded(flex: flex[3], child: Text(activity, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: dim))),
            Expanded(flex: flex[4], child: Text('${formatBytes(s.bytesIn)} / ${formatBytes(s.bytesOut)}', style: theme.textTheme.bodySmall?.copyWith(color: dim))),
            Expanded(
              flex: flex[5],
              child: s.closed
                  ? Align(alignment: Alignment.centerLeft, child: StatusPill(label: l10n.ftpClosed))
                  : Text(formatElapsed(now.difference(s.connectedAt)), style: mono),
            ),
            SizedBox(
              width: 44,
              child: s.closed
                  ? null
                  : IconButton(
                      tooltip: l10n.ftpDisconnect,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.power_settings_new_rounded),
                      onPressed: () => widget.onDisconnect(s.id),
                    ),
            ),
          ]),
        );
      },
    );
  }
}
