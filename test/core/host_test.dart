// 서비스 골격(BaseNetService)과 호스트(InProcessHost / IsolateHost / EventBatcher) 시험.
// 부하 시험은 성능 요구(PLAN.md §4.1: 로그·클라이언트 표시가 성능을 해치면 안 된다)를 확인한다.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lab_daemon/core/host.dart';
import 'package:lab_daemon/core/service.dart';

class _Config implements ServiceConfig {
  const _Config({this.failOnStart = false});

  factory _Config.fromJson(Map<String, Object?> json) => _Config(failOnStart: json['failOnStart'] as bool? ?? false);

  final bool failOnStart;

  @override
  Map<String, Object?> toJson() => {'failOnStart': failOnStart};
}

/// 화면 쪽으로 가는 스냅샷 이벤트의 예. Isolate 경계를 그대로 건넌다.
final class _CountEvent extends ServiceEvent {
  _CountEvent(super.service, this.count);

  final int count;
}

class _TestService extends BaseNetService<_Config> {
  _TestService({super.snapshotInterval}) : super('test');

  int stops = 0;
  int builds = 0;

  @override
  _Config decodeConfig(Map<String, Object?> json) => _Config.fromJson(json);

  @override
  Future<void> onStart(_Config config) async {
    log(LogLevel.info, 'logStarted', kind: 'START', args: {'id': id});
    if (config.failOnStart) throw StateError('port in use');
  }

  @override
  Future<void> onStop() async => stops++;

  @override
  Future<Object?> handleCommand(String name, Map<String, Object?> args) async {
    switch (name) {
      case 'echo':
        return args;
      case 'flood':
        for (var i = 0; i < (args['count']! as int); i++) {
          log(LogLevel.info, 'logFlood', args: {'i': i});
        }
        return null;
      case 'snapshots':
        for (var i = 1; i <= (args['count']! as int); i++) {
          scheduleSnapshot('count', () {
            builds++;
            return _CountEvent(id, i);
          });
        }
        return builds;
      case 'crash':
        Timer(Duration.zero, () => throw StateError('worker boom'));
        return null;
    }
    return super.handleCommand(name, args);
  }
}

NetService<ServiceConfig> createTestService() => _TestService();

Future<List<ServiceEvent>> _settle(Stream<ServiceEvent> events, Future<void> Function() action, {int millis = 400}) async {
  final received = <ServiceEvent>[];
  final sub = events.listen(received.add);
  await action();
  await Future<void>.delayed(Duration(milliseconds: millis));
  await sub.cancel();
  return received;
}

