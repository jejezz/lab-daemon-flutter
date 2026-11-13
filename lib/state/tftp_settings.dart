// TFTP 화면이 편집하는 값. 입력 중인 글자 그대로 저장하고, 서비스를 켤 때 [TftpSettings.toConfig]로 바꾼다.
// 저장 키는 `tftp_<이름>`이다 (localization.md §5).

import 'package:shared_preferences/shared_preferences.dart';

import '../core/ipv4.dart';
import '../core/tftp/config.dart';
import 'settings_common.dart';

enum TftpField { bindIp, port, rootDir, maxBlockSize, maxWindowSize, timeoutMs, maxTransfers }

class TftpSettings {
  const TftpSettings({
    this.bindIp = '',
    this.port = '69',
    this.rootDir = '',
    this.allowWrite = false,
    this.allowOverwrite = false,
    this.maxBlockSize = '1468',
    this.maxWindowSize = '8',
    this.timeoutMs = '2000',
    this.maxTransfers = '64',
    this.logPackets = false,
  });

  /// 비어 있으면 모든 NIC.
  final String bindIp;
  final String port;
  final String rootDir;
  final bool allowWrite;
  final bool allowOverwrite;
  final String maxBlockSize;
  final String maxWindowSize;
  final String timeoutMs;
  final String maxTransfers;
  final bool logPackets;

  static const _prefix = 'tftp_';

  factory TftpSettings.load(SharedPreferences prefs) {
    const d = TftpSettings();
    String s(String k, String v) => prefs.getString('$_prefix$k') ?? v;
    bool b(String k, bool v) => prefs.getBool('$_prefix$k') ?? v;
    return TftpSettings(
      bindIp: s('bind_ip', d.bindIp),
      port: s('port', d.port),
      rootDir: s('root_dir', d.rootDir),
      allowWrite: b('allow_write', d.allowWrite),
      allowOverwrite: b('allow_overwrite', d.allowOverwrite),
      maxBlockSize: s('max_block_size', d.maxBlockSize),
      maxWindowSize: s('max_window_size', d.maxWindowSize),
      timeoutMs: s('timeout_ms', d.timeoutMs),
      maxTransfers: s('max_transfers', d.maxTransfers),
      logPackets: b('log_packets', d.logPackets),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('${_prefix}bind_ip', bindIp);
    await prefs.setString('${_prefix}port', port);
    await prefs.setString('${_prefix}root_dir', rootDir);
    await prefs.setBool('${_prefix}allow_write', allowWrite);
    await prefs.setBool('${_prefix}allow_overwrite', allowOverwrite);
    await prefs.setString('${_prefix}max_block_size', maxBlockSize);
    await prefs.setString('${_prefix}max_window_size', maxWindowSize);
    await prefs.setString('${_prefix}timeout_ms', timeoutMs);
    await prefs.setString('${_prefix}max_transfers', maxTransfers);
    await prefs.setBool('${_prefix}log_packets', logPackets);
  }

  String valueOf(TftpField f) => switch (f) {
        TftpField.bindIp => bindIp,
        TftpField.port => port,
        TftpField.rootDir => rootDir,
        TftpField.maxBlockSize => maxBlockSize,
        TftpField.maxWindowSize => maxWindowSize,
        TftpField.timeoutMs => timeoutMs,
        TftpField.maxTransfers => maxTransfers,
      };

  TftpSettings withValue(TftpField f, String v) => copyWith(
        bindIp: f == TftpField.bindIp ? v : null,
        port: f == TftpField.port ? v : null,
        rootDir: f == TftpField.rootDir ? v : null,
        maxBlockSize: f == TftpField.maxBlockSize ? v : null,
        maxWindowSize: f == TftpField.maxWindowSize ? v : null,
        timeoutMs: f == TftpField.timeoutMs ? v : null,
        maxTransfers: f == TftpField.maxTransfers ? v : null,
      );

  TftpSettings copyWith({
    String? bindIp,
    String? port,
    String? rootDir,
    bool? allowWrite,
    bool? allowOverwrite,
    String? maxBlockSize,
    String? maxWindowSize,
    String? timeoutMs,
    String? maxTransfers,
    bool? logPackets,
  }) =>
      TftpSettings(
        bindIp: bindIp ?? this.bindIp,
        port: port ?? this.port,
        rootDir: rootDir ?? this.rootDir,
        allowWrite: allowWrite ?? this.allowWrite,
        allowOverwrite: allowOverwrite ?? this.allowOverwrite,
        maxBlockSize: maxBlockSize ?? this.maxBlockSize,
        maxWindowSize: maxWindowSize ?? this.maxWindowSize,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        maxTransfers: maxTransfers ?? this.maxTransfers,
        logPackets: logPackets ?? this.logPackets,
      );

  Map<TftpField, FieldError> validate() => {
        for (final (f, e) in [
          (TftpField.bindIp, checkOptionalIp(bindIp)),
          (TftpField.port, checkPort(port)),
          (TftpField.rootDir, checkDirectory(rootDir)),
          (TftpField.maxBlockSize, checkInt(maxBlockSize, 8, 65464)),
          (TftpField.maxWindowSize, checkInt(maxWindowSize, 1, 64)),
          (TftpField.timeoutMs, checkInt(timeoutMs, 50, 60000)),
          (TftpField.maxTransfers, checkInt(maxTransfers, 1, 1000)),
        ])
          f: ?e,
      };

  TftpConfig toConfig() => TftpConfig(
        rootDir: rootDir.trim(),
        bindAddress: bindIp.trim().isEmpty ? null : Ipv4.parse(bindIp),
        port: int.parse(port.trim()),
        allowWrite: allowWrite,
        allowOverwrite: allowOverwrite,
        maxBlockSize: int.parse(maxBlockSize.trim()),
        maxWindowSize: int.parse(maxWindowSize.trim()),
        timeoutMs: int.parse(timeoutMs.trim()),
        maxTransfers: int.parse(maxTransfers.trim()),
        logPackets: logPackets,
      );
}
