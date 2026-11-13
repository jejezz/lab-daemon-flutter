// 서비스 하나의 로그 패널: 최소 수준 필터, 검색(Ctrl+F), 일시정지, 지우기, 복사.
//
// 성능 (3CDaemon의 약점을 피한다):
//   - 서비스 Isolate가 보내는 묶음(최대 10번/초)마다 한 번만 다시 그린다 — 로그 한 줄마다 그리지 않는다.
//   - 목록은 보이는 줄만 만든다 (ListView.builder, 고정 줄 높이).
//   - 번역된 문구는 줄마다 한 번만 만들어 캐시한다 (Expando). 필터는 새 줄에만 적용하고(증분), 필터나 검색어를
//     바꿀 때만 전체를 다시 거른다.
//   - 화면의 버퍼도 최근 5000줄로 고정이다.

import 'dart:async';
import 'dart:collection';

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
  final _all = ListQueue<LogEvent>();
  var _visible = <LogEvent>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  StreamSubscription<LogEvent>? _subscription;
  LogLevel _minLevel = LogLevel.info;
  String _query = '';
  Timer? _redraw;
  bool _pendingScroll = false;

  /// 일시정지한 동안 들어온 줄 수. null이면 실시간.
  int? _pausedNew;

  /// 줄마다 번역 문구를 한 번만 만든다. 언어가 바뀌면 새 Expando로 바꾼다.
  var _texts = Expando<String>();
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    _all.addAll(widget.bus.history);
    _subscription = widget.bus.stream.listen(_onEvent);
  }

  @override
  void didUpdateWidget(LogPanel old) {
    super.didUpdateWidget(old);
    if (old.bus != widget.bus) {
      _subscription?.cancel();
      _all
        ..clear()
        ..addAll(widget.bus.history);
      _subscription = widget.bus.stream.listen(_onEvent);
      _refilter();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale != _locale) {
      _locale = locale;
      _texts = Expando<String>();
      _refilter();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _redraw?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String _text(LogEvent e) =>
      _texts[e] ??= formatLog(AppLocalizations.of(context), e);

  bool _matches(LogEvent e) {
    if (e.level.index < _minLevel.index) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return _text(e).toLowerCase().contains(q) ||
        (e.kind ?? '').toLowerCase().contains(q);
  }

  void _refilter() {
    _visible = [
      for (final e in _all)
        if (_matches(e)) e,
    ];
  }

  void _onEvent(LogEvent event) {
    _all.addLast(event);
    var removed = 0;
    while (_all.length > widget.bus.capacity) {
      _all.removeFirst();
      removed++;
    }
    if (_pausedNew != null) {
      _pausedNew = _pausedNew! + 1;
    } else {
      if (removed > 0) {
        _refilter();
      } else if (_matches(event)) {
        _visible.add(event);
      }
      _pendingScroll =
          !_scroll.hasClients ||
          _scroll.position.pixels >= _scroll.position.maxScrollExtent - 24;
    }
    // 묶음으로 들어오는 줄들을 한 번에 그린다.
    _redraw ??= Timer(const Duration(milliseconds: 50), () {
      _redraw = null;
      if (!mounted) return;
      setState(() {});
      if (_pendingScroll) {
        _pendingScroll = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    });
  }

  static String _levelName(AppLocalizations l10n, LogLevel level) => switch (level) {
    LogLevel.debug => l10n.logLevelDebug,
    LogLevel.info => l10n.logLevelInfo,
    LogLevel.warning => l10n.logLevelWarning,
    LogLevel.error => l10n.logLevelError,
  };

  static String _time(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }

  void _togglePause() => setState(() {
    if (_pausedNew == null) {
      _pausedNew = 0;
    } else {
      _pausedNew = null;
      _refilter();
    }
  });

  void _clear() {
    widget.bus.clear();
    setState(() {
      _all.clear();
      _visible = [];
      if (_pausedNew != null) _pausedNew = 0;
    });
  }

  Future<void> _copy(AppLocalizations l10n) async {
    final text = [
      for (final e in _visible)
        '${_time(e.time)} [${e.level.name.toUpperCase()}]${e.kind == null ? '' : ' ${e.kind}'} ${_text(e)}${e.detail == null ? '' : '\n${e.detail}'}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showInfoSnackBar(context, l10n.logCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final paused = _pausedNew != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Text(l10n.logTitle, style: theme.textTheme.titleSmall),
              const SizedBox(width: AppSpacing.md),
              // 최소 수준은 작은 메뉴 단추로 고른다 (좁은 창에서도 머리줄이 넘치지 않게).
              PopupMenuButton<LogLevel>(
                tooltip: l10n.logLevelTooltip,
                initialValue: _minLevel,
                onSelected: (level) => setState(() {
                  _minLevel = level;
                  _refilter();
                }),
                itemBuilder: (_) => [
                  for (final level in LogLevel.values)
                    CheckedPopupMenuItem(
                      value: level,
                      checked: level == _minLevel,
                      child: Text(_levelName(l10n, level)),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _levelName(l10n, _minLevel),
                        style: theme.textTheme.labelLarge,
                      ),
                      const Icon(Icons.arrow_drop_down_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // 검색 칸은 남는 폭에 맞춰 줄어든다 (좁은 창에서도 머리줄이 넘치지 않게).
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 220,
                      maxHeight: 32,
                    ),
                    child: TextField(
                      controller: _search,
                      focusNode: widget.searchFocus,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.logSearchHint,
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(AppRadius.button),
                          ),
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        _query = v;
                        _refilter();
                      }),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: paused ? l10n.logResume : l10n.logPause,
                iconSize: 20,
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                ),
                onPressed: _togglePause,
              ),
              IconButton(
                tooltip: l10n.logClear,
                iconSize: 20,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _clear,
              ),
              IconButton(
                tooltip: l10n.logCopy,
                iconSize: 20,
                icon: const Icon(Icons.copy_rounded),
                onPressed: _visible.isEmpty ? null : () => _copy(l10n),
              ),
            ],
          ),
        ),
        if (paused)
          Container(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 2,
            ),
            child: Text(
              l10n.logPausedBanner(_pausedNew!),
              style: theme.textTheme.labelMedium,
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: _visible.isEmpty
              ? Center(
                  child: Text(l10n.logEmpty, style: theme.textTheme.bodySmall),
                )
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    itemCount: _visible.length,
                    itemBuilder: (context, i) {
                      final e = _visible[i];
                      return _LogRow(
                        event: e,
                        text: _text(e),
                        time: _time(e.time),
                      );
                    },
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
      LogLevel.warning =>
        light ? AppColors.warningTextLight : AppColors.warning,
      LogLevel.error => light ? AppColors.dangerTextLight : AppColors.danger,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            style: base.copyWith(color: color),
            children: [
              TextSpan(
                text: '$time  ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (event.kind != null)
                TextSpan(
                  text: '${event.kind}  ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              TextSpan(text: text),
            ],
          ),
        ),
        if (event.detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Text(
              event.detail!,
              style: base.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}
