릴리스·버전·패키징·정보 창·아이콘·라이선스·UI/UX·글꼴·언어·테마는
https://github.com/jejezz/application-release-templates/tree/main/conventions
규약을 따른다. 이 앱에 적용된 규약 버전: conventions-v1

# Lab Daemon

DHCP, TFTP, FTP(이후 Syslog 등) 같은 랩용 네트워크 서비스를 한 앱에서 켜고 끄며 접속 현황과 로그를 실시간으로 보여주는 Windows 데스크톱 앱 (3CDaemon 유형). 보드 플래싱·랩 환경이 대상이다. 계획서는 `PLAN.md`.

## 정체성·플랫폼
- 식별자 `art.zoomon.labdaemon`, 표시 이름 `Lab Daemon`, 파일 이름 `LabDaemon`, 패키지 `lab_daemon`.
- 플랫폼은 **Windows만**. 릴리스 워크플로에서 macOS/Linux 잡을 뺐고, 표시 이름 원본은 `windows/runner/Runner.rc`의 `ProductName`이다 (macos/ 폴더가 없다).
- 앱은 **일반 권한(asInvoker)** 으로 실행한다. UDP 67/69, TCP 21 바인딩에 관리자 권한이 필요 없다 (2026-11-02 확인). 방화벽 인바운드 규칙은 설치 프로그램(`installer/windows/app.iss`)이 넣고, 개발 빌드는 서비스 시작 시 점검 대화상자의 [방화벽 규칙 추가](UAC)로 넣는다.
- 규약 저장소의 로컬 사본은 `C:\Users\jejez\MyWork\Projects\application-release-templates`에 있다 (FLUTTER 폴더 밖으로 옮겨졌다).
- `window_manager ^0.5.2`, `screen_retriever ^0.2.2`로 고정한다 (공통 `window_placement.dart`가 이 버전 API에 맞춰져 있다).
- 업데이터는 `app_updater`를 커밋 `22ebf8a`(updater-v0.2.0 내용, 릴리스 노트 요약)로 가리킨다. 규약 저장소에 `updater-v0.2.0` 태그가 생기면 `pubspec.yaml`의 `ref`를 태그로 바꾼다.

## 구조
- **코어 `lib/core/`** (순수 Dart): `NetService`/`BaseNetService`(service.dart), 서비스별 `dhcp/`·`tftp/`·`ftp/`. 각 서비스는 **자기 Isolate**에서 돈다(`IsolateHost`, host.dart). 시험은 `InProcessHost`로 같은 Isolate에서 돌린다. 설정은 `toJson`/`fromJson`으로 Isolate 경계를 건넌다.
- **상태 `lib/state/`**: 서비스마다 모델(`DhcpModel`·`TftpModel`·`FtpModel`, service_models.dart)이 설정·상태·**그 서비스만의 로그**(`LogBus`, 보관 줄 수는 서비스마다 선택, 기본 1000줄)·클라이언트 스냅샷을 가진다. 서비스 설정 값은 입력 문자열 그대로 `<서비스>_<이름>` 키로 저장한다.
- **화면 `lib/ui/`**: 설정 패널은 접고 펼 수 있고(가운데 띠 또는 Ctrl+B, 서비스마다 기억) 앱 바에는 켜진 서비스의 접속 주소(`IP[:포트]`, 기본 포트는 생략, DHCP는 IP만)가 나온다. 사이드바(서비스 목록) + 서비스별 화면(`service_page.dart`: 왼쪽 **그 서비스의 설정 패널**, 오른쪽 클라이언트 표, 아래 그 서비스의 로그). 서비스 설정은 서비스마다 따로 두고 하나의 화면에 섞지 않는다. 앱 설정 창(`lib/settings/settings_dialog.dart`)에는 "외형"만 있다.
- 서비스 로그는 번역하지 않은 ARB 키 + 인자로 내보내고 `lib/ui/log_format.dart`가 문구로 바꾼다. 새 `logDhcp…`/`logTftp…`/`logFtp…`/`logCheck…` 키를 추가하면 포맷터와 ARB(ko/en)에도 더한다 (`test/log_format_test.dart`가 빠진 키와 안 쓰는 키를 잡는다).

## 성능 (3CDaemon의 약점을 피한다)
- 패킷 처리 경로에서는 로그·표를 만들지 않는다: 표 스냅샷은 `scheduleSnapshot`이 최대 200~250ms에 한 번 만들고, 로그는 사건(요청·완료·실패)에만 남긴다.
- 서비스 Isolate → 화면 이벤트는 `EventBatcher`가 100ms마다 묶는다. 같은 종류의 스냅샷은 최신 것만, 로그는 묶음마다 400줄까지(넘치면 "N건 건너뜀").
- 로그 보관 줄 수는 100/500/1000/5000 중에서 고른다. 로그 패널은 보이는 줄만 그리고, 번역 문구를 줄마다 한 번만 만들며(Expando), 필터는 새 줄에만 적용한다.
- **Windows의 `RawDatagramSocket.send`는 OS 버퍼가 차면 0을 돌려주고 패킷을 버린다** (연달아 보내면 흔함). UDP를 보낼 때는 항상 `UdpSendQueue`(udp_queue.dart)를 거친다.

## 서비스별 결정
- **시작 전 점검은 앱 시작이 아니라 서비스 시작 때** 그 서비스의 포트만 본다 (`netcheck.dart`): 포트 충돌(netstat, 막음), 방화벽 허용 규칙(레지스트리, 경고), FTP 패시브 범위의 Windows 예약 포트(netsh, 경고/막음), DHCP는 다른 DHCP 서버(DISCOVER 프로브, 경고). PowerShell cmdlet은 10초 가까이 걸리고 `netsh` 일반 출력은 한국어로 번역돼서 쓰지 않는다.
- **DHCP 실장비 시험은 프로젝트 말미로 미룬다** (같은 망의 다른 DHCP 서버를 방해할 위험). TFTP·FTP를 먼저 시험한다.
- **FTP는 계정 하나**(사용자 이름 + 솔트 SHA-256 해시)와 **익명 허용**, **쓰기 허용** 스위치 하나뿐이다 (FileZilla 같은 계정별 권한은 두지 않는다). 패시브 기본 범위는 40000~40199 — Windows 동적 범위(49152~)는 Hyper-V/WSL이 100개씩 예약해 막히는 일이 있다.
- TFTP·FTP는 루트 폴더 밖으로 나갈 수 없다 (`fs_sandbox.dart`: `..`, 드라이브·ADS, 예약 장치 이름, 링크 탈출). 올리기는 임시 파일(`*.lab-part-*`)에 받다가 끝나면 이름을 바꾼다.

## 시험
- `testWidgets` 안의 실제 소켓·파일 I/O와 서비스 `stop()`은 FakeAsync에서 멈추므로 `tester.runAsync`로 감싼다. 시험 끝에서 화면을 내리고(`pumpWidget(SizedBox)`) 서비스를 멈춰야 남은 타이머 오류가 없다.
- TFTP·FTP는 실제 loopback 소켓으로 시험한다 (`test/support/tftp_client.dart`, `ftp_client.dart`). 시험의 FTP 패시브 범위는 49152 아래에서 고른다.
