import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/library_seat_queries.dart';
import '../design/app_tokens.dart';
import '../domain/library_seats.dart';
import '../domain/schedule.dart';
import '../platform/library_seat_reader.dart';
import '../platform/school_adapter.dart';
import 'app_controls.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';
import 'library_seat_page.dart';
import 'quiet_backdrop.dart';

class LibrarySeatQueryPage extends StatefulWidget {
  const LibrarySeatQueryPage({
    super.key,
    this.reader,
    this.now,
    this.officialPageBuilder,
  });

  final LibrarySeatReader? reader;
  final DateTime Function()? now;
  final WidgetBuilder? officialPageBuilder;

  @override
  State<LibrarySeatQueryPage> createState() => _LibrarySeatQueryPageState();
}

class _LibrarySeatQueryPageState extends State<LibrarySeatQueryPage> {
  late final LibrarySeatQueries _queries;
  late DateTime _date, _bookingBegin, _bookingEnd;
  LibraryArea? _area;
  TimeOfDay? _start, _end;
  String? _selected;
  int _bookingPage = 1;
  bool _showBookings = false,
      _openingOfficial = false,
      _onlyAvailable = false;

  DateTime _currentSchoolNow() => (widget.now ?? schoolNow)();
  bool get _busy => _openingOfficial || _queries.submitting;

