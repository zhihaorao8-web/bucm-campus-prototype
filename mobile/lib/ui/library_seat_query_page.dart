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
    _bookingPage = page;
    _selected = null;
    return _queries.loadBookings(_bookingBegin, _bookingEnd, page);
  }

  Future<void> _official() async {
    if (_openingOfficial) return;
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
    final normalized = dateOnly(date);
    if (normalized == _date && _queries.seats != null && !_queries.failed) {
      return;
    }
    setState(() {
      _date = normalized;
      _start = _end = null;
      _selected = null;
    });
    await _loadSeats();
  }

  Future<void> _chooseDate() async {
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
    final time = await showTimePicker(
      context: context,
      initialTime:
          (start ? _start : _end) ?? const TimeOfDay(hour: 8, minute: 30),
      helpText: start ? '选择开始时间' : '选择结束时间',
    );
    if (time == null || !mounted) return;
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
    if (bookings == _showBookings || _openingOfficial) return;
    setState(() => _showBookings = bookings);
    unawaited(bookings ? _loadBookings(_bookingPage) : _loadSeats());
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
                            onSelected: (_) => _switch(false),
                          ),
                          ChoiceChip(
                            label: const Text('我的预约'),
                            selected: _showBookings,
                            onSelected: (_) => _switch(true),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                AppLayout.minTap,
                                AppLayout.minTap,
                              ),
                            ),
                            onPressed: _openingOfficial ? null : _official,
                            child: Text(
                              _queries.needsLogin ? '打开学校页面登录' : '学校预约网页',
                            ),
                          ),
                        ],
                      ),
                      if (_queries.loading) ...[
                        const SizedBox(height: AppSpace.md),
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(4)),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
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
                      onPressed: _openingOfficial ? null : _official,
                    ),
                    AppActionButton(
                      label: '刷新',
                      icon: AppIcons.refresh,
                      outlined: true,
                      onPressed: _openingOfficial
                          ? null
                          : () => _showBookings
                                ? _loadBookings(_bookingPage)
                                : _loadSeats(),
                    ),
                  ],
                ),
              ],
              if (_queries.needsLogin) ...[
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
                      onPressed: _openingOfficial ? null : _official,
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
                      onPressed: _queries.loading || _openingOfficial
                          ? null
                          : () => _showBookings
                                ? _loadBookings(_bookingPage)
                                : _loadSeats(),
                    ),
                    AppActionButton(
                      label: '打开学校预约网页',
                      icon: AppIcons.chevronRight,
                      outlined: true,
                      onPressed: _openingOfficial ? null : _official,
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
                onChanged: (area) {
                  if (area == null) return;
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
                  onSelected: (_) => unawaited(_selectSeatDate(today)),
                ),
                ChoiceChip(
                  label: const Text('明天'),
                  selected: _date == tomorrow,
                  onSelected: (_) => unawaited(_selectSeatDate(tomorrow)),
                ),
                OutlinedButton(
                  onPressed: _chooseDate,
                  child: Text(isoDate(_date)),
                ),
                OutlinedButton(
                  onPressed: () => _chooseTime(true),
                  child: Text(_timeLabel(start, '开始')),
                ),
                OutlinedButton(
                  onPressed: () => _chooseTime(false),
                  child: Text(_timeLabel(end, '结束')),
                ),
                FilterChip(
                  label: const Text('仅看空闲'),
                  selected: _onlyAvailable,
                  onSelected: (value) => setState(() => _onlyAvailable = value),
                ),
                AppActionButton(
                  label: '刷新座位',
                  icon: AppIcons.refresh,
                  onPressed: _queries.loading || _openingOfficial
                      ? null
                      : _loadSeats,
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

  Widget _selectedBanner(
    BuildContext context,
    LibrarySeat seat,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
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
                  onPressed: () => setState(() => _selected = null),
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
            const SizedBox(height: AppSpace.sm),
            Text(
              '当前阶段仅提供选座与记录查询；提交预约将在下一阶段接入，如需立即预约可打开学校预约网页。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
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
              onTap: canSelect
                  ? () => setState(() => _selected = selected ? null : seat.id)
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
    final disabled = _queries.loading || _openingOfficial;
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
                  onPressed: _chooseBookingDates,
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
