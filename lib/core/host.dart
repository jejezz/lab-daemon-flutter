// 서비스를 돌리는 곳. 화면은 [ServiceHost]만 알고, 서비스가 같은 프로세스 안에서 도는지(테스트) 별도
// Isolate에서 도는지(앱) 모른다.
//
// [IsolateHost]가 성능의 핵심이다 (PLAN.md §4.1):
//   - 패킷 처리, 파일 읽기·쓰기, 로그 만들기는 모두 서비스 Isolate에서 일어나서 화면 스레드를 쓰지 않는다.
//   - 이벤트는 [batchInterval]마다 한 덩어리로 묶어 보낸다. 같은 종류의 스냅샷(Lease 표 등)은 최신 것만 보내고,
//     한 번에 너무 많은 로그가 쌓이면 넘치는 것은 버리고 개수만 알린다 → 어떤 부하에서도 화면으로 가는
//     메시지 양에 상한이 있다.

import 'dart:async';
import 'dart:isolate';

import 'service.dart';

/// 서비스를 만드는 함수. Isolate로 건너가야 하므로 반드시 최상위(또는 static) 함수여야 한다.
typedef ServiceFactory = NetService<ServiceConfig> Function();

class ServiceStartException implements Exception {
  ServiceStartException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ServiceHost {
  String get id;

  ServiceState get state;

  String? get error;

  Stream<ServiceEvent> get events;

  Future<void> start(Map<String, Object?> config);

  Future<void> stop();

  /// 서비스 고유 명령의 결과. 서비스가 던진 오류는 [ServiceStartException]이 아니라 일반 [StateError] 문구로 온다.
  Future<Object?> command(String name, [Map<String, Object?> args = const {}]);

  Future<void> dispose();
}

/// 같은 Isolate 안에서 서비스를 그대로 돌린다. 위젯 테스트와 단위 테스트용이다.
class InProcessHost implements ServiceHost {
  InProcessHost(this.service);

  final NetService<ServiceConfig> service;

  @override
  String get id => service.id;

  @override
  ServiceState get state => service.state;

  @override
  String? get error => service.error;

  @override
  Stream<ServiceEvent> get events => service.events;

  @override
  Future<void> start(Map<String, Object?> config) => service.start(service.decodeConfig(config));

  @override
  Future<void> stop() => service.stop();

  @override
  Future<Object?> command(String name, [Map<String, Object?> args = const {}]) => service.command(name, args);

  @override
  Future<void> dispose() => service.stop();
}

/// 서비스를 자기 Isolate에서 돌린다. Isolate는 처음 시작할 때 만들고, 오류로 죽으면 다음 시작 때 다시 만든다.
class IsolateHost implements ServiceHost {
  IsolateHost(this.id, this._factory, {this.batchInterval = const Duration(milliseconds: 100)});

  @override
  final String id;

  final ServiceFactory _factory;
  final Duration batchInterval;

  Isolate? _isolate;
  SendPort? _worker;
  ReceivePort? _inbox;
  ReceivePort? _errors;
  Future<SendPort>? _spawning;
  final _pending = <int, Completer<Object?>>{};
  var _nextRequest = 0;

  final _events = StreamController<ServiceEvent>.broadcast(sync: true);
  ServiceState _state = ServiceState.stopped;
  String? _error;
  bool _disposed = false;

  @override
  ServiceState get state => _state;

  @override
  String? get error => _error;

  @override
  Stream<ServiceEvent> get events => _events.stream;

  @override
  Future<void> start(Map<String, Object?> config) async {
    try {
      await _request('start', config);
    } on _RemoteError catch (e) {
      throw ServiceStartException(e.message);
    }
  }

  @override
  Future<void> stop() async {
    if (_worker == null) return;
    try {
      await _request('stop', const {});
    } on _RemoteError {
      // 중지 중의 오류는 상태 이벤트로 이미 알려졌다.
    }
  }

  @override
  Future<Object?> command(String name, [Map<String, Object?> args = const {}]) async {
    try {
      return await _request('command', {'name': name, 'args': args});
    } on _RemoteError catch (e) {
      throw StateError(e.message);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    _teardown('disposed');
    await _events.close();
  }

  // ---- Isolate 수명 -----------------------------------------------------------------------------

  Future<SendPort> _ensureWorker() => _spawning ??= _spawn();

  Future<SendPort> _spawn() async {
    final ready = Completer<SendPort>();
    final inbox = ReceivePort();
    final errors = ReceivePort();
    _inbox = inbox;
    _errors = errors;
    inbox.listen((message) => _onMessage(message, ready));
    errors.listen(_onWorkerError);
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        _WorkerInit(inbox.sendPort, _factory, batchInterval),
        onError: errors.sendPort,
        debugName: 'lab-daemon-$id',
      );
    } catch (e) {
      _teardown('$e');
      rethrow;
    }
    _worker = await ready.future;
    return _worker!;
  }

