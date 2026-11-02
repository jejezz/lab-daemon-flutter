import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/service.dart';

class _Config implements ServiceConfig {
  const _Config({this.failOnStart = false});

  final bool failOnStart;
}

class _FakeService extends BaseNetService<_Config> {
  _FakeService(super.id, super.bus);

  int stops = 0;

  @override
  Future<void> onStart(_Config config) async {
    log(LogLevel.info, 'logStarted', kind: 'START', args: {'id': id});
    if (config.failOnStart) throw StateError('port in use');
  }

  @override
  Future<void> onStop() async => stops++;
}

void main() {
  late LogBus bus;
  late _FakeService service;

  setUp(() {
    bus = LogBus(capacity: 3);
    service = _FakeService('dhcp', bus);
  });

  tearDown(() async {
    await service.dispose();
    await bus.dispose();
  });

  test('시작하면 starting → running, 멈추면 stopping → stopped 상태 이벤트를 낸다', () async {
    final states = <ServiceState>[];
    service.events.where((e) => e is StateEvent).cast<StateEvent>().listen((e) => states.add(e.state));

    expect(service.state, ServiceState.stopped);
    await service.start(const _Config());
    expect(service.state, ServiceState.running);
    await service.stop();
    expect(service.state, ServiceState.stopped);
    expect(states, [ServiceState.starting, ServiceState.running, ServiceState.stopping, ServiceState.stopped]);
  });

  test('시작이 실패하면 error 상태가 되고 정리한 뒤 예외를 다시 던진다', () async {
    final events = <ServiceEvent>[];
    service.events.listen(events.add);

    await expectLater(service.start(const _Config(failOnStart: true)), throwsStateError);
    expect(service.state, ServiceState.error);
    expect(service.error, contains('port in use'));
    expect(service.stops, 1, reason: '반쯤 열린 자원을 정리한다');
    expect(events.whereType<StateEvent>().last.error, contains('port in use'));

    // 오류 뒤에는 다시 시작할 수 있고, 성공하면 오류 원인이 지워진다.
    await service.start(const _Config());
    expect(service.state, ServiceState.running);
    expect(service.error, isNull);
  });

  test('실행 중에 다시 시작하면 거부하고, 멈춘 서비스를 멈춰도 아무 일 없다', () async {
    await service.stop();
    expect(service.stops, 0);
    await service.start(const _Config());
    await expectLater(service.start(const _Config()), throwsStateError);
    expect(service.state, ServiceState.running);
  });

  test('서비스 로그는 로그 버스에 모이고 용량을 넘으면 오래된 것부터 버린다', () async {
    final received = <LogEvent>[];
    bus.stream.listen(received.add);

    for (var i = 0; i < 4; i++) {
      await service.start(const _Config());
      await service.stop();
    }
    expect(received, hasLength(4));
    expect(received.first.service, 'dhcp');
    expect(received.first.key, 'logStarted');
    expect(received.first.kind, 'START');
    expect(received.first.args, {'id': 'dhcp'});
    expect(bus.history, hasLength(3));
    expect(identical(bus.history.last, received.last), isTrue);
  });

  test('레지스트리는 서비스 이벤트를 한 스트림으로 합치고 중복 등록을 막는다', () async {
    final registry = ServiceRegistry();
    final tftp = _FakeService('tftp', bus);
    registry.register(service);
    registry.register(tftp);
    expect(() => registry.register(_FakeService('dhcp', bus)), throwsArgumentError);
    expect(registry['tftp'], same(tftp));
    expect(registry.all, hasLength(2));

    final started = <String>[];
    registry.events
        .where((e) => e is StateEvent)
        .cast<StateEvent>()
        .where((e) => e.state == ServiceState.running)
        .listen((e) => started.add(e.service));
    await service.start(const _Config());
    await tftp.start(const _Config());
    expect(started, ['dhcp', 'tftp']);

    await registry.dispose();
    expect(service.state, ServiceState.stopped);
    expect(tftp.state, ServiceState.stopped);
    await tftp.dispose();
  });
}
