import 'dart:async';
import 'dart:io';

import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/library_seat_queries.dart';
import 'package:campus_schedule/config/network_policy.dart';
import 'package:campus_schedule/domain/library_seats.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/library_seat_reader.dart';
import 'package:campus_schedule/platform/school_adapter.dart';
import 'package:campus_schedule/ui/acrylic_surface.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/campus_login_page.dart';
import 'package:campus_schedule/ui/course_surface.dart';
import 'package:campus_schedule/ui/glass_navigation.dart';
import 'package:campus_schedule/ui/library_floor_overview.dart';
import 'package:campus_schedule/ui/library_seat_bookings.dart';
import 'package:campus_schedule/ui/library_seat_map.dart';
import 'package:campus_schedule/ui/library_seat_query_page.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'schedule_test.dart' show MemoryRepository;
import 'support/campus_login_webview.dart';
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
  double? x,
  double? y,
}) => LibrarySeat(
  id: id,
  label: label,
  open: open,
  viewOnly: viewOnly,
  hours: hours,
  reservations: reservations,
  rule: rule,
  x: x,
  y: y,
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
  Future<bool> Function()? onReuseSession;
  int reuseCalls = 0;
  int resetCount = 0;

  @override
  Future<bool> tryReuseCampusSession() {
    reuseCalls++;
    if (onReuseSession != null) return onReuseSession!();
    return Future.value(false);
  }

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
  Future<bool> Function(BuildContext context, String reason)? loginOpener,
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
      loginOpener: loginOpener,
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

Future<void> enterLibraryArea(
  WidgetTester tester, {
  String floor = '二层',
  String zoneKey = 'library-zone-north',
}) async {
  await reveal(tester, find.byKey(ValueKey('library-floor-card-$floor')));
  await tester.tap(find.byKey(ValueKey('library-floor-card-$floor')));
  await tester.pumpAndSettle();
  await reveal(tester, find.byKey(ValueKey(zoneKey)));
  await tester.tap(find.byKey(ValueKey(zoneKey)));
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
      await enterLibraryArea(tester);
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
      await enterLibraryArea(tester);
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
      await enterLibraryArea(tester);

      expect(find.text('共 5 席'), findsOneWidget);
      expect(find.text('空闲 1'), findsOneWidget);
      expect(find.text('半空闲 1'), findsOneWidget);
      expect(find.text('使用中 1'), findsOneWidget);
      expect(find.text('不可用 2'), findsOneWidget);
      expect(find.text('已约 10:00–11:00'), findsOneWidget);

      // Tapping partial seat opens the time-slot inspection sheet instead of silent no-op.
      await reveal(tester, find.text('N002'));
      await tester.tap(find.text('N002'));
      await tester.pumpAndSettle();
      expect(find.text('查看可约空档'), findsOneWidget);
      expect(find.text('N002 · 半空闲'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭时段选择'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-selected-capsule')), findsNothing);

      // Tapping available seat selects it and displays bottom floating capsule.
      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-selected-capsule')),
        findsOneWidget,
      );
      expect(find.text('二层北区 · N001'), findsOneWidget);
      expect(find.textContaining('2026-10-10 08:30–22:00'), findsOneWidget);

      // Tapping clear deselects it.
      await tester.tap(find.byTooltip('清除选择'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-selected-capsule')), findsNothing);

      // Filtering only available hides non-available items.
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
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-floor-card-二层')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-zone-north')));
      await tester.pump();
      requests[0].$2.complete([seat(id: '1', label: '今日座位')]);
      await tester.pumpAndSettle();

      await tester.tap(find.text('今日座位'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-selected-capsule')),
        findsOneWidget,
      );

      // Switch to tomorrow while a manual refresh on today could still be pending.
      await tester.tap(find.byKey(const ValueKey('library-refresh-button')));
      await tester.pump();
      await tester.tap(find.text('明天'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('library-selected-capsule')).hitTestable(),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.byKey(const ValueKey('library-selected-capsule')),
        findsNothing,
      );
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
          loginOpener: (context, _) async =>
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () {
                          phase = 1;
                          Navigator.of(context).pop(true);
                        },
                        child: const Text('模拟登录完成返回'),
                      ),
                    ),
                  ),
                ),
              ) ??
              false,
        ),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      // Step 1: needsLogin prompts user to authenticate.
      expect(find.text('需要登录学校账号'), findsOneWidget);
      await tester.tap(find.text('登录校园账号').last);
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
        await enterLibraryArea(tester);

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
      await enterLibraryArea(tester);

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
      await enterLibraryArea(tester);

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
          loginOpener: (context, _) async =>
              await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () {
                          seatsResult = [seat(id: '100', label: 'N001')];
                          Navigator.of(context).pop(true);
                        },
                        child: const Text('认证完成返回'),
                      ),
                    ),
                  ),
                ),
              ) ??
              false,
        ),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

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
      await tester.tap(find.byKey(const ValueKey('library-refresh-button')));
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
      await tester.tap(find.text('登录校园账号').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('认证完成返回'));
      await tester.pumpAndSettle();
      expect(find.text('校园账号登录成功，正在核对预约记录'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(reader.reserveCalls, 3);
      expect(find.text('待生效 · 预约编号 8001'), findsOneWidget);
      await tester.tap(find.text('选座'));
      await tester.pumpAndSettle();
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
      expect(seatCalls, 0);
      expect(find.byKey(const ValueKey('library-floor-card-二层')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-floor-card-二层')));
      await tester.pumpAndSettle();
      expect(seatCalls, 0);

      await tester.tap(find.byKey(const ValueKey('library-zone-north')));
      await tester.pumpAndSettle();
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
      expect(seatCalls, 0);
      expect(find.byKey(const ValueKey('library-floor-card-二层')), findsOneWidget);

      await enterLibraryArea(tester);
      expect(seatCalls, 1);
      expect(find.text('2N018'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-refresh-button')));
      await tester.pumpAndSettle();
      expect(seatCalls, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'floor map defaults when coordinates exist, zooms safely, and toggles to searchable segmented grid',
    variant: androidOnly,
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final items = [
        for (var i = 1; i <= 120; i++)
          seat(
            id: '$i',
            label: '2N${i.toString().padLeft(3, '0')}',
            x: 10 + (i % 12) * 7.0,
            y: 12 + (i ~/ 12) * 8.0,
          ),
      ];
      final reader = FakeLibrarySeatReader()..onSeats = (_, _) async => items;

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      // Floor map is active by default when coordinates are present.
      expect(
        find.byKey(const ValueKey('library-floor-map-viewport')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('library-seat-search')), findsNothing);

      // Zoom in and reset controls work smoothly.
      await tester.tap(find.byKey(const ValueKey('library-map-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.textContaining('缩放'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library-map-zoom-fit')));
      await tester.pumpAndSettle();
      expect(find.text('平面分布 · 双指缩放或点选座位'), findsOneWidget);

      // Tap a seat in map -> floating selected capsule appears.
      await tester.tap(find.text('2N001'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-selected-capsule')),
        findsOneWidget,
      );
      expect(find.text('二层北区 · 2N001'), findsOneWidget);

      // Toggle to compact grid, jump segment, and search for 2N115.
      await tester.tap(find.byKey(const ValueKey('library-view-grid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-seat-search')), findsOneWidget);
      expect(find.text('81–120'), findsOneWidget);

      await tester.tap(find.text('81–120'));
      await tester.pumpAndSettle();
      expect(find.text('2N001'), findsNothing);
      expect(find.text('2N081'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('library-seat-search')),
        '2N115',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(LibrarySeatGridRow),
          matching: find.text('2N115'),
        ),
        findsOneWidget,
      );
      expect(find.text('2N081'), findsNothing);

      // Searching an absent code shows empty guidance and clear action.
      await tester.enterText(
        find.byKey(const ValueKey('library-seat-search')),
        'NO_SUCH_SEAT',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('未找到包含'), findsOneWidget);
      await tester.tap(find.text('清空搜索'));
      await tester.pumpAndSettle();
      expect(find.text('2N001'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing coordinates fall back to grid and area sheet filters by floor',
    variant: androidOnly,
    (tester) async {
      String? requestedArea;
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async => const [
          LibraryArea('32', '二层北区', '二层'),
          LibraryArea('33', '三层南区', '三层'),
          LibraryArea('41', '四层阅览室', '四层'),
        ])
        ..onSeats = ((area, _) async {
          requestedArea = area;
          return [
            seat(id: '${area}01', label: area == '33' ? '3S001' : '2N001'),
          ];
        });

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      // Without coordinates, falls back to grid and disables map switch.
      expect(
        find.byKey(const ValueKey('library-floor-map-viewport')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('library-seat-search')), findsOneWidget);
      final mapButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('library-view-map')),
      );
      expect(mapButton.onPressed, isNull);

      // Open area drawer and filter to 三层.
      await tester.tap(find.byKey(const ValueKey('library-area-picker')));
      await tester.pumpAndSettle();
      expect(find.text('选择座位区域'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '三层'));
      await tester.pumpAndSettle();
      expect(find.text('四层阅览室'), findsNothing);
      await tester.tap(find.text('三层南区'));
      await tester.pumpAndSettle();

      expect(requestedArea, '33');
      expect(find.text('3S001'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'time slot sheet inspects partial seat gaps, validates duration, and applies clean gap selection',
    variant: androidOnly,
    (tester) async {
      const rule = LibrarySeatRule(minMinutes: 30, maxMinutes: 240);
      final reader = FakeLibrarySeatReader()
        ..onSeats = (_, _) async => [
          seat(
            id: '24',
            label: '2N024',
            reservations: [(at(10), at(12))],
            rule: rule,
          ),
        ];

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      // Open time slot sheet from partial seat 2N024.
      await tester.tap(find.text('2N024'));
      await tester.pumpAndSettle();

      expect(find.text('查看可约空档'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library-timeline-track')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(QuietSheet),
          matching: find.text('已约 10:00–12:00'),
        ),
        findsOneWidget,
      );
      expect(find.text('可用空档'), findsOneWidget);

      // Free gap 08:30–10:00 was auto-selected and fits 240m limit cleanly.
      expect(find.text('时段可用 · 共 1 小时 30 分钟'), findsOneWidget);
      expect(find.text('12:00–22:00'), findsOneWidget);

      // Picking 12:00–22:00 (10 hours) violates 4-hour max rule and disables apply CTA.
      await tester.tap(find.text('12:00–22:00'));
      await tester.pumpAndSettle();
      expect(find.textContaining('超过学校允许的最长时长'), findsOneWidget);
      final blockedButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '采用此时段并选中 2N024'),
      );
      expect(blockedButton.onPressed, isNull);

      // Switching back to 08:30–10:00 makes it valid and selects 2N024 cleanly.
      await tester.tap(find.text('08:30–10:00').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('采用此时段并选中 2N024'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('library-selected-capsule')),
        findsOneWidget,
      );
      expect(
        find.textContaining('2026-10-10 08:30–10:00 · 1 小时 30 分钟'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final variant in [
    (
      name: 'light-narrow-1.5x-floor',
      dark: false,
      scale: 1.5,
      highContrast: false,
      disableAnimations: false,
      glass: true,
    ),
    (
      name: 'dark-narrow-2.0x-hc-noglass',
      dark: true,
      scale: 2.0,
      highContrast: true,
      disableAnimations: true,
      glass: false,
    ),
  ]) {
    testWidgets(
      'Stage 7B responsive and accessibility check: ${variant.name}',
      variant: androidOnly,
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final reader = FakeLibrarySeatReader()
          ..onSeats = (_, _) async => [
            seat(id: '1', label: '2N001', x: 15, y: 20),
            seat(
              id: '2',
              label: '2N002',
              x: 55,
              y: 45,
              reservations: [(at(10), at(11))],
            ),
          ];

        await tester.pumpWidget(
          wrapLibraryPage(
            reader,
            now: () => DateTime(2026, 10, 10, 8, 0),
            dark: variant.dark,
            scale: variant.scale,
            highContrast: variant.highContrast,
            disableAnimations: variant.disableAnimations,
            settings: AppearanceSettings(glass: variant.glass),
          ),
        );
        await tester.pumpAndSettle();
        await enterLibraryArea(tester);

        await reveal(tester, find.text('2N001'));
        await tester.tap(find.text('2N001'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-selected-capsule')),
          findsOneWidget,
        );

        await reveal(tester, find.byKey(const ValueKey('library-view-grid')));
        await tester.tap(find.byKey(const ValueKey('library-view-grid')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-seat-search')), findsOneWidget);

        await reveal(tester, find.byKey(const ValueKey('library-time-picker')));
        await tester.tap(find.byKey(const ValueKey('library-time-picker')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-timeline-track')),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('关闭时段选择'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'dense mixed-spacing floor map avoids seat overlap and keeps zoom controls above viewport',
    variant: androidOnly,
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final items = <LibrarySeat>[
        // Main 4x6 block with standard spacing.
        for (var r = 0; r < 4; r++)
          for (var c = 0; c < 6; c++)
            seat(
              id: 'm_${r}_$c',
              label: '3S${(100 + r * 6 + c).toString().padLeft(3, '0')}',
              x: 20 + c * 5.0,
              y: 25 + r * 7.0,
            ),
        // Dense bottom strip (~2.3% horizontal spacing) similar to 三层南区 edge rows.
        for (var c = 0; c < 12; c++)
          seat(
            id: 'd_$c',
            label: '3S${(49 + c).toString().padLeft(3, '0')}',
            x: 55 + c * 2.3,
            y: 88,
          ),
      ];
      final reader = FakeLibrarySeatReader()..onSeats = (_, _) async => items;

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      final zoomRect = tester.getRect(
        find.byKey(const ValueKey('library-map-zoom-in')),
      );
      final viewportRect = tester.getRect(
        find.byKey(const ValueKey('library-floor-map-viewport')),
      );
      expect(zoomRect.overlaps(viewportRect), false);
      expect(zoomRect.bottom <= viewportRect.top, true);

      final seatMaterials = find
          .descendant(
            of: find.byKey(const ValueKey('library-floor-map-viewer')),
            matching: find.byType(Material),
          )
          .evaluate()
          .toList();
      expect(seatMaterials.length, items.length);

      final rects = <Rect>[
        for (final element in seatMaterials)
          tester.getRect(find.byElementPredicate((e) => e == element)),
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            false,
            reason: 'seat rects $i (${rects[i]}) and $j (${rects[j]}) overlapped',
          );
        }
      }

      // Zooming in twice reveals labels on the dense bottom row.
      await tester.tap(find.byKey(const ValueKey('library-map-zoom-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-map-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.textContaining('225%'), findsOneWidget);
      expect(find.text('3S049'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('focus classification and countdown hints respect active statuses and 7-day window', () {
    final now = DateTime(2026, 10, 10, 8, 5);
    const upcoming = LibraryBooking(
      '9001',
      '二层北区',
      '2N018',
      '2026-10-10 08:30',
      '2026-10-10 12:00',
      2 | 1024,
    );
    const inProgress = LibraryBooking(
      '9002',
      '二层北区',
      '2N019',
      '2026-10-10 07:30',
      '2026-10-10 10:05',
      4 | 64,
    );
    const farFuture = LibraryBooking(
      '9003',
      '二层北区',
      '2N020',
      '2026-10-25 09:00',
      '2026-10-25 12:00',
      2,
    );
    const ended = LibraryBooking(
      '9004',
      '三层南区',
      '3S001',
      '2026-10-09 14:00',
      '2026-10-09 18:00',
      128 | 4096,
    );
    const violated = LibraryBooking(
      '9005',
      '三层南区',
      '3S002',
      '2026-10-08 09:00',
      '2026-10-08 11:00',
      16,
    );

    expect(isFocusLibraryBooking(upcoming, now), true);
    expect(isFocusLibraryBooking(inProgress, now), true);
    expect(isFocusLibraryBooking(ended, now), false);
    expect(isFocusLibraryBooking(violated, now), false);

    expect(libraryBookingTimeHint(upcoming, now), '25 分钟后开始');
    expect(libraryBookingTimeHint(inProgress, now), '距结束还剩 2 小时');
    expect(libraryBookingTimeHint(farFuture, now), isNull);
    expect(libraryBookingTimeHint(ended, now), isNull);
  });

  testWidgets(
    'Stage 7C confirmation QuietSheets show rules, release impact, and send zero writes when closed',
    variant: androidOnly,
    (tester) async {
      const rule = LibrarySeatRule(
        minMinutes: 30,
        maxMinutes: 900,
        cancelMinutes: 30,
        limit: 8,
      );
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => [seat(id: '100', label: '2N018', rule: rule)])
        ..onBookings = ((_, _, page) async => LibraryBookingPage(
          [cancellationFixture],
          false,
          page: page,
          totalCount: 1,
        ));

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      await reveal(tester, find.text('2N018'));
      await tester.tap(find.text('2N018'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认预约'));
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('library-confirm-reservation-sheet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(QuietSheet),
          matching: find.text('确认预约座位'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('签到提示：预约生效后 30 分钟 内未签到'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭预约确认'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('library-confirm-reservation-sheet')),
        findsNothing,
      );
      expect(reader.reserveCalls, 0);

      await tester.tap(find.text('我的预约'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('取消预约'));
      await tester.tap(find.text('取消预约'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('library-confirm-cancel-sheet')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(QuietSheet),
          matching: find.text('确认取消预约'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('学校接受取消后，这笔预约将释放。取消资格由学校平台确认。'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('关闭取消确认'));
      await tester.pumpAndSettle();
      expect(reader.cancelCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Stage 7C my bookings layers focus AcrylicSurface tickets above history and supports quick ranges and empty CTA',
    variant: androidOnly,
    (tester) async {
      final queriedRanges = <(DateTime, DateTime)>[];
      var emptyMode = false;
      final reader = FakeLibrarySeatReader()
        ..onSeats = ((_, _) async => [seat(id: '100', label: '2N018')])
        ..onBookings = (begin, end, page) async {
          queriedRanges.add((begin, end));
          if (emptyMode) {
            return LibraryBookingPage(const [], false, page: page, totalCount: 0);
          }
          return const LibraryBookingPage(
            [
              LibraryBooking(
                '7002',
                '三层南区',
                'S008',
                '2026-10-08 14:00',
                '2026-10-08 18:00',
                128,
              ),
              LibraryBooking(
                '7001',
                '二层北区',
                '2N018',
                '2026-10-10 08:30',
                '2026-10-10 12:00',
                2 | 1024,
              ),
            ],
            false,
            page: 1,
            totalCount: 2,
          );
        };

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 5)),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);

      await tester.tap(find.text('我的预约'));
      await tester.pumpAndSettle();

      final focusFinder = find.byKey(const ValueKey('library-booking-focus-7001'));
      final historyFinder = find.byKey(const ValueKey('library-booking-history-7002'));
      expect(focusFinder, findsOneWidget);
      expect(
        find.descendant(of: focusFinder, matching: find.byType(AcrylicSurface)),
        findsOneWidget,
      );
      expect(find.text('25 分钟后开始'), findsOneWidget);
      expect(find.text('08:30–12:00'), findsOneWidget);
      expect(find.text('2026-10-10 · 今天'), findsOneWidget);
      expect(find.text('近期记录'), findsOneWidget);

      await reveal(tester, historyFinder);
      expect(historyFinder, findsOneWidget);
      expect(
        tester.getTopLeft(focusFinder).dy < tester.getTopLeft(historyFinder).dy,
        true,
      );

      // Quick range 近 30 天 triggers reload from today - 29 to today + 1 and transitions empty CTA back to 选座.
      emptyMode = true;
      await reveal(tester, find.text('近 30 天'));
      await tester.tap(find.text('近 30 天'));
      await tester.pumpAndSettle();
      expect(queriedRanges.last.$1, DateTime(2026, 9, 11));
      expect(queriedRanges.last.$2, DateTime(2026, 10, 11));
      expect(find.text('暂无座位预约'), findsOneWidget);

      await tester.tap(find.text('去选座'));
      await tester.pumpAndSettle();
      expect(find.text('2N018'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final variant in [
    (
      name: 'light-narrow-1.5x-stage7c',
      dark: false,
      scale: 1.5,
      highContrast: false,
      disableAnimations: false,
      glass: true,
    ),
    (
      name: 'dark-narrow-2.0x-hc-noglass-stage7c',
      dark: true,
      scale: 2.0,
      highContrast: true,
      disableAnimations: true,
      glass: false,
    ),
  ]) {
    testWidgets(
      'Stage 7C responsive and accessibility check: ${variant.name}',
      variant: androidOnly,
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const rule = LibrarySeatRule(
          minMinutes: 30,
          maxMinutes: 900,
          cancelMinutes: 30,
        );
        final reader = FakeLibrarySeatReader()
          ..onSeats = ((_, _) async => [seat(id: '1', label: '2N018', rule: rule)])
          ..onBookings = ((_, _, page) async => const LibraryBookingPage(
            [
              LibraryBooking(
                '7010',
                '二层北区',
                '2N018',
                '2099-10-10 08:30',
                '2099-10-10 12:00',
                2 | 1024,
              ),
              LibraryBooking(
                '7011',
                '三层南区',
                '3S001',
                '2026-10-08 14:00',
                '2026-10-08 18:00',
                128,
              ),
            ],
            false,
            page: 1,
            totalCount: 2,
          ));

        await tester.pumpWidget(
          wrapLibraryPage(
            reader,
            now: () => DateTime(2026, 10, 10, 8, 0),
            dark: variant.dark,
            scale: variant.scale,
            highContrast: variant.highContrast,
            disableAnimations: variant.disableAnimations,
            settings: AppearanceSettings(glass: variant.glass),
          ),
        );
        await tester.pumpAndSettle();
        await enterLibraryArea(tester);

        await reveal(tester, find.text('2N018'));
        await tester.tap(find.text('2N018'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('确认预约'));
        await tester.tap(find.text('确认预约'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-confirm-reservation-sheet')),
          findsOneWidget,
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, 600),
        );
        await tester.pumpAndSettle();
        await reveal(tester, find.text('我的预约'));
        await tester.tap(find.text('我的预约'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-booking-focus-7010')),
          findsOneWidget,
        );
        await reveal(tester, find.text('取消预约'));
        await tester.tap(find.text('取消预约'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('library-confirm-cancel-sheet')),
          findsOneWidget,
        );
        await tester.tap(find.text('保留预约'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'Stage 8A floor grouping, dedicated 2F vs 3F-5F parity, and zero schematic overlap',
    () {
      const sampleAreas = [
        LibraryArea('32', '二层北区', '图书馆二层'),
        LibraryArea('33', '三层南区', '图书馆三层'),
        LibraryArea('34', '三层西A区', '图书馆三层'),
        LibraryArea('35', '三层西B区', '图书馆三层'),
        LibraryArea('36', '三层西C区', '图书馆三层'),
        LibraryArea('37', '三层北区', '图书馆三层'),
        LibraryArea('41', '四层北区', '图书馆四层'),
        LibraryArea('42', '四层阅览室', '图书馆四层'),
      ];
      final groups = groupLibraryFloors(sampleAreas);
      expect(groups.map((g) => g.floor).toList(), [
        '图书馆二层',
        '图书馆三层',
        '图书馆四层',
      ]);
      expect(groups[0].kind, LibraryFloorKind.floor2);
      expect(groups[1].kind, LibraryFloorKind.standard3to5);
      expect(groups[2].kind, LibraryFloorKind.standard3to5);

      // Dedicated 2F north wing shares exact northeast rect with 3F-5F.
      expect(
        libraryZoneRect(LibraryZoneSlot.north, kind: LibraryFloorKind.floor2),
        libraryZoneRect(
          LibraryZoneSlot.north,
          kind: LibraryFloorKind.standard3to5,
        ),
      );
      expect(
        libraryZoneRect(LibraryZoneSlot.westA, kind: LibraryFloorKind.floor2),
        isNull,
      );
      expect(
        libraryZoneRect(LibraryZoneSlot.westC, kind: LibraryFloorKind.floor2),
        isNull,
      );
      expect(
        libraryZoneRect(LibraryZoneSlot.south, kind: LibraryFloorKind.floor2),
        isNull,
      );

      final resolved2F = resolveFloorZones(const LibraryFloorGroup(
        floor: '图书馆二层',
        areas: [
          LibraryArea('32', '二层北区', '图书馆二层'),
          LibraryArea('39', '二层南区', '图书馆二层'),
        ],
        kind: LibraryFloorKind.floor2,
      ));
      expect(resolved2F.mapped.keys.toList(), [LibraryZoneSlot.north]);
      expect(resolved2F.unmapped.single.id, '39');

      final resolved4F = resolveFloorZones(groups[2]);
      expect(resolved4F.mapped[LibraryZoneSlot.north]?.id, '41');
      expect(resolved4F.unmapped.single.id, '42');

      const nonOverlappingRects = <Rect>[
        libraryWestARect,
        libraryWestBRect,
        libraryCourtyardRect,
        libraryNorthNonSeatStrip,
        libraryWestCEastArmRect,
        libraryWestCSouthArmRect,
        libraryNorthZoneRect,
        librarySouthZoneRect,
        libraryCompassRect,
      ];
      for (var i = 0; i < nonOverlappingRects.length; i++) {
        for (var j = i + 1; j < nonOverlappingRects.length; j++) {
          expect(
            nonOverlappingRects[i].overlaps(nonOverlappingRects[j]),
            false,
            reason:
                'schematic rects $i (${nonOverlappingRects[i]}) and $j (${nonOverlappingRects[j]}) overlapped',
          );
        }
      }
    },
  );

  testWidgets(
    'Stage 8A 3-level spatial flow renders dedicated 2F map, L-shaped 西C dual-arm linkage, and lazy seat fetch',
    variant: androidOnly,
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final seatRequests = <String>[];
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async => const [
          LibraryArea('21', '二层北区', '图书馆二层'),
          LibraryArea('31', '三层北区', '图书馆三层'),
          LibraryArea('32', '三层南区', '图书馆三层'),
          LibraryArea('33', '三层西A区', '图书馆三层'),
          LibraryArea('34', '三层西B区', '图书馆三层'),
          LibraryArea('35', '三层西C区', '图书馆三层'),
          LibraryArea('41', '四层北区', '图书馆四层'),
          LibraryArea('42', '四层阅览室', '图书馆四层'),
        ])
        ..onSeats = (area, _) async {
          seatRequests.add(area);
          return [
            seat(
              id: '${area}01',
              label: area == '35' ? '3WC01' : '${area}S01',
              x: 25,
              y: 40,
            ),
          ];
        };

      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();

      // Level 1 shows floors only; zero seat requests triggered yet.
      expect(seatRequests, isEmpty);
      expect(find.byKey(const ValueKey('library-floor-card-图书馆二层')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-floor-card-图书馆三层')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-floor-card-图书馆四层')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-floor-schematic-canvas')), findsNothing);

      // 2F uses dedicated schematic: 北区 + 中庭 + ↑ 北 only, no 3F-5F zone labels.
      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆二层')));
      await tester.pumpAndSettle();
      expect(seatRequests, isEmpty);
      expect(find.byKey(const ValueKey('library-floor-schematic-canvas')), findsOneWidget);
      expect(find.text('北区'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('library-floor-schematic-canvas')),
          matching: find.text('中庭'),
        ),
        findsOneWidget,
      );
      expect(find.text('↑ 北'), findsOneWidget);
      expect(find.text('南区'), findsNothing);
      expect(find.text('西C'), findsNothing);

      // Breadcrumb returns to Level 1, then enter 3F 5-zone schematic.
      await tester.tap(find.byKey(const ValueKey('library-breadcrumb-floors')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆三层')));
      await tester.pumpAndSettle();
      expect(seatRequests, isEmpty);
      expect(find.byKey(const ValueKey('library-zone-north')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-zone-south')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-zone-westA')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-zone-westB')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-zone-westC-east')), findsOneWidget);
      expect(find.byKey(const ValueKey('library-zone-westC-south')), findsOneWidget);

      // Tapping east arm of L-shaped 西C loads 三层西C区 and shows locator pill.
      await tester.tap(find.byKey(const ValueKey('library-zone-westC-east')));
      await tester.pumpAndSettle();
      expect(seatRequests, ['35']);
      expect(find.text('3WC01'), findsOneWidget);
      expect(find.text('中庭东南翼 · ↑ 北'), findsOneWidget);

      // Tapping locator pill returns to 3F schematic; tapping south arm of 西C also opens 西C.
      await tester.tap(find.byKey(const ValueKey('library-level3-locator')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-zone-westC-south')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('library-zone-westC-south')));
      await tester.pumpAndSettle();
      expect(seatRequests, ['35', '35']);
      expect(find.text('3WC01'), findsOneWidget);

      // 4F shows extra unmapped zone button cleanly beneath schematic.
      await tester.tap(find.byKey(const ValueKey('library-breadcrumb-floors')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('library-floor-card-图书馆四层')));
      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆四层')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('library-zone-extra-42')));
      expect(find.text('四层阅览室'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Stage 8A spatial transitions block outgoing hit/focus, survive rapid interruption, step via system back, and honor reduced motion',
    variant: androidOnly,
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FakeLibrarySeatReader buildReader() => FakeLibrarySeatReader()
        ..onAreas = (() async => const [
          LibraryArea('21', '二层北区', '图书馆二层'),
          LibraryArea('31', '三层南区', '图书馆三层'),
          LibraryArea('32', '三层北区', '图书馆三层'),
        ])
        ..onSeats = (_, _) async => [
          seat(id: '10', label: '3S001', x: 20, y: 30),
        ];

      final reader = buildReader();
      await tester.pumpWidget(
        wrapLibraryPage(reader, now: () => DateTime(2026, 10, 10, 8, 0)),
      );
      await tester.pumpAndSettle();

      // 1. Mid-transition Level 1 -> Level 2 keeps outgoing blocked from hit/focus/semantics.
      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆三层')));
      await tester.pump(const Duration(milliseconds: 90));
      final spatial = find.byType(LibrarySpatialLevelTransition);
      final outgoingFocusBlocker = find.descendant(
        of: spatial,
        matching: find.byWidgetPredicate((w) => w is ExcludeFocus && w.excluding),
      );
      expect(outgoingFocusBlocker, findsOneWidget);
      expect(
        find.descendant(
          of: outgoingFocusBlocker,
          matching: find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: outgoingFocusBlocker,
          matching: find.byWidgetPredicate((w) => w is ExcludeSemantics && w.excluding),
        ),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.descendant(
          of: outgoingFocusBlocker,
          matching: find.byType(LibraryFloorListView),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(outgoingFocusBlocker, findsNothing);

      // 2. Rapid interruption: step back & switch floor mid-flight cleanly.
      await tester.tap(find.byKey(const ValueKey('library-breadcrumb-floors')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆三层')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-zone-south')), findsOneWidget);

      // 3. Mid-transition Level 2 -> Level 3 (zoneDrillIn) and Level 3 map <-> grid.
      await tester.tap(find.byKey(const ValueKey('library-zone-south')));
      await tester.pump(const Duration(milliseconds: 90));
      expect(outgoingFocusBlocker, findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-floor-map-viewport')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-view-grid')));
      await tester.pump(const Duration(milliseconds: 90));
      final modeSwitcher = find.byType(LibrarySeatViewModeTransition);
      final modeOutgoingFocusBlocker = find.descendant(
        of: modeSwitcher,
        matching: find.byWidgetPredicate((w) => w is ExcludeFocus && w.excluding),
      );
      expect(modeOutgoingFocusBlocker, findsOneWidget);
      expect(
        find.descendant(
          of: modeOutgoingFocusBlocker,
          matching: find.byType(LibrarySeatFloorMap),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(modeOutgoingFocusBlocker, findsNothing);

      // 4. PopScope system back steps cleanly Level 3 -> Level 2 -> Level 1.
      final navigator = Navigator.of(
        tester.element(find.byType(LibrarySeatQueryPage)),
      );
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-floor-schematic-canvas')), findsOneWidget);

      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-floor-card-图书馆二层')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      // 5. disableAnimations: true performs instant switch without lingering outgoing layers.
      await tester.pumpWidget(
        wrapLibraryPage(
          buildReader(),
          pageKey: UniqueKey(),
          now: () => DateTime(2026, 10, 10, 8, 0),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆三层')));
      await tester.pump();
      expect(find.byKey(const ValueKey('library-zone-south')), findsOneWidget);
      expect(outgoingFocusBlocker, findsNothing);

      await tester.tap(find.byKey(const ValueKey('library-zone-south')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('library-floor-map-viewport')), findsOneWidget);
      expect(outgoingFocusBlocker, findsNothing);

      await tester.tap(find.byKey(const ValueKey('library-view-grid')));
      await tester.pump();
      expect(find.byKey(const ValueKey('library-seat-search')), findsOneWidget);
      expect(modeOutgoingFocusBlocker, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final variant in [
    (
      name: 'light-narrow-1.5x-stage8a',
      dark: false,
      scale: 1.5,
      highContrast: false,
      disableAnimations: false,
      glass: true,
    ),
    (
      name: 'dark-narrow-2.0x-hc-noglass-stage8a',
      dark: true,
      scale: 2.0,
      highContrast: true,
      disableAnimations: true,
      glass: false,
    ),
  ]) {
    testWidgets(
      'Stage 8A responsive and accessibility check: ${variant.name}',
      variant: androidOnly,
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final reader = FakeLibrarySeatReader()
          ..onAreas = (() async => const [
            LibraryArea('21', '二层北区', '图书馆二层'),
            LibraryArea('31', '三层北区', '图书馆三层'),
            LibraryArea('32', '三层南区', '图书馆三层'),
            LibraryArea('33', '三层西A区', '图书馆三层'),
            LibraryArea('34', '三层西B区', '图书馆三层'),
            LibraryArea('35', '三层西C区', '图书馆三层'),
          ])
          ..onSeats = (_, _) async => [
            seat(id: '1', label: '3N001', x: 18, y: 24),
            seat(id: '2', label: '3N002', x: 48, y: 24),
          ];

        await tester.pumpWidget(
          wrapLibraryPage(
            reader,
            now: () => DateTime(2026, 10, 10, 8, 0),
            dark: variant.dark,
            scale: variant.scale,
            highContrast: variant.highContrast,
            disableAnimations: variant.disableAnimations,
            settings: AppearanceSettings(glass: variant.glass),
          ),
        );
        await tester.pumpAndSettle();

        // Check 2F schematic on narrow 320px + scaled typography.
        await reveal(tester, find.byKey(const ValueKey('library-floor-card-图书馆二层')));
        await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆二层')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-zone-north')), findsOneWidget);

        // Return to Level 1 and verify 3F schematic + Level 3 map & grid.
        await reveal(tester, find.byKey(const ValueKey('library-back-to-floors')));
        await tester.tap(find.byKey(const ValueKey('library-back-to-floors')));
        await tester.pumpAndSettle();

        await reveal(tester, find.byKey(const ValueKey('library-floor-card-图书馆三层')));
        await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆三层')));
        await tester.pumpAndSettle();
        await reveal(tester, find.byKey(const ValueKey('library-zone-westC-east')));
        await tester.tap(find.byKey(const ValueKey('library-zone-westC-east')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-floor-map-viewport')), findsOneWidget);

        await reveal(tester, find.byKey(const ValueKey('library-view-grid')));
        await tester.tap(find.byKey(const ValueKey('library-view-grid')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-seat-search')), findsOneWidget);

        await reveal(tester, find.byKey(const ValueKey('library-level3-locator')));
        await tester.tap(find.byKey(const ValueKey('library-level3-locator')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-floor-schematic-canvas')), findsOneWidget);

        await reveal(tester, find.byKey(const ValueKey('library-breadcrumb-floors')));
        await tester.tap(find.byKey(const ValueKey('library-breadcrumb-floors')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('library-floor-card-图书馆二层')), findsOneWidget);

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'Stage 8C isotropic layout keeps 西A区 compact and 南区 cloverleaf/edge rows square without overlap',
    () {
      final westASeats = <LibrarySeat>[
        for (var i = 0; i < 24; i++) ...[
          seat(
            id: 'wa_n_$i',
            label: '5WA${(i * 2 + 2).toString().padLeft(3, '0')}',
            x: 6.0 + i * 3.8,
            y: 55.0,
          ),
          seat(
            id: 'wa_s_$i',
            label: '5WA${(i * 2 + 1).toString().padLeft(3, '0')}',
            x: 6.0 + i * 3.8,
            y: 62.0,
          ),
        ],
      ];

      final westALayout = computeLibraryFloorMapLayout(westASeats, 340);
      expect(westALayout.canvasHeight, lessThan(180.0));
      final rowGap =
          (westALayout.positions[1].dy - westALayout.positions[0].dy).abs();
      expect(rowGap, lessThan(35.0));
      for (final size in westALayout.sizes) {
        expect((size.width - size.height).abs(), lessThan(0.01));
      }
      for (var i = 0; i < westALayout.positions.length; i++) {
        final ri = Rect.fromCenter(
          center: westALayout.positions[i],
          width: westALayout.sizes[i].width,
          height: westALayout.sizes[i].height,
        );
        for (var j = i + 1; j < westALayout.positions.length; j++) {
          final rj = Rect.fromCenter(
            center: westALayout.positions[j],
            width: westALayout.sizes[j].width,
            height: westALayout.sizes[j].height,
          );
          expect(ri.overlaps(rj), false);
        }
      }

      // 南区 fixture: symmetric 4-seat cloverleaf (phys dx == dy => y% span = 1.72 * x% span),
      // main study block, and dense window edge strip.
      const cloverStepX = 3.0;
      const cloverStepY = cloverStepX * LibrarySeatFloorMap.schoolCanvasAspect;
      final southSeats = <LibrarySeat>[
        // Main block
        for (var r = 0; r < 4; r++)
          for (var c = 0; c < 6; c++)
            seat(
              id: 'sm_${r}_$c',
              label: '5S${(60 + r * 6 + c).toString().padLeft(3, '0')}',
              x: 24.0 + c * 4.2,
              y: 20.0 + r * 6.5,
            ),
        // Cloverleaf 4-seat table cluster
        seat(id: 'sc_0', label: '5S033', x: 40.0, y: 60.0),
        seat(id: 'sc_1', label: '5S034', x: 40.0 + cloverStepX, y: 60.0),
        seat(id: 'sc_2', label: '5S031', x: 40.0, y: 60.0 + cloverStepY),
        seat(
          id: 'sc_3',
          label: '5S032',
          x: 40.0 + cloverStepX,
          y: 60.0 + cloverStepY,
        ),
        // Dense bottom window row
        for (var c = 0; c < 12; c++)
          seat(
            id: 'sd_$c',
            label: '5S${(100 + c).toString().padLeft(3, '0')}',
            x: 56.0 + c * 2.1,
            y: 86.0,
          ),
      ];

      final southLayout = computeLibraryFloorMapLayout(southSeats, 340);
      for (final size in southLayout.sizes) {
        final aspect = size.width / size.height;
        expect(aspect, inInclusiveRange(0.85, 1.18));
      }
      final cloverDx =
          (southLayout.positions[25].dx - southLayout.positions[24].dx).abs();
      final cloverDy =
          (southLayout.positions[26].dy - southLayout.positions[24].dy).abs();
      expect((cloverDy / cloverDx - 1.0).abs(), lessThan(0.05));
      for (var i = 0; i < southLayout.positions.length; i++) {
        final ri = Rect.fromCenter(
          center: southLayout.positions[i],
          width: southLayout.sizes[i].width,
          height: southLayout.sizes[i].height,
        );
        for (var j = i + 1; j < southLayout.positions.length; j++) {
          final rj = Rect.fromCenter(
            center: southLayout.positions[j],
            width: southLayout.sizes[j].width,
            height: southLayout.sizes[j].height,
          );
          expect(ri.overlaps(rj), false);
        }
      }
    },
  );

  testWidgets(
    'Stage 8C aligns breadcrumb segments, groups controls by function, and keeps 西A区 labels consistent across zoom',
    variant: androidOnly,
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final westASeats = <LibrarySeat>[
        for (var i = 0; i < 24; i++) ...[
          seat(
            id: 'wa_n_$i',
            label: '5WA${(i * 2 + 2).toString().padLeft(3, '0')}',
            x: 6.0 + i * 3.8,
            y: 55.0,
          ),
          seat(
            id: 'wa_s_$i',
            label: '5WA${(i * 2 + 1).toString().padLeft(3, '0')}',
            x: 6.0 + i * 3.8,
            y: 62.0,
          ),
        ],
      ];

      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async => const [
          LibraryArea('51', '五层西A区', '图书馆五层'),
          LibraryArea('52', '五层南区', '图书馆五层'),
          LibraryArea('53', '五层北区', '图书馆五层'),
        ])
        ..onSeats = ((_, _) async => westASeats);

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          dark: true,
          now: () => DateTime(2026, 11, 20, 9, 0),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('library-floor-card-图书馆五层')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-zone-westA')));
      await tester.pumpAndSettle();

      // 1. Breadcrumb segments share the same vertical center line.
      final crumbAllY = tester.getCenter(find.text('全部楼层')).dy;
      final crumbFloorY = tester.getCenter(find.text('图书馆五层')).dy;
      final crumbAreaY = tester.getCenter(find.text('五层西A区')).dy;
      final barCenterY =
          tester.getCenter(find.byKey(const ValueKey('library-breadcrumb-area'))).dy;
      expect((crumbAllY - crumbFloorY).abs(), lessThanOrEqualTo(1.5));
      expect((crumbFloorY - crumbAreaY).abs(), lessThanOrEqualTo(1.5));
      expect((crumbAllY - barCenterY).abs(), lessThanOrEqualTo(1.5));

      // 2. Controls card orders Location -> Date/Time -> Status & Only-Available.
      final locatorRect =
          tester.getRect(find.byKey(const ValueKey('library-level3-locator')));
      final viewToggleRect =
          tester.getRect(find.byKey(const ValueKey('library-view-grid')));
      final areaPickerRect =
          tester.getRect(find.byKey(const ValueKey('library-area-picker')));
      final todayCenterY = tester.getCenter(find.text('今天')).dy;
      final tomorrowCenterY = tester.getCenter(find.text('明天')).dy;
      final datePickerRect =
          tester.getRect(find.byKey(const ValueKey('library-date-picker')));
      final timePickerRect =
          tester.getRect(find.byKey(const ValueKey('library-time-picker')));
      final statsRect = tester.getRect(find.text('共 48 席'));
      final onlyAvailRect = tester.getRect(
        find.byKey(const ValueKey('library-only-available-toggle')),
      );

      expect((locatorRect.center.dy - viewToggleRect.center.dy).abs(), lessThan(8.0));
      expect(locatorRect.bottom, lessThanOrEqualTo(areaPickerRect.top));
      expect(areaPickerRect.bottom, lessThan(datePickerRect.top));
      expect((todayCenterY - datePickerRect.center.dy).abs(), lessThanOrEqualTo(1.5));
      expect((tomorrowCenterY - datePickerRect.center.dy).abs(), lessThanOrEqualTo(1.5));
      expect(datePickerRect.bottom, lessThan(timePickerRect.top));
      expect(timePickerRect.bottom, lessThan(statsRect.top));
      expect(timePickerRect.bottom, lessThan(onlyAvailRect.top));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);

      // 3. Dense 西A区 suppresses crowded labels consistently at 1.0x and reveals cleanly on zoom.
      final seatTextCount1x = find
          .descendant(
            of: find.byKey(const ValueKey('library-floor-map-viewer')),
            matching: find.byType(Text),
          )
          .evaluate()
          .length;
      expect(seatTextCount1x, 0);

      await tester.tap(find.byKey(const ValueKey('library-map-zoom-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-map-zoom-in')));
      await tester.pumpAndSettle();
      expect(find.text('5WA001'), findsOneWidget);
      expect(find.text('5WA048'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'library login silently reuses active CAS session without opening webpage',
    variant: androidOnly,
    (tester) async {
      var loggedIn = false;
      var openerCalls = 0;
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async {
          if (!loggedIn) throw LibraryReadFailure.login;
          return const [LibraryArea('32', '二层北区', '二层')];
        })
        ..onReuseSession = (() async {
          loggedIn = true;
          return true;
        })
        ..onSeats = ((_, _) async => [seat(id: '10', label: '2N010')]);

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 9),
          loginOpener: (_, _) async {
            openerCalls++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('需要登录学校账号'), findsOneWidget);

      await tester.tap(find.text('登录校园账号'));
      await tester.pumpAndSettle();
      expect(reader.reuseCalls, 1);
      expect(openerCalls, 0);
      expect(find.text('校园账号登录成功，正在获取座位状态'), findsOneWidget);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
        SnackBarBehavior.floating,
      );
      expect(find.text('二层'), findsOneWidget);
      expect(reader.reserveCalls, 0);
      expect(reader.cancelCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'library official login auto-closes after seatMenu succeeds and loads seat status',
    variant: androidOnly,
    (tester) async {
      final platform = CampusLoginTestPlatform();
      final previous = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = platform;
      if (previous != null) {
        addTearDown(() => InAppWebViewPlatform.instance = previous);
      }
      var loggedIn = false;
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async {
          if (!loggedIn) throw LibraryReadFailure.login;
          return const [LibraryArea('32', '二层北区', '二层')];
        })
        ..onSeats = ((_, _) async => [seat(id: '11', label: '2N011')]);

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 9),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('需要登录学校账号'), findsOneWidget);

      await tester.tap(find.text('登录校园账号'));
      await tester.pump();
      await tester.pump();
      expect(reader.reuseCalls, 1);
      expect(find.byType(CampusLoginPage), findsOneWidget);
      expect(find.text('学校官方页面 · 图书馆座位预约'), findsOneWidget);

      final view = platform.views.single;
      loggedIn = true;
      view.controller.ready = true;
      view.visit(SchoolEndpoints.librarySeatHome);
      await tester.pumpAndSettle();
      expect(find.byType(CampusLoginPage), findsNothing);
      expect(find.text('校园账号登录成功，正在获取座位状态'), findsOneWidget);
      expect(find.text('二层'), findsOneWidget);
      expect(reader.reserveCalls, 0);
      expect(reader.cancelCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'library login cancellation leaves state clean with zero writes or notice',
    variant: androidOnly,
    (tester) async {
      var areaCalls = 0;
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async {
          areaCalls++;
          throw LibraryReadFailure.login;
        });

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 9),
          loginOpener: (_, _) async => false,
        ),
      );
      await tester.pumpAndSettle();
      expect(areaCalls, 1);
      await tester.tap(find.text('登录校园账号'));
      await tester.pumpAndSettle();
      expect(reader.reuseCalls, 1);
      expect(areaCalls, 1);
      expect(find.text('校园账号登录成功，正在获取座位状态'), findsNothing);
      expect(find.text('需要登录学校账号'), findsOneWidget);
      expect(reader.reserveCalls, 0);
      expect(reader.cancelCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'interrupted reservation checks bookings first after login without retrying the write',
    variant: androidOnly,
    (tester) async {
      var loggedIn = true;
      var reserveCount = 0;
      var openerCalls = 0;
      final recoveryReads = <String>[];
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async => const [LibraryArea('32', '二层北区', '二层')])
        ..onSeats = ((_, _) async {
          if (!loggedIn) throw LibraryReadFailure.login;
          if (reserveCount != 0) recoveryReads.add('seats');
          return [seat(id: '100', label: 'N001')];
        })
        ..onBookings = ((begin, end, page) async {
          recoveryReads.add('bookings:${isoDate(begin)}:${isoDate(end)}:$page');
          return LibraryBookingPage(const [], false, page: page);
        })
        ..onReuseSession = (() async {
          loggedIn = true;
          return true;
        })
        ..onReserve = ((_, _, _, _) async {
          reserveCount++;
          loggedIn = false;
          return const LibraryWriteResult(LibraryWriteStatus.login);
        });

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 8, 0),
          loginOpener: (_, _) async {
            openerCalls++;
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      await enterLibraryArea(tester);
      await reveal(tester, find.text('N001'));
      await tester.tap(find.text('N001'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('确认预约'));
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交预约'));
      await tester.pumpAndSettle();

      expect(reserveCount, 1);
      expect(find.text('登录状态已中断，已停止本次提交'), findsOneWidget);
      await tester.tap(find.text('登录校园账号').last);
      await tester.pumpAndSettle();

      expect(reader.reuseCalls, 1);
      expect(openerCalls, 0);
      expect(reserveCount, 1);
      expect(reader.cancelCalls, 0);
      expect(recoveryReads, ['bookings:2026-10-05:2026-10-11:1']);
      expect(find.text('校园账号登录成功，正在核对预约记录'), findsOneWidget);
      expect(find.text('登录状态已中断，已停止本次提交'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'interrupted cancellation reloads bookings after login without repeating the write',
    variant: androidOnly,
    (tester) async {
      final reads = <(DateTime, DateTime, int)>[];
      final reader = FakeLibrarySeatReader()
        ..onBookings = ((begin, end, page) async {
          reads.add((begin, end, page));
          return LibraryBookingPage([cancellationFixture], false, page: page);
        })
        ..onCancelBooking = ((_) async =>
            const LibraryWriteResult(LibraryWriteStatus.login));
      await tester.pumpWidget(
        wrapLibraryPage(reader, loginOpener: (_, _) async => true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('我的预约'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('取消预约'));
      await tester.tap(find.text('取消预约'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();
      expect(reader.cancelCalls, 1);
      expect(reads, hasLength(1));
      await reveal(tester, find.text('登录校园账号'));
      await tester.tap(find.text('登录校园账号'));
      await tester.pumpAndSettle();
      expect(reads, [reads.first, reads.first]);
      expect(reader.cancelCalls, 1);
      expect(reader.reserveCalls, 0);
      expect(find.text('校园账号登录成功，正在核对预约记录'), findsOneWidget);
      expect(find.text('学校会话已失效'), findsNothing);
      await reveal(tester, find.text('取消预约'));
      await tester.tap(find.text('取消预约'));
      await tester.pumpAndSettle();
      expect(find.text('确认取消'), findsOneWidget);
      expect(reader.cancelCalls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'clearSession mid-authentication discards stale reuse and login result',
    variant: androidOnly,
    (tester) async {
      final folder = await tester.runAsync(
        () => Directory.systemTemp.createTemp('synthetic-lib-auth-race-'),
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => folder!.path);
      messenger.setMockMethodCallHandler(
        SchoolAdapter.channel,
        (call) async => null,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(SchoolAdapter.channel, null);
        await folder!.delete(recursive: true);
      });

      final reuseCompleter = Completer<bool>();
      var areaCalls = 0;
      var openerCalls = 0;
      final reader = FakeLibrarySeatReader()
        ..onAreas = (() async {
          areaCalls++;
          throw LibraryReadFailure.login;
        })
        ..onReuseSession = (() => reuseCompleter.future);

      await tester.pumpWidget(
        wrapLibraryPage(
          reader,
          now: () => DateTime(2026, 10, 10, 9),
          loginOpener: (_, _) async {
            openerCalls++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(areaCalls, 1);

      await tester.tap(find.text('登录校园账号'));
      await tester.pump();

      await tester.runAsync(() => SchoolAdapter().clearSession());
      reuseCompleter.complete(true);
      await tester.pumpAndSettle();

      expect(openerCalls, 0);
      expect(areaCalls, 1);
      expect(find.text('校园账号登录成功，正在获取座位状态'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
