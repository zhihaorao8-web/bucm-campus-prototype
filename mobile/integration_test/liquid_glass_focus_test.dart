import 'dart:io';
import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:campus_schedule/ui/today_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('focus optics receive the natural height inside a scrolling list', (
    tester,
  ) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/liquid_glass.frag',
    );
    final course = Course(
      id: 'synthetic-focus',
      name: '合成示例课程',
      teacher: '示例教师',
      place: '示例教学楼101',
      day: 1,
      weeks: '1-16',
      periods: [1, 2],
      segments: [TeachingSegment('08:30', '10:00')],
      semester: 'synthetic-term',
      termStart: DateTime(2026, 9, 7),
      dataSource: 'synthetic',
    );
    final event = Occurrence(
      course,
      course.segments.single,
      DateTime(2026, 11, 9),
    );
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
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
              theme: appTheme(dark ? Brightness.dark : Brightness.light),
              builder: (context, child) => MiuixThemeBridge(child: child!),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 640,
                    child: MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true,
                      ),
                      child: RepaintBoundary(
                        key: capture,
                        child: Stack(
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
                            ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                FocusCourseCard(
                                  event: event,
                                  now: DateTime(2026, 11, 9, 9),
                                ),
                              ],
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
        final surface = find.byType(LiquidGlassSurface);
        expect(surface, findsOneWidget);
        final size = tester.getSize(surface);
        expect(size.height, greaterThan(100));
        expect(size.height.isFinite, isTrue);
        expect(size.width, closeTo(288, .1));
        expect(find.text('合成示例课程'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${Directory.systemTemp.path}/liquid-focus-${dark ? 'dark' : 'light'}-$scale.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
