import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'navigation_motion.dart';
import 'app_controls.dart';
import 'app_icon_controls.dart';
import 'app_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_miuix/miuix.dart';
import '../application/schedule_controller.dart';
import '../application/appearance_controller.dart';
import '../data/demo_schedule.dart';
import '../data/classroom_library.dart';
import '../domain/schedule.dart';
import '../platform/library_seat_reader.dart';
import '../platform/campus_login_navigation.dart';
import 'campus_login_page.dart';
import 'course_widgets.dart';
import 'course_surface.dart';
import 'import_page.dart';
import 'library_seat_query_page.dart';
import 'week_grid.dart';
import 'weekday_tabs.dart';
import 'glass_navigation.dart';
import 'appearance_page.dart';
import 'privacy_data_page.dart';
import 'project_info_page.dart';
import 'classroom_import_page.dart';
import 'quiet_backdrop.dart';
import 'macintosh_hello_title.dart';
import 'today_focus.dart';
import 'today_quote_banner.dart';
import 'week_navigation.dart';
import 'schedule_sync_card.dart';
import 'app_theme.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.libraryReader});

  final LibrarySeatReader? libraryReader;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _todayTab = 0,
      _scheduleTab = 1,
      _libraryTab = 2,
      _settingsTab = 3,
      _tabCount = 4;
  static const _tabTitles = ['今日', '课表', '图书馆', '设置'];

  int tab = 0, week = 0, day = schoolNow().weekday;
  int? _targetTab;
  bool daily = false, demo = false, busy = false;
  double tabDrag = 0, _dockBottomInset = 0;
  final navigation = PageController();
  final dayController = ScrollController();
  final _libraryTabController = LibrarySeatTabController();
  ScrollController scrollFor(int index) =>
      index == _scheduleTab && daily ? dayController : pageControllers[index];
  String? selectedSemester;
  DateTime now = schoolNow();
  late final Timer ticker;
  final scrollBehaviors = List.generate(
    _tabCount,
    (_) => miuixScrollBehavior(snapOnRelease: false),
  );
  final pageControllers = List.generate(_tabCount, (_) => ScrollController());
  final classroomLibrary = ClassroomLibrary.shared;
  Set<String> recordingKeys = {};
  Timer? badgeTimer;
  int badgeTicket = 0, badgeRevision = 0;
  bool hasRecordings(Course course) =>
      !demo && recordingKeys.contains(ClassroomLibrary.key(course));
  void refreshRecordingBadges() {
    badgeTimer?.cancel();
    final ticket = ++badgeTicket;
    if (badgeRevision != classroomLibrary.revision) {
      badgeRevision = classroomLibrary.revision;
      if (mounted) setState(() => recordingKeys = {});
    }
    badgeTimer = Timer(const Duration(milliseconds: 150), () async {
      if (!mounted || ticket != badgeTicket) return;
      final saved = ref.read(scheduleProvider);
      if (!saved.hasValue) return;
      try {
        final availability = await classroomLibrary.availability(
          saved.requireValue.courses,
        );
        if (mounted && ticket == badgeTicket) {
          setState(
            () => recordingKeys = availability.entries
                .where(
                  (entry) => entry.value == RecordingAvailability.available,
                )
                .map((entry) => entry.key)
                .toSet(),
          );
        }
      } catch (_) {
        if (mounted && ticket == badgeTicket) {
          setState(() => recordingKeys = {});
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    classroomLibrary.changes.addListener(refreshRecordingBadges);
    ref.listenManual(scheduleProvider, (_, next) {
      if (next.hasValue) refreshRecordingBadges();
    }, fireImmediately: true);
    ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => now = schoolNow());
    });
  }

  @override
  void dispose() {
    ticker.cancel();
    navigation.dispose();
    dayController.dispose();
    _libraryTabController.dispose();
    badgeTicket++;
    badgeTimer?.cancel();
    classroomLibrary.changes.removeListener(refreshRecordingBadges);
    for (final behavior in scrollBehaviors) {
      behavior.state.dispose();
    }
    for (final controller in pageControllers) {
      controller.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshRecordingBadges();
      setState(() => now = schoolNow());
    }
  }

  void message(String text, {bool success = false}) => showAppNotice(
    context,
    text,
    success: success,
    bottomInset: (_dockBottomInset - MediaQuery.paddingOf(context).bottom)
        .clamp(0.0, 200.0),
  );
  void selectTerm(String? value) => setState(() {
    selectedSemester = value;
    week = 0;
  });
  void _exitDemo() => setState(() {
    demo = false;
    week = 0;
    selectedSemester = null;
  });
  void startDemo() => setState(() {
    demo = true;
    selectedSemester = null;
    week = 0;
  });
  Future<void> openImport() async {
    if (demo) {
      message('请先退出合成示例，再导入本人课表');
      return;
    }
    final imported = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            ImportPage(recoverUnreadable: ref.read(scheduleProvider).hasError),
      ),
    );
    if (mounted && imported != null) {
      selectTerm(imported);
      final summary = ref
          .read(scheduleProvider)
          .requireValue
          .summaryFor(imported);
      message('课表已保存，可以离线查看。${summary.split('\n').last}');
    }
  }

  Future<void> importClassroom() async {
    if (demo || busy) return;
    final data = ref.read(scheduleProvider).value;
    if (data == null) return;
    final semester = data.semesters.contains(selectedSemester)
        ? selectedSemester
        : data.semesters.firstOrNull;
    await openClassroomImport(
      context,
      data.courses.where((c) => c.semester == semester).toList(),
    );
  }

  Future<bool> confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> runAction(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) message('操作未完成，原有数据保留，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(scheduleProvider);
    final appearance = ref.watch(currentAppearanceProvider);
    return Scaffold(
      body: MiuixScaffold(
        containerColor: Colors.transparent,
        content: (dockInsets) {
          _dockBottomInset = dockInsets.bottom;
          return GestureDetector(
          onHorizontalDragStart:
              appearance.swipePages && MediaQuery.disableAnimationsOf(context)
              ? (_) => tabDrag = 0
              : null,
          onHorizontalDragUpdate:
              appearance.swipePages && MediaQuery.disableAnimationsOf(context)
              ? (event) => tabDrag += event.delta.dx
              : null,
          onHorizontalDragEnd:
              appearance.swipePages && MediaQuery.disableAnimationsOf(context)
              ? (event) {
                  final velocity = event.primaryVelocity ?? 0;
                  if (tabDrag.abs() > 64 || velocity.abs() > 450) {
                    final direction = tabDrag.abs() > 16 ? tabDrag : velocity;
                    selectTab(
                      (tab + (direction < 0 ? 1 : -1)).clamp(0, _tabCount - 1),
                    );
                  }
                }
              : null,
          child: PageView(
            key: const ValueKey('main-navigation-pager'),
            controller: navigation,
            allowImplicitScrolling: true,
            scrollCacheExtent: const ScrollCacheExtent.viewport(_tabCount - 1),
            physics:
                appearance.swipePages &&
                    !MediaQuery.disableAnimationsOf(context)
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            onPageChanged: (value) => setState(() {
              tab = value;
              if (_targetTab == value) {
                _targetTab = null;
              }
            }),
            children: [
              for (var index = 0; index < _tabCount; index++)
                RetainedNavigationPage(
                  key: ValueKey('navigation-page-$index'),
                  controller: navigation,
                  index: index,
                  selected: tab,
                  child: QuietBackdrop(
                    tab: index,
                    child: MiuixScaffold(
                      key: ValueKey('main-page-scaffold-$index'),
                      containerColor: Colors.transparent,
                      contentWindowInsets: EdgeInsets.fromLTRB(
                        dockInsets.left,
                        MediaQuery.paddingOf(context).top,
                        dockInsets.right,
                        dockInsets.bottom,
                      ),
                      topBar: navigationHeader(index, stored, appearance),
                      content: (insets) =>
                          navigationPage(index, insets, stored),
                    ),
                  ),
                ),
            ],
          ),
        );
        },
        bottomBar: AnimatedBuilder(
          animation: navigation,
          builder: (context, _) => GlassNavigation(
            selected: tab,
            position: navigationPosition(navigation, tab),
            onSelect: selectTab,
          ),
        ),
      ),
    );
  }

  Widget navigationHeader(
    int index,
    AsyncValue<ScheduleData> stored,
    AppearanceSettings appearance,
  ) => ListenableBuilder(
    listenable: scrollFor(index),
    builder: (context, _) {
      final opaque = AppVisualPolicy.of(context, appearance).opaque;
      final scroll = scrollFor(index);
      final tint = AppHeader.tint(
        scroll.hasClients ? scroll.positions.last.pixels : 0,
      );
      final topBar = MiuixTopAppBar(
        key: ValueKey('topbar-$index'),
        title: _tabTitles[index],
        largeTitleColor: index == _settingsTab ? null : Colors.transparent,
        color: Theme.of(context).colorScheme.surface,
        scrollBehavior: scrollBehaviors[index],
        blurred: !opaque,
        blurRadius: AppHeader.blur,
        blurTintAlpha: tint,
        actions: [
          if (demo)
            TextButton(onPressed: _exitDemo, child: const Text('退出示例')),
          if (!demo && stored.hasValue && index < _libraryTab)
            Tooltip(
              message: '导入或刷新课表',
              child: MiuixIconButton(
                minWidth: AppLayout.minTap,
                minHeight: AppLayout.minTap,
                onPressed: openImport,
                child: const AppIcon(AppIcons.sync),
              ),
            ),
          if (!demo && stored.hasValue && index == _scheduleTab)
            Tooltip(
              message: '统一导入录播',
              child: MiuixIconButton(
                key: const ValueKey('classroom-import-button'),
                minWidth: AppLayout.minTap,
                minHeight: AppLayout.minTap,
                onPressed: importClassroom,
                child: const AppIcon(AppIcons.mediaLibrary),
              ),
            ),
          if (!demo && index == _libraryTab) ...[
            Tooltip(
              message: '刷新座位或预约',
              child: MiuixIconButton(
                key: const ValueKey('library-refresh-button'),
                minWidth: AppLayout.minTap,
                minHeight: AppLayout.minTap,
                onPressed: _libraryTabController.refresh,
                child: const AppIcon(AppIcons.refresh),
              ),
            ),
            Tooltip(
              message: '打开学校预约网页',
              child: MiuixIconButton(
                key: const ValueKey('library-official-button'),
                minWidth: AppLayout.minTap,
                minHeight: AppLayout.minTap,
                onPressed: _libraryTabController.openOfficial,
                child: const AppIcon(AppIcons.globe),
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
      );
      if (index == _settingsTab) return topBar;
      final miuixTheme = MiuixTheme.of(context);
      return Stack(
        fit: StackFit.passthrough,
        children: [
          MiuixTheme(
            data: miuixTheme.copyWith(
              textStyles: miuixTheme.textStyles.copy(
                title1: miuixTheme.textStyles.title1.copyWith(
                  fontSize: AppType.artisticHeader,
                  height: 1.16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            child: topBar,
          ),
          Positioned.fill(
            child: MacintoshHelloHeaderOverlay(
              text: _tabTitles[index],
              scrollBehavior: scrollBehaviors[index],
              active: tab == index,
            ),
          ),
        ],
      );
    },
  );

  EdgeInsets pagePadding(
    EdgeInsets insets, {
    double horizontal = AppLayout.pageInset,
  }) => EdgeInsets.fromLTRB(
    horizontal + insets.left,
    insets.top + AppSpace.md,
    horizontal + insets.right,
    insets.bottom + AppSpace.xxl,
  );

  Widget demoNotice() => Padding(
    padding: const EdgeInsets.only(bottom: AppSpace.lg),
    child: Text(
      '合成示例，仅用于体验界面，不是本人课表',
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget termSelector(ScheduleData data, String semester) =>
      DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: semester,
          isExpanded: true,
          icon: const AppIcon(AppIcons.chevronDown),
          items: data.semesters
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    '$s 学期',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              )
              .toList(),
          onChanged: selectTerm,
        ),
      );

  Widget libraryTab(EdgeInsets insets) => LibrarySeatQueryPage(
    embedded: true,
    active:
        tab == _libraryTab &&
        (_targetTab == null || _targetTab == _libraryTab),
    demo: demo,
    onExitDemo: _exitDemo,
    reader: widget.libraryReader,
    scrollController: pageControllers[_libraryTab],
    contentInsets: insets,
    tabController: _libraryTabController,
  );

  Widget navigationPage(
    int index,
    EdgeInsets insets,
    AsyncValue<ScheduleData> stored,
  ) => MiuixScrollBehaviorListener(
    key: ValueKey('scroll-page-$index'),
    behavior: scrollBehaviors[index],
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: index == _libraryTab
            ? libraryTab(insets)
            : stored.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(semanticsLabel: '正在读取本地课表'),
                ),
                error: (error, stack) => index == _settingsTab
                    ? settings(const ScheduleData(), insets)
                    : Padding(
                        padding: const EdgeInsets.all(AppSpace.xl),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              '本地课表暂时无法读取，原文件已保留。重新导入成功后将替换无法读取的课表；也可在更多操作中恢复备份。',
                            ),
                            const SizedBox(height: 16),
                            MiuixButton(
                              colors: MiuixButtonDefaults.buttonColorsPrimary(
                                context,
                              ),
                              onPressed: openImport,
                              child: const Text('重新导入'),
                            ),
                            PopupMenuButton<String>(
                              tooltip: '更多恢复操作',
                              onSelected: (action) async {
                                if (action == 'retry') {
                                  ref.invalidate(scheduleProvider);
                                  return;
                                }
                                if (!await confirm(
                                  '恢复备份',
                                  '将使用上一份有效备份替换当前课表，原文件仍保留。',
                                )) {
                                  return;
                                }
                                try {
                                  await ref
                                      .read(scheduleProvider.notifier)
                                      .restoreBackup();
                                  if (mounted) message('已恢复备份课表');
                                } catch (_) {
                                  if (mounted) {
                                    message('没有可恢复的备份，或恢复未成功。原文件已保留，请重新导入。');
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'backup',
                                  child: Text('恢复备份'),
                                ),
                                PopupMenuItem(
                                  value: 'retry',
                                  child: Text('重新读取'),
                                ),
                              ],
                              child: const Padding(
                                padding: EdgeInsets.all(AppSpace.lg),
                                child: Text('更多操作'),
                              ),
                            ),
                          ],
                        ),
                      ),
                data: (saved) {
                  final data = demo ? demoSchedule(now) : saved;
                  final semester = data.semesters.contains(selectedSemester)
                      ? selectedSemester
                      : data.semesters.firstOrNull;
                  final courses = data.courses
                      .where((c) => c.semester == semester)
                      .toList();
                  return index == _settingsTab
                      ? settings(data, insets)
                      : courses.isEmpty
                      ? ListView(
                          key: PageStorageKey('empty-page-$index'),
                          controller: pageControllers[index],
                          padding: pagePadding(insets),
                          children: [
                            EmptySchedule(
                              onImport: openImport,
                              onDemo: startDemo,
                            ),
                          ],
                        )
                      : index == _todayTab
                      ? home(data, courses, semester!, insets)
                      : timetable(data, courses, semester!, insets);
                },
              ),
      ),
    ),
  );

  void selectTab(int value) {
    if (!navigation.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_targetTab != null) setState(() => _targetTab = null);
      navigation.jumpToPage(value);
    } else {
      setState(() => _targetTab = value);
      unawaited(
        navigation
            .animateToPage(
              value,
              duration: navigationDuration,
              curve: navigationCurve,
            )
            .whenComplete(() {
              if (mounted && _targetTab == value) {
                setState(() => _targetTab = null);
              }
            }),
      );
    }
  }

  Widget home(
    ScheduleData data,
    List<Course> courses,
    String semester,
    EdgeInsets insets,
  ) {
    final today = occurrencesOn(courses, now);
    final next = nextOccurrences(courses, now).firstOrNull;
    final current = today.where((e) => e.activeAt(now)).length;
    final teachingWeek = courses.first.weekAt(now);
    final maxWeek = courses
        .map((c) => c.maxWeek)
        .reduce((a, b) => a > b ? a : b);
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const PageStorageKey('today-page'),
      controller: pageControllers[0],
      padding: pagePadding(insets),
      children: [
        if (demo) demoNotice(),
        const TodayQuoteBanner(),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${shortDate(now)}，星期${weekdays[now.weekday - 1]}',
              style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: tabularTime,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.control,
                vertical: AppSpace.xs,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.inset),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Text(
                teachingWeek >= 1 && teachingWeek <= maxWeek
                    ? '第 $teachingWeek 教学周'
                    : '非教学周',
                style: TextStyle(
                  fontSize: AppType.caption,
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        termSelector(data, semester),
        const SizedBox(height: 16),
        if (next != null)
          FocusCourseCard(event: next, now: now, overlaps: current)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: Text(
              '这个学期没有后续课程了',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: Text(
                '今天的安排',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text('${today.map((e) => e.course.id).toSet().length} 门课'),
          ],
        ),
        const SizedBox(height: 16),
        if (today.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: Text('今天没有排课，留一点时间给自己。'),
          ),
        TodayCourseTimeline(
          events: today,
          now: now,
          hasRecordings: hasRecordings,
        ),
        const SizedBox(height: 16),
        Text(
          data.isDemo
              ? '所有课程均为合成示例'
              : '已保存到本机 · 本学期${data.lastImportFor(semester) == null ? '更新时间未知' : '更新于 ${schoolTimestamp(data.lastImportFor(semester)!)}'}',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget timetable(
    ScheduleData data,
    List<Course> courses,
    String semester,
    EdgeInsets insets,
  ) {
    final first = courses.first;
    final maximum = courses
        .map((c) => c.maxWeek)
        .reduce((a, b) => a > b ? a : b);
    final currentWeek = first.weekAt(now);
    final selectedWeek = (week == 0 || week > maximum ? currentWeek : week)
        .clamp(1, maximum);
    final monday = calendarAdd(first.termStart, (selectedWeek - 1) * 7);
    final selectedDate = calendarAdd(monday, day - 1);
    final events = occurrencesOn(courses, selectedDate);
    final header = <Widget>[
      if (demo) demoNotice(),
      Row(
        children: [
          Expanded(child: termSelector(data, semester)),
          const SizedBox(width: 8),
          ScheduleModeSwitch(
            daily: daily,
            onChanged: (value) => setState(() => daily = value),
          ),
        ],
      ),
      WeekNavigation(
        week: selectedWeek,
        range:
            '${monday.month}/${monday.day} – ${calendarAdd(monday, 6).month}/${calendarAdd(monday, 6).day}',
        isCurrent: selectedWeek == currentWeek,
        onPrevious: selectedWeek > 1
            ? () => setState(() => week = selectedWeek - 1)
            : null,
        onNext: selectedWeek < maximum
            ? () => setState(() => week = selectedWeek + 1)
            : null,
        onCurrent: () => setState(() {
          week = currentWeek.clamp(1, maximum);
          day = now.weekday;
        }),
      ),
      if (currentWeek < 1 || currentWeek > maximum)
        const Padding(
          padding: EdgeInsets.only(top: AppSpace.sm),
          child: Text('当前日期不在已导入的教学周范围内'),
        ),
    ];
    final dailyView = ListView(
      key: const PageStorageKey('timetable-day-page'),
      controller: dayController,
      padding: pagePadding(insets),
      children: [
        ...header,
        const SizedBox(height: 16),
        WeekdayTabs(
          day: day,
          onSelected: (value) => setState(() => day = value),
        ),
        const SizedBox(height: 24),
        ScheduleContentTransition(
          order:
              selectedDate.millisecondsSinceEpoch ~/
              Duration.millisecondsPerDay,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (events.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('这一天没有排课')),
                ),
              for (final (index, event) in events.indexed)
                CourseRow(
                  event: event,
                  hasRecordings: hasRecordings(event.course),
                  colorIndex: index % 5,
                  now: now,
                  conflict: events.any(
                    (other) => other != event && event.overlaps(other),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final padding = pagePadding(insets, horizontal: 8);
    final weeklyView = CustomScrollView(
      key: const PageStorageKey('timetable-page'),
      controller: pageControllers[1],
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left + AppSpace.sm,
            padding.top,
            padding.right + AppSpace.sm,
            AppSpace.xs,
          ),
          sliver: SliverList.list(children: header),
        ),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            // Fit the whole teaching day above the glass dock on normal phones.
            // Large text/short viewports may scroll vertically, never horizontally.
            final available =
                constraints.viewportMainAxisExtent -
                constraints.precedingScrollExtent -
                padding.bottom;
            final height = available < WeekGrid.minimumHeight(context)
                ? WeekGrid.minimumHeight(context)
                : available;
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(
                padding.left,
                0,
                padding.right,
                padding.bottom,
              ),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: height,
                  child: ScheduleContentTransition(
                    order:
                        monday.millisecondsSinceEpoch ~/
                        Duration.millisecondsPerDay,
                    child: WeekGrid(
                      courses: courses,
                      hasRecordings: hasRecordings,
                      monday: monday,
                      today: now,
                      onSelectDay: (value) => setState(() {
                        day = value;
                        daily = true;
                      }),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
    return ScheduleModeTransition(
      daily: daily,
      weekly: weeklyView,
      dailyView: dailyView,
    );
  }

  Widget settings(ScheduleData data, EdgeInsets insets) {
    final colors = Theme.of(context).colorScheme;
    final semester = data.semesters.contains(selectedSemester)
        ? selectedSemester
        : data.semesters.firstOrNull;
    return FocusTraversalGroup(
      child: CustomScrollView(
        key: const PageStorageKey('settings-page'),
        controller: pageControllers[_settingsTab],
        slivers: [
          // The externally painted bar must count as viewport obstruction.
          PinnedHeaderSliver(child: SizedBox(height: insets.top)),
          SliverPadding(
            padding: pagePadding(insets.copyWith(top: 0)),
            sliver: SliverList.list(
              children: [
                QuietCard(
                  key: const ValueKey('campus-account-card'),
                  cornerRadius: AppRadius.card,
                  insideMargin: EdgeInsets.zero,
                  child: AppArrowPreference(
                    key: const ValueKey('settings-campus-login'),
                    title: '登录校园账号',
                    summary: demo
                        ? '退出示例后可通过学校官方页面登录'
                        : '北京中医药大学统一身份认证 · 官方页面登录',
                    enabled: !busy && !demo,
                    startAction: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: AppIcon(
                        AppIcons.globe,
                        size: 20,
                        color: (!busy && !demo)
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    onClick: () => runAction(() async {
                      final opened = await openCampusLogin(
                        context,
                        target: CampusLoginTarget.teaching,
                        reason: '登录后返回设置',
                      );
                      if (mounted && opened) {
                        message('校园账号登录成功，教务系统已可访问', success: true);
                      }
                    }),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                sectionLabel('课表与录播'),
                ScheduleSyncCard(
                  semester: semester,
                  updated: semester == null
                      ? null
                      : data.lastImportFor(semester),
                  demo: demo,
                  onImport: busy ? null : openImport,
                  footer: AppArrowPreference(
                    key: const ValueKey('settings-import-recordings'),
                    title: '导入本学期录播',
                    summary: demo
                        ? '退出示例后可导入本学期录播'
                        : data.courses.isEmpty
                        ? '请先导入本学期课表'
                        : '汇总当前学期课程的轻新课堂录播',
                    startAction: const AppIcon(AppIcons.mediaLibrary),
                    enabled: !busy && !demo && data.courses.isNotEmpty,
                    onClick: importClassroom,
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                QuietCard(
                  cornerRadius: AppRadius.card,
                  insideMargin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      AppArrowPreference(
                        title: '外观设置',
                        summary: '主题、颜色、底栏与界面缩放',
                        startAction: const AppIcon(AppIcons.palette),
                        onClick: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const AppearancePage(),
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: AppSpace.comfortable,
                        endIndent: AppSpace.comfortable,
                        color: colors.outlineVariant,
                      ),
                      AppArrowPreference(
                        key: const ValueKey('privacy-data-entry'),
                        title: '隐私与数据',
                        summary: '退出学校会话、管理本地课表',
                        startAction: const AppIcon(AppIcons.sliders),
                        onClick: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PrivacyDataPage(
                              demo: demo,
                              onScheduleCleared: () => selectTerm(null),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                sectionLabel('校园服务'),
                QuietCard(
                  cornerRadius: AppRadius.card,
                  insideMargin: EdgeInsets.zero,
                  child: AppArrowPreference(
                    title: '图书馆座位预约',
                    summary: '也可从底部“图书馆”栏直接进入',
                    startAction: const AppIcon(AppIcons.book),
                    enabled: !busy && !demo,
                    onClick: () => selectTab(_libraryTab),
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                QuietCard(
                  cornerRadius: AppRadius.card,
                  insideMargin: EdgeInsets.zero,
                  child: AppArrowPreference(
                    key: const ValueKey('project-info-entry'),
                    title: '项目信息',
                    summary: '应用版本、开发者与源代码',
                    startAction: const AppIcon(AppIcons.info),
                    onClick: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProjectInfoPage(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: AppSpace.sm, bottom: AppSpace.md),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
