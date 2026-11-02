# Lab Daemon 계획서 (v3, Flutter / conventions-v1 기준)

> 근거: `application-release-templates`의 `conventions/` 및 `skills/flutter-app-bootstrap`.
> 규약이 "기능 구현 전에" 끝내라고 한 항목을 **P0**으로 먼저 두고, 서비스 기능은 그 뒤에 올린다.

## 1. 목적
3CDaemon처럼 랩/개발 환경에서 필요한 네트워크 서비스(**DHCP, TFTP, FTP**, 이후 Syslog 등)를
한 앱에서 켜고 끄며 실시간으로 모니터링하는 Windows용 Flutter 데스크톱 앱.
대표 시나리오: 보드 전원 → DHCP로 IP + 부팅 서버/파일 안내(option 66/67) → TFTP로 이미지 전송 → FTP/Syslog로 펌웨어·로그 교환.

## 2. 앱 정체성 (identity.md) — 확정
| 항목 | 값 | 비고 |
|---|---|---|
| 표시 이름 | **Lab Daemon** | `AppInfo.xcconfig PRODUCT_NAME`이 원본 |
| 파일 이름 | `LabDaemon` | 산출물, 설정 폴더 `%APPDATA%\LabDaemon` |
| 패키지 / 바이너리 | `lab_daemon` | pubspec `name:` |
| 저장소 | `lab-daemon-flutter` | `github.com/jejezz/lab-daemon-flutter` |
| 식별자 | `art.zoomon.labdaemon` | 모든 플랫폼 동일, 릴리스 후 변경 불가 |
| 게시자 / 저작권자 | `Jongyun Ahn` / `Copyright © 2026 Jongyun Ahn` | |
| 라이선스 | MIT | |
| 시작 버전 | `0.1.0-rc.1+1` → 첫 태그 `v0.1.0-rc.1` | 데스크톱 규칙 |
| Inno `AppId` | 새 GUID(`uuidgen`) | 릴리스 후 변경 금지 |

## 3. 플랫폼
- **1차: Windows만** (`flutter create --platforms=windows`). 릴리스 워크플로에서 macOS/Linux 잡 제거(추후 확장 시 복원).
- 데스크톱 전용 → 설정 UI는 `AlertDialog` + 좌측 섹션 구조 (settings-screen.md §1).
- **관리자 권한 (확정)**: 앱은 일반 권한(`asInvoker`)으로 실행한다. 일반 권한 프로세스에서 UDP 67/69, TCP 21 바인딩이 되는 것을 확인했다(2026-11-02). 방화벽 인바운드 규칙은 관리자 권한으로 도는 설치 프로그램이 추가·제거한다(`profile=any`).
  - P2에서 DHCP 응답(주소 없는 클라이언트에 대한 unicast 등)이 일반 권한에서 되는지 장비로 검증한다. 승격이 필요한 기능이 확인되면 서비스 호스트를 별도 관리자 프로세스로 분리하고(loopback TCP + 토큰), 서비스 시작 시점에만 UAC를 띄운다. 이를 위해 서비스는 `ServiceHost` 인터페이스(Isolate 구현 / 프로세스 구현)로 감싼다.

## 4. 서비스 구조 (핵심 설계)

### 4.1 공통 추상화
```dart
abstract class NetService {
  String get id;                       // 'dhcp' | 'tftp' | 'ftp' | ...
  ServiceState get state;              // stopped / starting / running / error
  Stream<ServiceEvent> get events;     // 로그·세션·전송·통계
  Future<void> start(ServiceConfig c);
  Future<void> stop();
}
```
- 서비스마다 **별도 Isolate**에서 실행, `SendPort`로 이벤트 전달·명령 수신. UI 스레드를 막지 않는다.
- **공용 로그 버스** 하나, 이벤트에 출처(서비스 id)·레벨·종류·키+인자(l10n)를 담는다.
- 서비스별 설정: 바인딩 NIC/IP, 포트, 루트 폴더(TFTP/FTP), 자동 시작 여부.
- 서비스 간 연동: DHCP의 option 66/67 기본값을 TFTP 설정(서버 IP·부팅 파일)에서 자동 채움.

### 4.2 서비스별 범위
| 서비스 | 1차 범위 | 이후 |
|---|---|---|
| **DHCP** | DORA/NAK/RELEASE/DECLINE/INFORM/RENEW, Range·마스크·GW·DNS·Lease Time, Lease 해제, 예약, 옵션(15/42/66/67), 충돌 검사, 기존 서버 감지, 영속화 | MAC 허용/차단, 이벤트 훅 |
| **TFTP** | RFC 1350 읽기/쓰기, 옵션 `blksize`/`tsize`/`timeout`(RFC 2347–2349), `windowsize`(RFC 7440), 루트 폴더 jail, 덮어쓰기/쓰기 허용 옵션, 전송 목록(진행률·속도) | 파일별 접근 제어 |
| **FTP** | 최소 명령: USER/PASS, PASV/EPSV, LIST/NLST, RETR, STOR, CWD, PWD, TYPE, SIZE, DELE, MKD/RMD, QUIT. 계정 목록, 루트 jail, 쓰기 권한 옵션, 세션 목록 | FTPS, 대역폭 제한 |
| **Syslog 수신** (선택) | UDP 514 수신, 소스별 필터, 파일 저장 | |

