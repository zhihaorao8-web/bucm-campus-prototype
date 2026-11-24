import 'dart:async';
import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'system contrast is opaque and reduced motion retains static blur',
    (tester) async {
      for (final highContrast in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAppearanceProvider.overrideWithValue(
                const AppearanceSettings(),
              ),
              liquidGlassSupportedProvider.overrideWithValue(false),
            ],
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  highContrast: highContrast,
                  disableAnimations: true,
                ),
                child: const SizedBox(
                  width: 240,
                  height: 60,
                  child: LiquidGlassSurface(child: Text('foreground')),
                ),
              ),
            ),
          ),
        );
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          !highContrast,
        );
      }
    },
  );
  for (final settings in [
    const AppearanceSettings(),
    const AppearanceSettings(glass: false),
    const AppearanceSettings(blur: false),
    const AppearanceSettings(contrast: 1),
  ]) {
    testWidgets('unsupported renderer respects material policy $settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(settings),
            liquidGlassSupportedProvider.overrideWithValue(false),
            liquidGlassProgramProvider.overrideWith(
              (ref) => throw StateError('must not load'),
            ),
          ],
          child: const MaterialApp(
            home: SizedBox(
              width: 240,
              height: 60,
              child: LiquidGlassSurface(child: Text('foreground')),
            ),
          ),
        ),
      );
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(
        filter.enabled,
        settings.glass && settings.blur && settings.contrast == 0,
      );
      expect(find.text('foreground'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('loading and failed program retain blur and foreground', (
    tester,
  ) async {
    final completer = Completer<ui.FragmentProgram>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppearanceProvider.overrideWithValue(
            const AppearanceSettings(),
          ),
          liquidGlassSupportedProvider.overrideWithValue(true),
          liquidGlassProgramProvider.overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 240,
            height: 60,
            child: LiquidGlassSurface(child: Text('foreground')),
          ),
        ),
      ),
    );
    expect(
      tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
      isTrue,
    );
    completer.completeError(StateError('synthetic load failure'));
    await tester.pumpAndSettle();
    expect(find.text('foreground'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
