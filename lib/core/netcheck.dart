// 서비스를 켜기 직전의 점검: 포트를 이미 다른 프로그램이 쓰는지, Windows 방화벽이 들어오는 연결을 막을지.
// 앱을 시작할 때가 아니라 **서비스를 시작할 때** 그 서비스의 포트만 점검한다.
//
// 속도와 언어: PowerShell의 NetSecurity/NetTCPIP cmdlet은 모듈을 읽느라 10초 가까이 걸리고, `netsh`는 한국어
// Windows에서 출력이 번역돼 파싱이 깨진다. 그래서 `netstat -ano`(포트 소유자)와 `reg query`(방화벽 규칙과
// 프로필 — 값 이름이 언어와 무관하고 일반 권한으로 읽힌다)만 쓴다. 전체가 0.5초 안팎이다.
//
// 한계: 방화벽 판정은 "이 프로그램이나 이 포트를 허용하는 규칙이 있는가"를 규칙 저장소에서 읽어 추정한다.
// 그룹 정책(GPO) 규칙과 서비스·주소 조건이 붙은 규칙은 보지 않는다. 그래서 결과는 경고이고 시작을 막지 않는다.
// 포트 충돌은 확실하므로(실제 바인딩도 실패한다) 시작을 막는다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ipv4.dart';

enum IssueKind { portInUse, firewallBlocked, otherDhcpServer, portsReserved }

/// 서비스를 켜기 전에 알아낸 문제 하나. [blocking]이면 켤 수 없고, 아니면 경고라서 사용자가 그래도 켤 수 있다.
class PreStartIssue {
  const PreStartIssue(this.kind, {required this.blocking, this.args = const {}});

  final IssueKind kind;
  final bool blocking;

  /// 화면과 로그가 문구를 채울 값 (번역하지 않는다).
  final Map<String, Object?> args;
}

class PreStartPort {
  const PreStartPort(this.protocol, this.port);

  /// `UDP` 또는 `TCP`.
  final String protocol;
  final int port;

  @override
  String toString() => '$protocol $port';

  @override
  bool operator ==(Object other) => other is PreStartPort && other.protocol == protocol && other.port == port;

  @override
  int get hashCode => Object.hash(protocol, port);
}

/// 외부 명령을 실행하고 표준 출력을 돌려준다. 시험에서 바꿔 끼운다.
typedef CommandRunner = Future<String> Function(String executable, List<String> arguments);

Future<String> runCommand(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments, stdoutEncoding: systemEncoding).timeout(const Duration(seconds: 8));
  return result.stdout as String;
}

// ---- 포트 소유자 (netstat) -------------------------------------------------------------------------

class SocketOwner {
  const SocketOwner({required this.protocol, required this.address, required this.port, required this.pid});

  final String protocol;
  final String address;
  final int port;
  final int pid;
}

/// `netstat -ano -p UDP|TCP` 출력에서 열려 있는 소켓을 읽는다. 머리글은 번역되지만 데이터 줄의 프로토콜 이름과
/// 열 위치는 같다. TCP는 상태 글자(번역될 수 있음) 대신 "원격 주소가 0.0.0.0:0"인 줄만 듣는 소켓으로 본다.
List<SocketOwner> parseNetstat(String output, String protocol) {
  final owners = <SocketOwner>[];
  for (final line in const LineSplitter().convert(output)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.toUpperCase() != protocol) continue;
    if (protocol == 'UDP' && parts.length < 4) continue;
    if (protocol == 'TCP' && (parts.length < 5 || !(parts[2] == '0.0.0.0:0' || parts[2] == '[::]:0'))) continue;
    final local = parts[1];
    final colon = local.lastIndexOf(':');
    if (colon < 0) continue;
    final port = int.tryParse(local.substring(colon + 1));
    final pid = int.tryParse(parts.last);
    if (port == null || pid == null) continue;
    owners.add(SocketOwner(protocol: protocol, address: local.substring(0, colon), port: port, pid: pid));
  }
  return owners;
}

