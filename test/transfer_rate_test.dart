import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/tftp/server.dart';
import 'package:lab_daemon/core/tftp/transfer.dart';
import 'package:lab_daemon/ui/clients/client_tables.dart';

TftpTransferInfo _info({required TransferState state, required int bytes, DateTime? endedAt, double rate = 0}) => TftpTransferInfo(
      id: 1,
      client: '127.0.0.1:1000',
      file: 'a.bin',
      upload: false,
      state: state,
      bytes: bytes,
      size: bytes,
      startedAt: DateTime(2026, 11, 13, 10),
      endedAt: endedAt,
      rate: rate,
      blksize: 512,
      windowsize: 1,
      mode: 'octet',
      failure: null,
      failureDetail: null,
    );

void main() {
  test('전송 중에는 지금 속도, 끝난 전송은 평균 속도를 보인다', () {
    final start = DateTime(2026, 11, 13, 10);
    expect(tftpRateText(_info(state: TransferState.active, bytes: 1, rate: 2 * 1024 * 1024), true), '2.0 MB/s');
    expect(tftpRateText(_info(state: TransferState.done, bytes: 4 * 1024 * 1024, endedAt: start.add(const Duration(seconds: 2))), false), '2.0 MB/s');
  });

  test('바이트가 없거나 시간이 0이면 비운다', () {
    final start = DateTime(2026, 11, 13, 10);
    expect(tftpRateText(_info(state: TransferState.failed, bytes: 0, endedAt: start.add(const Duration(seconds: 1))), false), '');
    expect(tftpRateText(_info(state: TransferState.done, bytes: 100, endedAt: start), false), '');
  });
}
