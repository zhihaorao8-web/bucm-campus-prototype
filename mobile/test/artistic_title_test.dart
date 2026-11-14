import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'ui_test.dart' show app;
import 'week_grid_test.dart' show weeklyPreviewData;

void main() {
  testWidgets(
    'Today and Schedule headers use bundled LongCang display font while Settings stays clean',
    (tester) async {
      await tester.runAsync(() async {
        final fontData = await rootBundle.load(
          'assets/fonts/LongCang-Regular.ttf',
        );
        expect(fontData.lengthInBytes, greaterThan(1000000));
        final loader = FontLoader('LongCang')
          ..addFont(Future.value(fontData));
        await loader.load();
      });

      for (final (dark, scale) in [(false, 1.0), (true, 1.5), (false, 2.0)]) {
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

        final todayHeader = find.byKey(
          const ValueKey('topbar-0'),
          skipOffstage: false,
        );
        final allTodayTexts = tester
            .widgetList<Text>(
              find.descendant(
                of: todayHeader,
                matching: find.byType(Text, skipOffstage: false),
                skipOffstage: false,
              ),
            )
            .where((t) => t.data == '今日')
            .toList();
        expect(allTodayTexts, isNotEmpty);
        expect(
          allTodayTexts.any((t) => t.style?.fontFamily == 'LongCang'),
          isTrue,
        );

        await tester.tap(find.byKey(const ValueKey('tab-1')));
        await tester.pumpAndSettle();
        final weekHeader = find.byKey(const ValueKey('topbar-1'));
        final weekTexts = tester
            .widgetList<Text>(
              find.descendant(of: weekHeader, matching: find.text('课表')),
            )
            .toList();
        expect(weekTexts, isNotEmpty);
        expect(weekTexts.any((t) => t.style?.fontFamily == 'LongCang'), isTrue);

        await tester.tap(find.byKey(const ValueKey('tab-2')));
        await tester.pumpAndSettle();
        final settingsHeader = find.byKey(const ValueKey('topbar-2'));
        final settingsTexts = tester
            .widgetList<Text>(
              find.descendant(of: settingsHeader, matching: find.text('设置')),
            )
            .toList();
        expect(settingsTexts, isNotEmpty);
        expect(
          settingsTexts.every((t) => t.style?.fontFamily != 'LongCang'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
}