/// [bindAddress]에 [port]를 묶으려 할 때 부딪히는 소켓: 같은 주소이거나 모든 주소(0.0.0.0)에 묶인 것.
List<SocketOwner> conflictsFor(List<SocketOwner> owners, Ipv4 bindAddress, PreStartPort port) => [
      for (final o in owners)
        if (o.protocol == port.protocol && o.port == port.port && (o.address == '0.0.0.0' || o.address == '$bindAddress')) o,
    ];

String? parseTasklistName(String output) {
  final line = const LineSplitter().convert(output).firstWhere((l) => l.startsWith('"'), orElse: () => '');
  if (line.isEmpty) return null;
  final end = line.indexOf('","');
  return end < 0 ? null : line.substring(1, end);
}

// ---- 예약된 포트 범위 (netsh) ------------------------------------------------------------------------

/// `netsh int ipv4 show excludedportrange protocol=tcp|udp` 출력의 예약 범위. 머리글은 번역되지만 숫자 두 개로
/// 된 줄의 형식은 같다. 끝의 `*`(관리자가 지정한 예약)는 무시한다.
List<(int, int)> parseExcludedRanges(String output) {
  final ranges = <(int, int)>[];
  for (final line in const LineSplitter().convert(output)) {
    final m = RegExp(r'^\s*(\d+)\s+(\d+)\s*\*?\s*$').firstMatch(line);
    if (m == null) continue;
    ranges.add((int.parse(m.group(1)!), int.parse(m.group(2)!)));
  }
  return ranges;
}

/// [low]..[high] 중 예약되지 않은 포트 수와 겹치는 예약 구간들.
(int, List<(int, int)>) availableInRange(int low, int high, List<(int, int)> excluded) {
  final hits = <(int, int)>[];
  for (final r in excluded) {
    if (r.$2 >= low && r.$1 <= high) hits.add((r.$1 < low ? low : r.$1, r.$2 > high ? high : r.$2));
  }
  var free = 0;
  for (var p = low; p <= high; p++) {
    if (!hits.any((h) => p >= h.$1 && p <= h.$2)) free++;
  }
  return (free, hits);
}

// ---- 방화벽 (레지스트리) ---------------------------------------------------------------------------

const _policyKey = r'HKLM\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy';
const _gpoKey = r'HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall';

/// 프로필 이름은 레지스트리의 것 그대로 쓴다. `Standard`가 화면의 "개인(Private)"이다.
const firewallProfiles = ['Domain', 'Standard', 'Public'];

class FirewallProfileState {
  const FirewallProfileState({required this.name, required this.enabled, required this.blocksInbound});

  final String name;
  final bool enabled;

  /// 허용 규칙이 없는 들어오는 연결을 막는 것이 기본인가.
  final bool blocksInbound;
}

FirewallProfileState parseProfile(String name, String policyOutput, [String gpoOutput = '']) {
  int? value(String output, String key) {
    final m = RegExp('^\\s+$key\\s+REG_DWORD\\s+0x([0-9a-fA-F]+)', multiLine: true).firstMatch(output);
    return m == null ? null : int.parse(m.group(1)!, radix: 16);
  }

  final enabled = value(gpoOutput, 'EnableFirewall') ?? value(policyOutput, 'EnableFirewall') ?? 1;
  final inbound = value(gpoOutput, 'DefaultInboundAction') ?? value(policyOutput, 'DefaultInboundAction') ?? 1;
  return FirewallProfileState(name: name, enabled: enabled != 0, blocksInbound: inbound != 0);
}

class FirewallRule {
  const FirewallRule({
    required this.allow,
    required this.profiles,
    required this.protocol,
    required this.ports,
    required this.program,
    required this.name,
  });

  final bool allow;

  /// 비어 있으면 모든 프로필.
  final Set<String> profiles;

  /// null이면 모든 프로토콜. TCP는 6, UDP는 17.
  final int? protocol;

  /// 비어 있으면 모든 포트.
  final List<(int, int)> ports;

  /// null이면 모든 프로그램.
  final String? program;
  final String name;

  bool coversProfile(String profile) => profiles.isEmpty || profiles.contains(profile);

  bool coversPort(PreStartPort p) {
    final proto = p.protocol == 'UDP' ? 17 : 6;
    if (protocol != null && protocol != 256 && protocol != proto) return false;
    return ports.isEmpty || ports.any((r) => p.port >= r.$1 && p.port <= r.$2);
  }
}

