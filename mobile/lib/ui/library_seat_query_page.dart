import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/library_seat_queries.dart';
import '../design/app_tokens.dart';
import '../domain/library_seats.dart';
import '../domain/schedule.dart';
import '../platform/campus_login_navigation.dart';
import '../platform/library_seat_reader.dart';
import '../platform/school_adapter.dart';
import 'acrylic_surface.dart';
import 'app_controls.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'campus_login_page.dart';
import 'classroom_section_switch.dart';
import 'course_surface.dart';
import 'library_floor_overview.dart';
import 'library_seat_bookings.dart';
import 'library_seat_map.dart';
import 'library_seat_page.dart';
import 'library_seat_sheets.dart';
import 'quiet_backdrop.dart';

class LibrarySeatTabController {
  VoidCallback? _onRefresh;
  VoidCallback? _onOpenOfficial;

  void _attach({
    required VoidCallback onRefresh,
    required VoidCallback onOpenOfficial,
  }) {
    _onRefresh = onRefresh;
    _onOpenOfficial = onOpenOfficial;
  }

  void _detach(VoidCallback onRefresh) {
    if (identical(_onRefresh, onRefresh)) {
      _onRefresh = null;
      _onOpenOfficial = null;
    }
  }

  void refresh() => _onRefresh?.call();
  void openOfficial() => _onOpenOfficial?.call();
  void dispose() {
    _onRefresh = null;
    _onOpenOfficial = null;
  }
}

class LibrarySeatQueryPage extends StatefulWidget {
  const LibrarySeatQueryPage({
    super.key,
    this.reader,
    this.now,
    this.loginOpener,
    this.officialPageBuilder,
    this.embedded = false,
    this.active = true,
    this.demo = false,
    this.onExitDemo,
    this.scrollController,
    this.contentInsets,
    this.tabController,
  });

  final LibrarySeatReader? reader;
  final DateTime Function()? now;
  final Future<bool> Function(BuildContext context, String reason)? loginOpener;
  final WidgetBuilder? officialPageBuilder;
  final bool embedded, active, demo;
  final VoidCallback? onExitDemo;
  final ScrollController? scrollController;
  final EdgeInsets? contentInsets;
  final LibrarySeatTabController? tabController;

  @override
  State<LibrarySeatQueryPage> createState() => _LibrarySeatQueryPageState();
}

class _LibrarySeatQueryPageState extends State<LibrarySeatQueryPage> {
  static const int _gridSegmentSize = 80;

  late final LibrarySeatQueries _queries;
  late DateTime _date, _bookingBegin, _bookingEnd;
  final TextEditingController _searchController = TextEditingController();
  LibraryArea? _area;
  LibrarySelectionLevel _level = LibrarySelectionLevel.floors;
  String? _selectedFloor, _recentFloor;
  LibraryZoneSlot? _activeZoneSlot, _recentZoneSlot;
  Alignment _activeZoneAnchor = Alignment.center;
  TimeOfDay? _start, _end;
  String? _selected;
  String _searchQuery = '';
  int _bookingPage = 1, _gridSegment = -1;
  LibrarySeatStatus? _statusFilter;
  bool _showBookings = false,
      _openingOfficial = false,
      _mapView = true,
      _started = false;

  DateTime _currentSchoolNow() => (widget.now ?? schoolNow)();
  bool get _busy => _openingOfficial || _queries.submitting;
  bool get _canRunNativeQueries =>
      widget.reader != null || defaultTargetPlatform == TargetPlatform.android;
  bool get _canStepBack =>
      widget.active &&
      !_showBookings &&
      !_busy &&
      _level != LibrarySelectionLevel.floors;
  double get _noticeBottomInset => widget.embedded
      ? ((widget.contentInsets?.bottom ?? 0) -
                MediaQuery.paddingOf(context).bottom)
            .clamp(0.0, 200.0)
      : 0.0;

  late final VoidCallback _tabRefreshCallback = _handleTabRefresh;
  late final VoidCallback _tabOfficialCallback = _handleTabOfficial;

  void _handleTabRefresh() {
    if (!mounted ||
        _busy ||
        _queries.loading ||
        widget.demo ||
        !_canRunNativeQueries) {
      return;
    }
    _started = true;
    _queries.clearSubmission();
    unawaited(
      _showBookings
          ? _loadBookings(_bookingPage)
          : (_level == LibrarySelectionLevel.areaSeats && _area != null
                ? _loadSeats()
                : _loadAreas()),
    );
  }

  void _handleTabOfficial() {
    if (!mounted || _busy || widget.demo || !_canRunNativeQueries) return;
    unawaited(_official());
  }

  void _maybeLazyStart() {
    if (!widget.embedded ||
        _started ||
        !widget.active ||
        widget.demo ||
        !_canRunNativeQueries) {
      return;
    }
    _started = true;
    unawaited(_loadAreas());
  }

