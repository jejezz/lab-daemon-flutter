// 하단 로그 패널: 모든 서비스의 로그를 시간순으로 보여 준다. 최소 수준 필터, 검색(Ctrl+F),
// 일시정지, 지우기, 복사. 일시정지 중에도 로그는 계속 쌓이고, 배너가 새 로그 수를 알려 준다.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'log_format.dart';
import 'widgets/error_snackbar.dart';

class LogPanel extends StatefulWidget {
  const LogPanel({super.key, required this.bus, required this.searchFocus});

  final LogBus bus;
  final FocusNode searchFocus;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _all = <LogEvent>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  StreamSubscription<LogEvent>? _subscription;
  LogLevel _minLevel = LogLevel.info;
  String _query = '';

  /// 일시정지한 시점의 로그 수. null이면 실시간.
  int? _pausedAt;

  @override
  void initState() {
    super.initState();
    _all.addAll(widget.bus.history);
    _subscription = widget.bus.stream.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onEvent(LogEvent event) {
    final stick = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    setState(() {
      _all.add(event);
      final overflow = _all.length - widget.bus.capacity;
      if (overflow > 0) {
        _all.removeRange(0, overflow);
        if (_pausedAt != null) _pausedAt = (_pausedAt! - overflow).clamp(0, _all.length);
      }
    });
    if (stick && _pausedAt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  List<LogEvent> _visible(AppLocalizations l10n) {
    final source = _pausedAt == null ? _all : _all.sublist(0, _pausedAt!);
    final q = _query.trim().toLowerCase();
    return [
      for (final e in source)
        if (e.level.index >= _minLevel.index &&
            (q.isEmpty ||
                formatLog(l10n, e).toLowerCase().contains(q) ||
                (e.kind ?? '').toLowerCase().contains(q) ||
                e.service.contains(q)))
          e,
    ];
  }

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  String _plainText(AppLocalizations l10n, List<LogEvent> events) => [
        for (final e in events)
          '${_time(e.time)} [${e.level.name.toUpperCase()}] ${e.service}${e.kind == null ? '' : ' ${e.kind}'} ${formatLog(l10n, e)}'
              '${e.detail == null ? '' : '\n${e.detail}'}',
      ].join('\n');

  void _togglePause() => setState(() => _pausedAt = _pausedAt == null ? _all.length : null);

  void _clear() {
    widget.bus.clear();
    setState(() {
      _all.clear();
      if (_pausedAt != null) _pausedAt = 0;
    });
  }

  Future<void> _copy(AppLocalizations l10n, List<LogEvent> events) async {
    await Clipboard.setData(ClipboardData(text: _plainText(l10n, events)));
    if (mounted) showInfoSnackBar(context, l10n.logCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final events = _visible(l10n);
    final paused = _pausedAt != null;
    final waiting = paused ? _all.length - _pausedAt! : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Row(
            children: [
              Text(l10n.logTitle, style: theme.textTheme.titleSmall),
              const SizedBox(width: AppSpacing.lg),
              SegmentedButton<LogLevel>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: LogLevel.debug, label: Text(l10n.logLevelDebug)),
                  ButtonSegment(value: LogLevel.info, label: Text(l10n.logLevelInfo)),
                  ButtonSegment(value: LogLevel.warning, label: Text(l10n.logLevelWarning)),
                  ButtonSegment(value: LogLevel.error, label: Text(l10n.logLevelError)),
                ],
                selected: {_minLevel},
                onSelectionChanged: (s) => setState(() => _minLevel = s.first),
              ),
              const Spacer(),
              SizedBox(
                width: 220,
                height: 32,
                child: TextField(
                  controller: _search,
                  focusNode: widget.searchFocus,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.logSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.button))),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              IconButton(
                tooltip: paused ? l10n.logResume : l10n.logPause,
                iconSize: 20,
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                onPressed: _togglePause,
              ),
              IconButton(tooltip: l10n.logClear, iconSize: 20, icon: const Icon(Icons.delete_sweep_outlined), onPressed: _clear),
              IconButton(
                tooltip: l10n.logCopy,
                iconSize: 20,
                icon: const Icon(Icons.copy_rounded),
                onPressed: events.isEmpty ? null : () => _copy(l10n, events),
              ),
            ],
          ),
        ),
        if (paused)
          Container(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
            child: Text(l10n.logPausedBanner(waiting), style: theme.textTheme.labelMedium),
          ),
        const Divider(height: 1),
        Expanded(
          child: events.isEmpty
              ? Center(child: Text(l10n.logEmpty, style: theme.textTheme.bodySmall))
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    itemCount: events.length,
                    itemBuilder: (context, i) => _LogRow(event: events[i], text: formatLog(l10n, events[i]), time: _time(events[i].time)),
                  ),
                ),
        ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.event, required this.text, required this.time});

  final LogEvent event;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final base = AppFonts.mono.copyWith(fontSize: 12, height: 1.45);
    final color = switch (event.level) {
      LogLevel.debug => theme.colorScheme.onSurfaceVariant,
      LogLevel.info => theme.colorScheme.onSurface,
      LogLevel.warning => light ? AppColors.warningTextLight : AppColors.warning,
      LogLevel.error => light ? AppColors.dangerTextLight : AppColors.danger,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(style: base.copyWith(color: color), children: [
            TextSpan(text: '$time  ', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            if (event.kind != null) TextSpan(text: '${event.kind}  ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: text),
          ]),
        ),
        if (event.detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Text(event.detail!, style: base.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
          ),
      ],
    );
  }
}
