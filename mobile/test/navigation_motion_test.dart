import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/app_shell.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/glass_navigation.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
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

  testWidgets(
    'dock liquid lens tracks paging clock, swipe position and reduced motion',
    (tester) async {
      await mount(tester);
      final dock = find.byType(GlassNavigation);
      final lens = find.descendant(
        of: dock,
        matching: find.byKey(const ValueKey('dock-lens')),
      );
      expect(lens, findsOneWidget);
      expect(
        find.descendant(of: dock, matching: find.byType(LiquidGlassSurface)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dock,
          matching: find.byKey(const ValueKey('dock-lens-fallback')),
        ),
        findsNothing,
      );
      expect(
        tester.getCenter(lens).dx,
        closeTo(tester.getCenter(find.byKey(const ValueKey('tab-0'))).dx, 1),
      );

      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final pagingPosition = tester.widget<GlassNavigation>(dock).position!;
      expect(pagingPosition, greaterThan(0));
      expect(pagingPosition, lessThan(2));
      expect(
        tester.getCenter(lens).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('tab-0'))).dx),
      );
      expect(
        tester.getCenter(lens).dx,
        lessThan(tester.getCenter(find.byKey(const ValueKey('tab-2'))).dx),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(lens).dx,
        closeTo(tester.getCenter(find.byKey(const ValueKey('tab-2'))).dx, 1),
      );

      await tester.tap(find.byKey(const ValueKey('tab-0')));
      await tester.pumpAndSettle();
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
      final swipePosition = tester.widget<GlassNavigation>(dock).position!;
      expect(swipePosition, greaterThan(.1));
      expect(swipePosition, lessThan(.5));
      expect(
        tester.getCenter(lens).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('tab-0'))).dx),
      );
      expect(
        tester.getCenter(lens).dx,
        lessThan(tester.getCenter(find.byKey(const ValueKey('tab-1'))).dx),
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(lens).dx,
        closeTo(tester.getCenter(find.byKey(const ValueKey('tab-0'))).dx, 1),
      );
      await tester.pumpWidget(const SizedBox());

      await mount(tester, reduced: true);
      expect(lens, findsOneWidget);
      expect(
        find.descendant(of: dock, matching: find.byType(LiquidGlassSurface)),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pump();
      expect(tester.widget<GlassNavigation>(dock).position, 3);
      expect(
        tester.getCenter(lens).dx,
        closeTo(tester.getCenter(find.byKey(const ValueKey('tab-3'))).dx, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'dock lens adapts to 320dp large text, 400dp cap and keyboard activation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          MemoryRepository(weeklyPreviewData(DateTime.now())),
          dark: true,
          scale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      final dock = find.byType(GlassNavigation);
      final lens = find.descendant(
        of: dock,
        matching: find.byKey(const ValueKey('dock-lens')),
      );
      expect(lens, findsOneWidget);
      expect(
        find.descendant(of: dock, matching: find.byType(LiquidGlassSurface)),
        findsOneWidget,
      );
      final dockRect = tester.getRect(find.byKey(const ValueKey('dock-blur')));
      final lensRect = tester.getRect(lens);
      expect(lensRect.left, greaterThanOrEqualTo(dockRect.left));
      expect(lensRect.right, lessThanOrEqualTo(dockRect.right));
      expect(lensRect.top, greaterThanOrEqualTo(dockRect.top));
      expect(lensRect.bottom, lessThanOrEqualTo(dockRect.bottom));
      for (var i = 0; i < GlassNavigation.labels.length; i++) {
        final tabSize = tester.getSize(find.byKey(ValueKey('tab-$i')));
        expect(tabSize.width, greaterThanOrEqualTo(48));
        expect(tabSize.height, greaterThanOrEqualTo(48));
        expect(find.text(GlassNavigation.labels[i]), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      tester.view.physicalSize = const Size(600, 844);
      tester.view.devicePixelRatio = 1;
      var selected = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            builder: (context, child) => MiuixThemeBridge(child: child!),
            home: Scaffold(
              bottomNavigationBar: StatefulBuilder(
                builder: (context, setState) => GlassNavigation(
                  selected: selected,
                  onSelect: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('dock-blur'))).width,
        lessThanOrEqualTo(400),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('tab-1')))
            .properties
            .selected,
        isTrue,
      );
      expect(
        tester.getCenter(lens).dx,
        closeTo(tester.getCenter(find.byKey(const ValueKey('tab-1'))).dx, 1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
