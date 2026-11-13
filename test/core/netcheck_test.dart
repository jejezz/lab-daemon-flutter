import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/ipv4.dart';
import 'package:lab_daemon/core/netcheck.dart';

const _exe = r'C:\Program Files\Lab Daemon\lab_daemon.exe';

// 한국어 Windows의 netstat: 머리글만 번역되고 데이터 줄 형식은 같다.
const _netstatUdp = '''

활성 연결

  프로토콜  로컬 주소              외부 주소              상태           PID
  UDP    0.0.0.0:67             *:*                                    1234
  UDP    0.0.0.0:5353           *:*                                    4321
  UDP    192.168.50.1:69        *:*                                    777
  UDP    [::]:69                *:*                                    888
  UDP    10.0.0.5:21            *:*                                    999
''';

const _netstatTcp = '''

활성 연결

  프로토콜  로컬 주소              외부 주소              상태           PID
  TCP    0.0.0.0:21             0.0.0.0:0              LISTENING       555
  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING       100
  TCP    192.168.50.1:21        192.168.50.9:51000     ESTABLISHED     556
  TCP    [::]:21                [::]:0                 LISTENING       557
''';

String _rules(List<String> lines) => 'HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\SharedAccess\\Parameters\\FirewallPolicy\\FirewallRules\n'
    '${[for (var i = 0; i < lines.length; i++) '    {rule-$i}    REG_SZ    ${lines[i]}'].join('\n')}\n';

const _allowApp = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Profile=Domain|Profile=Private|Profile=Public|App=$_exe|Name=Lab Daemon|';
const _allowPublicApp = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Profile=Public|App=C:\\PROGRAM FILES\\LAB DAEMON\\LAB_DAEMON.EXE|Name=lab_daemon.exe|';
const _allowUdp67AnyProgram = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=17|LPort=67|Name=DHCP any|';
const _blockApp = 'v2.31|Action=Block|Active=TRUE|Dir=In|Profile=Public|App=$_exe|Name=Block Lab Daemon|';
const _inactive = 'v2.31|Action=Allow|Active=FALSE|Dir=In|App=$_exe|Name=Off|';
const _outbound = 'v2.31|Action=Allow|Active=TRUE|Dir=Out|App=$_exe|Name=Out|';
const _service = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Svc=dnscache|Protocol=17|LPort=5353|Name=mDNS|';
const _portRange = 'v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=20-30|Name=FTP range|';

String _profile({int? enable, int? inbound}) =>
    '\nHKEY_...\\Profile\n${enable == null ? '' : '    EnableFirewall    REG_DWORD    0x$enable\n'}${inbound == null ? '' : '    DefaultInboundAction    REG_DWORD    0x$inbound\n'}';

