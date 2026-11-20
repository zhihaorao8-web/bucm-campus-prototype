import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:campus_schedule/ui/app_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all offline IconMCP SVGs decode and paint visible pixels', () async {
    expect(AppIcons.values.length, 49);
    for (final icon in AppIcons.values) {
      final picture = await vg.loadPicture(SvgAssetLoader(icon.asset), null);
      expect(picture.size, const Size(16, 16), reason: icon.name);
      final image = await picture.picture.toImage(48, 48);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      expect(
        List.generate(
          48 * 48,
          (i) => pixels.getUint8(i * 4 + 3),
        ).any((a) => a > 0),
        isTrue,
        reason: icon.name,
      );
      image.dispose();
      picture.picture.dispose();
    }
  });

  testWidgets('SVG inherits icon size, tint, opacity, shadows and semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: IconTheme(
            data: IconThemeData(
              size: 32,
              color: Colors.red,
              opacity: .4,
              shadows: [Shadow(color: Colors.black)],
            ),
            child: AppIcon(AppIcons.play, semanticLabel: '合成播放'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppIcon)), const Size(32, 32));
    expect(find.bySemanticsLabel('合成播放'), findsOneWidget);
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, .4);
    final images = tester
        .widgetList<SvgPicture>(find.byType(SvgPicture))
        .toList();
    expect(images.length, 2);
    expect(
      images.last.colorFilter,
      const ColorFilter.mode(Colors.red, BlendMode.srcIn),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'directional SVG mirrors in RTL without mirroring playback icons',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [AppIcon(AppIcons.arrowBack), AppIcon(AppIcons.play)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final transforms = find.descendant(
        of: find.byType(AppIcon).first,
        matching: find.byType(Transform),
      );
      expect(tester.widget<Transform>(transforms).transform.entry(0, 0), -1);
      expect(
        find.descendant(
          of: find.byType(AppIcon).last,
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