  @override
  void initState() {
    super.initState();
    _queries = LibrarySeatQueries(widget.reader ?? LibrarySeatReader());
    final today = dateOnly(_currentSchoolNow());
    _date = today;
    _bookingBegin = calendarAdd(today, 1 - today.weekday);
    _bookingEnd = calendarAdd(_bookingBegin, 6);
    SchoolAdapter.sessionChanges.addListener(_sessionCleared);
    if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_loadSeats());
    }
  }

  @override
  void dispose() {
    SchoolAdapter.sessionChanges.removeListener(_sessionCleared);
    _queries.dispose();
    super.dispose();
  }

  void _sessionCleared() {
    if (mounted) {
      setState(() {
        _selected = null;
        _area = null;
        _start = _end = null;
      });
    } else {
      _selected = null;
      _area = null;
      _start = _end = null;
    }
    unawaited(_queries.clearSession());
  }

  Future<void> _loadSeats() async {
    if (mounted && _selected != null) {
      setState(() => _selected = null);
    } else {
      _selected = null;
    }
    final date = _date;
    final selectedArea = await _queries.loadAreaSeats(
      preferredAreaId: _area?.id,
      date: date,
    );
    if (!mounted || _showBookings || _openingOfficial) return;
    if (selectedArea == null || _date != date) return;
    final hadArea = _area?.id == selectedArea.id;
    final opening = _queries.seats
        ?.expand((seat) => seat.hours)
        .firstOrNull;
    setState(() {
      _area = selectedArea;
      if (!hadArea || _start == null || _end == null) {
        if (opening != null) {
          _start = _time(opening.$1);
          _end = _time(opening.$2);
        } else {
          _start = null;
          _end = null;
        }
      }
    });
  }

  static TimeOfDay _time(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;
  static String _clockText(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _loadBookings([int page = 1]) {
    if (_busy) return Future<void>.value();
    _bookingPage = page;
    _selected = null;
    return _queries.loadBookings(_bookingBegin, _bookingEnd, page);
  }

  Future<void> _openBookingsFor(DateTime date, {bool reload = true}) async {
    if (_busy) return;
    final begin = calendarAdd(date, 1 - date.weekday);
    final end = calendarAdd(begin, 6);
    setState(() {
      _showBookings = true;
      _bookingBegin = begin;
      _bookingEnd = end;
      _bookingPage = 1;
      _selected = null;
    });
    if (reload || _queries.bookings == null) {
      await _queries.loadBookings(begin, end, 1);
    }
  }

  Future<void> _official() async {
    if (_busy) return;
    setState(() {
      _openingOfficial = true;
      _selected = null;
      _start = _end = null;
    });
    await _queries.clearSession();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: widget.officialPageBuilder ?? (_) => const LibrarySeatPage(),
      ),
    );
    if (!mounted) return;
    setState(() => _openingOfficial = false);
    await (_showBookings ? _loadBookings(_bookingPage) : _loadSeats());
  }

  Future<void> _selectSeatDate(DateTime date) async {
    if (_busy) return;
    final normalized = dateOnly(date);
    if (normalized == _date && _queries.seats != null && !_queries.failed) {
      return;
    }
    _queries.clearSubmission();
    setState(() {
      _date = normalized;
      _start = _end = null;
      _selected = null;
    });
    await _loadSeats();
  }

  Future<void> _chooseDate() async {
    if (_busy) return;
    final today = dateOnly(_currentSchoolNow());
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: calendarAdd(today, 365),
      helpText: '选择预约日期',
    );
    if (date == null || !mounted) return;
    await _selectSeatDate(date);
  }

  Future<void> _chooseTime(bool start) async {
    if (_busy) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
          (start ? _start : _end) ?? const TimeOfDay(hour: 8, minute: 30),
      helpText: start ? '选择开始时间' : '选择结束时间',
    );
    if (time == null || !mounted) return;
    _queries.clearSubmission();
    setState(() {
      if (start) {
        _start = time;
      } else {
        _end = time;
      }
      _selected = null;
    });
  }

  Future<void> _chooseBookingDates() async {
    if (_busy) return;
    final today = dateOnly(_currentSchoolNow());
    final range = await showDateRangePicker(
      context: context,
      firstDate: calendarAdd(today, -365),
      lastDate: calendarAdd(today, 365),
      initialDateRange: DateTimeRange(start: _bookingBegin, end: _bookingEnd),
      helpText: '选择预约查询范围',
    );
    if (range == null || !mounted) return;
    _bookingBegin = dateOnly(range.start);
    _bookingEnd = dateOnly(range.end);
    await _loadBookings(1);
  }

  void _switch(bool bookings) {
    if (bookings == _showBookings || _busy) return;
    setState(() => _showBookings = bookings);
    unawaited(bookings ? _loadBookings(_bookingPage) : _loadSeats());
  }

  List<String> _ruleLines(LibrarySeat seat) {
    final lines = <String>[];
    if (seat.hours.isNotEmpty) {
      final windows = seat.hours
          .map(
            (h) =>
                '${formatClockMinutes(h.$1)}–${formatClockMinutes(h.$2)}',
          )
          .join('、');
      lines.add('当日开放：$windows');
    }
    final rule = seat.rule;
    if (rule != null) {
      final min = rule.minMinutes;
      final max = rule.maxMinutes;
      if ((min != null && min > 0) || (max != null && max > 0)) {
        final parts = [
          if (min != null && min > 0) '最短 ${formatLibraryDuration(min)}',
          if (max != null && max > 0) '最长 ${formatLibraryDuration(max)}',
        ];
        lines.add('允许时长：${parts.join(' · ')}');
      }
      final earliest = rule.earliestMinutes;
      final latest = rule.latestMinutes;
      if (earliest != null || latest != null) {
        if ((earliest ?? 0) == 0 && (latest ?? 0) == 0) {
          lines.add('提前预约范围：当天');
        } else if (earliest != null && earliest > 0) {
          final latestText = latest != null && latest > 0
              ? '提前 ${formatLibraryDuration(latest)} 至 '
              : '最多提前 ';
          lines.add('提前预约范围：$latestText${formatLibraryDuration(earliest)}');
        }
      }
      final cancel = rule.cancelMinutes;
      if (cancel != null && cancel > 0) {
        lines.add(
          '签到提示：预约生效后 ${formatLibraryDuration(cancel)} 内未签到即视作违约 1 次，预约不再保留',
        );
      }
      if (rule.limitLabels.isNotEmpty) {
        lines.add('规则限制：${rule.limitLabels.join('、')}');
      }
    }
    if (lines.isEmpty) {
      lines.add('适用规则：以学校平台实时校验为准');
    }
    return lines;
  }

  Future<void> _confirmReservation(
    LibrarySeat seat,
    TimeOfDay start,
    TimeOfDay end,
  ) async {
    if (_busy) return;
    final startMin = _minutes(start);
    final endMin = _minutes(end);
    final now = _currentSchoolNow();
    final pastTodayStart =
        _date == dateOnly(now) && startMin < now.hour * 60 + now.minute;
    final durationIssue = seat.rule?.durationViolation(startMin, endMin);
    final blockingReason = pastTodayStart
        ? '开始时间早于当前时间，请先调整开始时间。'
        : durationIssue;
    final area = _area;
    final areaLabel = area?.label ?? '';
    final ruleLines = _ruleLines(seat);
    var confirmed = false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        return AlertDialog(
          title: const Text('确认预约座位'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  areaLabel.isEmpty ? seat.label : '$areaLabel · ${seat.label}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '日期：${isoDate(_date)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: tabularTime,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '时段：${_clockText(start)}–${_clockText(end)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: tabularTime,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Text('适用规则', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpace.xs),
                for (final line in ruleLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
                    child: Text(
                      line,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (blockingReason != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    blockingReason,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.sm),
                Text(
                  '确认后将向学校平台发送一次预约申请，并在“我的预约”中回查结果。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: blockingReason != null
                  ? null
                  : () {
                      if (confirmed) return;
                      confirmed = true;
                      Navigator.of(dialogContext).pop(true);
                    },
              child: const Text('确认提交预约'),
            ),
          ],
        );
      },
    );

    if (proceed != true || !mounted || _busy) return;
    final request = LibraryBookingRequest(
      areaId: area?.id ?? '',
      areaName: area?.name ?? '',
      areaLabel: areaLabel,
      seatId: seat.id,
      seatLabel: seat.label,
      date: _date,
      startMinutes: startMin,
      endMinutes: endMin,
      rule: seat.rule,
    );
    final outcome = await _queries.submitReservation(request);
    if (!mounted || outcome == null) return;
    setState(() => _selected = null);
  }

  String _timeLabel(TimeOfDay? value, String placeholder) =>
      value == null ? placeholder : '$placeholder ${_clockText(value)}';

  LibrarySeatStatus _seatStatus(
    LibrarySeat seat,
    TimeOfDay? start,
    TimeOfDay? end,
  ) {
    if (start != null && end != null && _minutes(start) < _minutes(end)) {
      return seat.statusOn(_date, _minutes(start), _minutes(end));
    }
    return seat.viewOnly
        ? LibrarySeatStatus.viewOnly
        : LibrarySeatStatus.closed;
  }

  String _statusLabel(LibrarySeatStatus status) => switch (status) {
    LibrarySeatStatus.available => '空闲',
    LibrarySeatStatus.partial => '半空闲',
    LibrarySeatStatus.occupied => '使用中',
    LibrarySeatStatus.closed => '不开放',
    LibrarySeatStatus.viewOnly => '仅查看',
  };

  Color _statusColor(ColorScheme colors, LibrarySeatStatus status) =>
      switch (status) {
        LibrarySeatStatus.available => colors.primary,
        LibrarySeatStatus.partial => colors.tertiary,
        LibrarySeatStatus.occupied => colors.error,
        LibrarySeatStatus.closed ||
        LibrarySeatStatus.viewOnly => colors.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final body = defaultTargetPlatform == TargetPlatform.android
        ? ListenableBuilder(
            listenable: _queries,
            builder: (_, _) => _content(context),
          )
        : const Center(child: Text('座位预约目前支持 Android。'));
    return QuietBackdrop(
      tab: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('图书馆座位预约'),
          leading: IconButton(
            tooltip: '返回',
            icon: const AppIcon(AppIcons.arrowBack),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: SafeArea(top: false, child: body),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final seats = _queries.seats;
    final page = _queries.bookings;
    final start = _start, end = _end;
    final hasValidRange =
        start != null && end != null && _minutes(start) < _minutes(end);

    final seatItems = <(LibrarySeat, LibrarySeatStatus)>[];
    var availableCount = 0;
    var partialCount = 0;
    var occupiedCount = 0;
    var unavailableCount = 0;
    LibrarySeat? selectedSeat;

    if (!_showBookings && seats != null) {
      for (final seat in seats) {
        final status = _seatStatus(seat, start, end);
        switch (status) {
          case LibrarySeatStatus.available:
            availableCount++;
          case LibrarySeatStatus.partial:
            partialCount++;
          case LibrarySeatStatus.occupied:
            occupiedCount++;
          case LibrarySeatStatus.closed:
          case LibrarySeatStatus.viewOnly:
            unavailableCount++;
        }
        if (seat.id == _selected && status == LibrarySeatStatus.available) {
          selectedSeat = seat;
        }
        if (!_onlyAvailable || status == LibrarySeatStatus.available) {
          seatItems.add((seat, status));
        }
      }
    }

    return CustomScrollView(
      key: PageStorageKey(_showBookings ? 'library_bookings' : 'library_seats'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            AppSpace.md,
          ),
          sliver: SliverList.list(
            children: [
              QuietCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: AppSpace.sm,
                        runSpacing: AppSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ChoiceChip(
                            label: const Text('选座'),
                            selected: !_showBookings,
                            onSelected: _busy ? null : (_) => _switch(false),
                          ),
                          ChoiceChip(
                            label: const Text('我的预约'),
                            selected: _showBookings,
                            onSelected: _busy ? null : (_) => _switch(true),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                AppLayout.minTap,
                                AppLayout.minTap,
                              ),
                            ),
                            onPressed: _busy ? null : _official,
                            child: Text(
                              _queries.needsLogin ? '打开学校页面登录' : '学校预约网页',
                            ),
                          ),
                        ],
                      ),
                      if (_queries.loading || _queries.submitting) ...[
                        const SizedBox(height: AppSpace.md),
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                        if (_queries.submitting) ...[
                          const SizedBox(height: AppSpace.sm),
                          Text(
                            '正在核对余位并提交预约…',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              if (_queries.submission != null) ...[
                const SizedBox(height: AppSpace.md),
                _submissionCard(context, _queries.submission!),
              ],
              if (_queries.sessionCleared &&
                  !_queries.loading &&
                  !_queries.needsLogin &&
                  !_queries.failed) ...[
                const SizedBox(height: AppSpace.md),
                _statusCard(
                  context,
                  title: '学校会话已清除',
                  detail: '请打开学校页面登录，或刷新后重新查询。',
                  actions: [
                    AppActionButton(
                      label: '打开学校页面登录',
                      icon: AppIcons.chevronRight,
                      onPressed: _busy ? null : _official,
                    ),
                    AppActionButton(
                      label: '刷新',
                      icon: AppIcons.refresh,
                      outlined: true,
                      onPressed: _busy
                          ? null
                          : () => _showBookings
                                ? _loadBookings(_bookingPage)
                                : _loadSeats(),
                    ),
                  ],
                ),
              ],
              if (_queries.needsLogin &&
                  _queries.submission?.kind !=
                      LibrarySubmissionKind.authInterrupted) ...[
                const SizedBox(height: AppSpace.md),
                _statusCard(
                  context,
                  title: '需要登录学校账号',
                  detail: '请在学校官方页面完成认证，返回应用后将自动重新查询。',
                  isError: false,
                  actions: [
                    AppActionButton(
                      label: '打开学校页面登录',
                      icon: AppIcons.chevronRight,
                      onPressed: _busy ? null : _official,
                    ),
                  ],
                ),
              ],
              if (_queries.failed) ...[
                const SizedBox(height: AppSpace.md),
                _statusCard(
                  context,
                  title: '查询未完成',
                  detail: '未能读取学校座位或预约数据，请检查网络后重试，或打开学校预约网页查看。',
                  isError: true,
                  actions: [
                    AppActionButton(
                      label: '重试查询',
                      icon: AppIcons.refresh,
                      onPressed: _queries.loading || _busy
                          ? null
                          : () => _showBookings
                                ? _loadBookings(_bookingPage)
                                : _loadSeats(),
                    ),
                    AppActionButton(
                      label: '打开学校预约网页',
                      icon: AppIcons.chevronRight,
                      outlined: true,
                      onPressed: _busy ? null : _official,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpace.md),
              if (_showBookings)
                _bookingControlsCard(context)
              else
                _seatControlsCard(
                  context,
                  seats: seats,
                  availableCount: availableCount,
                  partialCount: partialCount,
                  occupiedCount: occupiedCount,
                  unavailableCount: unavailableCount,
                ),
              if (!_showBookings && selectedSeat != null && hasValidRange) ...[
                const SizedBox(height: AppSpace.md),
                _selectedBanner(context, selectedSeat, start, end),
              ],
              if (!_showBookings &&
                  seats != null &&
                  seats.isNotEmpty &&
                  _onlyAvailable &&
                  seatItems.isEmpty) ...[
                const SizedBox(height: AppSpace.md),
                QuietCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Text(
                      '当前时段暂无空闲座位',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!_showBookings && seatItems.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(bottom: AppSpace.xxl),
            sliver: SliverList.builder(
              itemCount: seatItems.length,
              itemBuilder: (_, index) {
                final (seat, status) = seatItems[index];
                return _seatRow(
                  context,
                  seat,
                  status,
                  start: start,
                  end: end,
                  hasValidRange: hasValidRange,
                );
              },
            ),
          ),
        if (_showBookings && page != null)
          SliverPadding(
            padding: const EdgeInsets.only(bottom: AppSpace.xxl),
            sliver: SliverList.builder(
              itemCount: page.rows.length,
              itemBuilder: (_, index) => _bookingRow(context, page.rows[index]),
            ),
          ),
      ],
    );
  }

  Widget _statusCard(
    BuildContext context, {
    required String title,
    required String detail,
    required List<Widget> actions,
    bool isError = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isError ? colors.error : colors.primary,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _seatControlsCard(
    BuildContext context, {
    required List<LibrarySeat>? seats,
    required int availableCount,
    required int partialCount,
    required int occupiedCount,
    required int unavailableCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final List<LibraryArea> areas = _queries.areas ?? const [];
    final start = _start, end = _end;
    final invalidTimes =
        start != null && end != null && _minutes(start) >= _minutes(end);
    final today = dateOnly(_currentSchoolNow());
    final tomorrow = calendarAdd(today, 1);

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (areas.isNotEmpty) ...[
              DropdownButtonFormField<LibraryArea>(
                key: ValueKey(_area?.id),
                initialValue: areas.contains(_area) ? _area : areas.first,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '座位区域'),
                items: areas
                    .map(
                      (area) => DropdownMenuItem(
                        value: area,
                        child: Text(area.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (area) {
                        if (area == null) return;
                        _queries.clearSubmission();
                        setState(() {
                          _area = area;
                          _start = _end = null;
                          _selected = null;
                        });
                        unawaited(_loadSeats());
                      },
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (_queries.areas?.isEmpty == true) ...[
              Text(
                '暂无座位区域',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('今天'),
                  selected: _date == today,
                  onSelected: _busy
                      ? null
                      : (_) => unawaited(_selectSeatDate(today)),
                ),
                ChoiceChip(
                  label: const Text('明天'),
                  selected: _date == tomorrow,
                  onSelected: _busy
                      ? null
                      : (_) => unawaited(_selectSeatDate(tomorrow)),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _chooseDate,
                  child: Text(isoDate(_date)),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _chooseTime(true),
                  child: Text(_timeLabel(start, '开始')),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _chooseTime(false),
                  child: Text(_timeLabel(end, '结束')),
                ),
                FilterChip(
                  label: const Text('仅看空闲'),
                  selected: _onlyAvailable,
                  onSelected: _busy
                      ? null
                      : (value) => setState(() => _onlyAvailable = value),
                ),
                AppActionButton(
                  label: '刷新座位',
                  icon: AppIcons.refresh,
                  onPressed: _queries.loading || _busy
                      ? null
                      : () {
                          _queries.clearSubmission();
                          unawaited(_loadSeats());
                        },
                ),
              ],
            ),
            if (invalidTimes) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '结束时间须晚于开始时间。',
                style: theme.textTheme.bodyMedium?.copyWith(color: colors.error),
              ),
            ] else if (seats != null &&
                seats.isNotEmpty &&
                (start == null || end == null)) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '所选日期暂无开放时段。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (seats?.isEmpty == true) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                '该日期暂无座位',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            if (seats != null && seats.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(
                '共 ${seats.length} 个座位 · 空闲 $availableCount · 半空闲 $partialCount · 使用中 $occupiedCount · 不可用 $unavailableCount',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _submissionCard(BuildContext context, LibrarySubmissionState state) {
    final request = state.request;
    final slot =
        '${request.areaLabel.isEmpty ? request.seatLabel : '${request.areaLabel} · ${request.seatLabel}'} · '
        '${request.beginTimestamp}–${formatClockMinutes(request.endMinutes)}';
    switch (state.kind) {
      case LibrarySubmissionKind.confirmed:
        final booking = state.booking!;
        final labels = libraryBookingStatusLabels(booking.status);
        final statusText = labels.isEmpty ? '已登记' : labels.join(' · ');
        return _statusCard(
          context,
          title: '预约已核对',
          detail:
              '${booking.room.isEmpty ? booking.seat : '${booking.room} · ${booking.seat}'}'
              '（${booking.begin} 至 ${booking.end}）\n状态：$statusText · 预约编号 ${booking.id}',
          actions: [
            AppActionButton(
              label: '查看“我的预约”',
              icon: AppIcons.chevronRight,
              onPressed: _busy
                  ? null
                  : () => _openBookingsFor(request.date, reload: false),
            ),
            AppActionButton(
              label: '继续浏览座位',
              icon: AppIcons.refresh,
              outlined: true,
              onPressed: _busy ? null : _queries.clearSubmission,
            ),
          ],
        );
      case LibrarySubmissionKind.submittedUnverified:
        final idNote =
            state.bookingId.isEmpty ? '' : '（编号 ${state.bookingId}）';
        return _statusCard(
          context,
          title: '已提交预约，请核对“我的预约”',
          detail:
              '学校已接收 $slot 的预约请求$idNote，但自动回查暂未确认记录。为避免重复预约，系统不会自动重发。',
          actions: [
            AppActionButton(
              label: '去“我的预约”查单',
              icon: AppIcons.chevronRight,
              onPressed: _busy ? null : () => _openBookingsFor(request.date),
            ),
            AppActionButton(
              label: '打开学校预约网页',
              icon: AppIcons.chevronRight,
              outlined: true,
              onPressed: _busy ? null : _official,
            ),
          ],
        );
      case LibrarySubmissionKind.availabilityChanged:
        return _statusCard(
          context,
          title: '余位已变化，未提交预约',
          detail:
              '提交前复核显示 $slot 在所选时段已不可预约，已为你刷新最新座位列表，未向学校发送预约请求。',
          isError: true,
          actions: [
            AppActionButton(
              label: '关闭提示',
              icon: AppIcons.check,
              outlined: true,
              onPressed: _queries.clearSubmission,
            ),
          ],
        );
      case LibrarySubmissionKind.rejected:
        final schoolMsg = state.message.isEmpty
            ? '学校平台未接受本次预约申请。'
            : '学校返回：${state.message}。';
        return _statusCard(
          context,
          title: '学校平台未受理预约',
          detail: '$schoolMsg 已停止本次申请，不会自动重发；可核对余位或“我的预约”。',
          isError: true,
          actions: [
            AppActionButton(
              label: '去“我的预约”确认',
              icon: AppIcons.chevronRight,
              outlined: true,
              onPressed: _busy ? null : () => _openBookingsFor(request.date),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
              ),
              onPressed: _queries.clearSubmission,
              child: const Text('关闭'),
            ),
          ],
        );
      case LibrarySubmissionKind.webRequired:
        final reasonText = switch (state.reason) {
          'captcha' => '当前学校系统启用了预约验证码',
          'notice' => '当前区域要求确认预约须知',
          'theme' => '当前区域要求填写预约主题',
          'memo' => '当前区域要求填写预约备注',
          _ => '当前学校规则要求在官方网页确认步骤',
        };
        return _statusCard(
          context,
          title: '需要前往学校网页完成确认',
          detail: '$reasonText，请打开学校预约网页继续操作；原生端尚未发送写入请求。',
          actions: [
            AppActionButton(
              label: '打开学校预约网页',
              icon: AppIcons.chevronRight,
              onPressed: _busy ? null : _official,
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
              ),
              onPressed: _queries.clearSubmission,
              child: const Text('关闭'),
            ),
          ],
        );
      case LibrarySubmissionKind.precheckFailed:
        return _statusCard(
          context,
          title: '未完成提交前核验，已停止提交',
          detail: '未能读取学校最新余位或规则配置，本次尚未发送预约请求。请检查网络后重试，或打开学校预约网页查看。',
          isError: true,
          actions: [
            AppActionButton(
              label: '刷新座位',
              icon: AppIcons.refresh,
              onPressed: _busy
                  ? null
                  : () {
                      _queries.clearSubmission();
                      unawaited(_loadSeats());
                    },
            ),
            AppActionButton(
              label: '打开学校预约网页',
              icon: AppIcons.chevronRight,
              outlined: true,
              onPressed: _busy ? null : _official,
            ),
          ],
        );
      case LibrarySubmissionKind.authInterrupted:
        return _statusCard(
          context,
          title: '登录状态已中断，已停止本次提交',
          detail: '学校认证已过期或中断，已清空当前数据。请重新登录后先核对“我的预约”与座位状态；系统不会自动重发写请求。',
          actions: [
            AppActionButton(
              label: '打开学校页面登录',
              icon: AppIcons.chevronRight,
              onPressed: _busy ? null : _official,
            ),
          ],
        );
      case LibrarySubmissionKind.uncertain:
        return _statusCard(
          context,
          title: '提交结果暂不明确，请先查单',
          detail: '请求可能已送达学校但响应超时或连接中断。为避免重复预约，系统禁止自动重发，请先到“我的预约”核对。',
          isError: true,
          actions: [
            AppActionButton(
              label: '去“我的预约”查单',
              icon: AppIcons.chevronRight,
              onPressed: _busy ? null : () => _openBookingsFor(request.date),
            ),
            AppActionButton(
              label: '打开学校预约网页',
              icon: AppIcons.chevronRight,
              outlined: true,
              onPressed: _busy ? null : _official,
            ),
          ],
        );
    }
  }

  Widget _selectedBanner(
    BuildContext context,
    LibrarySeat seat,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final rules = _ruleLines(seat);
    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppIcon(
                  AppIcons.check,
                  size: AppControl.icon,
                  color: colors.primary,
                ),
                Text(
                  '已选候选座位',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(AppLayout.minTap, AppLayout.minTap),
                  ),
                  onPressed: _busy ? null : () => setState(() => _selected = null),
                  child: const Text('清除选择'),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              _area == null ? seat.label : '${_area!.label} · ${seat.label}',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${isoDate(_date)} ${_clockText(start)}–${_clockText(end)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: tabularTime,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            for (final line in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpace.md),
            AppActionButton(
              label: '确认预约',
              icon: AppIcons.check,
              onPressed: _busy
                  ? null
                  : () => _confirmReservation(seat, start, end),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seatRow(
    BuildContext context,
    LibrarySeat seat,
    LibrarySeatStatus status, {
    required TimeOfDay? start,
    required TimeOfDay? end,
    required bool hasValidRange,
  }) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final selected =
        _selected == seat.id && status == LibrarySeatStatus.available;
    final canSelect = status == LibrarySeatStatus.available;
    final label = _statusLabel(status);
    final statusColor = _statusColor(colors, status);
    final overlaps =
        hasValidRange &&
            (status == LibrarySeatStatus.partial ||
                status == LibrarySeatStatus.occupied)
        ? seat.overlappingReservations(
            _date,
            _minutes(start!),
            _minutes(end!),
          )
        : const <LibraryInterval>[];
    final detailText = overlaps.isNotEmpty
        ? '已约 ${overlaps.map(formatLibraryInterval).join('、')}'
        : status == LibrarySeatStatus.closed && seat.hours.isNotEmpty
        ? '开放 ${seat.hours.map((h) => '${formatClockMinutes(h.$1)}–${formatClockMinutes(h.$2)}').join('、')}'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: Semantics(
        button: canSelect,
        selected: selected,
        enabled: canSelect,
        child: CourseSurface(
          radius: AppRadius.input,
          color: selected
              ? colors.primaryContainer.withValues(alpha: .55)
              : null,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.input),
              onTap: canSelect && !_busy
                  ? () {
                      _queries.clearSubmission();
                      setState(() => _selected = selected ? null : seat.id);
                    }
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppLayout.minTap),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg,
                    vertical: AppSpace.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              seat.label,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpace.xs),
                            Text(
                              selected ? '已选 · $label' : label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: statusColor,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                            if (detailText != null) ...[
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                detailText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontFeatures: tabularTime,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (selected) ...[
                        const SizedBox(width: AppSpace.sm),
                        AppIcon(
                          AppIcons.check,
                          size: AppControl.icon,
                          color: colors.primary,
                          semanticLabel: '已选中',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingControlsCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final page = _queries.bookings;
    final begin = isoDate(_bookingBegin), end = isoDate(_bookingEnd);
    final disabled = _queries.loading || _busy;
    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _chooseBookingDates,
                  child: Text('$begin 至 $end'),
                ),
                AppActionButton(
                  label: '刷新预约',
                  icon: AppIcons.refresh,
                  onPressed: disabled ? null : () => _loadBookings(_bookingPage),
                ),
              ],
            ),
            if (page != null) ...[
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '第 ${page.page} 页 · 共 ${page.totalCount} 条',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: tabularTime,
                    ),
                  ),
                  if (page.page > 1)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppLayout.minTap,
                          AppLayout.minTap,
                        ),
                      ),
                      onPressed: disabled
                          ? null
                          : () => _loadBookings(page.page - 1),
                      child: const Text('上一页'),
                    ),
                  if (page.hasMore)
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(
                          AppLayout.minTap,
                          AppLayout.minTap,
                        ),
                      ),
                      onPressed: disabled
                          ? null
                          : () => _loadBookings(page.page + 1),
                      child: const Text('下一页'),
                    ),
                ],
              ),
              if (page.rows.isEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Text(
                  page.page == 1 && !page.hasMore ? '暂无座位预约' : '本页无座位预约',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _bookingRow(BuildContext context, LibraryBooking row) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final labels = libraryBookingStatusLabels(row.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        0,
        AppSpace.lg,
        AppSpace.sm,
      ),
      child: QuietCard(
        cornerRadius: AppRadius.input,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.room.isEmpty ? row.seat : '${row.room} · ${row.seat}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                '${row.begin} 至 ${row.end}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFeatures: tabularTime,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                labels.isEmpty
                    ? '预约编号 ${row.id}'
                    : '${labels.join(' · ')} · 预约编号 ${row.id}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: tabularTime,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