void main() {
  group('netstat 파싱', () {
    test('UDP 소켓을 주소·포트·PID로 읽는다', () {
      final owners = parseNetstat(_netstatUdp, 'UDP');
      expect(owners.map((o) => '${o.address}:${o.port}/${o.pid}'), ['0.0.0.0:67/1234', '0.0.0.0:5353/4321', '192.168.50.1:69/777', '[::]:69/888', '10.0.0.5:21/999']);
    });

    test('TCP는 듣는 소켓(원격이 0.0.0.0:0)만 읽는다 — 연결된 소켓과 번역될 수 있는 상태 글자는 보지 않는다', () {
      final owners = parseNetstat(_netstatTcp, 'TCP');
      expect(owners.map((o) => '${o.address}:${o.port}/${o.pid}'), ['0.0.0.0:21/555', '0.0.0.0:135/100', '[::]:21/557']);
    });

    test('같은 NIC 주소이거나 모든 주소에 묶인 소켓만 충돌로 본다', () {
      final udp = parseNetstat(_netstatUdp, 'UDP');
      final here = Ipv4.parse('192.168.50.1');
      expect(conflictsFor(udp, here, const PreStartPort('UDP', 67)).map((o) => o.pid), [1234], reason: '0.0.0.0:67');
      expect(conflictsFor(udp, here, const PreStartPort('UDP', 69)).map((o) => o.pid), [777], reason: '같은 주소만, [::]는 IPv4와 무관');
      expect(conflictsFor(udp, Ipv4.parse('192.168.60.1'), const PreStartPort('UDP', 69)), isEmpty, reason: '다른 NIC');
      expect(conflictsFor(udp, here, const PreStartPort('UDP', 21)), isEmpty, reason: '다른 NIC의 포트');
      expect(conflictsFor(udp, here, const PreStartPort('TCP', 67)), isEmpty, reason: '프로토콜이 다르다');
    });

    test('tasklist CSV에서 프로세스 이름을 읽는다', () {
      expect(parseTasklistName('"svchost.exe","1234","Services","0","12 K"\r\n'), 'svchost.exe');
      expect(parseTasklistName('정보: 지정한 조건에 맞는 작업이 없습니다.'), isNull);
    });
  });

  group('예약 포트', () {
    const output = '''
프로토콜 tcp 포트 제외 범위

시작 포트    끝 포트
----------    --------
      5357        5357
     50000       50059     *
     53945       54044

* - 관리 포트 제외
''';

    test('예약 범위를 읽는다 (번역된 머리글과 * 표시는 무시)', () {
      expect(parseExcludedRanges(output), [(5357, 5357), (50000, 50059), (53945, 54044)]);
    });

    test('범위와 겹치는 예약 구간과 남은 포트 수', () {
      final ranges = parseExcludedRanges(output);
      // 레코드 안의 리스트는 == 로 비교되지 않으므로 나눠서 본다.
      for (final (low, high, free, hits) in [
        (50000, 50100, 41, [(50000, 50059)]),
        (40000, 40199, 200, <(int, int)>[]),
        (50010, 50020, 0, [(50010, 50020)]),
      ]) {
        final (f, h) = availableInRange(low, high, ranges);
        expect(f, free, reason: '$low-$high');
        expect(h, hits, reason: '$low-$high');
      }
    });
  });

  group('방화벽 프로필', () {
    test('값이 없으면 켜짐 + 차단이 기본이다', () {
      final p = parseProfile('Public', _profile());
      expect(p.enabled, isTrue);
      expect(p.blocksInbound, isTrue);
    });

    test('끄거나 허용으로 바꾼 값을 읽고, 그룹 정책 값이 우선한다', () {
      expect(parseProfile('Private', _profile(enable: 0, inbound: 1)).enabled, isFalse);
      expect(parseProfile('Public', _profile(enable: 1, inbound: 0)).blocksInbound, isFalse);
      final overridden = parseProfile('Public', _profile(enable: 1), _profile(enable: 0));
      expect(overridden.enabled, isFalse);
    });
  });

  group('방화벽 규칙', () {
    test('활성인 들어오는 규칙만 읽고 서비스 규칙은 건너뛴다', () {
      final rules = parseFirewallRules(_rules([_allowApp, _inactive, _outbound, _service, _portRange]));
      expect(rules.map((r) => r.name), ['Lab Daemon', 'FTP range']);
      expect(rules.first.profiles, {'Domain', 'Private', 'Public'});
      expect(rules.last.ports, [(20, 30)]);
    });

    test('프로그램 허용 규칙은 모든 포트를 연다 (경로는 대소문자·구분자 무시)', () {
      final rules = parseFirewallRules(_rules([_allowPublicApp]));
      expect(firewallAllows(rules, 'Public', const PreStartPort('UDP', 67), _exe), isTrue);
      expect(firewallAllows(rules, 'Public', const PreStartPort('TCP', 21), _exe), isTrue);
      expect(firewallAllows(rules, 'Private', const PreStartPort('UDP', 67), _exe), isFalse, reason: '다른 프로필');
      expect(firewallAllows(rules, 'Public', const PreStartPort('UDP', 67), r'C:\other\lab_daemon.exe'), isFalse, reason: '다른 프로그램');
    });

    test('프로그램 조건 없는 규칙은 포트를 좁혀 둔 것만 인정한다', () {
      final rules = parseFirewallRules(_rules([_allowUdp67AnyProgram, _portRange]));
      expect(firewallAllows(rules, 'Public', const PreStartPort('UDP', 67), _exe), isTrue);
      expect(firewallAllows(rules, 'Public', const PreStartPort('UDP', 69), _exe), isFalse);
      expect(firewallAllows(rules, 'Public', const PreStartPort('TCP', 21), _exe), isTrue, reason: '20-30 범위');
      expect(firewallAllows(rules, 'Public', const PreStartPort('TCP', 31), _exe), isFalse);
      expect(firewallAllows(rules, 'Public', const PreStartPort('UDP', 21), _exe), isFalse, reason: 'TCP 규칙');
    });

    test('차단 규칙이 허용 규칙보다 우선한다', () {
      final rules = parseFirewallRules(_rules([_allowApp, _blockApp]));
      expect(firewallAllows(rules, 'Public', const PreStartPort('UDP', 67), _exe), isFalse);
      expect(firewallAllows(rules, 'Private', const PreStartPort('UDP', 67), _exe), isTrue);
    });

    test('방화벽이 꺼졌거나 기본이 허용인 프로필은 점검하지 않는다', () {
      final profiles = [
        parseProfile('Domain', _profile(enable: 1, inbound: 1)),
        parseProfile('Standard', _profile(enable: 0)),
        parseProfile('Public', _profile(enable: 1, inbound: 0)),
      ];
      final missing = uncoveredPorts(profiles: profiles, rules: const [], ports: const [PreStartPort('UDP', 67)], exePath: _exe);
      expect(missing.keys, ['Domain']);
    });
  });

  group('점검기 (가짜 명령 실행)', () {
    PreStartChecker checker({String udp = '', String tcp = '', String rules = '', Map<String, String> profiles = const {}, bool windows = true, List<String>? log}) {
      return PreStartChecker(
        exePath: _exe,
        isWindows: windows,
        run: (exe, args) async {
          log?.add('$exe ${args.join(' ')}');
          if (exe == 'netstat') return args.last == 'UDP' ? udp : tcp;
          if (exe == 'tasklist') return '"svchost.exe","1234","Services","0","12 K"';
          if (exe == 'reg') {
            final key = args[1];
            if (key.endsWith('FirewallRules')) return rules;
            return profiles[key.split(r'\').last] ?? '';
          }
          return '';
        },
      );
    }

    final here = Ipv4.parse('192.168.50.1');

    test('포트를 다른 프로그램이 쓰면 막는 문제로 알리고 프로세스 이름을 붙인다', () async {
      final issues = await checker(udp: _netstatUdp).check(bindAddress: here, ports: const [PreStartPort('UDP', 67)]);
      expect(issues, hasLength(1));
      expect(issues.single.kind, IssueKind.portInUse);
      expect(issues.single.blocking, isTrue);
      expect(issues.single.args, {'protocol': 'UDP', 'port': 67, 'pid': 1234, 'process': 'svchost.exe', 'address': '0.0.0.0'});
    });

    test('허용 규칙이 없으면 경고(막지 않음)이고 프로필과 포트를 알려 준다', () async {
      final issues = await checker(rules: _rules([_allowUdp67AnyProgram])).check(
        bindAddress: here,
        ports: const [PreStartPort('UDP', 67), PreStartPort('UDP', 69)],
      );
      expect(issues, hasLength(1));
      final issue = issues.single;
      expect(issue.kind, IssueKind.firewallBlocked);
      expect(issue.blocking, isFalse);
      expect(issue.args['profiles'], ['Domain', 'Private', 'Public'], reason: 'Standard는 화면 이름 Private로');
      expect(issue.args['ports'], ['UDP 69']);
      expect(issue.args['program'], _exe);
    });

    test('프로그램 허용 규칙이 있으면 문제 없다', () async {
      final issues = await checker(rules: _rules([_allowApp])).check(
        bindAddress: here,
        ports: const [PreStartPort('UDP', 67), PreStartPort('UDP', 69), PreStartPort('TCP', 21)],
      );
      expect(issues, isEmpty);
    });

    test('규칙을 읽지 못하면(빈 출력) 방화벽 문제를 지어내지 않는다', () async {
      expect(await checker().check(bindAddress: here, ports: const [PreStartPort('UDP', 67)]), isEmpty);
    });

    test('패시브 범위가 예약과 겹치면 경고하고, 전부 예약이면 막는다', () async {
      PreStartChecker withExcluded(String excluded) => PreStartChecker(
            exePath: _exe,
            isWindows: true,
            run: (exe, args) async => exe == 'netsh' ? excluded : '',
          );
      const excluded = '\n     50000       50059     *\n';
      final partial = await withExcluded(excluded).check(bindAddress: here, ports: const [PreStartPort('TCP', 21)], tcpRange: (50000, 50100));
      expect(partial.single.kind, IssueKind.portsReserved);
      expect(partial.single.blocking, isFalse);
      expect(partial.single.args, {'range': '50000-50100', 'reserved': ['50000-50059'], 'free': 41});

      final all = await withExcluded(excluded).check(bindAddress: here, ports: const [PreStartPort('TCP', 21)], tcpRange: (50010, 50020));
      expect(all.single.blocking, isTrue);

      expect(await withExcluded(excluded).check(bindAddress: here, ports: const [PreStartPort('TCP', 21)], tcpRange: (40000, 40199)), isEmpty);
    });

    test('Windows가 아니거나 포트가 없으면 아무것도 실행하지 않는다', () async {
      final log = <String>[];
      expect(await checker(windows: false, log: log).check(bindAddress: here, ports: const [PreStartPort('UDP', 67)]), isEmpty);
      expect(await checker(log: log).check(bindAddress: here, ports: const []), isEmpty);
      expect(log, isEmpty);
    });

    test('명령이 실패해도 예외 없이 문제 없음으로 본다', () async {
      final failing = PreStartChecker(exePath: _exe, isWindows: true, run: (e, a) async => throw const ProcessException('x', []));
      expect(await failing.check(bindAddress: here, ports: const [PreStartPort('UDP', 67)]), isEmpty);
    });
  });

  test('실제 이 PC에서 점검을 돌려 본다 (읽기 전용, 5초 안에 끝나야 한다)', () async {
    if (!Platform.isWindows) return;
    final sw = Stopwatch()..start();
    final issues = await PreStartChecker().check(
      bindAddress: Ipv4.parse('192.168.250.1'),
      ports: const [PreStartPort('UDP', 67), PreStartPort('UDP', 69), PreStartPort('TCP', 21)],
    );
    sw.stop();
    // ignore: avoid_print
    print('live pre-start check: ${sw.elapsedMilliseconds} ms, issues: ${[for (final i in issues) '${i.kind.name}${i.args}']}');
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
