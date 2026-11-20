import 'package:campus_schedule/ui/acrylic_surface.dart';
import 'package:campus_schedule/ui/course_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'ui_test.dart' show app;
import 'schedule_test.dart' show MemoryRepository;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'shared surfaces honor live accessibility/preferences dark=$dark',
      (tester) async {
        for (final mode in [
          'normal',
          'blur-off',
          'glass-off',
          'app-contrast',
          'system-contrast',
          'reduced',
        ]) {
          final settings = AppearanceSettings(
            blur: mode != 'blur-off',
            glass: mode != 'glass-off',
            contrast: mode == 'app-contrast' ? .5 : 0,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentAppearanceProvider.overrideWithValue(settings),
              ],
              child: MaterialApp(
                theme: appTheme(dark ? Brightness.dark : Brightness.light),
                home: MediaQuery(
                  data: MediaQueryData(
                    highContrast: mode == 'system-contrast',
                    disableAnimations: mode == 'reduced',
                  ),
                  child: const Scaffold(
                    body: Column(
                      children: [
                        AcrylicSurface(child: SizedBox(width: 100, height: 40)),
                        QuietSheet(child: SizedBox(width: 100, height: 40)),
                        CourseSurface(child: SizedBox(width: 100, height: 40)),
                        CourseSurface(
                          dense: true,
                          child: SizedBox(width: 100, height: 40),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final translucent = mode == 'normal' || mode == 'reduced';
          for (final filter in tester.widgetList<BackdropFilter>(
            find.byType(BackdropFilter),
          )) {
            expect(filter.enabled, translucent, reason: mode);
          }
          for (final surface in find.byType(CourseSurface).evaluate()) {
            final decorated =
                tester
                        .widgetList<DecoratedBox>(
                          find.descendant(
                            of: find.byWidget(surface.widget),
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .first
                        .decoration
                    as BoxDecoration;
            expect(decorated.gradient != null, translucent, reason: mode);
            if (!translucent) expect(decorated.color!.a, 1, reason: mode);
          }
          expect(tester.takeException(), isNull, reason: mode);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'decorations honor switches; card style changes real course rows',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(MemoryRepository(weeklyPreviewData(DateTime.now()))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('aurora-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('paper-grain')), findsOneWidget);
      expect(find.byKey(const ValueKey('course-color-rail')), findsWidgets);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(QuietBackdrop)),
      );
      await container
          .read(appearanceProvider.notifier)
          .change(
            (p) =>
                p.copyWith(aurora: false, paperTexture: false, softCards: true),
          );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('aurora-0')), findsNothing);
      expect(find.byKey(const ValueKey('paper-grain')), findsNothing);
      expect(find.byKey(const ValueKey('course-color-rail')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'high contrast removes decorative layers and reduced motion settles',
    (tester) async {
      await tester.pumpWidget(
        app(
          MemoryRepository(weeklyPreviewData(DateTime.now())),
          highContrast: true,
          reduceMotion: true,
          dark: true,
          scale: 1.5,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paper-grain')), findsNothing);
      expect(find.byKey(const ValueKey('aurora-0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('paper surfaces and course inks remain legible', () {
    final theme = appTheme(Brightness.light);
    expect(theme.colorScheme.surface, AppColors.paper);
    expect(theme.colorScheme.onSurface, const Color(0xFF1E2022));
    expect(theme.colorScheme.surfaceContainer, Colors.white);
  });
}