/// `reg query …\FirewallRules` 출력(값 하나가 `v2.31|Action=Allow|Active=TRUE|Dir=In|…` 한 줄)을 읽는다.
/// 활성이고 "들어오는" 규칙 중 서비스·그룹 조건이 없는 것만 돌려준다.
List<FirewallRule> parseFirewallRules(String output) {
  final rules = <FirewallRule>[];
  for (final line in const LineSplitter().convert(output)) {
    final m = RegExp(r'^\s+\S+\s+REG_SZ\s+(v\d+\.\d+\|.*)$').firstMatch(line);
    if (m == null) continue;
    final fields = <String, List<String>>{};
    for (final part in m.group(1)!.split('|').skip(1)) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      fields.putIfAbsent(part.substring(0, eq), () => []).add(part.substring(eq + 1));
    }
    String? one(String key) => fields[key]?.first;
    if (one('Active')?.toUpperCase() != 'TRUE' || one('Dir') != 'In') continue;
    if (fields.containsKey('Svc')) continue;
    final ports = <(int, int)>[];
    for (final entry in fields.entries) {
      if (!entry.key.startsWith('LPort')) continue;
      for (final value in entry.value) {
        final range = value.split('-');
        final low = int.tryParse(range.first);
        final high = int.tryParse(range.last);
        if (low != null && high != null) ports.add((low, high));
      }
    }
    rules.add(FirewallRule(
      allow: one('Action')?.toLowerCase() == 'allow',
      profiles: {...?fields['Profile']},
      protocol: int.tryParse(one('Protocol') ?? ''),
      ports: ports,
      program: one('App'),
      name: one('Name') ?? '',
    ));
  }
  return rules;
}

