import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/netcheck.dart';
import 'package:lab_daemon/core/os_info.dart';

void main() {
  test('빌드 번호로 Windows 11과 10을 가른다', () {
    expect(hostOsFrom('windows', '"Windows 11 Home" 10.0 (Build 26300)'), HostOs.windows11);
    expect(hostOsFrom('windows', '"Windows 10 Pro" 10.0 (Build 19045)'), HostOs.windows10);
    expect(hostOsFrom('windows', 'unknown'), HostOs.windows);
    expect(hostOsFrom('linux', 'Linux 6.1'), HostOs.other);
  });

  test('붙여 넣을 명령은 설치 프로그램이 넣는 규칙과 같은 인자를 쓴다', () {
    expect(
      PreStartChecker.ruleCommand(r'C:\Program Files\Lab Daemon\LabDaemon.exe'),
      r'netsh advfirewall firewall add rule name="Lab Daemon" dir=in action=allow program="C:\Program Files\Lab Daemon\LabDaemon.exe" enable=yes profile=any',
    );
  });
}