  void _onMessage(Object? message, Completer<SendPort> ready) {
    switch (message) {
      case SendPort():
        if (!ready.isCompleted) ready.complete(message);
      case EventBatch():
        for (final event in message.events) {
          if (event is StateEvent) {
            _state = event.state;
            _error = event.error;
          }
          if (!_events.isClosed) _events.add(event);
        }
      case _Reply():
        final completer = _pending.remove(message.id);
        if (completer == null) return;
        if (message.error != null) {
          completer.completeError(_RemoteError(message.error!));
        } else {
          completer.complete(message.value);
        }
    }
  }

  /// 서비스 Isolate가 잡히지 않은 오류로 죽었다: 오류 상태로 알리고 정리한다.
  void _onWorkerError(Object? message) {
    final text = message is List && message.isNotEmpty ? '${message.first}' : '$message';
    _state = ServiceState.error;
    _error = text;
    if (!_events.isClosed) _events.add(StateEvent(id, ServiceState.error, error: text));
    _teardown(text);
  }

  void _teardown(String reason) {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _inbox?.close();
    _errors?.close();
    _inbox = null;
    _errors = null;
    _worker = null;
    _spawning = null;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      completer.completeError(_RemoteError(reason));
    }
  }

  Future<Object?> _request(String op, Object? payload) async {
    final worker = await _ensureWorker();
    final id = _nextRequest++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    worker.send(_Request(id, op, payload));
    return completer.future;
  }
}

/// 서비스 Isolate에서 화면 쪽으로 가는 이벤트 한 묶음.
class EventBatch {
  const EventBatch(this.events);

  final List<ServiceEvent> events;
}

class _Request {
  const _Request(this.id, this.op, this.payload);

  final int id;
  final String op;
  final Object? payload;
}

class _Reply {
  const _Reply(this.id, {this.value, this.error});

  final int id;
  final Object? value;
  final String? error;
}

class _RemoteError implements Exception {
  _RemoteError(this.message);

  final String message;
}

class _WorkerInit {
  const _WorkerInit(this.toMain, this.factory, this.batchInterval);

  final SendPort toMain;
  final ServiceFactory factory;
  final Duration batchInterval;
}

/// 이벤트를 모아 [interval]마다 한 번 보낸다.
/// - 로그와 상태 변화는 도착 순서를 지킨다. 한 묶음에 로그가 [maxLogsPerBatch]개를 넘으면 나머지는 버리고
///   마지막에 "N건 건너뜀" 로그 하나를 더한다.
/// - 그 밖의 이벤트(스냅샷)는 종류마다 마지막 것만 보낸다.
/// - 서비스가 멈추거나 오류가 나면 밀려 있던 스냅샷은 버린다 (멈춘 뒤에 낡은 표가 도착하지 않게).
class EventBatcher {
  EventBatcher(this.serviceId, this._send, this._interval, {this.maxLogsPerBatch = 400});

  final String serviceId;
  final void Function(EventBatch batch) _send;
  final Duration _interval;
  final int maxLogsPerBatch;

  final _ordered = <ServiceEvent>[];
  final _latest = <Type, ServiceEvent>{};
  var _logs = 0;
  var _dropped = 0;
  Timer? _timer;

  void add(ServiceEvent event) {
    if (event is LogEvent) {
      if (_logs >= maxLogsPerBatch) {
        _dropped++;
        return;
      }
      _logs++;
      _ordered.add(event);
    } else if (event is StateEvent) {
      if (event.state == ServiceState.stopped || event.state == ServiceState.error) _latest.clear();
      _ordered.add(event);
    } else {
      _latest[event.runtimeType] = event;
    }
    if (_interval == Duration.zero) {
      flush();
    } else {
      _timer ??= Timer(_interval, flush);
    }
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_ordered.isEmpty && _latest.isEmpty && _dropped == 0) return;
    final events = <ServiceEvent>[..._ordered];
    if (_dropped > 0) {
      events.add(LogEvent(serviceId, LogLevel.warning, 'logDropped', args: {'count': _dropped}));
    }
    events.addAll(_latest.values);
    _ordered.clear();
    _latest.clear();
    _logs = 0;
    _dropped = 0;
    _send(EventBatch(events));
  }
}

Future<void> _workerMain(_WorkerInit init) async {
  final inbox = ReceivePort();
  final service = init.factory();
  final batcher = EventBatcher(service.id, init.toMain.send, init.batchInterval);
  service.events.listen(batcher.add);
  init.toMain.send(inbox.sendPort);

  await for (final message in inbox) {
    if (message is! _Request) continue;
    unawaited(_handle(service, batcher, init.toMain, message));
  }
}

Future<void> _handle(NetService<ServiceConfig> service, EventBatcher batcher, SendPort toMain, _Request request) async {
  Object? value;
  String? error;
  try {
    switch (request.op) {
      case 'start':
        await service.start(service.decodeConfig(Map<String, Object?>.from(request.payload! as Map)));
      case 'stop':
        await service.stop();
      case 'command':
        final p = request.payload! as Map;
        value = await service.command(p['name']! as String, Map<String, Object?>.from(p['args']! as Map));
      default:
        error = 'unknown request ${request.op}';
    }
  } catch (e) {
    error = '$e';
  }
  // 응답보다 이벤트가 먼저 도착하도록 밀려 있는 이벤트를 먼저 보낸다.
  batcher.flush();
  toMain.send(_Reply(request.id, value: value, error: error));
}
