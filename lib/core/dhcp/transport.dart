// UDP 송수신 추상화. 서버는 이 인터페이스만 알아서, 테스트는 소켓 없이 가짜 구현으로 DORA를 돌린다.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../ipv4.dart';
import '../udp_queue.dart';

export '../socket_errors.dart' show isAddressInUse, isPermissionDenied;

class DhcpDatagram {
  const DhcpDatagram(this.data, this.from, this.port);

  final Uint8List data;
  final Ipv4 from;
  final int port;
}

abstract interface class DhcpTransport {
  Stream<DhcpDatagram> get incoming;

  /// 실제로 묶인 포트 (0을 요청했으면 OS가 정한 포트).
  int get port;

  void send(Uint8List data, Ipv4 address, int port);

  Future<void> close();
}

typedef DhcpTransportFactory = Future<DhcpTransport> Function(Ipv4 bindAddress, int port);

/// `RawDatagramSocket` 구현. 브로드캐스트를 켜고, 다른 프로그램과 포트를 공유하지 않는다
/// (`reuseAddress: false`) — 이미 쓰고 있으면 바인딩이 실패해서 원인을 알려 줄 수 있다.
class UdpDhcpTransport implements DhcpTransport {
  UdpDhcpTransport._(this._socket) : _out = UdpSendQueue(_socket, limit: 256) {
    _subscription = _socket.listen((event) {
      if (event == RawSocketEvent.write) {
        _out.onWritable();
        return;
      }
      if (event != RawSocketEvent.read) return;
      for (var d = _socket.receive(); d != null; d = _socket.receive()) {
        _controller.add(DhcpDatagram(d.data, Ipv4.parse(d.address.address), d.port));
      }
    }, onError: _controller.addError, onDone: _controller.close);
  }

  static Future<UdpDhcpTransport> bind(Ipv4 address, int port, {bool reuseAddress = false}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress(address.toString()), port, reuseAddress: reuseAddress);
    socket.broadcastEnabled = true;
    return UdpDhcpTransport._(socket);
  }

  final RawDatagramSocket _socket;
  final UdpSendQueue _out;
  late final StreamSubscription<RawSocketEvent> _subscription;
  final _controller = StreamController<DhcpDatagram>.broadcast(sync: true);

  @override
  Stream<DhcpDatagram> get incoming => _controller.stream;

  @override
  int get port => _socket.port;

  @override
  void send(Uint8List data, Ipv4 address, int port) {
    _out.send(data, InternetAddress(address.toString()), port);
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    _socket.close();
    await _controller.close();
  }
}
