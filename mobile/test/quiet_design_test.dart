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
      await tester.tap(find.byKey(const ValueKey('tab-2')));
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
