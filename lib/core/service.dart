// 서비스 추상화와 공용 로그 버스 (PLAN.md §4.1). 이 폴더(lib/core/)는 Flutter에 의존하지 않는 순수 Dart다.
//
// - NetService: DHCP / TFTP / FTP 같은 서비스 하나. 시작·중지, 상태, 이벤트 스트림을 가진다.
// - ServiceEvent: 서비스가 밖으로 내보내는 모든 것. 로그와 상태 변화가 기본이고, 서비스마다 자기 이벤트
//   (Lease 변경, 전송 진행률 등)를 더한다.
// - LogBus: 모든 서비스의 로그를 한 줄기로 모으고 최근 N개를 들고 있다.
//
// 로그 문구는 번역하지 않는다: [LogEvent.key]와 [LogEvent.args]만 담고, 화면이 ARB에서 문구를 찾는다
// (conventions/localization.md). 패킷 원문 같은 데이터는 [LogEvent.detail]에 둔다.

import 'dart:async';
import 'dart:collection';

enum ServiceState { stopped, starting, running, stopping, error }

enum LogLevel { debug, info, warning, error }

abstract class ServiceEvent {
  ServiceEvent(this.service, {DateTime? time}) : time = time ?? DateTime.now();

  /// 이벤트를 낸 서비스의 [NetService.id].
  final String service;
  final DateTime time;
}

final class LogEvent extends ServiceEvent {
  LogEvent(
    super.service,
    this.level,
    this.key, {
    this.kind,
    this.args = const {},
    this.detail,
    super.time,
  });

  final LogLevel level;

  /// ARB 키. 예: `logDhcpOffer`.
  final String key;

  /// 필터에 쓰는 짧은 종류. 예: `DISCOVER`, `OFFER`.
  final String? kind;

  /// ARB 문구에 채울 값. 예: `{'ip': '192.168.50.100', 'mac': 'aa:bb:...'}`.
  final Map<String, Object?> args;

  /// 번역하지 않는 부가 내용 (패킷 16진수 덤프 등).
  final String? detail;
}

final class StateEvent extends ServiceEvent {
  StateEvent(super.service, this.state, {this.error, super.time});

  final ServiceState state;

  /// [ServiceState.error]일 때의 원인 (원문, 번역하지 않는다).
  final String? error;
}

/// 모든 서비스가 공유하는 로그 버스. 최근 [capacity]개를 보관하고 새 이벤트를 스트림으로 내보낸다.
class LogBus {
  LogBus({this.capacity = 2000});

  final int capacity;
  final _history = Queue<LogEvent>();
  final _controller = StreamController<LogEvent>.broadcast(sync: true);

  Stream<LogEvent> get stream => _controller.stream;

  /// 오래된 것부터.
  List<LogEvent> get history => List.unmodifiable(_history);

  void add(LogEvent event) {
    _history.addLast(event);
    while (_history.length > capacity) {
      _history.removeFirst();
    }
    _controller.add(event);
  }

  void clear() => _history.clear();

  Future<void> dispose() => _controller.close();
}

/// 서비스 설정의 표식. 서비스마다 자기 설정 클래스가 이를 구현한다.
abstract interface class ServiceConfig {}

abstract interface class NetService<C extends ServiceConfig> {
  /// `dhcp`, `tftp`, `ftp`처럼 변하지 않는 이름. 로그 필터와 설정 저장에 쓴다.
  String get id;

  ServiceState get state;

  /// 마지막 오류 원인. [ServiceState.error]가 아니면 null.
  String? get error;

  /// 로그, 상태 변화, 서비스 고유 이벤트. 브로드캐스트 스트림이다.
  Stream<ServiceEvent> get events;

  /// 멈춘 상태(또는 오류 상태)에서만 시작할 수 있다. 실패하면 상태가 error가 되고 예외를 다시 던진다.
  Future<void> start(C config);

  /// 이미 멈췄으면 아무것도 하지 않는다.
  Future<void> stop();
}

/// [NetService]의 공통 골격: 상태 전이, 이벤트 스트림, 로그 발행을 맡고 서비스는 [onStart]/[onStop]만 쓴다.
abstract class BaseNetService<C extends ServiceConfig> implements NetService<C> {
  BaseNetService(this.id, this.bus);

  @override
  final String id;

  final LogBus bus;

  final _events = StreamController<ServiceEvent>.broadcast(sync: true);
  ServiceState _state = ServiceState.stopped;
  String? _error;

  @override
  ServiceState get state => _state;

  @override
  String? get error => _error;

  @override
  Stream<ServiceEvent> get events => _events.stream;

  @override
  Future<void> start(C config) async {
    if (_state != ServiceState.stopped && _state != ServiceState.error) {
      throw StateError('$id is $_state');
    }
    _setState(ServiceState.starting);
    try {
      await onStart(config);
    } catch (e) {
      await _quietly(onStop);
      _setState(ServiceState.error, error: e.toString());
      rethrow;
    }
    _setState(ServiceState.running);
  }

  @override
  Future<void> stop() async {
    if (_state == ServiceState.stopped || _state == ServiceState.stopping) return;
    _setState(ServiceState.stopping);
    try {
      await onStop();
    } finally {
      _setState(ServiceState.stopped);
    }
  }

  /// 소켓을 열고 수신을 시작한다. 던지면 서비스는 error 상태가 된다.
  Future<void> onStart(C config);

  /// 소켓을 닫고 타이머를 멈춘다. 시작에 실패한 뒤에도 불리므로 반쯤 열린 상태를 견뎌야 한다.
  Future<void> onStop();

  /// 서비스 고유 이벤트를 내보낸다 (Lease 변경 등).
  void emit(ServiceEvent event) {
    if (!_events.isClosed) _events.add(event);
    if (event is LogEvent) bus.add(event);
  }

  void log(LogLevel level, String key, {String? kind, Map<String, Object?> args = const {}, String? detail}) =>
      emit(LogEvent(id, level, key, kind: kind, args: args, detail: detail));

  void _setState(ServiceState next, {String? error}) {
    _state = next;
    _error = next == ServiceState.error ? error : null;
    emit(StateEvent(id, next, error: _error));
  }

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}

/// 서비스 목록과 합쳐진 이벤트 스트림.
class ServiceRegistry {
  final _services = <String, NetService>{};
  final _subscriptions = <String, StreamSubscription<ServiceEvent>>{};
  final _events = StreamController<ServiceEvent>.broadcast(sync: true);

  List<NetService> get all => List.unmodifiable(_services.values);

  NetService? operator [](String id) => _services[id];

  Stream<ServiceEvent> get events => _events.stream;

  void register(NetService service) {
    if (_services.containsKey(service.id)) throw ArgumentError('Service already registered: ${service.id}');
    _services[service.id] = service;
    _subscriptions[service.id] = service.events.listen(_events.add);
  }

  Future<void> dispose() async {
    for (final s in _services.values) {
      await s.stop();
    }
    for (final sub in _subscriptions.values) {
      await sub.cancel();
    }
    await _events.close();
  }
}
