// UDP 송신 큐. `RawDatagramSocket.send`는 OS의 송신 버퍼가 차면 0을 돌려주고 그 데이터그램은 버려진다.
// Windows에서는 몇 개만 연달아 보내도 흔하게 일어난다 (시험: 8개 묶음의 60~75%가 0을 돌려줌).
// 그런 데이터그램을 줄 세워 두었다가 소켓이 다시 쓰기 가능해지면(RawSocketEvent.write) 순서대로 보낸다.
//
// 쓰는 쪽은 소켓 이벤트 처리기에서 [RawSocketEvent.write]를 받으면 [onWritable]을 불러야 한다.

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

class UdpSendQueue {
  UdpSendQueue(this.socket, {this.limit = 4096});

  final RawDatagramSocket socket;

  /// 줄 세울 수 있는 최대 데이터그램 수. 넘치면 가장 오래된 것부터 버린다 (상대가 응답하지 않는 경우의 상한).
  final int limit;

  final _pending = Queue<(Uint8List, InternetAddress, int)>();
  var _dropped = 0;

  int get pending => _pending.length;

  /// 상한을 넘어 버린 수.
  int get dropped => _dropped;

  void send(Uint8List data, InternetAddress address, int port) {
    if (_pending.isEmpty) {
      try {
        if (socket.send(data, address, port) > 0) return;
      } on SocketException {
        rethrow;
      }
    }
    _pending.add((data, address, port));
    while (_pending.length > limit) {
      _pending.removeFirst();
      _dropped++;
    }
    socket.writeEventsEnabled = true;
  }

  /// 쓰기 가능해졌을 때 밀린 데이터그램을 보낸다. 다시 막히면 다음 쓰기 이벤트를 기다린다.
  void onWritable() {
    while (_pending.isNotEmpty) {
      final (data, address, port) = _pending.first;
      if (socket.send(data, address, port) == 0) {
        socket.writeEventsEnabled = true;
        return;
      }
      _pending.removeFirst();
    }
  }

  void clear() => _pending.clear();
}
