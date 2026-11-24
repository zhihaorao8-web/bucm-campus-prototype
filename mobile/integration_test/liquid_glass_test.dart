import 'dart:ui' as ui;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/ui/liquid_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Impeller renders bounded optics, orientation and fallback', (
    tester,
  ) async {
    expect(ui.ImageFilter.isShaderFilterSupported, isTrue);
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/liquid_glass.frag',
    );
    for (final dark in [false, true]) {
      for (final width in [220.0, 300.0]) {
        final samples = <List<int>>[];
        for (final enabled in [false, true]) {
          final capture = GlobalKey();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentAppearanceProvider.overrideWithValue(
                  const AppearanceSettings(),
                ),
                liquidGlassSupportedProvider.overrideWithValue(enabled),
                liquidGlassProgramProvider.overrideWith((ref) async => program),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                home: Center(
                  child: RepaintBoundary(
                    key: capture,
                    child: SizedBox(
                      width: width,
                      height: 100,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.red, Colors.blue],
                              ),
                            ),
                          ),
                          const LiquidGlassSurface(
                            child: SizedBox.expand(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final pixels = await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final bytes = data.buffer.asUint8List().toList();
            image.dispose();
            return bytes;
          });
          samples.add(pixels!);
          final top = (10 * width.toInt() + width ~/ 2) * 4;
          final bottom = (90 * width.toInt() + width ~/ 2) * 4;
          expect(pixels[top], greaterThan(pixels[top + 2]));
          expect(pixels[bottom + 2], greaterThan(pixels[bottom]));
        }
        var changed = 0;
        for (var i = 0; i < samples.first.length; i++) {
          if ((samples.first[i] - samples.last[i]).abs() > 2) changed++;
        }
        expect(
          changed,
          greaterThan(100),
          reason: 'Shader must visibly refract the synthetic gradient',
        );
      }
    }
  });
}
