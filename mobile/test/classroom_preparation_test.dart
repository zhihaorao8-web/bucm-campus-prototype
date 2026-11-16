import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/classroom_playback_preparation.dart';
import 'classroom_player_test.dart' show snapshot;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic-preparation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final actions = <String>[];
  setUp(() {
    actions.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      actions.add(call.method);
      return call.method == 'prepare' ? snapshot() : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final handoff in [false, true]) {
    test('native session cleanup respects player handoff $handoff', () async {
      final preparation = ClassroomPlaybackPreparation(
        channel: channel,
        active: () => true,
        command: (_) async => {'state': 'opening'},
      );
      final state = await preparation.prepare(
        'synthetic-view',
        'synthetic-record',
      );
      expect(state!.session, 'synthetic-session');
      if (handoff) preparation.handoff();
      await preparation.release();
      expect(actions, ['begin', 'prepare', if (!handoff) 'dispose', 'cancel']);
    });
  }

  test('cancelled begin cannot issue playback command or prepare', () async {
    var commands = 0;
    final preparation = ClassroomPlaybackPreparation(
      channel: channel,
      active: () => false,
      command: (_) async {
        commands++;
        return {'state': 'opening'};
      },
    );
    expect(
      await preparation.prepare('synthetic-view', 'synthetic-record'),
      isNull,
    );
    await preparation.release();
    expect(commands, 0);
    expect(actions, ['begin', 'cancel']);
  });

  test('official playback rejection cannot start native media', () async {
    final preparation = ClassroomPlaybackPreparation(
      channel: channel,
      active: () => true,
      command: (_) async => {'state': 'authentication'},
    );
    await expectLater(
      preparation.prepare('synthetic-view', 'synthetic-record'),
      throwsFormatException,
    );
    await preparation.release();
    expect(actions, ['begin', 'cancel']);
  });

  test(
    'late prepared session is released when operation becomes inactive',
    () async {
      final gate = Completer<Object?>();
      var active = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        actions.add(call.method);
        return call.method == 'prepare' ? gate.future : null;
      });
      final preparation = ClassroomPlaybackPreparation(
        channel: channel,
        active: () => active,
        command: (_) async => {'state': 'opening'},
      );
      final preparing = preparation.prepare(
        'synthetic-view',
        'synthetic-record',
      );
      await Future<void>.delayed(Duration.zero);
      active = false;
      gate.complete(snapshot());
      await preparing;
      await preparation.release();
      expect(actions, ['begin', 'prepare', 'dispose', 'cancel']);
    },
  );

  test('failure text never reflects raw platform details', () {
    final message = ClassroomPlaybackPreparation.failureMessage(
      PlatformException(
        code: 'UNKNOWN',
        message: 'synthetic-sensitive-details',
      ),
    );
    expect(message, isNot(contains('synthetic-sensitive-details')));
    expect(
      ClassroomPlaybackPreparation.failureMessage(TimeoutException('raw')),
      contains('超时'),
    );
  });
}
