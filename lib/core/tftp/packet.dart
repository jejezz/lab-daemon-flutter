// TFTP 패킷 (RFC 1350)과 옵션 확장 (RFC 2347 옵션, 2348 blksize, 2349 timeout·tsize, 7440 windowsize).
//
// 모든 패킷은 2바이트 연산 코드로 시작하고 숫자는 빅엔디언이다.
//   RRQ/WRQ  | 01/02 | 파일 이름 \0 | 모드 \0 | (옵션 \0 값 \0)* |
//   DATA     | 03    | 블록 번호 2바이트 | 데이터 0~blksize바이트 |
//   ACK      | 04    | 블록 번호 2바이트 |
//   ERROR    | 05    | 오류 코드 2바이트 | 메시지 \0 |
//   OACK     | 06    | (옵션 \0 값 \0)* |

import 'dart:convert';
import 'dart:typed_data';

abstract final class TftpOp {
  static const rrq = 1;
  static const wrq = 2;
  static const data = 3;
  static const ack = 4;
  static const error = 5;
  static const oack = 6;
}

abstract final class TftpError {
  static const undefined = 0;
  static const notFound = 1;
  static const accessViolation = 2;
  static const diskFull = 3;
  static const illegalOperation = 4;
  static const unknownTid = 5;
  static const fileExists = 6;
  static const noSuchUser = 7;
  static const optionRefused = 8;
}

/// 기본 블록 크기 (옵션 협상이 없을 때).
const tftpDefaultBlockSize = 512;

/// 읽기·쓰기 요청 하나.
class TftpRequest {
  const TftpRequest({required this.write, required this.filename, required this.mode, required this.options});

  final bool write;
  final String filename;

  /// 소문자로 바꾼 전송 모드: `octet`, `netascii`, `mail`.
  final String mode;

  /// 옵션 이름(소문자) → 값.
  final Map<String, String> options;
}

/// RRQ/WRQ 파싱. 올바른 요청이 아니면 null.
TftpRequest? parseRequest(Uint8List data) {
  if (data.length < 6) return null;
  final op = (data[0] << 8) | data[1];
  if (op != TftpOp.rrq && op != TftpOp.wrq) return null;
  // \0으로 끝나는 문자열들로 나눈다. 마지막 문자열도 \0로 끝나야 한다.
  final strings = <String>[];
  var start = 2;
  for (var i = 2; i < data.length; i++) {
    if (data[i] != 0) continue;
    strings.add(utf8.decode(data.sublist(start, i), allowMalformed: true));
    start = i + 1;
  }
  if (start != data.length || strings.length < 2 || strings.length.isOdd) return null;
  if (strings[0].isEmpty) return null;
  final options = <String, String>{};
  for (var i = 2; i + 1 < strings.length; i += 2) {
    options.putIfAbsent(strings[i].toLowerCase(), () => strings[i + 1]);
  }
  return TftpRequest(write: op == TftpOp.wrq, filename: strings[0], mode: strings[1].toLowerCase(), options: options);
}

Uint8List buildRequest({required bool write, required String filename, String mode = 'octet', Map<String, String> options = const {}}) {
  final out = BytesBuilder();
  out.add([0, write ? TftpOp.wrq : TftpOp.rrq]);
  out.add(utf8.encode(filename));
  out.addByte(0);
  out.add(utf8.encode(mode));
  out.addByte(0);
  for (final MapEntry(key: k, value: v) in options.entries) {
    out.add(utf8.encode(k));
    out.addByte(0);
    out.add(utf8.encode(v));
    out.addByte(0);
  }
  return out.toBytes();
}

/// 블록 번호는 2바이트라서 65535 다음은 0으로 돈다 (큰 파일의 관례).
Uint8List buildData(int block, Uint8List payload) {
  final out = Uint8List(4 + payload.length);
  out[1] = TftpOp.data;
  out[2] = (block >> 8) & 0xFF;
  out[3] = block & 0xFF;
  out.setRange(4, out.length, payload);
  return out;
}

Uint8List buildAck(int block) => Uint8List.fromList([0, TftpOp.ack, (block >> 8) & 0xFF, block & 0xFF]);

Uint8List buildError(int code, String message) {
  final text = utf8.encode(message);
  return Uint8List.fromList([0, TftpOp.error, (code >> 8) & 0xFF, code & 0xFF, ...text, 0]);
}

Uint8List buildOack(Map<String, String> options) {
  final out = BytesBuilder();
  out.add([0, TftpOp.oack]);
  for (final MapEntry(key: k, value: v) in options.entries) {
    out.add(utf8.encode(k));
    out.addByte(0);
    out.add(utf8.encode(v));
    out.addByte(0);
  }
  return out.toBytes();
}

/// 연산 코드. 2바이트보다 짧으면 -1.
int tftpOpcode(Uint8List data) => data.length < 2 ? -1 : (data[0] << 8) | data[1];

/// DATA/ACK의 블록 번호. 4바이트보다 짧으면 -1.
int tftpBlock(Uint8List data) => data.length < 4 ? -1 : (data[2] << 8) | data[3];

/// ERROR 패킷의 코드와 메시지.
(int, String)? parseError(Uint8List data) {
  if (data.length < 5 || tftpOpcode(data) != TftpOp.error) return null;
  var end = data.length;
  if (data.last == 0) end--;
  return ((data[2] << 8) | data[3], utf8.decode(data.sublist(4, end < 4 ? 4 : end), allowMalformed: true));
}

/// OACK 패킷의 옵션 (이름은 소문자).
Map<String, String>? parseOack(Uint8List data) {
  if (data.length < 2 || tftpOpcode(data) != TftpOp.oack) return null;
  final strings = <String>[];
  var start = 2;
  for (var i = 2; i < data.length; i++) {
    if (data[i] != 0) continue;
    strings.add(utf8.decode(data.sublist(start, i), allowMalformed: true));
    start = i + 1;
  }
  if (strings.length.isOdd) return null;
  return {for (var i = 0; i < strings.length; i += 2) strings[i].toLowerCase(): strings[i + 1]};
}