void main() {
  group('BaseNetService', () {
    test('시작하면 starting → running, 멈추면 stopping → stopped 상태 이벤트를 낸다', () async {
      final service = _TestService();
      final states = <ServiceState>[];
      service.events.where((e) => e is StateEvent).cast<StateEvent>().listen((e) => states.add(e.state));

      await service.start(const _Config());
      expect(service.state, ServiceState.running);
      await service.stop();
      expect(states, [ServiceState.starting, ServiceState.running, ServiceState.stopping, ServiceState.stopped]);
      await service.dispose();
    });

    test('시작이 실패하면 error 상태가 되고 정리한 뒤 예외를 다시 던진다. 다시 시작할 수 있다', () async {
      final service = _TestService();
      await expectLater(service.start(const _Config(failOnStart: true)), throwsStateError);
      expect(service.state, ServiceState.error);
      expect(service.error, contains('port in use'));
      expect(service.stops, 1, reason: '반쯤 열린 자원을 정리한다');

      await service.start(const _Config());
      expect(service.state, ServiceState.running);
      expect(service.error, isNull);
      await expectLater(service.start(const _Config()), throwsStateError, reason: '실행 중에는 다시 시작할 수 없다');
      await service.dispose();
    });

    test('모르는 명령은 UnsupportedError', () async {
      final service = _TestService();
      await expectLater(service.command('nope', const {}), throwsUnsupportedError);
      await service.dispose();
    });

    test('스냅샷은 패킷마다 요청해도 간격마다 한 번만 만든다', () async {
      final service = _TestService(snapshotInterval: const Duration(milliseconds: 60));
      await service.start(const _Config());
      final received = <_CountEvent>[];
      service.events.listen((e) {
        if (e is _CountEvent) received.add(e);
      });

      await service.command('snapshots', {'count': 5000});
      expect(service.builds, 0, reason: '요청 시점에는 만들지 않는다');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(service.builds, 1);
      expect(received.single.count, 5000, reason: '마지막 요청의 내용이 나온다');
      await service.dispose();
    });

    test('간격이 0이면 바로 만들고, 중지하면 밀린 스냅샷을 버린다', () async {
      final immediate = _TestService(snapshotInterval: Duration.zero);
      await immediate.start(const _Config());
      await immediate.command('snapshots', {'count': 3});
      expect(immediate.builds, 3);
      await immediate.dispose();

      final pending = _TestService(snapshotInterval: const Duration(milliseconds: 80));
      await pending.start(const _Config());
      final received = <ServiceEvent>[];
      pending.events.listen(received.add);
      await pending.command('snapshots', {'count': 2});
      await pending.stop();
      await Future<void>.delayed(const Duration(milliseconds: 160));
      expect(received.whereType<_CountEvent>(), isEmpty, reason: '멈춘 뒤에 낡은 표가 나가면 안 된다');
      await pending.dispose();
    });
  });

  group('LogBus', () {
    test('용량을 넘으면 오래된 것부터 버린다', () {
      final bus = LogBus(capacity: 3);
      for (var i = 0; i < 5; i++) {
        bus.add(LogEvent('x', LogLevel.info, 'k$i'));
      }
      expect(bus.history.map((e) => e.key), ['k2', 'k3', 'k4']);
      bus.clear();
      expect(bus.length, 0);
    });
  });

  group('EventBatcher', () {
    test('로그와 상태는 순서를 지키고 스냅샷은 종류마다 마지막 것만 보낸다', () {
      final sent = <EventBatch>[];
      final batcher = EventBatcher('test', sent.add, const Duration(hours: 1));
      batcher.add(LogEvent('test', LogLevel.info, 'a'));
      batcher.add(_CountEvent('test', 1));
      batcher.add(StateEvent('test', ServiceState.running));
      batcher.add(_CountEvent('test', 2));
      batcher.add(LogEvent('test', LogLevel.info, 'b'));
      batcher.flush();

      final events = sent.single.events;
      expect(events.map((e) => e.runtimeType.toString()), ['LogEvent', 'StateEvent', 'LogEvent', '_CountEvent']);
      expect((events.last as _CountEvent).count, 2);
    });

    test('한 묶음의 로그 상한을 넘으면 버리고 건너뛴 개수를 알린다', () {
      final sent = <EventBatch>[];
      final batcher = EventBatcher('test', sent.add, const Duration(hours: 1), maxLogsPerBatch: 10);
      for (var i = 0; i < 1000; i++) {
        batcher.add(LogEvent('test', LogLevel.info, 'k$i'));
      }
      batcher.flush();

      final logs = sent.single.events.whereType<LogEvent>().toList();
      expect(logs, hasLength(11), reason: '10개 + 건너뜀 알림 1개');
      expect(logs.last.key, 'logDropped');
      expect(logs.last.args['count'], 990);

      // 다음 묶음은 다시 상한까지 받는다.
      batcher.add(LogEvent('test', LogLevel.info, 'after'));
      batcher.flush();
      expect(sent.last.events.whereType<LogEvent>().single.key, 'after');
    });

    test('멈추거나 오류가 나면 밀려 있던 스냅샷을 버린다', () {
      final sent = <EventBatch>[];
      final batcher = EventBatcher('test', sent.add, const Duration(hours: 1));
      batcher.add(_CountEvent('test', 9));
      batcher.add(StateEvent('test', ServiceState.stopped));
      batcher.flush();
      expect(sent.single.events.whereType<_CountEvent>(), isEmpty);
    });

    test('아무것도 없으면 보내지 않는다', () {
      final sent = <EventBatch>[];
      EventBatcher('test', sent.add, const Duration(hours: 1)).flush();
      expect(sent, isEmpty);
    });
  });

  group('InProcessHost', () {
    test('설정 JSON으로 시작하고 명령을 전달한다', () async {
      final host = InProcessHost(_TestService());
      await host.start(const _Config().toJson());
      expect(host.state, ServiceState.running);
      expect(await host.command('echo', {'a': 1}), {'a': 1});
      await host.dispose();
      expect(host.state, ServiceState.stopped);
    });
  });

  group('IsolateHost', () {
    late IsolateHost host;

    setUp(() => host = IsolateHost('test', createTestService, batchInterval: const Duration(milliseconds: 30)));

    tearDown(() => host.dispose());

    test('별도 Isolate에서 시작·중지하고 상태와 로그가 도착한다', () async {
      final events = await _settle(host.events, () async {
        await host.start(const _Config().toJson());
        await host.stop();
      });
      expect(host.state, ServiceState.stopped);
      final states = events.whereType<StateEvent>().map((e) => e.state).toList();
      expect(states, [ServiceState.starting, ServiceState.running, ServiceState.stopping, ServiceState.stopped]);
      final started = events.whereType<LogEvent>().firstWhere((e) => e.key == 'logStarted');
      expect(started.kind, 'START');
      expect(started.args, {'id': 'test'});
    });

    test('명령의 결과가 돌아온다 (JSON 값이 Isolate 경계를 건넌다)', () async {
      await host.start(const _Config().toJson());
      expect(await host.command('echo', {'list': [1, 2], 'text': '한글'}), {'list': [1, 2], 'text': '한글'});
      await expectLater(host.command('nope'), throwsStateError);
    });

    test('시작 실패는 ServiceStartException으로 오고 상태는 error', () async {
      final events = await _settle(host.events, () async {
        await expectLater(host.start(const _Config(failOnStart: true).toJson()), throwsA(isA<ServiceStartException>()));
      });
      expect(host.state, ServiceState.error);
      expect(host.error, contains('port in use'));
      expect(events.whereType<StateEvent>().last.state, ServiceState.error);
      // 오류 뒤에도 다시 시작할 수 있다.
      await host.start(const _Config().toJson());
      expect(host.state, ServiceState.running);
    });

    test('중지하지 않은 서비스는 아무 일도 하지 않는 stop이 안전하다', () async {
      await host.stop();
      expect(host.state, ServiceState.stopped);
    });

    test('서비스 Isolate가 죽으면 오류 상태가 되고 다음 시작에서 다시 만들어진다', () async {
      await host.start(const _Config().toJson());
      final events = await _settle(host.events, () async => host.command('crash'), millis: 500);
      expect(host.state, ServiceState.error);
      expect(events.whereType<StateEvent>().last.error, contains('worker boom'));

      await host.start(const _Config().toJson());
      expect(host.state, ServiceState.running);
    });

    test('로그 5만 건이 쏟아져도 화면 쪽 이벤트는 상한이 있고 메인 Isolate가 멈추지 않는다', () async {
      await host.start(const _Config().toJson());
      var received = 0;
      var batches = 0;
      var dropped = 0;
      final sub = host.events.listen((e) {
        received++;
        if (e is LogEvent && e.key == 'logDropped') dropped += e.args['count']! as int;
      });

      // 메인 Isolate가 부하 동안 계속 돌아가는지: 10ms 타이머의 가장 긴 간격을 잰다.
      var maxGap = Duration.zero;
      var last = DateTime.now();
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final now = DateTime.now();
        if (now.difference(last) > maxGap) maxGap = now.difference(last);
        last = now;
        batches++;
      });

      await host.command('flood', {'count': 50000});
      await Future<void>.delayed(const Duration(milliseconds: 600));
      ticker.cancel();
      await sub.cancel();

      expect(batches, greaterThan(20), reason: '메인 Isolate의 타이머가 계속 돌았다');
      expect(maxGap, lessThan(const Duration(milliseconds: 500)), reason: '가장 긴 멈춤 $maxGap');
      // 50000건 중 묶음마다 400건까지만 도착한다. 묶음은 30ms 간격이라 600ms 동안 많아야 수십 개다.
      expect(received, lessThan(50000 ~/ 2), reason: '받은 이벤트 $received');
      expect(received + dropped, greaterThanOrEqualTo(50000), reason: '버린 만큼은 개수로 알렸다 (받음 $received + 건너뜀 $dropped)');
    });
  });
}
