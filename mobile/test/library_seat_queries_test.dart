import 'dart:async';
import 'dart:io';

import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/library_seat_queries.dart';
import 'package:campus_schedule/domain/library_seats.dart';
import 'package:campus_schedule/platform/library_seat_reader.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/library_seat_query_page.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_appearance.dart';

LibrarySeat seat({
  String id = '1',
  String label = '合成座位',
  bool viewOnly = false,
  bool open = true,
  List<LibraryHours> hours = const [(510, 1320)],
  List<LibraryInterval> reservations = const [],
}) => LibrarySeat(
  id: id,
  label: label,
  open: open,
  viewOnly: viewOnly,
  hours: hours,
  reservations: reservations,
);

class FakeLibrarySeatReader extends LibrarySeatReader {
  final pending = <Completer<List<LibrarySeat>>>[];
  final List<LibraryArea> areaList = const [
    LibraryArea('32', '二层北区', '二层'),
    LibraryArea('33', '三层南区', '三层'),
  ];

  Future<List<LibraryArea>> Function()? onAreas;
  Future<List<LibrarySeat>> Function(String area, DateTime date)? onSeats;
  Future<LibraryBookingPage> Function(DateTime begin, DateTime end, int page)?
  onBookings;
  int resetCount = 0;

  @override
  Future<List<LibraryArea>> areas() {
    if (onAreas != null) return onAreas!();
    return Future.value(areaList);
  }

  @override
  Future<List<LibrarySeat>> seats(String area, DateTime date) {
    if (onSeats != null) return onSeats!(area, date);
    final next = Completer<List<LibrarySeat>>();
    pending.add(next);
    return next.future;
  }

  @override
  Future<LibraryBookingPage> bookings(DateTime begin, DateTime end, int page) {
    if (onBookings != null) return onBookings!(begin, end, page);
    return Future.value(LibraryBookingPage(const [], false, page: page));
  }

  @override
  Future<void> reset() async {
    resetCount++;
  }
}

Widget wrapLibraryPage(
  LibrarySeatReader reader, {
  Key? pageKey,
  DateTime Function()? now,
  WidgetBuilder? officialPageBuilder,
  bool dark = false,
  double scale = 1.0,
  bool highContrast = false,
  bool disableAnimations = false,
  AppearanceSettings settings = const AppearanceSettings(),
}) => ProviderScope(
  overrides: [
    ambientMotionEnabledProvider.overrideWithValue(false),
    appearanceRepositoryProvider.overrideWithValue(
      MemoryAppearanceRepository(settings),
    ),
    currentAppearanceProvider.overrideWithValue(settings),
  ],
  child: MaterialApp(
    theme: appTheme(dark ? Brightness.dark : Brightness.light, settings: settings),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        highContrast: highContrast,
        disableAnimations: disableAnimations,
      ),
      child: MiuixThemeBridge(child: child!),
    ),
    home: LibrarySeatQueryPage(
      key: pageKey,
      reader: reader,
      now: now,
      officialPageBuilder: officialPageBuilder,
    ),
  ),
);

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 180);
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
}

