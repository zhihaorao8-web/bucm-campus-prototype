import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/schedule_controller.dart';
import '../design/app_tokens.dart';
import '../domain/schedule.dart';
import 'app_controls.dart';
import 'app_icons.dart';
import 'course_widgets.dart';
import 'quiet_backdrop.dart';

class ScheduleSearchPage extends ConsumerStatefulWidget {
  const ScheduleSearchPage({
    super.key,
    required this.semester,
    required this.hasRecordings,
    required this.onImport,
    this.demoData,
  });

  final String? semester;
  final bool Function(Course) hasRecordings;
  final VoidCallback onImport;
  final ScheduleData? demoData;

  @override
  ConsumerState<ScheduleSearchPage> createState() => _ScheduleSearchPageState();
}

class _ScheduleSearchPageState extends ConsumerState<ScheduleSearchPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _queryChanged() {
    if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final demoData = widget.demoData;
    final stored = demoData == null
        ? ref.watch(scheduleProvider)
        : AsyncData(demoData);
    return QuietBackdrop(
      tab: 1,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('学期内找课'),
          centerTitle: false,
          leading: IconButton(
            tooltip: '返回课表',
            icon: const AppIcon(AppIcons.arrowBack),
            onPressed: () => Navigator.maybePop(context),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          top: false,
          child: stored.when(
            data: _body,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _emptySchedule(unreadable: true),
          ),
        ),
      ),
    );
  }

  Widget _body(ScheduleData data) {
    final semester = widget.semester ?? data.semesters.firstOrNull;
    final courses = data.courses.where((c) => c.semester == semester).toList();
    if (semester == null || courses.isEmpty) return _emptySchedule();

    final now = schoolNow();
    final query = _input.text;
    final matches = searchCourseOccurrences(
      courses,
      semester: semester,
      query: query,
      now: now,
    ).entries.toList();
    final inset =
        MediaQuery.textScalerOf(context).scale(AppType.body) >
            AppType.body * 1.5
        ? AppSpace.lg
        : AppLayout.pageInset;
    final theme = Theme.of(context);
    return CustomScrollView(
      key: const ValueKey('course-search-results'),
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, AppSpace.xs, inset, AppSpace.lg),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _searchInput(theme, query),
                const SizedBox(height: AppSpace.sm),
                Text(
                  data.isDemo ? '$semester 学期 · 合成示例' : '$semester 学期',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (query.trim().isNotEmpty && matches.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(inset, AppSpace.lg, inset, inset),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('未找到匹配的课程', style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpace.sm),
                  const Text('试试更短的课名'),
                ],
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(inset, 0, inset, AppSpace.lg),
          sliver: SliverList.builder(
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final date = matches[index].key;
              final matchingEvents = matches[index].value;
              final week = matchingEvents.first.course.weekAt(date);
              final ended = matchingEvents.every(
                (event) => !event.end.isAfter(now),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        '${shortDate(date)} 周${weekdays[date.weekday - 1]}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      ended ? '第 $week 周 · 已结束' : '第 $week 周',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    ...scheduleDayCourseRows(
                      occurrencesOn(courses, date),
                      now: now,
                      hasRecordings: widget.hasRecordings,
                      matchingCourses: matchingEvents
                          .map((event) => event.course)
                          .toSet(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _searchInput(ThemeData theme, String query) {
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.input),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return TextField(
      key: const ValueKey('course-search-input'),
      controller: _input,
      focusNode: _focus,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: (_) => _queryChanged(),
      decoration: InputDecoration(
        hintText: '输入课程名',
        filled: true,
        fillColor: colors.surfaceContainerLow,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.all(AppSpace.md),
        prefixIcon: const Padding(
          padding: EdgeInsets.all(AppSpace.md),
          child: AppIcon(AppIcons.search, size: AppControl.icon),
        ),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: '清空课程名',
                icon: const AppIcon(AppIcons.close, size: AppControl.icon),
                onPressed: () {
                  _input.clear();
                  _queryChanged();
                  _focus.requestFocus();
                },
              ),
      ),
    );
  }

  Widget _emptySchedule({bool unreadable = false}) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AppLayout.pageInset),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AppIcon(
            AppIcons.calendar,
            color: theme.colorScheme.primary,
            size: AppLayout.minTap,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          unreadable ? '课表暂时无法读取' : '尚未导入课表',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpace.sm),
        const Text('导入课表后，即可离线搜索课程。'),
        const SizedBox(height: AppSpace.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: AppActionButton(
            label: '从学校导入课表',
            icon: AppIcons.sync,
            onPressed: widget.onImport,
          ),
        ),
      ],
    );
  }
}
