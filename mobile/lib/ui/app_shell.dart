import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_miuix/miuix.dart';
import '../application/schedule_controller.dart';
import '../application/appearance_controller.dart';
import '../data/demo_schedule.dart';
import '../domain/schedule.dart';
import '../platform/school_adapter.dart';
import 'course_widgets.dart';
import 'import_page.dart';
import 'week_grid.dart';
import 'weekday_tabs.dart';
import 'glass_navigation.dart';
import 'appearance_page.dart';
import 'project_info_page.dart';
import 'classroom_import_page.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int tab = 0, week = 0, day = schoolNow().weekday;
  bool daily = false, demo = false, busy = false;
  double tabDrag = 0;
  String? selectedSemester;
  DateTime now = schoolNow();
  late final Timer ticker;
  final scrollBehaviors = List.generate(
    3,
    (_) => miuixScrollBehavior(snapOnRelease: false),
  );
  final pageControllers = List.generate(3, (_) => ScrollController());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => now = schoolNow());
    });
  }

  @override
  void dispose() {
    ticker.cancel();
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
      setState(() => now = schoolNow());
    }
  }

  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  void selectTerm(String? value) => setState(() {
    selectedSemester = value;
    week = 0;
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
    final imported = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ImportPage()));
    if (mounted && imported != null) {
      selectTerm(imported);
      message('课表已保存，可以离线查看');
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
        topBar: MiuixTopAppBar(
          key: ValueKey('topbar-$tab'),
          title: ['今日', '课表', '设置'][tab],
          scrollBehavior: scrollBehaviors[tab],
          blurred: appearance.blur && !MediaQuery.highContrastOf(context),
          blurRadius: 44,
          blurTintAlpha: Theme.of(context).brightness == Brightness.dark
              ? .82
              : .72,
          actions: [
            if (demo)
              TextButton(
                onPressed: () => setState(() {
                  demo = false;
                  week = 0;
                  selectedSemester = null;
                }),
                child: const Text('退出示例'),
              ),
            if (!demo && stored.hasValue && tab != 2)
              Tooltip(
                message: '导入或刷新课表',
                child: MiuixIconButton(
                  minWidth: 48,
                  minHeight: 48,
                  onPressed: openImport,
                  child: const Icon(Icons.sync_outlined),
                ),
              ),
            if (!demo && stored.hasValue && tab == 1)
              Tooltip(
                message: '统一导入录播',
                child: MiuixIconButton(
                  key: const ValueKey('classroom-import-button'),
                  minWidth: 48,
                  minHeight: 48,
                  onPressed: importClassroom,
                  child: const Icon(Icons.video_library_outlined),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
        content: (insets) => MiuixScrollBehaviorListener(
          key: ValueKey('scroll-page-$tab'),
          behavior: scrollBehaviors[tab],
          child: GestureDetector(
            onHorizontalDragStart: appearance.swipePages
                ? (_) => tabDrag = 0
                : null,
            onHorizontalDragUpdate: appearance.swipePages
                ? (event) => tabDrag += event.delta.dx
                : null,
            onHorizontalDragEnd: appearance.swipePages
                ? (event) {
                    final velocity = event.primaryVelocity ?? 0;
                    if (tabDrag.abs() > 64 || velocity.abs() > 450) {
                      final direction = tabDrag.abs() > 16 ? tabDrag : velocity;
                      setState(
                        () =>
                            tab = (tab + (direction < 0 ? 1 : -1)).clamp(0, 2),
                      );
                    }
                  }
                : null,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: stored.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: '正在读取本地课表',
                    ),
                  ),
                  error: (error, stack) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('本地课表暂时无法读取。文件已保留，请重试。'),
                        const SizedBox(height: 16),
                        MiuixButton(
                          colors: MiuixButtonDefaults.buttonColorsPrimary(
                            context,
                          ),
                          onPressed: () => ref.invalidate(scheduleProvider),
                          child: const Text('重新读取'),
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
                    return tab == 2
                        ? settings(data, insets)
                        : courses.isEmpty
                        ? ListView(
                            key: PageStorageKey('empty-page-$tab'),
                            controller: pageControllers[tab],
                            padding: pagePadding(insets),
                            children: [
                              EmptySchedule(
                                onImport: openImport,
                                onDemo: startDemo,
                              ),
                            ],
                          )
                        : tab == 0
                        ? home(data, courses, semester!, insets)
                        : timetable(data, courses, semester!, insets);
                  },
                ),
              ),
            ),
          ),
        ),
        bottomBar: GlassNavigation(
          selected: tab,
          onSelect: (value) => setState(() => tab = value),
        ),
      ),
    );
  }

  EdgeInsets pagePadding(EdgeInsets insets, {double horizontal = 24}) =>
      EdgeInsets.fromLTRB(
        horizontal + insets.left,
        insets.top + 12,
        horizontal + insets.right,
        insets.bottom + 32,
      );

  Widget demoNotice() => Padding(
    padding: const EdgeInsets.only(bottom: 16),
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
          icon: const Icon(Icons.expand_more),
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

  Widget home(
    ScheduleData data,
    List<Course> courses,
    String semester,
    EdgeInsets insets,
  ) {
    final today = occurrencesOn(courses, now);
    final next = nextOccurrences(courses, now).firstOrNull;
    final current = today.where((e) => e.activeAt(now)).length;
    final colors = Theme.of(context).colorScheme;
    return ListView(
      key: const PageStorageKey('today-page'),
      controller: pageControllers[0],
      padding: pagePadding(insets),
      children: [
        if (demo) demoNotice(),
        Text(
          '${shortDate(now)}，星期${weekdays[now.weekday - 1]}',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge!.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        termSelector(data, semester),
        const SizedBox(height: 16),
        if (next != null)
          MiuixCard(
            cornerRadius: 28,
            insideMargin: const EdgeInsets.all(24),
            onPressed: () =>
                showCourseDetails(context, next.course, date: next.date),
            child: DefaultTextStyle(
              style: Theme.of(
                context,
              ).textTheme.bodyLarge!.copyWith(color: colors.onSurface),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    next.activeAt(now)
                        ? '正在上课${current > 1 ? '，有$current门课程重叠' : ''}'
                        : '下一节课',
                  ),
                  const SizedBox(height: 20),
                  Text(
                    next.segment.start,
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    next.activeAt(now)
                        ? '${next.segment.end} 下课'
                        : next.start.difference(now).inMinutes < 60
                        ? '${next.start.difference(now).inMinutes + 1}分钟内开始'
                        : '${shortDate(next.date)}，周${weekdays[next.date.weekday - 1]}',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    next.course.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(courseLocation(next.course)),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
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
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('今天没有排课，留一点时间给自己。'),
          ),
        for (final (index, event) in today.indexed)
          CourseRow(
            event: event,
            colorIndex: index % 5,
            now: now,
            conflict: today.any(
              (other) =>
                  other != event &&
                  other.course.id != event.course.id &&
                  event.overlaps(other),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          data.isDemo
              ? '所有课程均为合成示例'
              : '已保存到本机${data.importedAt == null ? '' : '，最近导入 ${shortDate(data.importedAt!)}'}',
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
          SizedBox(
            width: 116,
            child: MiuixTabRow(
              tabs: const ['周', '日'],
              minWidth: 46,
              maxWidth: 46,
              itemSpacing: 4,
              selectedTabIndex: daily ? 1 : 0,
              onTabSelected: (value) => setState(() => daily = value == 1),
            ),
          ),
        ],
      ),
      Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed: selectedWeek > 1
                ? () => setState(() => week = selectedWeek - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '第 $selectedWeek 周',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${monday.month}/${monday.day} – ${calendarAdd(monday, 6).month}/${calendarAdd(monday, 6).day}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              week = currentWeek.clamp(1, maximum);
              day = now.weekday;
            }),
            child: const Text('本周'),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: selectedWeek < maximum
                ? () => setState(() => week = selectedWeek + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      if (currentWeek < 1 || currentWeek > maximum)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('当前日期不在已导入的教学周范围内'),
        ),
    ];
    if (daily) {
      return ListView(
        key: const PageStorageKey('timetable-page'),
        controller: pageControllers[1],
        padding: pagePadding(insets),
        children: [
          ...header,
          const SizedBox(height: 16),
          WeekdayTabs(
            day: day,
            onSelected: (value) => setState(() => day = value),
          ),
          const SizedBox(height: 24),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('这一天没有排课')),
            ),
          for (final (index, event) in events.indexed)
            CourseRow(
              event: event,
              colorIndex: index % 5,
              conflict: events.any(
                (other) => other != event && event.overlaps(other),
              ),
            ),
        ],
      );
    }
    final padding = pagePadding(insets, horizontal: 8);
    return CustomScrollView(
      key: const PageStorageKey('timetable-page'),
      controller: pageControllers[1],
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            padding.left + 8,
            padding.top,
            padding.right + 8,
            4,
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
                  child: WeekGrid(
                    courses: courses,
                    monday: monday,
                    today: now,
                    onSelectDay: (value) => setState(() {
                      day = value;
                      daily = true;
                    }),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget settings(ScheduleData data, EdgeInsets insets) => ListView(
    key: const PageStorageKey('settings-page'),
    controller: pageControllers[2],
    padding: pagePadding(insets),
    children: [
      sectionLabel('外观'),
      MiuixCard(
        cornerRadius: 24,
        insideMargin: EdgeInsets.zero,
        child: MiuixArrowPreference(
          title: '外观设置',
          summary: '主题、颜色、底栏与界面缩放',
          startAction: const Icon(Icons.palette_outlined),
          onClick: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AppearancePage()),
          ),
        ),
      ),
      const SizedBox(height: 24),
      sectionLabel('轻新课堂'),
      MiuixCard(
        cornerRadius: 24,
        insideMargin: EdgeInsets.zero,
        child: MiuixArrowPreference(
          title: '统一导入录播',
          summary: '当前学期课表课程 · 导入后直接查看列表',
          startAction: const Icon(Icons.video_library_outlined),
          enabled: !busy && !demo && data.courses.isNotEmpty,
          onClick: importClassroom,
        ),
      ),
      const SizedBox(height: 24),
      sectionLabel('登录与隐私'),
      MiuixCard(
        cornerRadius: 24,
        insideMargin: EdgeInsets.zero,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '密码只在学校官方页面输入。应用不保存密码，不上传课表。学校会话失效后，需要你重新登录。',
                style: TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
            MiuixArrowPreference(
              title: '退出学校会话',
              summary: '保留离线课表，清除录播目录',
              enabled: !busy,
              startAction: const Icon(Icons.logout),
              onClick: () async {
                if (!await confirm('退出学校会话？', '将清除学校网页会话和已导入的录播目录，离线课表继续保留。')) {
                  return;
                }
                await runAction(() async {
                  await SchoolAdapter().clearSession();
                  if (mounted) message('已清除本机学校会话');
                });
              },
            ),
            MiuixArrowPreference(
              title: '清空本地课表',
              summary: '删除所有学期的本地课程',
              startAction: const Icon(Icons.delete_outline),
              enabled: !busy && !demo && data.courses.isNotEmpty,
              onClick: () async {
                if (!await confirm('清空本地课表？', '将删除所有学期的本地课程。之后可以重新从学校导入。')) {
                  return;
                }
                await runAction(() async {
                  await ref.read(scheduleProvider.notifier).clear();
                  if (mounted) {
                    selectTerm(null);
                    message('已清空本地课表');
                  }
                });
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      MiuixCard(
        cornerRadius: 24,
        insideMargin: EdgeInsets.zero,
        child: MiuixArrowPreference(
          key: const ValueKey('project-info-entry'),
          title: '项目信息',
          summary: '应用版本、开发者与源代码',
          startAction: const Icon(Icons.info_outline),
          onClick: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ProjectInfoPage()),
          ),
        ),
      ),
    ],
  );

  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
