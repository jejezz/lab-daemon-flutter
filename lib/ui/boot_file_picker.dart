// DHCP의 부팅 파일(option 67)을 TFTP 서비스의 루트 폴더 안에서 고른다. 골라야 하는 이름은 TFTP 서버가 내줄 수 있는
// 경로(루트 기준 상대 경로, `/` 구분)와 같아야 하므로, 손으로 쓰다 틀리지 않게 폴더를 보여 준다.

import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'format.dart';

class BootFileCandidate {
  const BootFileCandidate(this.path, this.size);

  /// 루트 기준 상대 경로 (`/` 구분).
  final String path;
  final int size;
}

/// [root] 아래의 파일 목록 (경로순, 많으면 [limit]개까지). 폴더가 없으면 빈 목록.
Future<List<BootFileCandidate>> listBootCandidates(String root, {int limit = 2000}) async {
  final dir = Directory(root);
  if (root.trim().isEmpty || !await dir.exists()) return const [];
  final found = <BootFileCandidate>[];
  final prefix = dir.absolute.path.replaceAll(r'\', '/');
  final base = prefix.endsWith('/') ? prefix : '$prefix/';
  try {
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.absolute.path.replaceAll(r'\', '/');
      if (!path.startsWith(base)) continue;
      found.add(BootFileCandidate(path.substring(base.length), await entity.length()));
      if (found.length >= limit) break;
    }
  } catch (_) {
    // 읽다가 실패한 곳까지의 목록을 보여 준다.
  }
  found.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  return found;
}

/// 고른 상대 경로를 돌려준다 (취소하면 null).
Future<String?> pickBootFile(BuildContext context, String root) => showDialog<String>(
      context: context,
      builder: (context) => _BootFileDialog(root: root),
    );

class _BootFileDialog extends StatefulWidget {
  const _BootFileDialog({required this.root});

  final String root;

  @override
  State<_BootFileDialog> createState() => _BootFileDialogState();
}

class _BootFileDialogState extends State<_BootFileDialog> {
  late final Future<List<BootFileCandidate>> _files = listBootCandidates(widget.root);
  String _query = '';
  static const _shown = 200;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.dhcpBootPickTitle),
      content: SizedBox(
        width: 520,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search_rounded, size: 18), hintText: l10n.dhcpBootPickSearch, border: const OutlineInputBorder()),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: FutureBuilder<List<BootFileCandidate>>(
                future: _files,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final all = snapshot.data!;
                  final matches = [for (final f in all) if (_query.isEmpty || f.path.toLowerCase().contains(_query)) f];
                  if (matches.isEmpty) return Center(child: Text(l10n.dhcpBootPickEmpty, style: theme.textTheme.bodySmall));
                  final shown = matches.take(_shown).toList();
                  return Column(children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: shown.length,
                        itemExtent: 40,
                        itemBuilder: (context, i) => ListTile(
                          dense: true,
                          title: Text(shown[i].path, overflow: TextOverflow.ellipsis, style: AppFonts.userContent),
                          trailing: Text(formatBytes(shown[i].size), style: theme.textTheme.bodySmall),
                          onTap: () => Navigator.pop(context, shown[i].path),
                        ),
                      ),
                    ),
                    if (matches.length > shown.length) Text(l10n.dhcpBootPickMore(shown.length), style: theme.textTheme.bodySmall),
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel))],
    );
  }
}
