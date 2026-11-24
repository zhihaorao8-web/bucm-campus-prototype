import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campus_schedule/application/appearance_controller.dart';
import 'package:campus_schedule/application/schedule_controller.dart';
import 'package:campus_schedule/domain/schedule.dart';
import 'package:campus_schedule/platform/app_platform.dart';
import 'package:campus_schedule/ui/app_shell.dart';
import 'package:campus_schedule/ui/app_theme.dart';
import 'package:campus_schedule/ui/course_interaction.dart';
import 'package:campus_schedule/ui/course_widgets.dart';
import 'package:campus_schedule/ui/course_surface.dart';
import 'package:campus_schedule/ui/quiet_backdrop.dart';
import 'package:campus_schedule/ui/today_focus.dart';
import 'package:campus_schedule/ui/classroom_course_page.dart';
import 'package:campus_schedule/ui/week_navigation.dart';
import 'support/memory_appearance.dart';
import 'schedule_test.dart' show MemoryRepository, sample;
import 'week_grid_test.dart' show weeklyPreviewData;

Widget frame(
  Widget child, {
  bool reduced = false,
  bool contrast = false,
  double scale = 1,
}) => ProviderScope(
  overrides: [
    appearanceRepositoryProvider.overrideWithValue(
      MemoryAppearanceRepository(),
    ),
  ],
  child: MaterialApp(
    theme: appTheme(reduced ? Brightness.dark : Brightness.light),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduced,
        highContrast: contrast,
        textScaler: TextScaler.linear(scale),
      ),
      child: MiuixThemeBridge(child: child!),
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  for (final contrast in [false, true]) {
    testWidgets(
      'full course sheet keeps fields and dismissal at large text; contrast=$contrast',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final course = Course.fromJson({
          ...sample().toJson(),
          'dataSource': 'synthetic',
        });
        await tester.pumpWidget(
          frame(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showCourseInformation(context, course),
                child: const Text('完整信息'),
              ),
            ),
            contrast: contrast,
            reduced: contrast,
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('完整信息'));
        await tester.pumpAndSettle();
        final sheet = find.byType(QuietSheet);
        expect(sheet, findsOneWidget);
        expect(tester.getRect(sheet).top, greaterThanOrEqualTo(0));
        expect(find.text(course.name), findsOneWidget);
        expect(find.text('合成示例'), findsOneWidget);
        final filter = tester.widget<BackdropFilter>(
          find.descendant(of: sheet, matching: find.byType(BackdropFilter)),
        );
        expect(filter.enabled, !contrast);
        await tester.ensureVisible(find.text('北京时间'));
        await tester.pumpAndSettle();
        expect(find.text('08:30–10:00'), findsOneWidget);
        await tester.ensureVisible(find.text('完成'));
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final reduced in [false, true]) {
    testWidgets(
      'press cancellation restores card and does not activate; reduced=$reduced',
      (tester) async {
        var activated = 0;
        await tester.pumpWidget(
          frame(
            CoursePressable(
              onPressed: () => activated++,
              child: const SizedBox(
                key: ValueKey('press-content'),
                width: 200,
                height: 80,
              ),
            ),
            reduced: reduced,
          ),
        );
        await tester.pumpAndSettle();
        final content = find.byKey(const ValueKey('press-content'));
        final original = tester.getRect(content);
        final gesture = await tester.startGesture(original.center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        if (reduced) {
          expect(tester.getRect(content).width, closeTo(original.width, .01));
        } else {
          expect(tester.getRect(content).width, lessThan(original.width));
          expect(
            tester.getRect(content).width,
            greaterThan(original.width * .97),
          );
        }
        await gesture.cancel();
        await tester.pumpAndSettle();
        expect(activated, 0);
        expect(tester.getRect(content).width, closeTo(original.width, .1));
        final drag = await tester.startGesture(original.center);
        await tester.pump();
        await drag.moveBy(const Offset(0, -60));
        await drag.up();
        await tester.pumpAndSettle();
        expect(activated, 0);
        expect(tester.getRect(content).width, closeTo(original.width, .1));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(activated, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'repeated course occurrences enter and return without duplicate heroes; reduced=$reduced',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final course = Course.fromJson({
          ...sample().toJson(),
          'dataSource': 'synthetic',
        });
        final event = Occurrence(
          course,
          course.segments.first,
          DateTime(2026, 11, 13),
        );
        await tester.pumpWidget(
          frame(
            Column(
              children: [
                FocusCourseCard(event: event, now: DateTime(2026, 11, 13, 8)),
                CourseRow(event: event),
                CourseRow(event: event),
              ],
            ),
            reduced: reduced,
          ),
        );
        await tester.pumpAndSettle();
        final tags = tester
            .widgetList<Hero>(find.byType(Hero))
            .map((h) => h.tag)
            .toList();
        expect(tags.toSet().length, tags.length);
        expect(tags.length, reduced ? 0 : 3);
        final source = find.byType(CourseRow).first;
        final location = tester.getTopLeft(source);
        await tester.tap(source);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        final page = find.byType(ClassroomCoursePage);
        expect(page, findsOneWidget);
        final route = ModalRoute.of(tester.element(page))!;
        expect(route, isA<CourseDetailsRoute>());
        final bar = tester.getRect(
          find.descendant(of: page, matching: find.byType(AppBar)),
        );
        final summary = tester.getRect(
          find.descendant(of: page, matching: find.byType(QuietCard)).first,
        );
        expect(summary.top, closeTo(bar.bottom + 16, .5));
        expect(
          tester.getRect(find.byKey(const ValueKey('course-detail-list'))).top,
          bar.top,
        );
        expect(
          route.transitionDuration,
          reduced ? Duration.zero : const Duration(milliseconds: 280),
        );
        Navigator.of(tester.element(page)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(ClassroomCoursePage), findsNothing);
        expect(tester.getTopLeft(find.byType(CourseRow).first), location);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('repeated taps cannot open a second pending course route', (
    tester,
  ) async {
    var openings = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      frame(
        CourseCardLink(
          onOpen: (_) {
            openings++;
            return pending.future;
          },
          child: const SizedBox(width: 200, height: 80, child: Text('打开课程')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开课程'));
    await tester.tap(find.text('打开课程'));
    await tester.pumpAndSettle();
    expect(openings, 1);
    pending.complete();
    await tester.pump();
    await tester.tap(find.text('打开课程'));
    await tester.pumpAndSettle();
    expect(openings, 2);
    await tester.pumpWidget(const SizedBox());
  });

  Widget buildShellApp(
    ScheduleData data, {
    required bool dark,
    required bool predictiveBack,
  }) => ProviderScope(
    overrides: [
      ambientMotionEnabledProvider.overrideWithValue(false),
      repositoryProvider.overrideWithValue(MemoryRepository(data)),
      appearanceRepositoryProvider.overrideWithValue(
        MemoryAppearanceRepository(
          AppearanceSettings(predictiveBack: predictiveBack),
        ),
      ),
      appInfoProvider.overrideWith(
        (ref) async => const AppPlatformInfo(
          version: 'test',
          build: '7',
          sdk: 36,
          systemAccent: 0xff00897b,
        ),
      ),
    ],
    child: MaterialApp(
      theme: appTheme(
        dark ? Brightness.dark : Brightness.light,
        settings: AppearanceSettings(predictiveBack: predictiveBack),
      ).copyWith(platform: TargetPlatform.android),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MiuixThemeBridge(child: child!),
      home: const AppShell(),
    ),
  );

  void expectNoNestedBackdropFilters(WidgetTester tester) {
    for (final element in find
        .byType(BackdropFilter, skipOffstage: false)
        .evaluate()) {
      final ancestors = find
          .ancestor(
            of: find.byElementPredicate((candidate) => candidate == element),
            matching: find.byType(BackdropFilter, skipOffstage: false),
          )
          .evaluate()
          .where((ancestor) => ancestor != element);
      expect(
        ancestors,
        isEmpty,
        reason: 'Nested BackdropFilter found under ${element.widget.key}',
      );
    }
  }

  void expectAllBackdropFiltersDisabled(
    WidgetTester tester, {
    required String reason,
  }) {
    for (final element in find
        .byType(BackdropFilter, skipOffstage: false)
        .evaluate()) {
      final filter = element.widget as BackdropFilter;
      expect(filter.enabled, isFalse, reason: '$reason (${filter.key})');
    }
  }

  for (final (dark, predictiveBack) in [(false, true), (true, false)]) {
    testWidgets(
      'course route push and pop suspend all backdrop filters including Hero pop shuttle and keep zero nesting (dark=$dark predictiveBack=$predictiveBack)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          buildShellApp(
            weeklyPreviewData(DateTime.now()),
            dark: dark,
            predictiveBack: predictiveBack,
          ),
        );
        await tester.pumpAndSettle();

        expectNoNestedBackdropFilters(tester);
        expect(
          tester
              .widget<BackdropFilter>(find.byKey(const ValueKey('dock-blur')))
              .enabled,
          isTrue,
        );
        expect(
          tester
              .widget<BackdropFilter>(
                find.descendant(
                  of: find.byKey(const ValueKey('dock-lens')),
                  matching: find.byType(BackdropFilter),
                ),
              )
              .enabled,
          isTrue,
        );
        expect(
          tester
              .widget<BackdropFilter>(
                find.byKey(const ValueKey('focus-acrylic-blur')),
              )
              .enabled,
          isTrue,
        );
        final topBar0 = find.byKey(
          const ValueKey('topbar-0'),
          skipOffstage: false,
        );
        expect(tester.widget<MiuixTopAppBar>(topBar0).blurred, isTrue);

        Future<void> verifyTransitionFrom(Finder trigger, String label) async {
          await tester.ensureVisible(trigger);
          await tester.pumpAndSettle();
          await tester.tap(trigger);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));

          expectAllBackdropFiltersDisabled(
            tester,
            reason: 'mid-push from $label',
          );
          final midPushBar = tester.widget<MiuixTopAppBar>(topBar0);
          expect(midPushBar.blurred, isFalse);
          expect(midPushBar.color!.a, lessThan(1.0));
          expect(tester.takeException(), isNull);

          await tester.pumpAndSettle();
          expect(find.byType(ClassroomCoursePage), findsOneWidget);
          expectNoNestedBackdropFilters(tester);
          expect(
            tester
                .widget<BackdropFilter>(
                  find.descendant(
                    of: find.byType(QuietSliverAppBar),
                    matching: find.byType(BackdropFilter),
                  ),
                )
                .enabled,
            isTrue,
          );
          expect(
            tester
                .widget<BackdropFilter>(
                  find.byKey(const ValueKey('classroom-section-blur')),
                )
                .enabled,
            isTrue,
          );
          expect(
            tester
                .widget<BackdropFilter>(
                  find.descendant(
                    of: find.byKey(const ValueKey('classroom-section-indicator')),
                    matching: find.byType(BackdropFilter),
                  ),
                )
                .enabled,
            isTrue,
          );

          await tester.tap(find.text('完成'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));

          expectAllBackdropFiltersDisabled(
            tester,
            reason: 'mid-pop to $label (including Hero pop shuttle)',
          );
          expect(tester.widget<MiuixTopAppBar>(topBar0).blurred, isFalse);
          expect(tester.takeException(), isNull);

          await tester.pumpAndSettle();
          expect(find.byType(ClassroomCoursePage), findsNothing);
          expect(
            tester
                .widget<BackdropFilter>(find.byKey(const ValueKey('dock-blur')))
                .enabled,
            isTrue,
          );
          expect(
            tester
                .widget<BackdropFilter>(
                  find.descendant(
                    of: find.byKey(const ValueKey('dock-lens')),
                    matching: find.byType(BackdropFilter),
                  ),
                )
                .enabled,
            isTrue,
          );
          if (find.byKey(const ValueKey('focus-acrylic-blur')).evaluate().isNotEmpty) {
            expect(
              tester
                  .widget<BackdropFilter>(
                    find.byKey(const ValueKey('focus-acrylic-blur')),
                  )
                  .enabled,
              isTrue,
            );
          }
          expect(tester.widget<MiuixTopAppBar>(topBar0).blurred, isTrue);
          expect(tester.takeException(), isNull);
        }

        await verifyTransitionFrom(
          find.byKey(const ValueKey('today-focus')),
          'FocusCourseCard',
        );
        await verifyTransitionFrom(
          find
              .descendant(
                of: find.byKey(const PageStorageKey('today-page')),
                matching: find.byType(CourseRow),
              )
              .first,
          'CourseRow',
        );
        tester
            .widget<ListView>(find.byKey(const PageStorageKey('today-page')))
            .controller!
            .jumpTo(0);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<BackdropFilter>(
                find.byKey(const ValueKey('focus-acrylic-blur')),
              )
              .enabled,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'ScheduleModeTransition suspends ScheduleModeSwitch and WeekdayTabs blur during cross-fade',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        buildShellApp(
          weeklyPreviewData(DateTime.now()),
          dark: false,
          predictiveBack: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-1')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<BackdropFilter>(
              find.descendant(
                of: find.byType(ScheduleModeSwitch),
                matching: find.byType(BackdropFilter),
              ),
            )
            .enabled,
        isTrue,
      );

      await tester.tap(find.text('日'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      for (final element in find
          .descendant(
            of: find.byType(ScheduleModeSwitch, skipOffstage: false),
            matching: find.byType(BackdropFilter, skipOffstage: false),
          )
          .evaluate()) {
        expect((element.widget as BackdropFilter).enabled, isFalse);
      }
      for (final element in find
          .byKey(const ValueKey('weekday-acrylic-blur'), skipOffstage: false)
          .evaluate()) {
        expect((element.widget as BackdropFilter).enabled, isFalse);
      }
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BackdropFilter>(
              find.descendant(
                of: find.byType(ScheduleModeSwitch),
                matching: find.byType(BackdropFilter),
              ),
            )
            .enabled,
        isTrue,
      );
      expect(
        tester
            .widget<BackdropFilter>(
              find.byKey(const ValueKey('weekday-acrylic-blur')),
            )
            .enabled,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