String _normalizePath(String p) => p.replaceAll('/', r'\').toLowerCase();

/// [exePath] 프로그램이 [port]로 들어오는 연결을 [profile]에서 받을 수 있는지.
/// 막는 규칙이 있으면 막힘, 그다음 허용 규칙(이 프로그램 전용이거나 프로그램 조건 없이 이 포트를 여는 것)이 있으면 허용.
bool firewallAllows(List<FirewallRule> rules, String profile, PreStartPort port, String exePath) {
  bool matches(FirewallRule r) {
    if (!r.coversProfile(profile) || !r.coversPort(port)) return false;
    final program = r.program;
    if (program != null) return _normalizePath(program) == _normalizePath(exePath);
    // 프로그램 조건이 없는 규칙은 포트나 프로토콜을 좁혀 둔 것만 인정한다 (모든 것을 여는 규칙은 드물고 의도가 불분명).
    return r.ports.isNotEmpty;
  }

  final applicable = rules.where(matches).toList();
  if (applicable.any((r) => !r.allow)) return false;
  return applicable.any((r) => r.allow);
}

/// 방화벽이 켜져 있고 기본이 "차단"인 프로필 중에서, 허용 규칙이 없는 포트가 있는 프로필과 그 포트들.
Map<String, List<PreStartPort>> uncoveredPorts({
  required List<FirewallProfileState> profiles,
  required List<FirewallRule> rules,
  required List<PreStartPort> ports,
  required String exePath,
}) {
  final result = <String, List<PreStartPort>>{};
  for (final profile in profiles) {
    if (!profile.enabled || !profile.blocksInbound) continue;
    // 규칙 안에서는 같은 프로필을 `Private`라고 부른다 (레지스트리 키 이름은 `Standard`).
    final ruleProfile = profile.name == 'Standard' ? 'Private' : profile.name;
    final missing = [for (final p in ports) if (!firewallAllows(rules, ruleProfile, p, exePath)) p];
    if (missing.isNotEmpty) result[profile.name] = missing;
  }
  return result;
}

// ---- 점검기 -------------------------------------------------------------------------------------

/// 서비스를 켜기 전 점검. Windows가 아니면 아무것도 찾지 않는다.
class PreStartChecker {
  PreStartChecker({CommandRunner? run, String? exePath, bool? isWindows})
      : _run = run ?? runCommand,
        exePath = exePath ?? Platform.resolvedExecutable,
        _isWindows = isWindows ?? Platform.isWindows;

  final CommandRunner _run;
  final String exePath;
  final bool _isWindows;

  Future<String> _safe(String exe, List<String> args) async {
    try {
      return await _run(exe, args);
    } catch (_) {
      return '';
    }
  }

  /// 포트 충돌(막음)과 방화벽 경고를 합쳐서 돌려준다. 점검 도구가 실패하면 그 부분은 문제 없음으로 본다.
  ///
  /// [tcpRange]를 주면(FTP 패시브 범위) Windows가 그 범위의 포트를 예약해 두었는지도 본다.
  Future<List<PreStartIssue>> check({required Ipv4 bindAddress, required List<PreStartPort> ports, (int, int)? tcpRange}) async {
    if (!_isWindows || ports.isEmpty) return const [];
    final results = await Future.wait([
      _safe('netstat', ['-ano', '-p', 'UDP']),
      _safe('netstat', ['-ano', '-p', 'TCP']),
      _safe('reg', ['query', '$_policyKey\\FirewallRules']),
      for (final name in firewallProfiles) _safe('reg', ['query', '$_policyKey\\${name}Profile']),
      for (final name in firewallProfiles) _safe('reg', ['query', '$_gpoKey\\${name}Profile']),
      if (tcpRange != null) _safe('netsh', ['int', 'ipv4', 'show', 'excludedportrange', 'protocol=tcp']),
    ]);

    final issues = <PreStartIssue>[];

    final owners = [...parseNetstat(results[0], 'UDP'), ...parseNetstat(results[1], 'TCP')];
    for (final port in ports) {
      for (final owner in conflictsFor(owners, bindAddress, port)) {
        final name = parseTasklistName(await _safe('tasklist', ['/FI', 'PID eq ${owner.pid}', '/FO', 'CSV', '/NH']));
        issues.add(PreStartIssue(IssueKind.portInUse, blocking: true, args: {
          'protocol': port.protocol,
          'port': port.port,
          'pid': owner.pid,
          'process': name,
          'address': owner.address,
        }));
      }
    }

    if (tcpRange != null) {
      final (free, hits) = availableInRange(tcpRange.$1, tcpRange.$2, parseExcludedRanges(results[9]));
      if (hits.isNotEmpty) {
        issues.add(PreStartIssue(IssueKind.portsReserved, blocking: free == 0, args: {
          'range': '${tcpRange.$1}-${tcpRange.$2}',
          'reserved': [for (final h in hits) h.$1 == h.$2 ? '${h.$1}' : '${h.$1}-${h.$2}'],
          'free': free,
        }));
      }
    }

    final rules = parseFirewallRules(results[2]);
    if (rules.isNotEmpty) {
      final profiles = [
        for (var i = 0; i < firewallProfiles.length; i++) parseProfile(firewallProfiles[i], results[3 + i], results[6 + i]),
      ];
      final missing = uncoveredPorts(profiles: profiles, rules: rules, ports: ports, exePath: exePath);
      if (missing.isNotEmpty) {
        issues.add(PreStartIssue(IssueKind.firewallBlocked, blocking: false, args: {
          'profiles': [for (final p in missing.keys) p == 'Standard' ? 'Private' : p],
          'ports': {for (final list in missing.values) for (final p in list) '$p'}.toList(),
          'program': exePath,
        }));
      }
    }
    return issues;
  }

  /// 이 프로그램을 모든 프로필에서 허용하는 규칙을 추가한다. 관리자 권한이 필요해서 Windows가 UAC 창을 띄우고,
  /// 사용자가 거부하면 false다. 설치 프로그램이 같은 규칙을 넣으므로 설치본에서는 보통 필요 없다.
  Future<bool> requestFirewallRule() async {
    if (!_isWindows) return false;
    const ruleName = 'Lab Daemon';
    final args = 'advfirewall firewall add rule name="$ruleName" dir=in action=allow program="$exePath" enable=yes profile=any';
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Start-Process -FilePath netsh -ArgumentList '${args.replaceAll("'", "''")}' -Verb RunAs -Wait -WindowStyle Hidden",
      ]).timeout(const Duration(minutes: 2));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
