import 'dart:async';
import 'dart:io';

import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/library_seat_queries.dart';
import 'package:campus_schedule/domain/library_seats.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/library_seat_reader.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/glass_navigation.dart';
import 'package:campus_schedule/ui/library_seat_query_page.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_test.dart' show MemoryRepository;
import 'support/memory_appearance.dart';
import 'ui_test.dart' show app;

LibrarySeat seat({
  String id = '1',
  String label = '合成座位',
  bool viewOnly = false,
  bool open = true,
  List<LibraryHours> hours = const [(510, 1320)],
  List<LibraryInterval> reservations = const [],
  LibrarySeatRule? rule,
}) => LibrarySeat(
  id: id,
  label: label,
  open: open,
  viewOnly: viewOnly,
  hours: hours,
  reservations: reservations,
  rule: rule,
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
  Future<LibraryWriteResult> Function(
    String seatId,
    DateTime date,
    int startMinutes,
    int endMinutes,
  )?
  onReserve;
  int reserveCalls = 0;
  Future<LibraryWriteResult> Function(LibraryBooking)? onCancelBooking;
  int cancelCalls = 0;
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
  Future<LibraryWriteResult> reserve({
    required String seatId,
    required DateTime date,
    required int startMinutes,
    required int endMinutes,
  }) {
    reserveCalls++;
    if (onReserve != null) {
      return onReserve!(seatId, date, startMinutes, endMinutes);
    }
    return Future.value(const LibraryWriteResult(LibraryWriteStatus.ok));
  }

  @override
  Future<LibraryWriteResult> cancelBooking(
    LibraryBooking booking,
    DateTime begin,
    DateTime end,
    int page,
  ) {
    cancelCalls++;
    return onCancelBooking!(booking);
  }

  @override
  Future<void> reset() async {
    resetCount++;
  }
}

