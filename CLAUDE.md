릴리스·버전·패키징·정보 창·아이콘·라이선스·UI/UX·글꼴·언어·테마는
https://github.com/jejezz/application-release-templates/tree/main/conventions
규약을 따른다. 이 앱에 적용된 규약 버전: conventions-v1

# Lab Daemon

DHCP, TFTP, FTP(이후 Syslog 등) 같은 랩용 네트워크 서비스를 한 앱에서 켜고 끄며 접속 현황과 로그를 실시간으로 보여주는 Windows 데스크톱 앱 (3CDaemon 유형). 보드 플래싱·랩 환경이 대상이다.

- 식별자 `art.zoomon.labdaemon`, 표시 이름 `Lab Daemon`, 파일 이름 `LabDaemon`, 패키지 `lab_daemon`.
- 플랫폼은 **Windows만**. 릴리스 워크플로에서 macOS/Linux 잡을 뺐고, 표시 이름 원본은 `windows/runner/Runner.rc`의 `ProductName`이다 (macos/ 폴더가 없다).
- 실행 파일 매니페스트는 `requireAdministrator`다. 개발 중 `flutter run`은 관리자 권한 터미널에서 한다. 일반 권한으로 포트 67/69/21을 열 수 있는지 DHCP 서버 구현 단계(P2)에서 실제 장비로 검증한 뒤 이 방침을 확정한다.
- 서비스(DHCP/TFTP/FTP)는 `lib/core/`의 순수 Dart `NetService` 구현으로 만들고, 각자 별도 Isolate에서 돌린다. 로그 버스는 공용이다. 계획서는 `PLAN.md`.
- 모든 UI·로그 문구는 ARB(ko 기준 + en). 패킷 원문과 파일 이름은 번역하지 않는다.
- `window_manager ^0.5.2`, `screen_retriever ^0.2.2`로 고정한다 (공통 `window_placement.dart`가 이 버전 API에 맞춰져 있고, 최신판은 컴파일이 안 된다).