### 4.3 보안 원칙
- 기본 **선택한 NIC에만 바인딩**. 모든 인터페이스(0.0.0.0) 바인딩은 명시적 옵션.
- FTP는 평문 → 익명 접속 기본 꺼짐, 쓰기 기본 꺼짐, 경로 탈출(`..`, 절대경로, 심볼릭 링크) 차단.
- 시작 전 점검 다이얼로그: 포트 점유, NIC 고정 IP 여부, 기존 DHCP 감지, 루트 폴더 존재.

## 5. 요구사항 (DHCP 기준, 사용자 요청)
| # | 항목 | 구현 |
|---|---|---|
| R1 | 관리자 권한 | 일반 권한으로 실행, 설치 프로그램이 방화벽 규칙 추가(§3). 승격이 필요해지면 서비스 시작 시점에만 요청 |
| R2 | Range / 서브넷 / 게이트웨이 | DHCP 설정 섹션, 형식·범위·서브넷 소속 검증 |
| R3 | 실시간 상태·강화된 로그 | 서비스 목록 상태 + 서비스별 표 + 공용 로그 패널(필터·일시정지·복사·파일 저장) |
| R4 | Lease 해제 | 개별/전체. 우클릭, 버튼, `Del`, `Ctrl+Shift+Del`. 확인 대화상자 |
| R5 | Lease Time | `30s`, `10m`, `12h`, `infinite` |

추가 제안(NIC 선택, 기존 서버 감지, 예약, DNS/옵션, 영속화, 충돌 검사, 로그 파일, 통계, 이벤트 훅)은 DHCP 코어에 §4.2대로 배치.

## 6. 규약에서 오는 필수 사항 (P0)
| 영역 | 규약 | 이 앱에서의 적용 |
|---|---|---|
| 디자인 | Saturn 테마, M3, `GlassCard`/`StatusPill` | `common/lib/theme/app_theme.dart` 복사. 서비스 상태·Lease 상태는 `StatusPill` |
| 밀도 | 본문/행 13, 보조 11, 앱 바 44, 앱 바 아이콘 20 통일, 밀집 목록 `NoSplash` | 표·로그 밀집 |
| 창 | 작업 앱 1200×720, 최소 960×600, `WindowPlacement`, 첫 프레임 뒤 `show()` | `flutter_window.cpp`의 자동 `Show()` 제거 |
| 언어 | gen-l10n, ko 기준 + en 필수, 첫 커밋부터 ARB, `localeResolutionCallback` | UI·로그 문구 모두 ARB 키. 패킷 원문·파일명은 제외 |
| 설정 | `AlertDialog`+좌측 섹션, "외형"(모드·색 구성·언어) 첫 섹션, 키 `theme_mode`/`theme_palette`/`app_locale`/`text_scale`, 앱 고유 `<기능>_<이름>` | 섹션: 외형 / 일반(NIC·권한·자동 시작) / DHCP / TFTP / FTP / 로그. 앱 바 `… 설정 \| 정보`, `Ctrl+,` |
| 정보 창 | `showAppAboutDialog`, 버전 `package_info_plus`, 추가 라이선스 | `common/lib/about/` 복사 |
| 글꼴 | SeoulNamsan 400/700/800 + 고정폭 | 로그·MAC/IP는 고정폭 |
| 아이콘 | `assets/icon/source_glyph.png` → `generate_icons.py` | Icons8 글리프 필요(없으면 임시 글리프 + 잔여 항목) |
| 키보드 | 주요 기능 단축키, 우클릭 메뉴에 표기 | `Space` 선택 서비스 시작/중지, `Ctrl+R`, `Del`, `Ctrl+Shift+Del`, `Ctrl+F`(로그 찾기), `F1` |
| 오류/확인 | 스낵바+복사 액션, 되돌릴 수 없는 작업만 확인(기본 포커스 취소) | 포트 점유, 권한, 잘못된 입력 |
| 업데이트 | `app_updater`(updater-v0.1.0), `APP_VERSION` define | `lib/update/` 복사 |
| 버전/태그 | `pubspec.yaml` 원본, build +1, annotated 태그, `chore(release): vX.Y.Z`, 한국어 Conventional Commits | `scripts/bump-version.sh` |
| 릴리스 | `check → 빌드 → release`, Flutter 3.47.1 고정, `LabDaemon-<ver>-windows-x64-setup.exe` + `SHA256SUMS.txt` | Inno `app.iss`: en+ko, 방화벽 규칙 추가 옵션 검토 |
| README / CLAUDE.md | `init_readme.py` en/ko 뼈대, `conventions-v1` 한 줄 | rc 단계는 구조만 |
| 검증 | `flutter gen-l10n && flutter analyze && flutter test`, `tools/audit_app.py --stage bootstrap` | ❌ 0개 |

