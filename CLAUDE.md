릴리스·버전·패키징·정보 창·아이콘·라이선스·UI/UX·글꼴·언어·테마는
https://github.com/jejezz/application-release-templates/tree/main/conventions
규약을 따른다. 이 앱에 적용된 규약 버전: conventions-v1

# Lab Daemon

DHCP, TFTP, FTP(이후 Syslog 등) 같은 랩용 네트워크 서비스를 한 앱에서 켜고 끄며 접속 현황과 로그를 실시간으로 보여주는 Windows 데스크톱 앱 (3CDaemon 유형). 보드 플래싱·랩 환경이 대상이다.

- 식별자 `art.zoomon.labdaemon`, 표시 이름 `Lab Daemon`, 파일 이름 `LabDaemon`, 패키지 `lab_daemon`.
- 플랫폼은 **Windows만**. 릴리스 워크플로에서 macOS/Linux 잡을 뺐고, 표시 이름 원본은 `windows/runner/Runner.rc`의 `ProductName`이다 (macos/ 폴더가 없다).
- 앱은 **일반 권한(asInvoker)** 으로 실행한다. UDP 67/69, TCP 21 바인딩은 관리자 권한이 필요 없다는 것을 확인했다 (2026-11-02). 방화벽 인바운드 규칙은 관리자 권한으로 도는 설치 프로그램(`installer/windows/app.iss`)이 추가·제거한다. DHCP 응답 동작(주소 없는 클라이언트에 대한 unicast 등)이 일반 권한에서 되는지는 P2에서 실제 장비로 검증하고, 승격이 필요한 기능이 확인되면 서비스 호스트를 별도 관리자 프로세스로 분리한다 (`ServiceHost` 인터페이스로 Isolate/프로세스를 바꿔 끼운다).
- 서비스(DHCP/TFTP/FTP)는 `lib/core/`의 순수 Dart `NetService` 구현으로 만들고, 각자 별도 Isolate에서 돌린다. 로그 버스는 공용이다. 계획서는 `PLAN.md`.
- 모든 UI·로그 문구는 ARB(ko 기준 + en). 패킷 원문과 파일 이름은 번역하지 않는다.
- `window_manager ^0.5.2`, `screen_retriever ^0.2.2`로 고정한다 (공통 `window_placement.dart`가 이 버전 API에 맞춰져 있고, 최신판은 컴파일이 안 된다).
- 테마·색 구성·언어는 앱 바 메뉴가 아니라 설정 창(`lib/settings/settings_dialog.dart`)의 "외형" 구역에서 바꾼다 (settings-screen.md). 앱 바 오른쪽은 `… | 설정 | 정보`, 단축키 `Ctrl+,`. 서비스별 설정 구역은 `SettingsSection`에 더한다.
- 화면은 `lib/ui/`(홈 · 사이드바 · DHCP 본문 · Lease 표 · 로그 패널), 상태는 `lib/state/`(`LabDaemonController`, `DhcpSettings`)다. 서비스 로그는 번역하지 않은 ARB 키 + 인자로 내보내고 `lib/ui/log_format.dart`가 문구로 바꾼다. 새 `logDhcp…` 키를 서비스에 추가하면 포맷터와 ARB(ko/en)에도 더해야 한다 (`test/log_format_test.dart`가 빠진 키를 잡는다).
- DHCP 서버를 켜기 전에 같은 망의 다른 DHCP 서버를 확인한다 (`lib/core/dhcp/detector.dart`). 위젯 테스트는 `testWidgets` 안에서 서버를 `await stop()`하면 FakeAsync에서 멈추므로 `tester.runAsync`로 감싼다.
