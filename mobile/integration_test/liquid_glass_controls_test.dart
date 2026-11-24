import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/glass_navigation.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:campus_schedule/ui/classroom_section_switch.dart';
import 'package:campus_schedule/ui/week_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'liquid controls remain interactive at narrow width and large text',
    (tester) async {
      expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/liquid_glass.frag',
      );
      for (final dark in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          var selected = 0;
          var daily = false;
          var section = 0;
          var library = 0;
          final capture = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentAppearanceProvider.overrideWithValue(
                  const AppearanceSettings(),
                ),
                liquidGlassProgramProvider.overrideWith((ref) async => program),
              ],
              child: MaterialApp(
                builder: (context, child) => MiuixThemeBridge(
                  child: Material(type: MaterialType.transparency, child: child!),
                ),
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: Center(
                  child: SizedBox(
                    width: 320,
                    height: 440,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: RepaintBoundary(
                        key: capture,
                        child: StatefulBuilder(
                          builder: (context, setState) => Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: dark
                                        ? [
                                            Colors.indigo,
                                            Colors.black,
                                            Colors.teal,
                                          ]
                                        : [
                                            Colors.lightBlue,
                                            Colors.white,
                                            Colors.amber,
                                          ],
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.topCenter,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      ScheduleModeSwitch(
                                        daily: daily,
                                        onChanged: (value) =>
                                            setState(() => daily = value),
                                      ),
                                      const SizedBox(height: 16),
                                      ClassroomSectionSwitch(
                                        tabs: const ['录播', '直播'],
                                        selectedIndex: section,
                                        onSelected: (value) =>
                                            setState(() => section = value),
                                      ),
                                      const SizedBox(height: 16),
                                      ClassroomSectionSwitch(
                                        tabs: const ['选座', '我的预约'],
                                        selectedIndex: library,
                                        onSelected: (value) =>
                                            setState(() => library = value),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: GlassNavigation(
                                  selected: selected,
                                  onSelect: (index) =>
                                      setState(() => selected = index),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(LiquidGlassSurface), findsNWidgets(4));
          await tester.tap(find.text('日'));
          await tester.pumpAndSettle();
          expect(daily, isTrue);
          await tester.tap(find.text('直播'));
          await tester.pumpAndSettle();
          expect(section, 1);
          await tester.tap(find.text('我的预约'));
          await tester.pumpAndSettle();
          expect(library, 1);
          for (final index in [3, 1, 0]) {
            await tester.tap(find.byKey(ValueKey('tab-$index')));
            await tester.pumpAndSettle();
            expect(selected, index);
            expect(tester.takeException(), isNull);
          }
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${Directory.systemTemp.path}/liquid-controls-${dark ? 'dark' : 'light'}-$scale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
    },
  );
}