const cancellationFixture = LibraryBooking(
  '8002',
  '合成区域',
  'N002',
  '2099-10-10 09:00',
  '2099-10-10 12:00',
  2,
);

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
  final androidOnly = TargetPlatformVariant.only(TargetPlatform.android);
  test(
    'one pending cancellation refreshes the same page and blocks a repeated tap',
    () async {
      final reply = Completer<LibraryWriteResult>();
      var listReads = 0;
      final reader = FakeLibrarySeatReader()
        ..onCancelBooking = ((_) => reply.future)
        ..onBookings = ((_, _, page) async => LibraryBookingPage(
          listReads++ == 0 ? [cancellationFixture] : [],
          false,
          page: page,
        ));
      final queries = LibrarySeatQueries(reader);
      addTearDown(queries.dispose);
      final day = DateTime(2099, 10, 10);
      await queries.loadBookings(day, day, 1);
      final running = queries.cancelBooking(cancellationFixture, day, day, 1);
      await queries.cancelBooking(cancellationFixture, day, day, 1);
      reply.complete(const LibraryWriteResult(LibraryWriteStatus.ok));
      await running;
      expect(reader.cancelCalls, 1);
      expect(listReads, 2);
      expect(queries.cancellation?.removed, true);
      expect(queries.bookings?.rows, isEmpty);
    },
  );

  test(
    'lost cancellation response remains uncertain after a refresh and does not re-send',
    () async {
      final reader = FakeLibrarySeatReader()
        ..onCancelBooking = ((_) async => throw StateError('synthetic timeout'))
        ..onBookings = ((_, _, page) async =>
            LibraryBookingPage([cancellationFixture], false, page: page));
      final queries = LibrarySeatQueries(reader);
      addTearDown(queries.dispose);
      final day = DateTime(2099, 10, 10);
      await queries.loadBookings(day, day, 1);
      await queries.cancelBooking(cancellationFixture, day, day, 1);
      await queries.cancelBooking(cancellationFixture, day, day, 1);
      expect(reader.cancelCalls, 1);
      expect(queries.cancellation?.status, LibraryWriteStatus.uncertain);
      expect(queries.cancellation?.removed, false);
      expect(queries.bookings?.rows, [cancellationFixture]);
    },
  );

  test(
    'a started reservation never reaches the cancellation transport',
    () async {
      const expired = LibraryBooking(
        '8003',
        '合成区域',
        'N003',
        '2000-10-10 09:00',
        '2000-10-10 12:00',
        2,
      );
      final reader = FakeLibrarySeatReader()
        ..onBookings = ((_, _, page) async =>
            LibraryBookingPage([expired], false, page: page));
      final queries = LibrarySeatQueries(reader);
      addTearDown(queries.dispose);
      final day = DateTime(2000, 10, 10);
      await queries.loadBookings(day, day, 1);
      await queries.cancelBooking(expired, day, day, 1);
      expect(reader.cancelCalls, 0);
    },
  );

  testWidgets(
    'cancel confirmation shows the target and keeps the booking when dismissed',
    variant: androidOnly,
    (tester) async {
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => [seat()])
        ..onBookings = ((_, _, page) async => LibraryBookingPage(
          [cancellationFixture],
          false,
          page: page,
          totalCount: 1,
        ));
      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2099, 10, 10)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的预约'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('取消预约'));
      await tester.tap(find.text('取消预约'));
      await tester.pumpAndSettle();
      expect(find.text('确认取消预约'), findsOneWidget);
      expect(find.textContaining('预约编号 8002').last, findsOneWidget);
      await tester.tap(find.text('保留预约'));
      await tester.pumpAndSettle();
      expect(reader.cancelCalls, 0);
      expect(find.text('确认取消预约'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  final day = DateTime(2026, 10, 10);
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
        await reveal(tester, find.text('确认预约'));
        await tester.tap(find.text('确认预约'));
        await tester.pumpAndSettle();
        expect(find.text('确认预约座位'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(reader.reserveCalls, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test('seat rules decode limits, check durations, and match confirmed bookings', () {
    const rule = LibrarySeatRule(
      minMinutes: 30,
      maxMinutes: 240,
      earliestMinutes: 1440,
      latestMinutes: 0,
      cancelMinutes: 30,
      limit: 1 | 8 | 32,
    );
    expect(formatLibraryDuration(150), '2 小时 30 分钟');
    expect(formatLibraryDuration(1440), '1 天');
    expect(rule.limitLabels, ['需要审核', '增删改预约不发送短信', '预约结束必须操作才能离开']);
    expect(rule.durationViolation(540, 550), contains('至少 30 分钟'));
    expect(rule.durationViolation(540, 900), contains('最长 4 小时'));
    expect(rule.durationViolation(540, 660), isNull);

    final req = LibraryBookingRequest(
      areaId: '32',
      areaName: '二层北区',
      areaLabel: '二层 · 二层北区',
      seatId: '100',
      seatLabel: '2N001',
      date: DateTime(2026, 10, 10),
      startMinutes: 540,
      endMinutes: 660,
      rule: rule,
    );
    expect(req.beginTimestamp, '2026-10-10 09:00');
    expect(req.endTimestamp, '2026-10-10 11:00');
    expect(req.weekBegin, DateTime(2026, 10, 5));
    expect(req.weekEnd, DateTime(2026, 10, 11));
    expect(
      req.matchesBooking(
        const LibraryBooking(
          '5566',
          '二层北区',
          '2N001',
          '2026-10-10 09:00',
          '2026-10-10 11:00',
          2,
        ),
        bookingId: '5566',
      ),
      true,
    );
    expect(
      req.matchesBooking(
        const LibraryBooking(
          '9999',
          '二层北区',
          '2N001',
          '2026-10-10 09:00',
          '2026-10-10 11:00',
          128,
        ),
        bookingId: '5566',
      ),
      false,
    );
    expect(
      req.matchesBooking(
        const LibraryBooking(
          '5566',
          '二层北区',
          '2N001',
          '2026-10-10 09:00',
          '2026-10-10 11:00',
          2,
        ),
      ),
      true,
    );
  });

  test('duplicate submitReservation calls send only one write', () async {
    final writeCompleter = Completer<LibraryWriteResult>();
    final reader = FakeLibrarySeatReader()
      ..onSeats = ((_, _) async => [seat(id: '100', label: 'N001')])
      ..onReserve = ((_, _, _, _) => writeCompleter.future)
      ..onBookings = ((_, _, _) async => const LibraryBookingPage([
        LibraryBooking(
          '5566',
          '二层北区',
          'N001',
          '2026-10-10 08:30',
          '2026-10-10 22:00',
          2,
        ),
      ], false));
    final controller = LibrarySeatQueries(reader);
    addTearDown(controller.dispose);

    final req = LibraryBookingRequest(
      areaId: '32',
      areaName: '二层北区',
      areaLabel: '二层 · 二层北区',
      seatId: '100',
      seatLabel: 'N001',
      date: day,
      startMinutes: 510,
      endMinutes: 1320,
    );

    final first = controller.submitReservation(req);
    final second = await controller.submitReservation(req);
    expect(second, isNull);
    writeCompleter.complete(
      const LibraryWriteResult(LibraryWriteStatus.ok, bookingId: '5566'),
    );
    final outcome = await first;
    expect(reader.reserveCalls, 1);
    expect(outcome?.kind, LibrarySubmissionKind.confirmed);
  });

  testWidgets(
    'confirmation dialog verifies rules and confirms single submission into my bookings',
    variant: androidOnly,
    (tester) async {
      const rule = LibrarySeatRule(
        minMinutes: 30,
        maxMinutes: 900,
        earliestMinutes: 1440,
        latestMinutes: 0,
        cancelMinutes: 30,
        limit: 8,
      );
      var bookings = const <LibraryBooking>[];
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => [seat(id: '100', label: 'N001', rule: rule)])
        ..onReserve = ((_, _, _, _) async {
          bookings = const [
            LibraryBooking(
              '5566',
              '二层北区',
              'N001',
              '2026-10-10 08:30',
              '2026-10-10 22:00',
              2,
            ),
          ];
          return const LibraryWriteResult(
            LibraryWriteStatus.ok,
            bookingId: '5566',
            message: '预约成功',
          );
        })
        ..onBookings = ((_, _, page) async => LibraryBookingPage(
          bookings,
          false,
          page: page,
          totalCount: bookings.length,
        ));

      // Before 08:30 so default 08:30-22:00 is not in the past.
      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();

      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认预约'));
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();

      expect(find.text('确认预约座位'), findsOneWidget);
      expect(find.text('日期：2026-10-10'), findsOneWidget);
      expect(find.text('时段：08:30–22:00'), findsOneWidget);
      expect(find.textContaining('最长 15 小时'), findsWidgets);
      expect(find.textContaining('最多提前 1 天'), findsWidgets);

      // Cancel issues zero writes.
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(reader.reserveCalls, 0);

      // Confirm once issues one write and verifies in bookings.
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交预约'));
      await tester.pumpAndSettle();

      expect(reader.reserveCalls, 1);
      expect(find.text('预约已核对'), findsOneWidget);
      expect(find.textContaining('预约编号 5566'), findsOneWidget);

      await tester.tap(find.text('查看“我的预约”'));
      await tester.pumpAndSettle();
      expect(find.text('二层北区 · N001'), findsOneWidget);
      expect(find.text('待生效 · 预约编号 5566'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'dialog blocks invalid duration or past start time on today without sending writes',
    variant: androidOnly,
    (tester) async {
      const strictRule = LibrarySeatRule(minMinutes: 30, maxMinutes: 240);
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => [
          seat(id: '100', label: 'N001', rule: strictRule),
        ]);

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 9, 30)),
      );
      await tester.pumpAndSettle();

      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认预约'));
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();

      expect(find.text('开始时间早于当前时间，请先调整开始时间。'), findsOneWidget);
      final pastConfirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '确认提交预约'),
      );
      expect(pastConfirm.onPressed, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('明天'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认预约'));
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();

      expect(find.textContaining('超过学校允许的最长时长'), findsOneWidget);
      final overDurationConfirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '确认提交预约'),
      );
      expect(overDurationConfirm.onPressed, isNull);
      expect(reader.reserveCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'handles availability change, rejection, web-required, auth interruption without auto-retry, and uncertain查单',
    variant: androidOnly,
    (tester) async {
      var seatsResult = [seat(id: '100', label: 'N001')];
      LibraryWriteResult Function() reserveBehavior = () =>
          const LibraryWriteResult(LibraryWriteStatus.ok, bookingId: '1');
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => seatsResult)
        ..onReserve = ((_, _, _, _) async => reserveBehavior())
        ..onBookings = ((_, _, page) async => LibraryBookingPage(
          const [
            LibraryBooking(
              '8001',
              '二层北区',
              'N001',
              '2026-10-10 08:30',
              '2026-10-10 22:00',
              2,
            ),
          ],
          false,
          page: page,
          totalCount: 1,
        ));

      Future<void> openAndConfirmFirstSeat() async {
        await reveal(tester, find.text('N001'));
        await tester.tap(find.text('N001'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('确认预约'));
        await tester.tap(find.text('确认预约'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认提交预约'));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 8, 0),
          officialPageBuilder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {
                  seatsResult = [seat(id: '100', label: 'N001')];
                  Navigator.of(context).pop();
                },
                child: const Text('认证完成返回'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Availability changed during pre-check -> 0 writes.
      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认预约'));
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();
      seatsResult = [
        seat(id: '100', label: 'N001', reservations: [(at(10), at(12))]),
      ];
      await tester.tap(find.text('确认提交预约'));
      await tester.pumpAndSettle();
      expect(find.text('余位已变化，未提交预约'), findsOneWidget);
      expect(reader.reserveCalls, 0);

      // Reset seat back to available.
      seatsResult = [seat(id: '100', label: 'N001')];
      await tester.tap(find.text('刷新座位'));
      await tester.pumpAndSettle();

      // 2. School rejection -> 1 write, no retry.
      reserveBehavior = () => const LibraryWriteResult(
        LibraryWriteStatus.rejected,
        message: '预约人数已达上限',
      );
      await openAndConfirmFirstSeat();
      expect(reader.reserveCalls, 1);
      expect(find.text('学校平台未受理预约'), findsOneWidget);
      expect(find.textContaining('预约人数已达上限'), findsOneWidget);

      // 3. Web required -> 1 write call (preflight stopped in bridge), no retry.
      reserveBehavior = () => const LibraryWriteResult(
        LibraryWriteStatus.webRequired,
        reason: 'captcha',
      );
      await openAndConfirmFirstSeat();
      expect(reader.reserveCalls, 2);
      expect(find.text('需要前往学校网页完成确认'), findsOneWidget);
      expect(find.textContaining('验证码'), findsOneWidget);

      // 4. Auth interrupted -> clears personal data, re-login does NOT auto-retry POST!
      reserveBehavior = () =>
          const LibraryWriteResult(LibraryWriteStatus.login);
      await openAndConfirmFirstSeat();
      expect(reader.reserveCalls, 3);
      expect(find.text('登录状态已中断，已停止本次提交'), findsOneWidget);
      expect(find.text('需要登录学校账号'), findsNothing);
      expect(find.text('N001'), findsNothing);
      await tester.tap(find.text('打开学校页面登录').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('认证完成返回'));
      await tester.pumpAndSettle();
      expect(reader.reserveCalls, 3);
      expect(find.text('N001'), findsOneWidget);

      // 5. Timeout / uncertain -> no auto-retry, prompts user to verify in My Bookings.
      reserveBehavior = () =>
          const LibraryWriteResult(LibraryWriteStatus.uncertain);
      await openAndConfirmFirstSeat();
      expect(reader.reserveCalls, 4);
      expect(find.text('提交结果暂不明确，请先查单'), findsOneWidget);
      await tester.tap(find.text('去“我的预约”查单'));
      await tester.pumpAndSettle();
      expect(reader.reserveCalls, 4);
      expect(find.text('待生效 · 预约编号 8001'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('LibrarySeat.fromJson parses valid coordinates and rejects out-of-range pairs', () {
    Map<String, dynamic> payload(Object? x, Object? y) => {
      'id': '1',
      'label': '2N001',
      'open': true,
      'viewOnly': false,
      'hours': [
        ['08:30', '22:00'],
      ],
      'reservations': const <Object>[],
      'x': x,
      'y': y,
    };

    final valid = LibrarySeat.fromJson(payload(12.5, 64));
    expect(valid.hasCoordinates, true);
    expect(valid.x, 12.5);
    expect(valid.y, 64.0);

    for (final (x, y) in [
      (null, 20),
      (10, null),
      (-0.1, 20),
      (10, 100.1),
      (double.nan, 10),
    ]) {
      final invalid = LibrarySeat.fromJson(payload(x, y));
      expect(invalid.hasCoordinates, false);
      expect(invalid.x, isNull);
      expect(invalid.y, isNull);
    }
  });

  testWidgets(
    'embedded library page loads lazily only when active and stays offline in demo mode',
    (tester) async {
      var areaCalls = 0;
      var seatCalls = 0;
      final reader = FakeLibrarySeatReader()
        ..onAreas = () async {
          areaCalls++;
          return const [LibraryArea('32', '二层北区', '二层')];
        }
        ..onSeats = (_, _) async {
          seatCalls++;
          return [seat(id: '10', label: '2N010')];
        };

      Widget buildEmbedded({
        required bool active,
        required bool demo,
        VoidCallback? onExitDemo,
      }) => ProviderScope(
        overrides: [
          appearanceRepositoryProvider.overrideWithValue(
            MemoryAppearanceRepository(),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: LibrarySeatQueryPage(
              reader: reader,
              embedded: true,
              active: active,
              demo: demo,
              onExitDemo: onExitDemo,
              now: () => DateTime(2026, 10, 10, 9),
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildEmbedded(active: false, demo: false));
      await tester.pumpAndSettle();
      expect(areaCalls, 0);
      expect(seatCalls, 0);

      await tester.pumpWidget(buildEmbedded(active: true, demo: true));
      await tester.pumpAndSettle();
      expect(areaCalls, 0);
      expect(seatCalls, 0);
      expect(find.text('合成示例模式'), findsOneWidget);

      var exited = false;
      await tester.pumpWidget(
        buildEmbedded(
          active: true,
          demo: true,
          onExitDemo: () => exited = true,
        ),
      );
      await tester.tap(find.text('退出示例'));
      await tester.pumpAndSettle();
      expect(exited, true);

      await tester.pumpWidget(buildEmbedded(active: true, demo: false));
      await tester.pumpAndSettle();
      expect(areaCalls, 1);
      expect(seatCalls, 1);
      expect(find.text('2N010'), findsOneWidget);

      await tester.pumpWidget(buildEmbedded(active: false, demo: false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(buildEmbedded(active: true, demo: false));
      await tester.pumpAndSettle();
      expect(areaCalls, 1);
      expect(seatCalls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'AppShell four-tab dock switches to 图书馆 lazily and Settings entry jumps to 图书馆 tab',
    variant: androidOnly,
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var seatCalls = 0;
      final reader = FakeLibrarySeatReader()
        ..onSeats = (_, _) async {
          seatCalls++;
          return [seat(id: '10', label: '2N018')];
        };

      await tester.pumpWidget(
        app(MemoryRepository(const ScheduleData()), libraryReader: reader),
      );
      await tester.pumpAndSettle();

      expect(GlassNavigation.labels, ['今日', '课表', '图书馆', '设置']);
      expect(seatCalls, 0);

      // Going straight from 今日 (0) to 设置 (3) must not wake the library reader.
      await tester.tap(find.byKey(const ValueKey('tab-3')));
      await tester.pumpAndSettle();
      expect(seatCalls, 0);
      expect(find.text('图书馆座位预约'), findsOneWidget);
      expect(find.text('也可从底部“图书馆”栏直接进入'), findsOneWidget);

      // Tapping Settings -> 图书馆座位预约 jumps to the 图书馆 tab and loads seats.
      await tester.scrollUntilVisible(
        find.text('图书馆座位预约'),
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('settings-page')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('图书馆座位预约'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Semantics>(find.byKey(const ValueKey('tab-2')))
            .properties
            .selected,
        isTrue,
      );
      expect(seatCalls, 1);
      expect(find.text('2N018'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-refresh-button')));
      await tester.pumpAndSettle();
      expect(seatCalls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