  @override
  void initState() {
    super.initState();
    _queries = LibrarySeatQueries(widget.reader ?? LibrarySeatReader());
    final today = dateOnly(_currentSchoolNow());
    _date = today;
    _bookingBegin = calendarAdd(today, 1 - today.weekday);
    _bookingEnd = calendarAdd(_bookingBegin, 6);
    SchoolAdapter.sessionChanges.addListener(_sessionCleared);
    widget.tabController?._attach(
      onRefresh: _tabRefreshCallback,
      onOpenOfficial: _tabOfficialCallback,
    );
    if (!widget.embedded) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        _started = true;
        unawaited(_loadAreas());
      }
    } else {
      _maybeLazyStart();
    }
  }

  @override
  void didUpdateWidget(covariant LibrarySeatQueryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabController != widget.tabController) {
      oldWidget.tabController?._detach(_tabRefreshCallback);
      widget.tabController?._attach(
        onRefresh: _tabRefreshCallback,
        onOpenOfficial: _tabOfficialCallback,
      );
    }
    _maybeLazyStart();
  }

  @override
  void dispose() {
    widget.tabController?._detach(_tabRefreshCallback);
    SchoolAdapter.sessionChanges.removeListener(_sessionCleared);
    _searchController.dispose();
    _queries.dispose();
    super.dispose();
  }

  void _sessionCleared() {
    _searchController.clear();
    if (mounted) {
      setState(() {
        _level = LibrarySelectionLevel.floors;
        _selectedFloor = null;
        _recentFloor = null;
        _activeZoneSlot = null;
        _recentZoneSlot = null;
        _activeZoneAnchor = Alignment.center;
        _selected = null;
        _area = null;
        _start = _end = null;
        _searchQuery = '';
        _gridSegment = -1;
        _statusFilter = null;
      });
    } else {
      _level = LibrarySelectionLevel.floors;
      _selectedFloor = null;
      _recentFloor = null;
      _activeZoneSlot = null;
      _recentZoneSlot = null;
      _activeZoneAnchor = Alignment.center;
      _selected = null;
      _area = null;
      _start = _end = null;
      _searchQuery = '';
      _gridSegment = -1;
      _statusFilter = null;
    }
    unawaited(_queries.clearSession());
  }

  Future<void> _loadAreas() async {
    await _queries.loadAreas();
    if (!mounted || _showBookings || _openingOfficial) return;
    final floors = groupLibraryFloors(_queries.areas ?? const []);
    if (_selectedFloor != null &&
        !floors.any((group) => group.floor == _selectedFloor)) {
      setState(() {
        _level = LibrarySelectionLevel.floors;
        _selectedFloor = null;
        _area = null;
        _selected = null;
        _activeZoneSlot = null;
        _recentZoneSlot = null;
        _activeZoneAnchor = Alignment.center;
      });
    }
  }

  Future<void> _loadSeats() async {
    final targetArea = _area;
    if (targetArea == null) {
      await _loadAreas();
      return;
    }
    if (mounted && _selected != null) {
      setState(() => _selected = null);
    } else {
      _selected = null;
    }
    final date = _date;
    final selectedArea = await _queries.loadAreaSeats(
      preferredAreaId: targetArea.id,
      date: date,
    );
    if (!mounted ||
        _showBookings ||
        _openingOfficial ||
        _level != LibrarySelectionLevel.areaSeats ||
        _area?.id != targetArea.id ||
        _date != date) {
      return;
    }
    if (selectedArea == null) return;
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

  void _openFloor(LibraryFloorGroup group) {
    if (_busy) return;
    _queries.clearSubmission();
    setState(() {
      _level = LibrarySelectionLevel.floorMap;
      _selectedFloor = group.floor;
      _recentZoneSlot = null;
      _area = null;
      _selected = null;
      _activeZoneAnchor = Alignment.center;
    });
  }

  void _openZone(LibraryArea area, LibraryZoneSlot? slot, Alignment anchor) {
    if (_busy) return;
    _queries.clearSubmission();
    _searchController.clear();
    setState(() {
      _level = LibrarySelectionLevel.areaSeats;
      _selectedFloor = area.floor.trim().isEmpty
          ? (_selectedFloor ?? '座位区域')
          : area.floor.trim();
      _area = area;
      _activeZoneSlot = slot;
      _activeZoneAnchor = anchor;
      _recentZoneSlot = null;
      _start = _end = null;
      _selected = null;
      _searchQuery = '';
      _gridSegment = -1;
      _statusFilter = null;
    });
    unawaited(_loadSeats());
  }

  void _backToFloorMap() {
    if (_busy || _level != LibrarySelectionLevel.areaSeats) return;
    _queries.clearSubmission();
    _searchController.clear();
    setState(() {
      _recentZoneSlot = _activeZoneSlot;
      _level = LibrarySelectionLevel.floorMap;
      _selected = null;
      _searchQuery = '';
      _gridSegment = -1;
      _statusFilter = null;
    });
  }

  void _backToFloors() {
    if (_busy || _level == LibrarySelectionLevel.floors) return;
    _queries.clearSubmission();
    _searchController.clear();
    setState(() {
      _recentFloor = _selectedFloor;
      _level = LibrarySelectionLevel.floors;
      _area = null;
      _selected = null;
      _activeZoneSlot = null;
      _recentZoneSlot = null;
      _searchQuery = '';
      _gridSegment = -1;
      _statusFilter = null;
    });
  }

  void _stepBack() {
    if (_level == LibrarySelectionLevel.areaSeats) {
      _backToFloorMap();
    } else if (_level == LibrarySelectionLevel.floorMap) {
      _backToFloors();
    }
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

  Future<void> _authenticate({String reason = '登录后自动获取座位状态'}) async {
    if (_busy || _queries.loading) return;
    final revision = SchoolAdapter.sessionChanges.value;
    final interrupted = _queries.needsLogin ? _queries.submission : null;
    setState(() {
      _openingOfficial = true;
      _selected = null;
    });
    await _queries.resetReaderForAuthentication();
    if (!mounted || revision != SchoolAdapter.sessionChanges.value) {
      if (mounted) setState(() => _openingOfficial = false);
      return;
    }
    var signedIn = await _queries.tryReuseCampusSession();
    if (!mounted || revision != SchoolAdapter.sessionChanges.value) {
      if (mounted) setState(() => _openingOfficial = false);
      return;
    }
    if (!signedIn) {
      signedIn =
          await (widget.loginOpener?.call(context, reason) ??
              openCampusLogin(
                context,
                target: CampusLoginTarget.library,
                reason: reason,
              ));
    }
    if (!mounted || revision != SchoolAdapter.sessionChanges.value) {
      if (mounted) setState(() => _openingOfficial = false);
      return;
    }
    setState(() {
      _openingOfficial = false;
      if (signedIn) _started = true;
    });
    if (!signedIn) return;
    showAppNotice(
      context,
      interrupted != null || _showBookings
          ? '校园账号登录成功，正在核对预约记录'
          : '校园账号登录成功，正在获取座位状态',
      success: true,
      bottomInset: _noticeBottomInset,
    );
    if (interrupted != null) {
      await _openBookingsFor(interrupted.request.date);
      if (mounted &&
          revision == SchoolAdapter.sessionChanges.value &&
          _queries.bookings != null) {
        _queries.clearSubmission();
      }
      return;
    }
    if (_showBookings) {
      await _loadBookings(_bookingPage);
      if (mounted && revision == SchoolAdapter.sessionChanges.value) {
        _queries.finishCancellationAuthentication();
      }
      return;
    }
    await (_level == LibrarySelectionLevel.areaSeats && _area != null
        ? _loadSeats()
        : _loadAreas());
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
    setState(() {
      _openingOfficial = false;
      _started = true;
    });
    await (_showBookings
        ? _loadBookings(_bookingPage)
        : (_level == LibrarySelectionLevel.areaSeats && _area != null
              ? _loadSeats()
              : _loadAreas()));
  }

  Future<void> _selectSeatDate(DateTime date) async {
    if (_busy) return;
    final normalized = dateOnly(date);
    if (normalized == _date && _queries.seats != null && !_queries.failed) {
      return;
    }
    _queries.clearSubmission();
    _searchController.clear();
    setState(() {
      _date = normalized;
      _start = _end = null;
      _selected = null;
      _searchQuery = '';
      _gridSegment = -1;
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

  Future<void> _chooseArea(List<LibraryArea> areas) async {
    if (_busy || areas.isEmpty) return;
    final chosen = await showLibraryAreaSheet(
      context,
      areas: areas,
      selected: _area,
    );
    if (chosen == null || chosen.id == _area?.id || !mounted) return;
    _queries.clearSubmission();
    _searchController.clear();
    final slot = matchLibraryZoneSlot(chosen);
    setState(() {
      _level = LibrarySelectionLevel.areaSeats;
      _selectedFloor = chosen.floor.trim().isEmpty
          ? (_selectedFloor ?? '座位区域')
          : chosen.floor.trim();
      _area = chosen;
      _activeZoneSlot = slot;
      _activeZoneAnchor = libraryZoneAnchor(slot);
      _recentZoneSlot = null;
      _start = _end = null;
      _selected = null;
      _searchQuery = '';
      _gridSegment = -1;
    });
    await _loadSeats();
  }

  Future<void> _chooseTimeSlot({LibrarySeat? focusSeat}) async {
    if (_busy) return;
    final seats = _queries.seats ?? const <LibrarySeat>[];
    final openHours = focusSeat != null && focusSeat.hours.isNotEmpty
        ? focusSeat.hours
        : seats.firstWhere(
            (seat) => seat.hours.isNotEmpty,
            orElse: () => const LibrarySeat(
              id: '',
              label: '',
              open: true,
              viewOnly: false,
              hours: [(510, 1320)],
              reservations: [],
            ),
          ).hours;
    final rule =
        focusSeat?.rule ??
        seats.map((seat) => seat.rule).whereType<LibrarySeatRule>().firstOrNull;
    final picked = await showLibraryTimeSlotSheet(
      context,
      date: _date,
      currentSchoolNow: _currentSchoolNow(),
      initialStart: _start,
      initialEnd: _end,
      openHours: openHours,
      focusSeat: focusSeat,
      rule: rule,
    );
    if (picked == null || !mounted) return;
    _queries.clearSubmission();
    setState(() {
      _start = picked.start;
      _end = picked.end;
      if (picked.selectSeat &&
          focusSeat != null &&
          focusSeat.statusOn(
                _date,
                _minutes(picked.start),
                _minutes(picked.end),
              ) ==
              LibrarySeatStatus.available) {
        _selected = focusSeat.id;
        if (_statusFilter == LibrarySeatStatus.partial) {
          _statusFilter = null;
        }
      } else {
        _selected = null;
      }
    });
  }

  void _toggleStatusFilter(LibrarySeatStatus status) {
    if (_busy) return;
    setState(() {
      _statusFilter = _statusFilter == status ? null : status;
      if (_statusFilter != null && _statusFilter != LibrarySeatStatus.available) {
        _selected = null;
      }
    });
  }

  void _handleSeatSelect(LibrarySeat seat) {
    if (_busy) return;
    _queries.clearSubmission();
    setState(() => _selected = _selected == seat.id ? null : seat.id);
  }

  void _handleUnavailableTap(LibrarySeat seat, LibrarySeatStatus status) {
    if (_busy) return;
    final label = LibrarySeatPalette.statusLabel(status);
    showAppNotice(
      context,
      '${seat.label} 当前时段$label',
      bottomInset: _noticeBottomInset,
    );
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
    _bookingPage = 1;
    await _loadBookings(1);
  }

  Future<void> _selectBookingRange(DateTime begin, DateTime end) async {
    if (_busy) return;
    final nextBegin = dateOnly(begin);
    final nextEnd = dateOnly(end);
    if (nextBegin == _bookingBegin &&
        nextEnd == _bookingEnd &&
        _queries.bookings != null &&
        !_queries.failed) {
      return;
    }
    _bookingBegin = nextBegin;
    _bookingEnd = nextEnd;
    _bookingPage = 1;
    await _loadBookings(1);
  }

  void _switch(bool bookings) {
    if (bookings == _showBookings || _busy) return;
    setState(() => _showBookings = bookings);
    if (bookings) {
      unawaited(_loadBookings(_bookingPage));
    } else if (_level == LibrarySelectionLevel.areaSeats && _area != null) {
      unawaited(_loadSeats());
    } else if (_queries.areas == null) {
      unawaited(_loadAreas());
    }
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
    final proceed = await showLibraryConfirmReservationSheet(
      context,
      seat: seat,
      areaLabel: areaLabel,
      date: _date,
      start: start,
      end: end,
      ruleLines: ruleLines,
      blockingReason: blockingReason,
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

  @override
  Widget build(BuildContext context) {
    final canStepBack = _canStepBack;
    if (widget.embedded) {
      if (widget.demo) {
        return _embeddedNotice(
          context,
          title: '合成示例模式',
          detail: '合成示例模式下不访问学校图书馆预约，退出示例后可使用。',
          actions: [
            if (widget.onExitDemo != null)
              AppActionButton(
                label: '退出示例',
                icon: AppIcons.check,
                onPressed: widget.onExitDemo,
              ),
          ],
        );
      }
      if (!_canRunNativeQueries) {
        return _embeddedNotice(
          context,
          title: '图书馆座位预约',
          detail: '座位预约目前支持 Android。',
        );
      }
      return PopScope(
        canPop: !canStepBack,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && canStepBack) _stepBack();
        },
        child: ListenableBuilder(
          listenable: _queries,
          builder: (_, _) => _content(context),
        ),
      );
    }
    final body = defaultTargetPlatform == TargetPlatform.android
        ? ListenableBuilder(
            listenable: _queries,
            builder: (_, _) => _content(context),
          )
        : const Center(child: Text('座位预约目前支持 Android。'));
    return PopScope(
      canPop: !canStepBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canStepBack) _stepBack();
      },
      child: QuietBackdrop(
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
            actions: defaultTargetPlatform == TargetPlatform.android
                ? [
                    ListenableBuilder(
                      listenable: _queries,
                      builder: (_, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Tooltip(
                            message: '刷新座位或预约',
                            child: IconButton(
                              key: const ValueKey('library-refresh-button'),
                              onPressed: _busy || _queries.loading
                                  ? null
                                  : _handleTabRefresh,
                              icon: const AppIcon(AppIcons.refresh),
                            ),
                          ),
                          Tooltip(
                            message: '打开学校预约网页',
                            child: IconButton(
                              key: const ValueKey('library-official-button'),
                              onPressed: _busy ? null : _official,
                              icon: const AppIcon(AppIcons.globe),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]
                : null,
          ),
          body: SafeArea(top: false, child: body),
        ),
      ),
    );
  }

  Widget _embeddedNotice(
    BuildContext context, {
    required String title,
    required String detail,
    List<Widget> actions = const [],
  }) {
    final insets = widget.contentInsets ?? EdgeInsets.zero;
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return CustomScrollView(
      key: const PageStorageKey('library-tab-page'),
      controller: widget.scrollController,
      slivers: [
        PinnedHeaderSliver(child: SizedBox(height: insets.top)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg + insets.left,
            AppSpace.md,
            AppSpace.lg + insets.right,
            insets.bottom + AppSpace.xxl,
          ),
          sliver: SliverList.list(
            children: [
              if (actions.isNotEmpty)
                _statusCard(
                  context,
                  title: title,
                  detail: detail,
                  actions: actions,
                )
              else
                QuietCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          detail,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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

    final allEntries = <(LibrarySeat, LibrarySeatStatus)>[];
    final filteredItems = <(LibrarySeat, LibrarySeatStatus)>[];
    var availableCount = 0;
    var partialCount = 0;
    var occupiedCount = 0;
    var unavailableCount = 0;
    LibrarySeat? selectedSeat;

    if (!_showBookings && seats != null) {
      for (final seat in seats) {
        final status = _seatStatus(seat, start, end);
        allEntries.add((seat, status));
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
        if (_statusFilter == null || status == _statusFilter) {
          filteredItems.add((seat, status));
        }
      }
    }

    final hasFloorMap = canUseLibraryFloorMap(seats);
    final usingMap = hasFloorMap && _mapView;
    final trimmedQuery = _searchQuery.trim().toLowerCase();
    final searchedItems = usingMap || trimmedQuery.isEmpty
        ? filteredItems
        : filteredItems
              .where(
                (entry) => entry.$1.label.toLowerCase().contains(trimmedQuery),
              )
              .toList();

    final segmentCount = usingMap ||
            trimmedQuery.isNotEmpty ||
            searchedItems.length <= _gridSegmentSize
        ? 0
        : (searchedItems.length / _gridSegmentSize).ceil();
    final activeSegment =
        segmentCount <= 1 ? -1 : _gridSegment.clamp(-1, segmentCount - 1);
    final segmentLabels = segmentCount <= 1
        ? const <String>[]
        : [
            for (var i = 0; i < segmentCount; i++)
              '${i * _gridSegmentSize + 1}–${math.min((i + 1) * _gridSegmentSize, searchedItems.length)}',
          ];
    final gridItems = activeSegment < 0
        ? searchedItems
        : searchedItems.sublist(
            activeSegment * _gridSegmentSize,
            math.min(
              (activeSegment + 1) * _gridSegmentSize,
              searchedItems.length,
            ),
          );

    final insets = widget.embedded
        ? (widget.contentInsets ?? EdgeInsets.zero)
        : EdgeInsets.zero;
    final contentWidth = math.max(
      240.0,
      math.min(MediaQuery.sizeOf(context).width, 1000.0) -
          (AppSpace.lg * 2 + insets.left + insets.right),
    );
    final gridColumns = LibrarySeatGridRow.columnsFor(context, contentWidth);
    final gridRowCount = (gridItems.length / gridColumns).ceil();

    final now = _currentSchoolNow();
    final bookingFocusRows = <LibraryBooking>[];
    final bookingHistoryRows = <LibraryBooking>[];
    if (_showBookings && page != null) {
      for (final row in page.rows) {
        if (isFocusLibraryBooking(row, now)) {
          bookingFocusRows.add(row);
        } else {
          bookingHistoryRows.add(row);
        }
      }
    }
    final bookingWidgets = <Widget>[
      for (final row in bookingFocusRows)
        LibraryBookingFocusTicket(
          row: row,
          now: now,
          canCancel: _queries.canCancelBooking(row),
          busy: _busy,
          onCancel: () => _confirmCancellation(row),
          onOpenOfficial: _official,
        ),
      if (bookingFocusRows.isNotEmpty && bookingHistoryRows.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.xs,
            AppSpace.lg,
            AppSpace.sm,
          ),
          child: Text(
            '近期记录',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      for (final row in bookingHistoryRows)
        LibraryBookingHistoryRow(
          row: row,
          canCancel: _queries.canCancelBooking(row),
          busy: _busy,
          onCancel: () => _confirmCancellation(row),
        ),
    ];

    final floors = groupLibraryFloors(_queries.areas ?? const []);
    final currentFloorGroup = _selectedFloor == null
        ? floors.firstOrNull
        : floors.where((g) => g.floor == _selectedFloor).firstOrNull ??
              floors.firstOrNull;
    final activeFloorGroup =
        currentFloorGroup ??
        (_area == null
            ? null
            : LibraryFloorGroup(
                floor: _area!.floor,
                areas: [_area!],
                kind: classifyLibraryFloor(_area!.floor, [_area!]),
              ));

    final showCapsule =
        !_showBookings &&
        _level == LibrarySelectionLevel.areaSeats &&
        selectedSeat != null &&
        hasValidRange;
    final extraCapsuleSpace = showCapsule ? 108.0 : 0.0;
    final bottomInset =
        (widget.embedded ? insets.bottom + AppSpace.xxl : AppSpace.xxl) +
        extraCapsuleSpace;
    final hasBottomList = _showBookings && bookingWidgets.isNotEmpty;

    Widget buildGridSection() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibrarySeatGridControls(
          searchController: _searchController,
          query: _searchQuery,
          totalFilteredCount: searchedItems.length,
          segmentIndex: activeSegment,
          segmentCount: segmentCount,
          segmentLabels: segmentLabels,
          onQueryChanged: (value) => setState(() {
            _searchQuery = value;
            _gridSegment = -1;
          }),
          onSegmentSelected: (index) => setState(() => _gridSegment = index),
        ),
        if (gridItems.isEmpty && trimmedQuery.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          QuietCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '未找到包含“${_searchQuery.trim()}”的座位',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Text('清空搜索'),
                  ),
                ],
              ),
            ),
          ),
        ] else if (gridRowCount > 0) ...[
          const SizedBox(height: AppSpace.md),
          for (var rowIndex = 0; rowIndex < gridRowCount; rowIndex++) ...[
            if (rowIndex > 0) const SizedBox(height: AppSpace.sm),
            LibrarySeatGridRow(
              items: gridItems.sublist(
                rowIndex * gridColumns,
                math.min((rowIndex + 1) * gridColumns, gridItems.length),
              ),
              columns: gridColumns,
              date: _date,
              start: start,
              end: end,
              hasValidRange: hasValidRange,
              selectedSeatId: _selected,
              busy: _busy,
              onSelectSeat: _handleSeatSelect,
              onInspectPartial: (seat) =>
                  unawaited(_chooseTimeSlot(focusSeat: seat)),
              onUnavailableTap: _handleUnavailableTap,
            ),
          ],
        ],
      ],
    );

    Widget buildSpatialSeatContent() {
      switch (_level) {
        case LibrarySelectionLevel.floors:
          if (_queries.loading && _queries.areas == null) {
            return const LibraryFloorListSkeleton();
          }
          if (_queries.areas?.isEmpty == true) {
            return QuietCard(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Text(
                  '暂无座位区域',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          if (floors.isEmpty) {
            return const SizedBox.shrink();
          }
          return LibraryFloorListView(
            floors: floors,
            recentFloor: _recentFloor,
            busy: _busy,
            onSelectFloor: _openFloor,
          );
        case LibrarySelectionLevel.floorMap:
          if (currentFloorGroup == null) {
            if (_queries.loading) return const LibraryFloorListSkeleton();
            return const SizedBox.shrink();
          }
          return LibraryFloorSchematicView(
            group: currentFloorGroup,
            recentZoneSlot: _recentZoneSlot,
            busy: _busy,
            onSelectZone: _openZone,
            onBackToFloors: _backToFloors,
          );
        case LibrarySelectionLevel.areaSeats:
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _seatControlsCard(
                context,
                floorGroup: activeFloorGroup,
                seats: seats,
                hasFloorMap: hasFloorMap,
                usingMap: usingMap,
                availableCount: availableCount,
                partialCount: partialCount,
                occupiedCount: occupiedCount,
                unavailableCount: unavailableCount,
              ),
              if (_queries.loading && seats == null) ...[
                const SizedBox(height: AppSpace.md),
                const LibrarySeatLoadingSkeleton(),
              ],
              if (seats != null && seats.isNotEmpty) ...[
                const SizedBox(height: AppSpace.md),
                if (filteredItems.isEmpty)
                  QuietCard(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _statusFilter == LibrarySeatStatus.partial
                                  ? '当前时段暂无半空闲座位'
                                  : '当前时段暂无空闲座位',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => _statusFilter = null),
                            child: const Text('显示全部'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  LibrarySeatViewModeTransition(
                    usingMap: usingMap,
                    mapChild: LibrarySeatFloorMap(
                      key: ValueKey('library-floor-map-${_area?.id ?? ''}'),
                      allSeats: allEntries,
                      visibleSeats: filteredItems,
                      selectedSeatId: _selected,
                      busy: _busy,
                      onSelectSeat: _handleSeatSelect,
                      onInspectPartial: (seat) =>
                          unawaited(_chooseTimeSlot(focusSeat: seat)),
                      onUnavailableTap: _handleUnavailableTap,
                    ),
                    gridChild: buildGridSection(),
                  ),
              ],
            ],
          );
      }
    }

    final spatialContentKey = switch (_level) {
      LibrarySelectionLevel.floors => 'floors',
      LibrarySelectionLevel.floorMap =>
        'floor:${currentFloorGroup?.floor ?? _selectedFloor ?? ''}',
      LibrarySelectionLevel.areaSeats => 'area:${_area?.id ?? ''}',
    };

    final scrollView = CustomScrollView(
      key: widget.embedded
          ? const PageStorageKey('library-tab-page')
          : PageStorageKey(
              _showBookings ? 'library_bookings' : 'library_seats',
            ),
      controller: widget.embedded ? widget.scrollController : null,
      slivers: [
        if (widget.embedded)
          PinnedHeaderSliver(child: SizedBox(height: insets.top)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg + insets.left,
            AppSpace.md,
            AppSpace.lg + insets.right,
            hasBottomList ? AppSpace.sm : bottomInset,
          ),
          sliver: SliverList.list(
            children: [
              IgnorePointer(
                ignoring: _busy,
                child: Opacity(
                  opacity: _busy ? 0.65 : 1.0,
                  child: ClassroomSectionSwitch(
                    tabs: const ['选座', '我的预约'],
                    selectedIndex: _showBookings ? 1 : 0,
                    onSelected: (index) => _switch(index == 1),
                  ),
                ),
              ),
              if (_queries.loading ||
                  _queries.submitting ||
                  _openingOfficial) ...[
                const SizedBox(height: AppSpace.sm),
                const ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
                if (_queries.submitting) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    _showBookings ? '正在核对并取消预约…' : '正在核对余位并提交预约…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
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
                  detail: '点击后优先复用校园登录状态并自动获取座位；如需验证，将在学校官方页面完成后自动返回。',
                  actions: [
                    AppActionButton(
                      label: '登录校园账号',
                      icon: AppIcons.chevronRight,
                      onPressed: _busy ? null : _authenticate,
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
                  !(_showBookings && _queries.cancellation != null) &&
                  _queries.submission?.kind !=
                      LibrarySubmissionKind.authInterrupted) ...[
                const SizedBox(height: AppSpace.md),
                _statusCard(
                  context,
                  title: '需要登录学校账号',
                  detail: '点击后优先复用校园登录状态并自动获取座位；如需验证，将在学校官方页面完成后自动返回。',
                  isError: false,
                  actions: [
                    AppActionButton(
                      label: '登录校园账号',
                      icon: AppIcons.chevronRight,
                      onPressed: _busy ? null : _authenticate,
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
              if (_showBookings) ...[
                LibraryBookingsControlsCard(
                  begin: _bookingBegin,
                  end: _bookingEnd,
                  now: now,
                  page: page,
                  busy: _busy,
                  loading: _queries.loading,
                  onSelectRange: (b, e) => unawaited(_selectBookingRange(b, e)),
                  onChooseCustomRange: _chooseBookingDates,
                  onRefresh: () => unawaited(_loadBookings(_bookingPage)),
                  onPageChanged: (nextPage) =>
                      unawaited(_loadBookings(nextPage)),
                ),
                if (_queries.cancellation != null) ...[
                  const SizedBox(height: AppSpace.md),
                  _cancellationCard(context, _queries.cancellation!),
                ],
                if (_queries.loading && page == null) ...[
                  const SizedBox(height: AppSpace.md),
                  const LibraryBookingsLoadingSkeleton(),
                ],
                if (page != null && page.rows.isEmpty) ...[
                  const SizedBox(height: AppSpace.md),
                  LibraryBookingsEmptyCard(
                    page: page,
                    begin: _bookingBegin,
                    end: _bookingEnd,
                    now: now,
                    busy: _busy,
                    onGoToSelectSeat: () => _switch(false),
                    onViewRecent30Days: () {
                      final today = dateOnly(now);
                      unawaited(
                        _selectBookingRange(
                          calendarAdd(today, -29),
                          calendarAdd(today, 1),
                        ),
                      );
                    },
                  ),
                ],
              ] else ...[
                if (floors.isNotEmpty ||
                    _level != LibrarySelectionLevel.floors) ...[
                  LibrarySpatialBreadcrumbBar(
                    level: _level,
                    floorName: currentFloorGroup?.floor ?? _selectedFloor,
                    areaName: _area?.name,
                    busy: _busy,
                    onSelectFloors: _backToFloors,
                    onSelectFloorMap: _backToFloorMap,
                  ),
                  const SizedBox(height: AppSpace.md),
                ],
                LibrarySpatialLevelTransition(
                  level: _level.index,
                  contentKey: spatialContentKey,
                  focusAnchor: _activeZoneAnchor,
                  child: buildSpatialSeatContent(),
                ),
              ],
            ],
          ),
        ),
        if (_showBookings && bookingWidgets.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.only(
              left: insets.left,
              right: insets.right,
              bottom: bottomInset,
            ),
            sliver: SliverList.builder(
              itemCount: bookingWidgets.length,
              itemBuilder: (_, index) => bookingWidgets[index],
            ),
          ),
      ],
    );

    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        scrollView,
        Positioned(
          left: AppSpace.lg + insets.left,
          right: AppSpace.lg + insets.right,
          bottom: widget.embedded ? insets.bottom : AppSpace.md,
          child: IgnorePointer(
            ignoring: !showCapsule,
            child: AnimatedSwitcher(
              duration: reduced ? Duration.zero : AppMotion.contentEnter,
              reverseDuration: reduced ? Duration.zero : AppMotion.contentExit,
              switchInCurve: AppMotion.navigationCurve,
              switchOutCurve: AppMotion.navigationCurve,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  for (final prev in previousChildren)
                    ExcludeSemantics(
                      child: ExcludeFocus(child: IgnorePointer(child: prev)),
                    ),
                  ?currentChild,
                ],
              ),
              transitionBuilder: (child, animation) => reduced
                  ? child
                  : FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.14),
                          end: Offset.zero,
                        ).animate(animation),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.95,
                            end: 1.0,
                          ).animate(animation),
                          alignment: Alignment.bottomCenter,
                          child: child,
                        ),
                      ),
                    ),
              child: showCapsule
                  ? _selectedCapsule(context, selectedSeat, start, end)
                  : const SizedBox.shrink(key: ValueKey('library-no-capsule')),
            ),
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
    required LibraryFloorGroup? floorGroup,
    required List<LibrarySeat>? seats,
    required bool hasFloorMap,
    required bool usingMap,
    required int availableCount,
    required int partialCount,
    required int occupiedCount,
    required int unavailableCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final List<LibraryArea> areas = _queries.areas ?? const [];
    final start = _start, end = _end;
    final invalidTimes =
        start != null && end != null && _minutes(start) >= _minutes(end);
    final today = dateOnly(_currentSchoolNow());
    final tomorrow = calendarAdd(today, 1);
    final timeLabel = start != null && end != null
        ? '${_clockText(start)}–${_clockText(end)}'
        : '选择时段';
    final locatorSlots = floorGroup == null
        ? {?_activeZoneSlot}
        : resolveFloorZones(floorGroup).mapped.keys.toSet();
    final surfaceColor = colors.surfaceContainerLow.withValues(
      alpha: highContrast ? 1.0 : .82,
    );
    final borderColor = highContrast ? colors.outline : colors.outlineVariant;
    final borderWidth = highContrast ? 1.0 : 0.7;

    Widget surfaceControlButton({
      required Key key,
      required String label,
      required AppIconData trailingIcon,
      required VoidCallback? onTap,
      AppIconData? leadingIcon,
      String? trailingLabel,
      double minHeight = 38,
      TextStyle? textStyle,
    }) {
      return Material(
        color: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(width: borderWidth, color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: 7,
              ),
              child: Row(
                children: [
                  if (leadingIcon != null) ...[
                    AppIcon(leadingIcon, size: 16, color: colors.primary),
                    const SizedBox(width: AppSpace.xs),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          textStyle ??
                          theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabularTime,
                          ),
                    ),
                  ),
                  if (trailingLabel != null) ...[
                    const SizedBox(width: AppSpace.xs),
                    Text(
                      trailingLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpace.xs),
                  AppIcon(
                    trailingIcon,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget daySegment({
      required String label,
      required bool selected,
      required VoidCallback? onTap,
    }) {
      return Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.small - 2),
          onTap: onTap,
          child: AnimatedContainer(
            duration: reduced ? Duration.zero : AppMotion.segment,
            curve: AppMotion.segmentCurve,
            constraints: const BoxConstraints(minHeight: 34, minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            decoration: BoxDecoration(
              color: selected
                  ? (highContrast
                        ? colors.primary
                        : colors.primaryContainer.withValues(alpha: 0.92))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.small - 2),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected
                    ? (highContrast ? colors.onPrimary : colors.primary)
                    : colors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    Widget buildDayQuickSwitch({required bool expanded}) {
      final todayCell = daySegment(
        label: '今天',
        selected: _date == today,
        onTap: _busy ? null : () => unawaited(_selectSeatDate(today)),
      );
      final tomorrowCell = daySegment(
        label: '明天',
        selected: _date == tomorrow,
        onTap: _busy ? null : () => unawaited(_selectSeatDate(tomorrow)),
      );
      return Material(
        color: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(width: borderWidth, color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: expanded
                ? [
                    Expanded(child: todayCell),
                    const SizedBox(width: 2),
                    Expanded(child: tomorrowCell),
                  ]
                : [
                    todayCell,
                    const SizedBox(width: 2),
                    tomorrowCell,
                  ],
          ),
        ),
      );
    }

    Widget viewModeToggle() => CourseSurface(
      dense: true,
      radius: AppRadius.small,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('library-view-map'),
            tooltip: hasFloorMap ? '平面选座图' : '当前区域暂无平面坐标',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: usingMap
                  ? colors.primaryContainer
                  : Colors.transparent,
              foregroundColor: usingMap
                  ? colors.primary
                  : colors.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.small - 2),
              ),
            ),
            onPressed: !_busy && hasFloorMap
                ? () => setState(() => _mapView = true)
                : null,
            icon: const AppIcon(AppIcons.map, size: AppControl.icon),
          ),
          IconButton(
            key: const ValueKey('library-view-grid'),
            tooltip: '紧凑网格',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: !usingMap
                  ? colors.primaryContainer
                  : Colors.transparent,
              foregroundColor: !usingMap
                  ? colors.primary
                  : colors.onSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.small - 2),
              ),
            ),
            onPressed: !_busy ? () => setState(() => _mapView = false) : null,
            icon: const AppIcon(AppIcons.grid, size: AppControl.icon),
          ),
        ],
      ),
    );

    Widget groupDivider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Divider(
        height: 1,
        thickness: 0.6,
        color: colors.outlineVariant.withValues(
          alpha: highContrast ? 0.85 : 0.42,
        ),
      ),
    );

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section 1: 空间定位与视图
            if (floorGroup != null) ...[
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    LibrarySpatialLocatorPill(
                      floorKind: floorGroup.kind,
                      activeSlots: locatorSlots,
                      activeSlot: _activeZoneSlot,
                      busy: _busy,
                      onBackToFloorMap: _backToFloorMap,
                    ),
                    viewModeToggle(),
                  ],
                ),
              ),
              if (areas.isNotEmpty) const SizedBox(height: AppSpace.sm),
            ],
            if (areas.isNotEmpty) ...[
              if (floorGroup != null)
                surfaceControlButton(
                  key: const ValueKey('library-area-picker'),
                  label: _area?.label ?? areas.first.label,
                  trailingIcon: AppIcons.chevronDown,
                  minHeight: 42,
                  textStyle: theme.textTheme.titleSmall,
                  onTap: _busy ? null : () => _chooseArea(areas),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: surfaceControlButton(
                        key: const ValueKey('library-area-picker'),
                        label: _area?.label ?? areas.first.label,
                        trailingIcon: AppIcons.chevronDown,
                        minHeight: 42,
                        textStyle: theme.textTheme.titleSmall,
                        onTap: _busy ? null : () => _chooseArea(areas),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    viewModeToggle(),
                  ],
                ),
            ] else if (_queries.areas?.isEmpty == true) ...[
              Text(
                '暂无座位区域',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            groupDivider(),
            // Section 2: 预约日期与时段（统一材质与高度）
            LayoutBuilder(
              builder: (context, constraints) {
                final stackDateRow =
                    constraints.maxWidth < 285 ||
                    MediaQuery.textScalerOf(context).scale(14) > 19.5;
                final datePicker = surfaceControlButton(
                  key: const ValueKey('library-date-picker'),
                  leadingIcon: AppIcons.calendar,
                  label: isoDate(_date),
                  trailingIcon: AppIcons.chevronDown,
                  onTap: _busy ? null : _chooseDate,
                );
                if (stackDateRow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IntrinsicHeight(
                        child: buildDayQuickSwitch(expanded: true),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      datePicker,
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buildDayQuickSwitch(expanded: false),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: datePicker),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpace.xs),
            surfaceControlButton(
              key: const ValueKey('library-time-picker'),
              leadingIcon: AppIcons.clock,
              label: timeLabel,
              trailingLabel: '调整',
              trailingIcon: AppIcons.chevronRight,
              onTap: _busy ? null : () => _chooseTimeSlot(),
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
              groupDivider(),
              // Section 3: 席位统计与筛选
              _statusLegend(
                context,
                total: seats.length,
                availableCount: availableCount,
                partialCount: partialCount,
                occupiedCount: occupiedCount,
                unavailableCount: unavailableCount,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusLegend(
    BuildContext context, {
    required int total,
    required int availableCount,
    required int partialCount,
    required int occupiedCount,
    required int unavailableCount,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final onlyAvailable = _statusFilter == LibrarySeatStatus.available;

    Widget pill({
      required LibrarySeatStatus status,
      required String text,
      VoidCallback? onTap,
      bool active = false,
    }) {
      final tone = LibrarySeatPalette.toneOf(context, status);
      return Semantics(
        button: onTap != null,
        selected: active,
        child: Material(
          color: active ? colors.primaryContainer : tone.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.small),
            side: BorderSide(
              width: active ? 1.2 : 0.7,
              color: active ? colors.primary : tone.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.small),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: 5,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tone.dot,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: active ? colors.primary : tone.foreground,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      fontFeatures: tabularTime,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final onlyAvailableToggle = Semantics(
      button: true,
      toggled: onlyAvailable,
      child: Material(
        color: onlyAvailable
            ? (highContrast ? colors.primary : colors.primaryContainer)
            : colors.surfaceContainerLow.withValues(
                alpha: highContrast ? 1.0 : .82,
              ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(
            width: onlyAvailable ? 1.2 : (highContrast ? 1.0 : 0.7),
            color: onlyAvailable
                ? colors.primary
                : (highContrast ? colors.outline : colors.outlineVariant),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('library-only-available-toggle'),
          borderRadius: BorderRadius.circular(AppRadius.small),
          onTap: _busy
              ? null
              : () => _toggleStatusFilter(LibrarySeatStatus.available),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.sm,
              vertical: 5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onlyAvailable) ...[
                  AppIcon(
                    AppIcons.check,
                    size: 13,
                    color: highContrast ? colors.onPrimary : colors.primary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  '仅看空闲',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onlyAvailable
                        ? (highContrast ? colors.onPrimary : colors.primary)
                        : colors.onSurfaceVariant,
                    fontWeight: onlyAvailable
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpace.sm,
        runSpacing: AppSpace.xs,
        children: [
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.xs),
                child: Text(
                  '共 $total 席',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: tabularTime,
                  ),
                ),
              ),
              pill(
                status: LibrarySeatStatus.available,
                text: '空闲 $availableCount',
                active: _statusFilter == LibrarySeatStatus.available,
                onTap: () => _toggleStatusFilter(LibrarySeatStatus.available),
              ),
              pill(
                status: LibrarySeatStatus.partial,
                text: '半空闲 $partialCount',
                active: _statusFilter == LibrarySeatStatus.partial,
                onTap: () => _toggleStatusFilter(LibrarySeatStatus.partial),
              ),
              if (occupiedCount > 0)
                pill(
                  status: LibrarySeatStatus.occupied,
                  text: '使用中 $occupiedCount',
                ),
              if (unavailableCount > 0)
                pill(
                  status: LibrarySeatStatus.closed,
                  text: '不可用 $unavailableCount',
                ),
            ],
          ),
          onlyAvailableToggle,
        ],
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
              label: '登录校园账号',
              icon: AppIcons.chevronRight,
              onPressed: _busy
                  ? null
                  : () => _authenticate(reason: '登录后核对本次预约记录'),
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

  Widget _selectedCapsule(
    BuildContext context,
    LibrarySeat seat,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final duration = formatLibraryDuration(_minutes(end) - _minutes(start));
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AcrylicSurface(
          key: const ValueKey('library-selected-capsule'),
          radius: AppRadius.card,
          blurKey: const ValueKey('library-selected-blur'),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _area == null ? seat.label : '${_area!.name} · ${seat.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: tabularTime,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isoDate(_date)} ${_clockText(start)}–${_clockText(end)} · $duration',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: tabularTime,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '清除选择',
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: const AppIcon(AppIcons.close, size: AppControl.icon),
                  onPressed: _busy ? null : () => setState(() => _selected = null),
                ),
                const SizedBox(width: AppSpace.xs),
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.md,
                      vertical: AppSpace.sm,
                    ),
                    minimumSize: const Size(0, 42),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _confirmReservation(seat, start, end),
                  child: const Text('确认预约'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmCancellation(LibraryBooking row) async {
    if (_busy || !_queries.canCancelBooking(row)) return;
    final page = _bookingPage;
    final begin = _bookingBegin, end = _bookingEnd;
    final proceed = await showLibraryConfirmCancelSheet(
      context,
      booking: row,
    );
    if (proceed != true ||
        !mounted ||
        _busy ||
        !_showBookings ||
        page != _bookingPage ||
        begin != _bookingBegin ||
        end != _bookingEnd) {
      return;
    }
    await _queries.cancelBooking(row, begin, end, page);
  }

  Widget _cancellationCard(
    BuildContext context,
    LibraryCancellationState result,
  ) {
    final (title, detail) = switch (result.status) {
      LibraryWriteStatus.ok when result.removed => (
        '取消已核对',
        '学校接受了取消请求，已从当前预约列表移除。',
      ),
      LibraryWriteStatus.ok => ('学校已接受取消请求', '请刷新预约列表或到学校网页核对最终状态。'),
      LibraryWriteStatus.notEligible => (
        '当前无法取消',
        '预约可能已开始、已结束、发生变更或不属于当前账号。请刷新后查看。',
      ),
      LibraryWriteStatus.rejected => ('学校拒绝取消', '请到学校网页查看该预约的状态和适用规则。'),
      LibraryWriteStatus.webRequired => ('请在学校网页办理', '此预约需要在学校网页确认取消。'),
      LibraryWriteStatus.precheckFailed => ('取消未提交', '未能读取最新预约。请刷新列表后再确认。'),
      LibraryWriteStatus.login => ('学校会话已失效', '重新登录后请先查看预约状态。应用不会自动重发。'),
      LibraryWriteStatus.uncertain => ('取消结果待核对', '暂未收到学校的明确答复。请先查单。应用不会自动重发。'),
    };
    return _statusCard(
      context,
      title: title,
      detail: _queries.needsLogin
          ? detail
          : [result.booking.seat, detail].join(' · '),
      isError: result.status != LibraryWriteStatus.ok,
      actions: [
        if (!_queries.needsLogin)
          AppActionButton(
            label: '核对预约',
            icon: AppIcons.refresh,
            onPressed: _busy || _queries.loading
                ? null
                : () => _loadBookings(_bookingPage),
          ),
        AppActionButton(
          label: _queries.needsLogin ? '登录校园账号' : '打开学校预约网页',
          icon: AppIcons.chevronRight,
          outlined: true,
          onPressed: _busy
              ? null
              : (_queries.needsLogin ? _authenticate : _official),
        ),
      ],
    );
  }
}
