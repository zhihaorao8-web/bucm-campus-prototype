import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:campus_schedule/ui/acrylic_surface.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'support/memory_appearance.dart';
import 'ui_test.dart' show app;
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  testWidgets(
    'ambient motion stops in background, hidden routes and reduced motion',
    (tester) async {
      Future<void> mount({
        bool reduced = false,
        bool visible = true,
        int tab = 0,
      }) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appearanceRepositoryProvider.overrideWithValue(
                MemoryAppearanceRepository(),
              ),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                  enabled: visible,
                  child: QuietBackdrop(tab: tab, child: const SizedBox()),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await mount();
      await tester.pump(const Duration(seconds: 6));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await mount(visible: false);
      expect(tester.binding.transientCallbackCount, 0);
      await mount(reduced: true);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.byKey(const ValueKey('aurora-0')), findsOneWidget);
      await mount(tab: 1);
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final highContrast in [false, true]) {
    testWidgets(
      'focus surface preserves content and honors contrast=$highContrast',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appearanceRepositoryProvider.overrideWithValue(
                MemoryAppearanceRepository(),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(Brightness.light),
              home: MediaQuery(
                data: MediaQueryData(highContrast: highContrast),
                child: const Scaffold(
                  body: AcrylicSurface(child: Text('课程名称与地点')),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('课程名称与地点'), findsOneWidget);
        expect(
          tester
              .widget<BackdropFilter>(
                find.byKey(const ValueKey('focus-acrylic-blur')),
              )
              .enabled,
          !highContrast,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Today header gains reading protection on scroll', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      app(MemoryRepository(weeklyPreviewData(DateTime.now()))),
    );
    await tester.pumpAndSettle();
    final header = find.byKey(const ValueKey('topbar-0'));
    final initial = tester.widget<MiuixTopAppBar>(header).blurTintAlpha;
    await tester.drag(
      find.byKey(const PageStorageKey('today-page')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MiuixTopAppBar>(header).blurTintAlpha,
      greaterThan(initial),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
