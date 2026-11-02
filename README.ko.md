<!-- From jejezz/application-release-templates common/tool/readme @ conventions-v1.
     tool/readme/init_readme.py가 만든 파일입니다 — conventions/readme-guide.md 참고.
     {{TODO: …}}를 모두 채우십시오. 하나라도 남아 있으면 tool/readme/check_readme.py가 실패합니다. -->

<p align="center">
  <img src="assets/icon/app_icon.png" width="128" alt="Lab Daemon 아이콘">
</p>

<h1 align="center">Lab Daemon</h1>

<p align="center">
  랩 환경을 위한 <b>Windows 네트워크 서비스 실행기</b> — DHCP, TFTP, FTP 서버를 함께 켜고 Lease·전송·로그를 실시간으로 확인합니다.
</p>

<p align="center">
  <a href="https://github.com/jejezz/lab-daemon-flutter/releases/latest"><img src="https://img.shields.io/github/v/release/jejezz/lab-daemon-flutter?style=flat-square&color=4c9dff" alt="최신 릴리스"></a>
  <a href="https://github.com/jejezz/lab-daemon-flutter/releases"><img src="https://img.shields.io/github/downloads/jejezz/lab-daemon-flutter/total?style=flat-square&color=7c5cff" alt="다운로드"></a>
  <img src="https://img.shields.io/badge/platform-Windows-34d399?style=flat-square" alt="Windows">
  <img src="https://img.shields.io/badge/built%20with-Flutter-02569b?style=flat-square" alt="Flutter">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/jejezz/lab-daemon-flutter?style=flat-square" alt="MIT 라이선스"></a>
</p>

<p align="center">
  <a href="README.md">English</a> · <b>한국어</b>
</p>

<p align="center">
  <img src="docs/screenshots/demo.gif" width="720" alt="Lab Daemon 데모: {{TODO: GIF가 보여주는 흐름}}">
</p>

## 기능

- **{{TODO: 기능}}** — {{TODO: 무엇을 하는지 구체적으로 (이름, 숫자, 형식)}}
- **{{TODO: 기능}}** — {{TODO: …}}
- **{{TODO: 기능}}** — {{TODO: …}}
- **라이트·다크, 한국어·English** — 시스템 설정을 따르거나 툴바에서 고를 수 있습니다

<p align="center">
  <img src="docs/screenshots/home.png" width="360" alt="{{TODO: 화면 1}}">
  <img src="docs/screenshots/detail.png" width="360" alt="{{TODO: 화면 2}}">
</p>

## 설치

[**Releases**](https://github.com/jejezz/lab-daemon-flutter/releases/latest)에서 받습니다.

| OS | 파일 |
|---|---|
| Windows 10/11 (x64) | `LabDaemon-<버전>-windows-x64-setup.exe` |

**Windows:** 설치 프로그램에 아직 코드 서명이 없어서 SmartScreen이 "Windows의 PC 보호" 창을 띄웁니다. **추가 정보 → 실행**을 누르세요.

## 동작 방식

{{TODO: 궁금한 사람을 위한 2~4문장 — 흥미로운 기술적 선택 한 가지. 말할 것이 없으면 이 절을 지웁니다.}}

## 개발

```bash
flutter pub get
flutter run -d windows
```

{{TODO: 빌드에 더 필요한 것(네이티브 도구, 환경 변수). 구조 문서 링크: [ARCHITECTURE.md](ARCHITECTURE.md), [UI_UX.md](UI_UX.md).}}

릴리스: `scripts/bump-version.sh patch` → 병합 → `vX.Y.Z` 태그. CI가 모든 플랫폼을 빌드해서 올립니다. 규칙: [application-release-templates/conventions](https://github.com/jejezz/application-release-templates/tree/main/conventions).

## 크레딧

- 글꼴: [서울남산체](https://www.seoul.go.kr/seoul/font.do) (서울특별시)
- 아이콘: [Icons8](https://icons8.com)

## 라이선스

[MIT](LICENSE) © 2026 Jongyun Ahn
