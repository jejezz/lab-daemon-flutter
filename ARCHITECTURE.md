# Lab Daemon 구조

개발자용 문서입니다. 사용법은 [README](README.ko.md), 작업 규칙과 결정의 이유는 [CLAUDE.md](CLAUDE.md), 계획과 진행은 [PLAN.md](PLAN.md)에 있습니다.

## 한눈에

```
lib/
  core/       순수 Dart: 서비스(DHCP·TFTP·FTP), 시작 전 점검, 소켓·파일 도구
  state/      화면이 읽는 모델: 서비스별 설정·상태·로그·클라이언트 스냅샷
  ui/         서비스 화면, 표, 로그 패널, 대화상자
  settings/   앱 설정 창(외형: 모드·색 구성·언어·글자 크기)
  l10n/       ARB(ko 원본, en)
```

화면(`ui`)은 모델(`state`)을 보고, 모델은 서비스(`core`)를 `ServiceHost`로만 만납니다. `core`는 Flutter를 모릅니다.

## 서비스와 Isolate

- 모든 서비스는 `NetService`(`core/service.dart`)를 구현하고 `BaseNetService`가 공통을 맡습니다: 상태(`stopped`·`starting`·`running`·`error`), 이벤트 스트림, 최신 것만 남기는 스냅샷(`scheduleSnapshot`).
- 각 서비스는 **자기 Isolate**에서 돕니다(`IsolateHost`, `core/host.dart`). 시험은 같은 Isolate에서 도는 `InProcessHost`를 씁니다.
- 설정은 `ServiceConfig.toJson`/`fromJson`으로 Isolate 경계를 건넙니다. 서비스는 UI 객체를 모릅니다.
- 서비스 → 화면 이벤트는 `EventBatcher`가 100ms마다 한 묶음으로 보냅니다. 같은 종류의 스냅샷은 최신 것만, 로그는 묶음마다 400줄까지이고 넘치면 "N건 건너뜀" 한 줄을 남깁니다.

## 서비스

| 서비스 | 위치 | 요점 |
|---|---|---|
| DHCP | `core/dhcp/` | `engine`(순수 로직: DORA·NAK·RELEASE·DECLINE·INFORM), `pool`(주소 풀·Lease), `transport`(UDP 67), `detector`(다른 DHCP 서버 찾기) |
| TFTP | `core/tftp/` | `packet`(파서), `transfer`(전송 하나: 윈도 크기·재전송), `server`(UDP 69, 전송마다 소켓), `netascii` |
| FTP | `core/ftp/` | `session`(제어 연결 하나), `server`(수락·패시브 포트 관리), `config`(계정 하나 + 익명) |
| HTTP | `core/http/` | `server`(dart:io `HttpServer`: GET/HEAD·Range·ETag·폴더 목록·PUT 올리기), `config`. 요청 하나가 요청 목록의 한 줄 |

공통 도구: `fs_sandbox.dart`(TFTP·FTP가 루트 폴더 밖으로 나가지 못하게), `udp_queue.dart`(Windows에서 `send`가 0을 돌려주고 패킷을 버리는 문제를 막는 전송 큐), `socket_errors.dart`(바인딩 오류를 "포트 사용 중"·"권한 없음"으로 구분).

## 시작 전 점검

`core/netcheck.dart`의 `PreStartChecker`가 서비스를 **켤 때** 그 서비스의 포트만 봅니다.

- 포트 충돌: `netstat -ano` + `tasklist` (막음)
- 방화벽 허용 규칙: 레지스트리 조회 (경고, 해결 방법 안내와 [방화벽 규칙 추가])
- FTP 패시브 범위의 Windows 예약 포트: `netsh int ipv4 show excludedportrange` (경고/막음)
- DHCP: 다른 DHCP 서버 (DISCOVER 프로브, 경고)

PowerShell cmdlet은 10초 가까이 걸리고 `netsh` 일반 출력은 번역되어서 쓰지 않습니다. 결과는 로그에 `CHECK` 줄로 남고, 화면은 `ui/actions.dart`의 대화상자로 보여 줍니다.

## 상태와 화면

- `state/service_model.dart`: 서비스마다 하나인 `ServiceModel`. 설정(입력 문자열 그대로 `<서비스>_<이름>` 키로 저장), 상태, **그 서비스만의 로그**(`LogBus`, 보관 줄 수 선택), 클라이언트 스냅샷, 시작 절차(검증 → 점검 → 확인 → 시작)를 가집니다.
- `state/controller.dart`: 세 모델과 선택한 서비스, NIC 목록을 묶습니다.
- 화면은 앱 바(켜진 서비스의 접속 주소) + 사이드바(서비스 목록) + 서비스 화면입니다. 서비스 화면은 가운데 클라이언트 표, 아래 로그, 오른쪽에 접히는 설정 패널입니다. 서비스 설정은 서비스마다 따로 두고 한 화면에 섞지 않습니다.
- 서비스 로그는 번역하지 않은 ARB 키와 인자로 나가고 `ui/log_format.dart`가 문구로 바꿉니다. 새 로그 키를 만들면 포맷터와 ARB(ko·en)도 함께 더합니다(`test/log_format_test.dart`가 빠진 키와 안 쓰는 키를 잡습니다).

## 성능 원칙

3CDaemon의 약점(요청이 몰리면 화면이 굳음)을 피하는 것이 설계의 중심입니다.

- 패킷 처리 경로에서는 로그나 표를 만들지 않습니다. 표 스냅샷은 200~250ms에 한 번, 로그는 요청·완료·실패 같은 사건에만.
- 로그 패널은 보이는 줄만 그리고, 번역 문구를 줄마다 한 번만 만들며(`Expando`), 필터는 새 줄에만 적용합니다.
- 렌더러는 Skia입니다(Impeller는 `--enable-impeller`로 켬).

## 시험

`flutter test`로 돌립니다.

- `test/core/`: 서비스는 실제 loopback 소켓으로 시험합니다(`test/support/tftp_client.dart`, `ftp_client.dart`). DHCP는 가짜 전송(`fake_transport.dart`)으로 패킷을 주고받습니다.
- `test/home_screen_test.dart`: 위젯 시험. 실제 소켓·파일 I/O와 서비스 `stop()`은 `tester.runAsync`로 감싸고, 끝에서 화면을 내린 뒤 서비스를 멈춥니다.
- DHCP 실장비 시험은 같은 망의 다른 DHCP 서버를 방해할 수 있어 프로젝트 말미로 미룹니다.

## 배포

규약(`application-release-templates/conventions`)을 따릅니다: 태그 `vX.Y.Z`를 밀면 CI(`release.yml`)가 Windows 설치 프로그램(Inno Setup)을 만들어 GitHub Releases에 올립니다. 설치 프로그램은 관리자 권한으로 돌며 방화벽 인바운드 규칙을 넣고 지웁니다. 앱은 일반 권한으로 실행합니다.
