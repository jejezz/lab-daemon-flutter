## 설치 / Install

| OS | 받을 파일 / File |
|---|---|
| Windows 10/11 (x64) | `*-windows-x64-setup.exe` |

**Windows**: 설치 프로그램에 아직 코드 서명이 없어서 SmartScreen이 "Windows의 PC 보호" 창을 띄웁니다. **추가 정보 → 실행**을 누르면 설치가 진행됩니다.
The installer isn't code-signed yet, so SmartScreen shows "Windows protected your PC" — choose **More info → Run anyway**.

받은 파일은 `SHA256SUMS.txt`로 확인할 수 있습니다: `certutil -hashfile <파일> SHA256` 결과가 `SHA256SUMS.txt`와 같은지 비교하세요
