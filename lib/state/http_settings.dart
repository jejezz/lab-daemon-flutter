// HTTP 화면이 편집하는 값. 입력 중인 글자 그대로 저장하고, 서비스를 켤 때 [HttpSettings.toConfig]로 바꾼다.
// 저장 키는 `http_<이름>`이다 (localization.md §5).

import 'package:shared_preferences/shared_preferences.dart';

import '../core/http/config.dart';
import '../core/ipv4.dart';
import 'settings_common.dart';

enum HttpField { bindIp, port, rootDir, maxConnections, idleTimeout }

class HttpSettings {
  const HttpSettings({
    this.bindIp = '',
    this.port = '80',
    this.rootDir = '',
    this.allowListing = true,
    this.allowWrite = false,
    this.allowOverwrite = false,
    this.maxConnections = '64',
    this.idleTimeout = '30',
  });

  /// 비어 있으면 모든 NIC.
  final String bindIp;
  final String port;
  final String rootDir;
  final bool allowListing;
  final bool allowWrite;
  final bool allowOverwrite;
  final String maxConnections;
  final String idleTimeout;

  static const _prefix = 'http_';

  factory HttpSettings.load(SharedPreferences prefs) {
    const d = HttpSettings();
    String s(String k, String v) => prefs.getString('$_prefix$k') ?? v;
    bool b(String k, bool v) => prefs.getBool('$_prefix$k') ?? v;
    return HttpSettings(
      bindIp: s('bind_ip', d.bindIp),
      port: s('port', d.port),
      rootDir: s('root_dir', d.rootDir),
      allowListing: b('allow_listing', d.allowListing),
      allowWrite: b('allow_write', d.allowWrite),
      allowOverwrite: b('allow_overwrite', d.allowOverwrite),
      maxConnections: s('max_connections', d.maxConnections),
      idleTimeout: s('idle_timeout', d.idleTimeout),
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString('${_prefix}bind_ip', bindIp);
    await prefs.setString('${_prefix}port', port);
    await prefs.setString('${_prefix}root_dir', rootDir);
    await prefs.setBool('${_prefix}allow_listing', allowListing);
    await prefs.setBool('${_prefix}allow_write', allowWrite);
    await prefs.setBool('${_prefix}allow_overwrite', allowOverwrite);
    await prefs.setString('${_prefix}max_connections', maxConnections);
    await prefs.setString('${_prefix}idle_timeout', idleTimeout);
  }

  String valueOf(HttpField f) => switch (f) {
        HttpField.bindIp => bindIp,
        HttpField.port => port,
        HttpField.rootDir => rootDir,
        HttpField.maxConnections => maxConnections,
        HttpField.idleTimeout => idleTimeout,
      };

  HttpSettings withValue(HttpField f, String v) => copyWith(
        bindIp: f == HttpField.bindIp ? v : null,
        port: f == HttpField.port ? v : null,
        rootDir: f == HttpField.rootDir ? v : null,
        maxConnections: f == HttpField.maxConnections ? v : null,
        idleTimeout: f == HttpField.idleTimeout ? v : null,
      );

  HttpSettings copyWith({
    String? bindIp,
    String? port,
    String? rootDir,
    bool? allowListing,
    bool? allowWrite,
    bool? allowOverwrite,
    String? maxConnections,
    String? idleTimeout,
  }) =>
      HttpSettings(
        bindIp: bindIp ?? this.bindIp,
        port: port ?? this.port,
        rootDir: rootDir ?? this.rootDir,
        allowListing: allowListing ?? this.allowListing,
        allowWrite: allowWrite ?? this.allowWrite,
        allowOverwrite: allowOverwrite ?? this.allowOverwrite,
        maxConnections: maxConnections ?? this.maxConnections,
        idleTimeout: idleTimeout ?? this.idleTimeout,
      );

  Map<HttpField, FieldError> validate() => {
        for (final (f, e) in [
          (HttpField.bindIp, checkOptionalIp(bindIp)),
          (HttpField.port, checkPort(port)),
          (HttpField.rootDir, checkDirectory(rootDir)),
          (HttpField.maxConnections, checkInt(maxConnections, 1, 10000)),
          (HttpField.idleTimeout, checkInt(idleTimeout, 1, 3600)),
        ])
          f: ?e,
      };

  HttpConfig toConfig() => HttpConfig(
        rootDir: rootDir.trim(),
        bindAddress: bindIp.trim().isEmpty ? null : Ipv4.parse(bindIp),
        port: int.parse(port.trim()),
        allowListing: allowListing,
        allowWrite: allowWrite,
        allowOverwrite: allowOverwrite,
        maxConnections: int.parse(maxConnections.trim()),
        idleTimeoutSeconds: int.parse(idleTimeout.trim()),
      );
}