## 7. 코드 구조
```
lab-daemon-flutter/
  lib/
    main.dart, app_identity.dart
    theme/ settings/ about/ window/ update/      # common 복사
    core/                                         # 순수 Dart (Flutter 의존 없음)
      service.dart        # NetService, ServiceState, ServiceEvent, 로그 버스
      netutil.dart        # NIC 열거, ICMP/ARP, 포트 점유 확인
      dhcp/ packet.dart pool.dart server.dart store.dart
      tftp/ packet.dart server.dart session.dart
      ftp/  commands.dart server.dart session.dart auth.dart
    state/                # ServiceController: Isolate 중개, 서비스 레지스트리
    ui/                   # home(사이드바+본문), dhcp_view, tftp_view, ftp_view, log_panel, settings_dialog
    l10n/ app_ko.arb, app_en.arb
  test/                   # 코어 단위 테스트 + common 테스트
  windows/runner/runner.exe.manifest
```

## 8. 화면
```
┌ AppBar: Lab Daemon                                      [설정] [정보] ┐
├ 서비스 ─┬ 본문 (선택한 서비스) ──────────────────────────────────────┤
│ ●DHCP ▶ │ 상태 바: NIC · Pool · GW · Lease · 사용률 · 통계            │
│ ●TFTP ▶ │ Lease 표 / 전송 목록 / 세션 목록                            │
│ ○FTP  ▶ │                                                             │
├─────────┴─────────────────────────────────────────────────────────────┤
│ 로그 패널 (출처·레벨 필터, 고정폭, 색상, 일시정지, 복사, 저장)         │
└────────────────────────────────────────────────────────────────────────┘
```
빈 상태: 48px 아이콘 + 안내 + "서비스 시작" 버튼.

## 9. 위험 / 주의
- **Windows UDP 67/69**: ICS 등 점유 시 바인딩 실패 → 점유 프로세스 안내.
- **수신 NIC 식별 불가**: `RawDatagramSocket`은 수신 인터페이스 정보를 주지 않음 → 선택 NIC IP에 바인딩, 실제 장비 검증.
- **TFTP 전송 포트**: 요청마다 임시 포트(TID)를 쓰므로 방화벽 규칙은 프로그램 단위로 설계.
- **FTP 패시브 포트 범위**: 고정 범위 지정 + 방화벽 규칙.
- **ARP/ICMP**: Dart 기본 API에 없음 → `ping` 호출 우선, 필요 시 FFI `SendARP`.
- **서버 NIC는 고정 IP 필요**: 시작 시 검사·경고.
- **회사망 오염 방지**: NIC 확인 + 기존 DHCP 감지 필수.

## 10. 마일스톤
| 단계 | 내용 | 완료 기준 |
|---|---|---|
| **P0** 부트스트랩 | `flutter-app-bootstrap` 절차(정체성, common 복사, 테마·l10n·설정·정보·업데이트, 워크플로, README 뼈대, CLAUDE.md, 매니페스트) | `audit_app.py --stage bootstrap` ❌ 0, 로컬 빌드 성공 |
| **P0b** 첫 태그 | `v0.1.0-rc.1` 푸시 | 프리릴리스에 설치 프로그램 + SHA256SUMS |
| **P1** 코어 | `NetService` 추상화, 로그 버스, DHCP 패킷/풀 + 단위 테스트 | 테스트 통과 |
| **P2** DHCP 서버 | Isolate 서버, DORA, 기본 설정, NIC 선택, **권한 방식 확정** | 실제 장비 1대 IP 수신 |
| **P3** DHCP UI | 사이드바, 상태 바, Lease 표, 로그 패널, 해제, 설정 섹션, 단축키 | 실시간 갱신, 해제 후 재할당 |
| **P4** DHCP 확장 | 예약, 영속화, 충돌 검사, 기존 서버 감지, 로그 파일, 옵션 | 재시작 후 Lease 유지 |
| **P5** TFTP | 서버, 옵션 협상, 전송 목록, DHCP option 66/67 연동 | 보드가 DHCP→TFTP로 이미지 수신 |
| **P6** FTP | 최소 명령, 계정, jail, 세션 목록 | 일반 FTP 클라이언트로 업/다운로드 |
| **P7** 마감 | 스크린샷·데모 GIF, README 완성, 도움말, 정식 `v0.1.0` | `release-check` 통과 |
| 이후 | Syslog 수신, macOS/Linux 확장 | |

테스트: 코어 단위 테스트, Wireshark + 가상 클라이언트(Hyper-V VM/스크립트)로 통신 확인.

## 11. 남은 결정
1. 1차 릴리스(`v0.1.0`) 범위: DHCP만 / DHCP+TFTP / 3개 모두?
2. ~~관리자 권한~~ → 확정: 일반 권한 실행 + 설치 시 방화벽 규칙(§3).
3. Syslog 수신을 로드맵에 넣을지.
4. 프로젝트 위치: `C:\Users\jejez\MyWork\Projects\FLUTTER\lab-daemon-flutter`(제안)?
5. 아이콘 글리프(Icons8 투명 PNG)를 줄 수 있는지, 임시 글리프로 시작할지.
