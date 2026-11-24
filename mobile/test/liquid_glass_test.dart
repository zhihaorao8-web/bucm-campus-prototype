import 'dart:async';
import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:campus_schedule/ui/visual_policy.dart';
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

  testWidgets(
    'BackdropSuspensionScope disables LiquidGlassSurface filter while staying translucent',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(),
            ),
            liquidGlassSupportedProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(
            home: BackdropSuspensionScope(
              suspended: true,
              child: SizedBox(
                width: 240,
                height: 60,
                child: LiquidGlassSurface(
                  blurKey: ValueKey('scoped-glass'),
                  child: Text('foreground'),
                ),
              ),
            ),
          ),
        ),
      );
      final filter = tester.widget<BackdropFilter>(
        find.byKey(const ValueKey('scoped-glass')),
      );
      expect(filter.enabled, isFalse);
      final box = filter.child! as ColoredBox;
      expect(box.color, Colors.transparent);
      expect(find.text('foreground'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BackdropSuspensionAnimation tracks active animation values and respects outer suspension',
    (tester) async {
      final controller = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 200),
      );
      addTearDown(controller.dispose);
      Future<void> mount({required bool outerSuspended}) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentAppearanceProvider.overrideWithValue(
                const AppearanceSettings(),
              ),
              liquidGlassSupportedProvider.overrideWithValue(false),
            ],
            child: MaterialApp(
              home: BackdropSuspensionScope(
                suspended: outerSuspended,
                child: BackdropSuspensionAnimation(
                  animation: controller,
                  child: const SizedBox(
                    width: 240,
                    height: 60,
                    child: LiquidGlassSurface(
                      blurKey: ValueKey('anim-glass'),
                      child: Text('foreground'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await mount(outerSuspended: false);
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('anim-glass')))
            .enabled,
        isTrue,
      );

      controller.forward();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('anim-glass')))
            .enabled,
        isFalse,
      );

      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('anim-glass')))
            .enabled,
        isTrue,
      );

      controller.value = 0.5;
      await tester.pump();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('anim-glass')))
            .enabled,
        isFalse,
      );

      controller.value = 1.0;
      await tester.pump();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('anim-glass')))
            .enabled,
        isTrue,
      );

      await mount(outerSuspended: true);
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('anim-glass')))
            .enabled,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BackdropTransitionBuilder suspends outgoing and incoming routes across push and pop',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentAppearanceProvider.overrideWithValue(
              const AppearanceSettings(),
            ),
            liquidGlassSupportedProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    const SizedBox(
                      width: 240,
                      height: 60,
                      child: LiquidGlassSurface(
                        blurKey: ValueKey('route-a-glass'),
                        child: Text('Route A'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: SizedBox(
                              width: 240,
                              height: 60,
                              child: LiquidGlassSurface(
                                blurKey: ValueKey('route-b-glass'),
                                child: Text('Route B'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Push B'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('route-a-glass')))
            .enabled,
        isTrue,
      );

      await tester.tap(find.text('Push B'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<BackdropFilter>(
              find.byKey(const ValueKey('route-a-glass'), skipOffstage: false),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('route-b-glass')))
            .enabled,
        isFalse,
      );

      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('route-b-glass')))
            .enabled,
        isTrue,
      );

      Navigator.of(tester.element(find.text('Route B'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        tester
            .widget<BackdropFilter>(
              find.byKey(const ValueKey('route-a-glass'), skipOffstage: false),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<BackdropFilter>(
              find.byKey(const ValueKey('route-b-glass'), skipOffstage: false),
            )
            .enabled,
        isFalse,
      );

      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(find.byKey(const ValueKey('route-a-glass')))
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
