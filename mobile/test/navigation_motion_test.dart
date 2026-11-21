import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/app_shell.dart';
import 'package:campus_schedule/ui/glass_navigation.dart';
import 'ui_test.dart' show app;
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  for (final (dark, scale) in [
    (false, 1.0),
    (true, 1.0),
    (false, 1.5),
    (true, 1.5),
  ]) {
    testWidgets(
      'switching a collapsed page never shifts its content vertically dark=$dark scale=$scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          app(
            MemoryRepository(weeklyPreviewData(DateTime.now())),
            dark: dark,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final today = find.byKey(const PageStorageKey('today-page'));
        await tester.drag(today, const Offset(0, -220));
        await tester.pumpAndSettle();
        final anchor = find.byKey(
          const ValueKey('today-focus'),
          skipOffstage: false,
        );
        final before = tester.getTopLeft(anchor).dy;
        final scroll = tester.widget<ListView>(today).controller!;
        final offset = scroll.offset;
        final target = find.byKey(
          const ValueKey('topbar-1'),
          skipOffstage: false,
        );
        final targetY = tester.getTopLeft(target).dy;
        final targetHeight = tester.getSize(target).height;
        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pump();
        for (var frame = 0; frame < 10; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(scroll.offset, closeTo(offset, .01));
          expect(
            tester.getTopLeft(anchor).dy,
            closeTo(before, .5),
            reason:
                'Outgoing body must not relayout when another header expands (frame $frame)',
          );
          expect(tester.getTopLeft(target).dy, closeTo(targetY, .5));
          expect(tester.getSize(target).height, closeTo(targetHeight, .5));
        }
        await tester.pumpAndSettle();
        final settingsTitle = find.descendant(
          of: find.byKey(
            const PageStorageKey('settings-page'),
            skipOffstage: false,
          ),
          matching: find.text('登录校园账号', skipOffstage: false),
        );
        final settingsY = tester.getTopLeft(settingsTitle).dy;
        await tester.tap(find.byKey(const ValueKey('tab-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tab-3')));
        await tester.pump();
        for (var frame = 0; frame < 13; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(
            tester.getTopLeft(settingsTitle).dy,
            closeTo(settingsY, .5),
            reason:
                'Cold non-adjacent destination must already have its final insets',
          );
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tab-0')));
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(offset, .01));
        expect(tester.getTopLeft(anchor).dy, closeTo(before, .5));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  Future<void> mount(WidgetTester tester, {bool reduced = false}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(
        MemoryRepository(weeklyPreviewData(DateTime.now())),
        reduceMotion: reduced,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'navigation moves content and dock together and retargets rapid taps',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final position = tester
          .widget<GlassNavigation>(find.byType(GlassNavigation))
          .position!;
      expect(position, greaterThan(0));
      expect(position, lessThan(1));
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pump(const Duration(milliseconds: 25));
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pump(const Duration(milliseconds: 35));
      await tester.tap(find.byKey(const ValueKey('tab-0')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        0,
      );
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).position,
        closeTo(0, .001),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'swipe follows finger, cancellation restores page and completed swipe selects destination',
    (tester) async {
      await mount(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      await container
          .read(appearanceProvider.notifier)
          .change((p) => p.copyWith(swipePages: true));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(320, 600));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      final position = tester
          .widget<GlassNavigation>(find.byType(GlassNavigation))
          .position!;
      expect(position, greaterThan(.1));
      expect(position, lessThan(.5));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).position,
        closeTo(0, .001),
      );
      await tester.fling(
        find.byKey(const ValueKey('main-navigation-pager')),
        const Offset(-310, 0),
        900,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reduced motion changes tabs immediately and preserves swipe preference',
    (tester) async {
      await mount(tester, reduced: true);
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pump();
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).position,
        3,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      await container
          .read(appearanceProvider.notifier)
          .change((p) => p.copyWith(swipePages: true));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('main-navigation-pager')),
        const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<GlassNavigation>(find.byType(GlassNavigation)).selected,
        2,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