void main() {
  final day = DateTime(2026, 10, 10);
  final androidOnly = TargetPlatformVariant.only(TargetPlatform.android);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime.utc(2026, 10, 10, hour - 8, minute);

  test(
    'seat statuses use the selected time, cover overlaps and exclude view-only seats',
    () {
      expect(seat().statusOn(day, 540, 660), LibrarySeatStatus.available);
      expect(seat().statusOn(day, 480, 660), LibrarySeatStatus.closed);
      expect(
        seat(open: false).statusOn(day, 540, 660),
        LibrarySeatStatus.closed,
      );
      expect(
        seat(viewOnly: true).statusOn(day, 540, 660),
        LibrarySeatStatus.viewOnly,
      );
      expect(
        seat(reservations: [(at(10), at(11))]).statusOn(day, 540, 660),
        LibrarySeatStatus.partial,
      );
      expect(
        seat(
          reservations: [(at(9), at(10)), (at(10), at(11))],
        ).statusOn(day, 540, 660),
        LibrarySeatStatus.occupied,
      );
      expect(
        seat(reservations: [(at(8), at(9))]).statusOn(day, 540, 660),
        LibrarySeatStatus.available,
      );

      final overlaps = seat(
        reservations: [(at(14), at(15)), (at(10, 30), at(11, 30))],
      ).overlappingReservations(day, 600, 960);
      expect(overlaps.map(formatLibraryInterval).toList(), [
        '10:30–11:30',
        '14:00–15:00',
      ]);
      expect(formatClockMinutes(510), '08:30');
    },
  );

  test('booking status bitmasks decode official flags and unknown codes', () {
    expect(libraryBookingStatusLabels(null), isEmpty);
    expect(libraryBookingStatusLabels(4 | 64), ['生效中', '已签到']);
    expect(libraryBookingStatusLabels(2 | 1024), ['待生效', '审核通过']);
    expect(libraryBookingStatusLabels(128 | 16), ['已结束', '违约']);
    expect(libraryBookingStatusLabels(256 | 512 | 2048 | 4096), [
      '待审核',
      '审核未通过',
      '暂离中',
      '已签离',
    ]);
    expect(libraryBookingStatusLabels(32768), ['学校状态码 32768']);
  });

  test(
    'a later selection wins and a reset discards responses for the previous session',
    () async {
      final reader = FakeLibrarySeatReader();
      final controller = LibrarySeatQueries(reader);
      addTearDown(controller.dispose);
      final first = controller.loadSeats('1', day);
      final second = controller.loadSeats('2', day);
      reader.pending[1].complete([]);
      await second;
      reader.pending[0].complete([seat()]);
      await first;
      expect(controller.seats, isEmpty);

      final priorAccount = controller.loadSeats('2', day);
      await controller.clearSession();
      reader.pending[2].complete([seat()]);
      await priorAccount;
      expect(controller.seats, isNull);
      expect(controller.loading, false);
      expect(controller.sessionCleared, true);

      final third = controller.loadAreaSeats(preferredAreaId: '33', date: day);
      await Future<void>.delayed(Duration.zero);
      final fourth = controller.loadAreaSeats(preferredAreaId: '32', date: day);
      reader.pending[4].complete([seat(id: '3201', label: 'A01')]);
      final chosen = await fourth;
      expect(chosen?.id, '32');
      reader.pending[3].complete([seat(id: '3301', label: 'B01')]);
      expect(await third, isNull);
      expect(controller.seats?.single.id, '3201');
      expect(controller.sessionCleared, false);
    },
  );

  test(
    'expiration clears already loaded personal data and stays distinct from query failure',
    () async {
      final reader = FakeLibrarySeatReader();
      final controller = LibrarySeatQueries(reader);
      addTearDown(controller.dispose);
      controller.bookings = const LibraryBookingPage([], false);
      final expired = controller.loadSeats('1', day);
      reader.pending[0].completeError(LibraryReadFailure.login);
      await expired;
      expect(controller.needsLogin, true);
      expect(controller.bookings, isNull);
      final failed = controller.loadSeats('1', day);
      reader.pending[1].completeError(LibraryReadFailure.unavailable);
      await failed;
      expect(controller.needsLogin, false);
      expect(controller.failed, true);
    },
  );

  testWidgets(
    'seat page handles empty areas, empty seats, and seats with no open hours',
    variant: androidOnly,
    (tester) async {
      final emptyAreaReader = FakeLibrarySeatReader()
        ..onAreas = () async => const [];
      await tester.pumpWidget(
        wrapLibraryPage(
          emptyAreaReader,
          pageKey: UniqueKey(),
          now: () => DateTime(2026, 10, 10, 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无座位区域'), findsOneWidget);

      final emptySeatReader = FakeLibrarySeatReader()
        ..onSeats = (_, _) async => const [];
      await tester.pumpWidget(
        wrapLibraryPage(
          emptySeatReader,
          pageKey: UniqueKey(),
          now: () => DateTime(2026, 10, 10, 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('该日期暂无座位'), findsOneWidget);

      final closedDayReader = FakeLibrarySeatReader()
        ..onSeats = (_, _) async => [
          seat(id: '10', label: 'N001', hours: const []),
          seat(id: '11', label: 'N002', viewOnly: true, hours: const []),
        ];
      await tester.pumpWidget(
        wrapLibraryPage(
          closedDayReader,
          pageKey: UniqueKey(),
          now: () => DateTime(2026, 10, 10, 10),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('所选日期暂无开放时段。'), findsOneWidget);
      expect(find.text('N001'), findsOneWidget);
      expect(find.text('不开放'), findsOneWidget);
      expect(find.text('N002'), findsOneWidget);
      expect(find.text('仅查看'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'seat page lists all statuses, supports candidate selection and only-available filter',
    variant: androidOnly,
    (tester) async {
      final reader = FakeLibrarySeatReader()
        ..onSeats = (_, _) async => [
          seat(id: '1', label: 'N001'),
          seat(
            id: '2',
            label: 'N002',
            reservations: [(at(10), at(11))],
          ),
          seat(
            id: '3',
            label: 'N003',
            reservations: [(at(8, 30), at(22))],
          ),
          seat(id: '4', label: 'N004', open: false),
          seat(id: '5', label: 'N005', viewOnly: true),
        ];

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 9)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('共 5 个座位 · 空闲 1 · 半空闲 1 · 使用中 1 · 不可用 2'),
        findsOneWidget,
      );
      expect(find.text('已约 10:00–11:00'), findsOneWidget);

      // Tapping partial seat does not select it.
      await reveal(tester, find.text('N002'));
      await tester.tap(find.text('N002'));
      await tester.pumpAndSettle();
      expect(find.text('已选候选座位'), findsNothing);

      // Tapping available seat selects it and displays candidate summary.
      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('已选候选座位'));
      expect(find.text('已选候选座位'), findsOneWidget);
      expect(find.text('二层 · 二层北区 · N001'), findsOneWidget);
      expect(find.text('2026-10-10 08:30–22:00'), findsOneWidget);

      // Tapping clear deselects it.
      await reveal(tester, find.text('清除选择'));
      await tester.tap(find.text('清除选择'));
      await tester.pumpAndSettle();
      expect(find.text('已选候选座位'), findsNothing);

      // Filtering only available hides non-available rows.
      await reveal(tester, find.text('仅看空闲'));
      await tester.tap(find.text('仅看空闲'));
      await tester.pumpAndSettle();
      expect(find.text('N001'), findsOneWidget);
      expect(find.text('N002'), findsNothing);
      expect(find.text('N005'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'switching date discards stale seat response and clears prior selection',
    variant: androidOnly,
    (tester) async {
      final today = DateTime(2026, 10, 10);
      final tomorrow = DateTime(2026, 10, 11);
      final requests = <(DateTime, Completer<List<LibrarySeat>>)>[];
      final reader = FakeLibrarySeatReader()
        ..onSeats = (_, date) {
          final c = Completer<List<LibrarySeat>>();
          requests.add((date, c));
          return c.future;
        };

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 9)),
      );
      await tester.pump();
      requests[0].$2.complete([seat(id: '1', label: '今日座位')]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('今日座位'));
      await tester.pumpAndSettle();
      expect(find.text('已选候选座位'), findsOneWidget);

      // Switch to tomorrow while a manual refresh on today could still be pending.
      await tester.tap(find.text('刷新座位'));
      await tester.pump();
      await tester.tap(find.text('明天'));
      await tester.pump();

      expect(find.text('已选候选座位'), findsNothing);
      expect(requests.length, 3);
      expect(requests[1].$1, today);
      expect(requests[2].$1, tomorrow);

      requests[2].$2.complete([seat(id: '2', label: '明日座位')]);
      await tester.pumpAndSettle();
      requests[1].$2.complete([seat(id: '9', label: '迟到旧座位')]);
      await tester.pumpAndSettle();

      expect(find.text('明日座位'), findsOneWidget);
      expect(find.text('迟到旧座位'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'bookings tab decodes statuses, supports pagination and handles empty list',
    variant: androidOnly,
    (tester) async {
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => [seat()])
        ..onBookings = (_, _, page) async {
          if (page == 1) {
            return const LibraryBookingPage(
              [
                LibraryBooking(
                  '7001',
                  '二层北区',
                  'N001',
                  '2026-10-10 08:30',
                  '2026-10-10 12:00',
                  4 | 64,
                ),
              ],
              true,
              page: 1,
              totalCount: 12,
            );
          }
          return const LibraryBookingPage(
            [
              LibraryBooking(
                '7002',
                '三层南区',
                'S008',
                '2026-10-09 14:00',
                '2026-10-09 18:00',
                128,
              ),
            ],
            false,
            page: 2,
            totalCount: 12,
          );
        };

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 9)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的预约'));
      await tester.pumpAndSettle();

      expect(find.text('第 1 页 · 共 12 条'), findsOneWidget);
      expect(find.text('二层北区 · N001'), findsOneWidget);
      expect(find.text('生效中 · 已签到 · 预约编号 7001'), findsOneWidget);

      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 页 · 共 12 条'), findsOneWidget);
      expect(find.text('三层南区 · S008'), findsOneWidget);
      expect(find.text('已结束 · 预约编号 7002'), findsOneWidget);

      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('二层北区 · N001'), findsOneWidget);

      reader.onBookings = (_, _, page) async =>
          LibraryBookingPage(const [], false, page: page, totalCount: 0);
      await tester.tap(find.text('刷新预约'));
      await tester.pumpAndSettle();
      expect(find.text('暂无座位预约'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'login expiration, failure retry, and global session clear behave safely',
    variant: androidOnly,
    (tester) async {
      final folder = await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-lib-session-'),
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => folder!.path);
      messenger.setMockMethodCallHandler(SchoolAdapter.channel, (_) async => null);
      addTearDown(() async {
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(SchoolAdapter.channel, null);
        await folder!.delete(recursive: true);
      });

      var phase = 0;
      final reader = FakeLibrarySeatReader()
        ..onSeats = (_, _) async {
          if (phase == 0) throw LibraryReadFailure.login;
          if (phase == 1) throw LibraryReadFailure.unavailable;
          return [seat(id: '88', label: '恢复后座位')];
        };

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 9),
          officialPageBuilder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  phase = 1;
                  Navigator.of(context).pop();
                },
                child: const Text('模拟登录完成返回'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: needsLogin prompts user to open official page.
      expect(find.text('需要登录学校账号'), findsOneWidget);
      await tester.tap(find.text('打开学校页面登录').last);
      await tester.pumpAndSettle();
      expect(find.text('模拟登录完成返回'), findsOneWidget);

      // Step 2: pop triggers reload -> phase 1 fails -> retry recovers at phase 2.
      await tester.tap(find.text('模拟登录完成返回'));
      await tester.pumpAndSettle();
      expect(find.text('查询未完成'), findsOneWidget);

      phase = 2;
      await tester.tap(find.text('重试查询'));
      await tester.pumpAndSettle();
      expect(find.text('恢复后座位'), findsOneWidget);

      // Step 3: global SchoolAdapter.clearSession clears seats and shows prompt.
      await tester.runAsync(() => SchoolAdapter().clearSession());
      await tester.pumpAndSettle();
      expect(find.text('恢复后座位'), findsNothing);
      expect(find.text('学校会话已清除'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scenario in [
    (
      name: 'light-narrow-1.5x',
      dark: false,
      scale: 1.5,
      highContrast: false,
      disableAnimations: false,
    ),
    (
      name: 'dark-narrow-2.0x-hc-reduced',
      dark: true,
      scale: 2.0,
      highContrast: true,
      disableAnimations: true,
    ),
  ]) {
    testWidgets(
      'responsive and accessibility check: ${scenario.name}',
      variant: androidOnly,
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final reader = FakeLibrarySeatReader()
          ..onSeats = (_, _) async => [
            seat(id: '1', label: 'A001'),
            seat(id: '2', label: 'A002', reservations: [(at(10), at(11))]),
          ];

        await tester.pumpWidget(
          wrapLibraryPage(
            reader,
            now: () => DateTime(2026, 10, 10, 9),
            dark: scenario.dark,
            scale: scenario.scale,
            highContrast: scenario.highContrast,
            disableAnimations: scenario.disableAnimations,
          ),
        );
        await tester.pumpAndSettle();

        await reveal(tester, find.text('A001'));
        await tester.tap(find.text('A001'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('已选候选座位'));
        expect(find.text('已选候选座位'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
