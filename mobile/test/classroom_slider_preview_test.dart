import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/classroom_seek_surface.dart';
import 'classroom_controls_test.dart' show ControlsHarness;

const preview = ValueKey('classroom-slider-seek-preview');

String clock(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds';
}

void main() {
  for (final fullscreen in [false, true]) {
    for (final playing in [false, true]) {
      testWidgets(
        'slider previews centered time then seeks once, fullscreen=$fullscreen playing=$playing',
        (tester) async {
          final h = ControlsHarness()
            ..data.addAll({'playing': playing, 'wanted': playing});
          final duration = !fullscreen && !playing ? 10800000 : 600000;
          h.data['duration'] = duration;
          await h.open(
            tester,
            size: fullscreen ? const Size(900, 500) : const Size(400, 800),
            fullscreen: fullscreen,
          );
          final slider = tester.getRect(find.byType(Slider));
          final gesture = await tester.startGesture(
            slider.centerLeft + const Offset(40, 0),
          );
          await gesture.moveTo(slider.center);
          await tester.pump();
          final target = tester
              .widget<Slider>(find.byType(Slider))
              .value
              .toInt();
          final expectedTime = '${clock(target)} / ${clock(duration)}';
          expect(
            target,
            inInclusiveRange((duration * .4).round(), (duration * .6).round()),
          );
          expect(find.byKey(preview), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(preview),
              matching: find.text(expectedTime),
            ),
            findsOneWidget,
          );
          final video = tester.getRect(find.byType(ClassroomSeekSurface));
          final center = tester.getRect(find.byKey(preview)).center;
          expect((center - video.center).distance, lessThan(1));
          await gesture.moveTo(slider.centerRight - const Offset(40, 0));
          await tester.pump();
          expect(
            find.descendant(
              of: find.byKey(preview),
              matching: find.text(expectedTime),
            ),
            findsNothing,
          );
          await gesture.moveTo(slider.center);
          await tester.pump();
          final endTarget = tester
              .widget<Slider>(find.byType(Slider))
              .value
              .toInt();
          final endTime = '${clock(endTarget)} / ${clock(duration)}';
          expect(endTarget, closeTo(target, 2));
          h.data['position'] = 90000;
          await h.refresh(tester);
          await tester.pump(const Duration(seconds: 4));
          expect(
            find.descendant(
              of: find.byKey(preview),
              matching: find.text(endTime),
            ),
            findsOneWidget,
          );
          expect(h.actions.where((a) => a == 'seek'), isEmpty);
          await h.capture(
            tester,
            fullscreen ? 'slider-landscape' : 'slider-portrait',
          );
          await gesture.up();
          await tester.pump();
          expect(find.byKey(preview), findsNothing);
          expect(h.actions.where((a) => a == 'seek').length, 1);
          expect(h.player.state.position, endTarget);
          expect(h.player.state.wanted, playing);
          await h.close(tester);
        },
      );
    }
  }

  for (final interruption in ['cancel', 'background', 'duration', 'error']) {
    testWidgets('slider preview clears without seeking on $interruption', (
      tester,
    ) async {
      final h = ControlsHarness();
      await h.open(
        tester,
        size: const Size(640, 320),
        textScale: 2,
        brightness: Brightness.dark,
      );
      final slider = tester.getRect(find.byType(Slider));
      final gesture = await tester.startGesture(slider.center);
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(preview), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (interruption == 'cancel') {
        await h.capture(tester, 'slider-small-dark-large-text');
      }
      if (interruption == 'cancel') {
        await gesture.cancel();
      } else {
        if (interruption == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
        } else {
          h.data[interruption == 'duration' ? 'duration' : 'error'] =
              interruption == 'duration' ? 240000 : 'AUTHENTICATION';
          await h.refresh(tester);
        }
        await gesture.up();
      }
      await tester.pump();
      expect(find.byKey(preview), findsNothing);
      expect(h.actions.where((a) => a == 'seek'), isEmpty);
      if (interruption == 'background') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
      }
      await h.close(tester);
    });
  }
}
