import 'dart:math' as math;
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/quote_service.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/ui/app_shell.dart';
import 'package:campus_schedule/ui/appearance_page.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'schedule_test.dart' show MemoryRepository;
import 'support/memory_appearance.dart';
import 'week_grid_test.dart' show weeklyPreviewData;

Future<ProviderContainer> _pumpQuoteHarness(
  WidgetTester tester, {
  required QuoteService service,
  required MemoryAppearanceRepository appearanceRepo,
  required ScheduleData schedule,
  required Widget home,
  bool dark = false,
  double scale = 1.0,
  bool highContrast = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      ambientMotionEnabledProvider.overrideWithValue(false),
      quoteServiceProvider.overrideWithValue(service),
      appearanceRepositoryProvider.overrideWithValue(appearanceRepo),
      repositoryProvider.overrideWithValue(MemoryRepository(schedule)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(appearanceProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        key: ObjectKey(container),
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            highContrast: highContrast,
          ),
          child: MiuixThemeBridge(child: child!),
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('DailyQuote parses valid Hitokoto JSON and rejects invalid payloads', () {
    final parsed = DailyQuote.tryFromHitokotoJson({
      'hitokoto': '  山川异域，风月同天。  ',
      'from': ' 绣袈裟衣缘 ',
      'from_who': ' 长屋 ',
    });
    expect(parsed, isNotNull);
    expect(parsed!.text, '山川异域，风月同天。');
    expect(parsed.attribution, '绣袈裟衣缘 · 长屋');
    expect(parsed.isOnline, isTrue);

    expect(DailyQuote.tryFromHitokotoJson({'hitokoto': ''}), isNull);
    expect(
      DailyQuote.tryFromHitokotoJson({'hitokoto': '坏\x00控制字符'}),
      isNull,
    );
    expect(
      DailyQuote.tryFromHitokotoJson({'hitokoto': '字' * 121}),
      isNull,
    );
  });

  test('QuoteService stays strictly offline unless allowOnline is true', () async {
    var called = 0;
    final offlineFirst = QuoteService(
      fetcher: () async {
        called++;
        return const DailyQuote(
          text: '在线句',
          source: '一言',
          isOnline: true,
        );
      },
    );

    final first = await offlineFirst.nextQuote(
      allowOnline: false,
      random: math.Random(1),
    );
    expect(first.isOnline, isFalse);
    expect(called, 0);

    final nextLocal = offlineFirst.pickLocal(
      random: math.Random(1),
      excludeText: first.text,
    );
    expect(nextLocal.text, isNot(first.text));

    final online = await offlineFirst.nextQuote(allowOnline: true);
    expect(called, 1);
    expect(online.isOnline, isTrue);
    expect(online.text, '在线句');

    final failing = QuoteService(
      fetcher: () async => throw StateError('offline'),
    );
    final fallback = await failing.nextQuote(
      allowOnline: true,
      random: math.Random(2),
    );
    expect(fallback.isOnline, isFalse);
    expect(QuoteService.localQuotes.any((q) => q.text == fallback.text), isTrue);
  });

  test('AppearanceSettings keeps old JSON compatibility and validates onlineQuotes', () {
    final legacy = const AppearanceSettings().toJson()..remove('onlineQuotes');
    final loaded = AppearanceSettings.fromJson(legacy);
    expect(loaded.onlineQuotes, isFalse);

    final enabled = AppearanceSettings.fromJson({
      ...legacy,
      'onlineQuotes': true,
    });
    expect(enabled.onlineQuotes, isTrue);

    expect(
      () => AppearanceSettings.fromJson({...legacy, 'onlineQuotes': 'yes'}),
      throwsFormatException,
    );
  });

  testWidgets(
    'Today page renders top random quote, refreshes on tap, and supports small/large scale',
    (tester) async {
      var hits = 0;
      final service = QuoteService(
        fetcher: () async {
          hits++;
          return DailyQuote(
            text: '远赴人间惊鸿宴 $hits',
            source: '合成一言',
            author: '测试',
            isOnline: true,
          );
        },
      );
      final schedule = weeklyPreviewData(DateTime.now());

      for (final (width, dark, scale, highContrast) in [
        (390.0, false, 1.0, false),
        (320.0, true, 1.5, false),
        (320.0, false, 2.0, true),
      ]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpQuoteHarness(
          tester,
          service: service,
          appearanceRepo: MemoryAppearanceRepository(),
          schedule: schedule,
          dark: dark,
          scale: scale,
          highContrast: highContrast,
          home: const AppShell(),
        );

        final strip = find.byKey(const ValueKey('today-quote-strip'));
        expect(strip, findsOneWidget);
        expect(hits, 0);

        final beforeText = tester
            .widgetList<Text>(
              find.descendant(of: strip, matching: find.byType(Text)),
            )
            .first
            .data;
        await tester.tap(find.byKey(const ValueKey('today-quote-refresh')));
        await tester.pumpAndSettle();
        final afterText = tester
            .widgetList<Text>(
              find.descendant(of: strip, matching: find.byType(Text)),
            )
            .first
            .data;
        expect(afterText, isNot(beforeText));
        expect(hits, 0);
        expect(tester.takeException(), isNull);
      }

      // Empty schedule retains compact above-the-fold CTA without quote strip.
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpQuoteHarness(
        tester,
        service: service,
        appearanceRepo: MemoryAppearanceRepository(),
        schedule: const ScheduleData(),
        home: const AppShell(),
      );
      expect(find.byKey(const ValueKey('today-quote-strip')), findsNothing);
      expect(find.text('先体验合成示例'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Appearance setting onlineQuotes switch toggles and triggers online fetch',
    (tester) async {
      var onlineHits = 0;
      final service = QuoteService(
        fetcher: () async {
          onlineHits++;
          return const DailyQuote(
            text: '清风拂山岗',
            source: '测试词话',
            isOnline: true,
          );
        },
      );
      await _pumpQuoteHarness(
        tester,
        service: service,
        appearanceRepo: MemoryAppearanceRepository(
          const AppearanceSettings(onlineQuotes: true),
        ),
        schedule: weeklyPreviewData(DateTime.now()),
        home: const AppShell(),
      );
      expect(onlineHits, greaterThanOrEqualTo(1));
      expect(find.text('清风拂山岗'), findsOneWidget);
      expect(find.text('一言'), findsOneWidget);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final toggleRepo = MemoryAppearanceRepository();
      await _pumpQuoteHarness(
        tester,
        service: service,
        appearanceRepo: toggleRepo,
        schedule: const ScheduleData(),
        home: const AppearancePage(),
      );
      final toggleFinder = find.text('在线一言');
      await tester.scrollUntilVisible(toggleFinder, 200);
      await tester.ensureVisible(toggleFinder);
      await tester.pumpAndSettle();
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();
      expect(toggleRepo.value.onlineQuotes, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
