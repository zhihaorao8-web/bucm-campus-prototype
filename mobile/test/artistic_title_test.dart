import 'package:campus_schedule/ui/macintosh_hello_glyphs.g.dart';
import 'package:campus_schedule/ui/macintosh_hello_title.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'ui_test.dart' show app;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  testWidgets(
    'Today and Schedule headers render B1 Macintosh Hello vector titles while Settings stays clean',
    (tester) async {
      expect(
        macintoshHelloB1Glyphs.keys,
        containsAll(['今', '日', '课', '表']),
      );

      for (final (dark, scale) in [(false, 1.0), (true, 1.5), (false, 2.0)]) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          KeyedSubtree(
            key: ValueKey('$dark-$scale'),
            child: app(
              MemoryRepository(weeklyPreviewData(DateTime.now())),
              dark: dark,
              scale: scale,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('hello-title-今日')),
          findsOneWidget,
        );
        expect(find.text('今日'), findsWidgets);

        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('hello-title-课表')),
          findsOneWidget,
        );
        expect(find.text('课表'), findsWidgets);

        await tester.tap(find.byKey(const ValueKey('tab-2')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('hello-title-图书馆')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('topbar-2')),
            matching: find.text('图书馆'),
          ),
          findsWidgets,
        );

        await tester.tap(find.byKey(const ValueKey('tab-3')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('hello-title-设置')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('topbar-3')),
            matching: find.text('设置'),
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'MacintoshHelloTitle animates strokes progressively on entrance and settles cleanly',
    (tester) async {
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [ambientMotionEnabledProvider.overrideWithValue(true)],
          child: MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.white,
              body: RepaintBoundary(
                key: boundaryKey,
                child: const Center(
                  child: MacintoshHelloTitle(
                    text: '今日',
                    color: Colors.black,
                    glyphSize: 80,
                    active: true,
                    duration: Duration(milliseconds: 1200),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      Future<int> countInkPixels() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData();
        image.dispose();
        final data = bytes!.buffer.asUint8List();
        var ink = 0;
        for (var i = 0; i < data.length; i += 4) {
          if (data[i + 3] > 20) ink++;
        }
        return ink;
      }

      // Advance progressively through the write-on timeline.
      await tester.pump(const Duration(milliseconds: 180));
      final earlyInk = await tester.runAsync(countInkPixels) ?? 0;

      await tester.pump(const Duration(milliseconds: 450));
      final midInk = await tester.runAsync(countInkPixels) ?? 0;

      await tester.pump(const Duration(milliseconds: 800));
      final doneInk = await tester.runAsync(countInkPixels) ?? 0;

      expect(earlyInk, greaterThan(20));
      expect(midInk, greaterThan(earlyInk));
      expect(doneInk, greaterThan(midInk));

      // Reduce-motion immediately snaps to completed ink without waiting.
      final reducedKey = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [ambientMotionEnabledProvider.overrideWithValue(true)],
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp(
              home: Scaffold(
                backgroundColor: Colors.white,
                body: RepaintBoundary(
                  key: reducedKey,
                  child: const Center(
                    child: MacintoshHelloTitle(
                      text: '课表',
                      color: Colors.black,
                      glyphSize: 80,
                      active: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final reducedInk =
          await tester.runAsync(() async {
            final boundary =
                reducedKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData();
            image.dispose();
            final data = bytes!.buffer.asUint8List();
            var ink = 0;
            for (var i = 0; i < data.length; i += 4) {
              if (data[i + 3] > 20) ink++;
            }
            return ink;
          }) ??
          0;
      expect(reducedInk, greaterThan(400));
      expect(tester.takeException(), isNull);
    },
  );
}
