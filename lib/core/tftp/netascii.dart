// netascii 변환 (RFC 764 / 1350): 줄 끝이 줄바꿈(LF)인 파일과 네트워크의 CR LF 사이를 오간다.
//   보내기: LF → CR LF, 홀로 있는 CR → CR NUL
//   받기:   CR LF → LF, CR NUL → CR
// Windows의 `tftp` 명령은 `-i`를 주지 않으면 netascii로 전송한다. 블록 경계에서 CR과 그 다음 글자가
// 갈라질 수 있어서 변환기는 상태를 가진다.

import 'dart:typed_data';

/// 파일 → 네트워크 (보내기). 입력을 조각으로 넣어도 같은 결과가 나온다.
class NetasciiEncoder {
  Uint8List convert(Uint8List input) {
    final out = BytesBuilder(copy: false);
    final chunk = <int>[];
    for (final b in input) {
      if (b == 0x0A) {
        chunk
          ..add(0x0D)
          ..add(0x0A);
      } else if (b == 0x0D) {
        chunk
          ..add(0x0D)
          ..add(0x00);
      } else {
        chunk.add(b);
      }
    }
    out.add(chunk);
    return out.toBytes();
  }
}

/// 네트워크 → 파일 (받기). 마지막 CR이 다음 조각의 첫 글자를 기다릴 수 있다.
class NetasciiDecoder {
  bool _pendingCr = false;

  Uint8List convert(Uint8List input) {
    final out = <int>[];
    for (final b in input) {
      if (_pendingCr) {
        _pendingCr = false;
        if (b == 0x0A) {
          out.add(0x0A);
          continue;
        }
        if (b == 0x00) {
          out.add(0x0D);
          continue;
        }
        // CR 뒤에 이상한 글자: CR을 그대로 두고 이 글자를 이어서 처리한다.
        out.add(0x0D);
      }
      if (b == 0x0D) {
        _pendingCr = true;
      } else {
        out.add(b);
      }
    }
    return Uint8List.fromList(out);
  }

  /// 전송이 끝났을 때 남은 CR을 내보낸다.
  Uint8List finish() {
    if (!_pendingCr) return Uint8List(0);
    _pendingCr = false;
    return Uint8List.fromList([0x0D]);
  }
}
