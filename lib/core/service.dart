// 서비스 추상화 (PLAN.md §4.1). 이 폴더(lib/core/)는 Flutter에 의존하지 않는 순수 Dart다.
//
// - NetService: DHCP / TFTP / FTP 같은 서비스 하나. 시작·중지, 상태, 이벤트 스트림, 명령을 가진다.
//   서비스는 별도 Isolate(lib/core/host.dart)에서 돌므로 화면 스레드와 CPU를 나누지 않는다.
// - ServiceEvent: 서비스가 밖으로 내보내는 모든 것. 로그와 상태 변화가 기본이고, 서비스마다 자기 이벤트
//   (Lease 표, 전송 목록 등)를 더한다. 이 객체들은 Isolate 사이로 그대로 복사되어 건너간다.
// - LogBus: 서비스 하나의 로그를 화면 쪽에서 모아 두는 고정 크기 버퍼.
//
// 성능 원칙 (3CDaemon의 약점을 피한다):
//   1. 로그·클라이언트 정보를 만드는 비용이 패킷 처리 경로에 끼어들지 않는다: 표 스냅샷은 바뀔 때 "표시만"
//      해 두고 [BaseNetService.scheduleSnapshot]이 일정 간격으로 한 번만 만든다.
//   2. 화면으로 가는 이벤트는 배치로 묶고 같은 종류의 스냅샷은 최신 것만 보낸다 (host.dart).
//   3. 화면의 버퍼는 크기가 정해져 있다.
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

/// 서비스 하나의 로그를 모아 두는 고정 크기 버퍼. 화면 쪽에서 쓰며, 가득 차면 오래된 것부터 버린다.
/// 추가는 O(1)이고 구독자가 없으면 스트림 비용도 없다.
class LogBus {
  LogBus({this.capacity = 5000});

  final int capacity;
  final _history = Queue<LogEvent>();
  final _controller = StreamController<LogEvent>.broadcast(sync: true);

  Stream<LogEvent> get stream => _controller.stream;

  int get length => _history.length;

  /// 오래된 것부터. 복사본이므로 자주 부르지 않는다 (화면이 처음 열릴 때 한 번).
  List<LogEvent> get history => List.unmodifiable(_history);

  void add(LogEvent event) {
    _history.addLast(event);
    while (_history.length > capacity) {
      _history.removeFirst();
    }
    if (_controller.hasListener) _controller.add(event);
  }

  void clear() => _history.clear();

  Future<void> dispose() => _controller.close();
}

/// 서비스 설정의 표식. Isolate 경계와 저장소를 건널 수 있게 JSON 형태로 바꿀 수 있어야 한다.
abstract interface class ServiceConfig {
  Map<String, Object?> toJson();
}

abstract interface class NetService<C extends ServiceConfig> {
  /// `dhcp`, `tftp`, `ftp`처럼 변하지 않는 이름. 로그와 설정 저장에 쓴다.
  String get id;

  ServiceState get state;

  /// 마지막 오류 원인. [ServiceState.error]가 아니면 null.
  String? get error;

  /// 로그, 상태 변화, 서비스 고유 이벤트. 브로드캐스트 스트림이다.
  Stream<ServiceEvent> get events;

  /// [toJson]으로 만든 설정을 다시 읽는다. 올바르지 않으면 [FormatException].
  C decodeConfig(Map<String, Object?> json);

  /// 멈춘 상태(또는 오류 상태)에서만 시작할 수 있다. 실패하면 상태가 error가 되고 예외를 다시 던진다.
  Future<void> start(C config);

  /// 이미 멈췄으면 아무것도 하지 않는다.
  Future<void> stop();

  /// 서비스 고유 명령 (예: DHCP의 `releaseIp`). 모르는 명령은 [UnsupportedError].
  Future<Object?> command(String name, Map<String, Object?> args);
}

/// [NetService]의 공통 골격: 상태 전이, 이벤트 스트림, 로그 발행, 스냅샷 제한을 맡고 서비스는
/// [onStart]/[onStop]/[handleCommand]만 쓴다.
abstract class BaseNetService<C extends ServiceConfig> implements NetService<C> {
  /// [snapshotInterval]: 표 스냅샷을 만드는 최소 간격. [Duration.zero]이면 요청 즉시 만든다 (테스트).
  BaseNetService(this.id, {this.snapshotInterval = const Duration(milliseconds: 200)});

  @override
  final String id;

  final Duration snapshotInterval;

  final _events = StreamController<ServiceEvent>.broadcast(sync: true);
  ServiceState _state = ServiceState.stopped;
  String? _error;

  final _snapshotBuilders = <String, ServiceEvent Function()>{};
  final _dirtySnapshots = <String>{};
  Timer? _snapshotTimer;

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
      _dropSnapshots();
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
      _dropSnapshots();
      _setState(ServiceState.stopped);
    }
  }

  @override
  Future<Object?> command(String name, Map<String, Object?> args) => handleCommand(name, args);

  /// 소켓을 열고 수신을 시작한다. 던지면 서비스는 error 상태가 된다.
  Future<void> onStart(C config);

  /// 소켓을 닫고 타이머를 멈춘다. 시작에 실패한 뒤에도 불리므로 반쯤 열린 상태를 견뎌야 한다.
  Future<void> onStop();

  /// 서비스 고유 명령. 기본은 아무 명령도 모른다.
  Future<Object?> handleCommand(String name, Map<String, Object?> args) async =>
      throw UnsupportedError('$id does not support "$name"');

  /// 서비스 고유 이벤트를 내보낸다.
  void emit(ServiceEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void log(LogLevel level, String key, {String? kind, Map<String, Object?> args = const {}, String? detail}) =>
      emit(LogEvent(id, level, key, kind: kind, args: args, detail: detail));

  /// 화면용 표(스냅샷)가 바뀌었다고 알린다. 패킷마다 불러도 되고, 실제 스냅샷은 [snapshotInterval]에
  /// 한 번만 [build]로 만든다 — 표가 커져도 패킷 처리 비용이 늘지 않는다. [key]가 같으면 합쳐진다.
  void scheduleSnapshot(String key, ServiceEvent Function() build) {
    _snapshotBuilders[key] = build;
    if (snapshotInterval == Duration.zero) {
      emit(build());
      return;
    }
    _dirtySnapshots.add(key);
    _snapshotTimer ??= Timer(snapshotInterval, flushSnapshots);
  }

  /// 밀려 있는 스냅샷을 지금 만든다 (중지 직전이나 테스트에서).
  void flushSnapshots() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    if (_dirtySnapshots.isEmpty) return;
    final keys = _dirtySnapshots.toList();
    _dirtySnapshots.clear();
    for (final key in keys) {
      final build = _snapshotBuilders[key];
      if (build != null) emit(build());
    }
  }

  void _dropSnapshots() {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    _dirtySnapshots.clear();
    _snapshotBuilders.clear();
  }

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
    _dropSnapshots();
    await _events.close();
  }
}
