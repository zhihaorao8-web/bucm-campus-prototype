import '../config/runtime_config.dart';
import '../config/classroom_limits.dart';
import '../design/app_tokens.dart';
import 'course_interaction.dart';
import 'course_surface.dart';
import 'quiet_backdrop.dart';
import 'app_icon_controls.dart';
import 'app_icons.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../application/classroom_import_progress.dart';
import '../application/classroom_connection_coordinator.dart';
import '../application/classroom_import_coordinator.dart';
import '../application/classroom_playback_preparation.dart';
import '../application/classroom_connection_status.dart';
import '../data/classroom_links.dart';
import '../data/classroom_library.dart';
import '../data/classroom_playback_progress.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';
import '../platform/classroom_access.dart';
import '../platform/classroom_api_reader.dart';
import '../platform/classroom_page_scripts.dart';
import '../platform/test_diagnostics.dart';
import '../platform/classroom_read_progress.dart';
import '../platform/classroom_policy.dart';
import '../platform/classroom_player.dart';
import '../platform/classroom_session_cache.dart';
import 'classroom_player_page.dart';
import 'classroom_player_route.dart';
import 'classroom_connection_card.dart';
import 'classroom_recording_timeline.dart';
import 'classroom_section_switch.dart';
import 'course_widgets.dart' show showCourseInformation;

enum _Purpose { browse, records, playback }

class _SchoolTab {
  _SchoolTab({
    this.windowId,
    required this.purpose,
    InAppWebViewKeepAlive? retained,
  }) : retained = retained ?? InAppWebViewKeepAlive();
  final InAppWebViewKeepAlive retained;
  final int? windowId;
  _Purpose purpose;
  InAppWebViewController? controller;
  bool routed = false;
  bool advancing = false, navigationStopped = false;
  int entryHops = 0;
  Timer? loadTimer;
  int ccLoads = 0;
  String? dedicatedTarget;
  bool dedicatedRecovered = false, loadTimedOut = false;
}

/// Course UI reuses the official WebView session for bounded entry navigation
/// and metadata. Authentication stays visible; no automated credential entry.
class ClassroomCoursePage extends StatefulWidget {
  const ClassroomCoursePage({
    super.key,
    required this.course,
    this.date,
    required this.onDetails,
    this.links,
    this.probe,
    this.library,
    this.importCourses,
    this.onImportResult,
    this.progressStore,
    this.transitionTag,
  });
  final Course course;
  final Object? transitionTag;
  final DateTime? date;
  final void Function(BuildContext) onDetails;
  final ClassroomLinks? links;
  final ProbeEndpoint? probe;
  final ClassroomLibrary? library;
  final List<Course>? importCourses;
  final ValueChanged<ClassroomConnectionStatus>? onImportResult;
  final ClassroomPlaybackProgressStore? progressStore;
  @override
  State<ClassroomCoursePage> createState() => _ClassroomCoursePageState();
}

class _ClassroomCoursePageState extends State<ClassroomCoursePage>
    with WidgetsBindingObserver {
  final tabs = <_SchoolTab>[];
  final scroll = ScrollController();
  late final links = widget.links ?? ClassroomLinks.shared;
  List<ClassroomCourse>? catalog;
  ClassroomCourse? selected;
  RecordingPage? recordings;
  int active = 0, recordTab = 0, catalogTab = 0, section = 0, attempts = 0;
  late final connection = ClassroomConnectionCoordinator(probe: widget.probe);
  int get generation => connection.generation;
  final scripts = ClassroomPageScripts();
  int playbackGeneration = 0;
  bool showWeb = false,
      busy = false,
      loading = false,
      rememberedAttempted = false;
  String? entry, message;
  ClassroomConnectionPhase connectionPhase = ClassroomConnectionPhase.idle;
  ClassroomConnectionStatus get connectionStatus =>
      ClassroomConnectionStatus(connectionPhase, message);
  bool automaticEntry = true, automaticPath = false;
  int timelinePage = 1, lessonPage = 1;
  late final readProgress = connection.readProgress;
  bool foreground = true;
  final cache = ClassroomSessionCache.shared;
  late int cacheRevision;
  late final library = widget.library ?? ClassroomLibrary.shared;
  late final ClassroomImportCoordinator importCoordinator;
  int get libraryRevision => importCoordinator.revision;
  ClassroomArchive? archive;
  ClassroomRecording? queuedPlayback;
  GlobalKey? playbackButton;
  bool playbackReducedMotion = false;
  String? queuedCourseId;
  bool autoCollecting = false;
  late final collection = importCoordinator.collection;
  List<ClassroomCourse>? get importMatches => collection.matches;
  int get sourceIndex => collection.sourceIndex;
  bool get collecting => bulk || autoCollecting;
  int get displayPage => archive?.displayPage(recordings!) ?? recordings!.page;
  int queuedPage = 1;
  int? livePage;
  String? liveCourse;
  bool needsCatalog = false, authVisible = false;
  int importIndex = 0, imported = 0;
  bool importFinished = false, importingPage = false;
  List<RecordingPage> get importPages => collection.pages;
  final skipped = <String>[];
  Map<String, ClassroomArchive> get completedArchives => collection.completed;
  late final importProgress = ClassroomImportProgress(
    widget.importCourses ?? [widget.course],
  );
  List<int>? retryQueue;
  final completedTasksKey = GlobalKey();
  bool get bulk => widget.importCourses != null;
  Course get localCourse =>
      bulk ? importProgress.items[importIndex].course : widget.course;
  bool get browserVisible =>
      showWeb && (authVisible || (!bulk && queuedPlayback == null));

  DateTime? fetchedAt;
  double lastOffset = 0;
  bool restored = false, validateRestored = false, freshReadPending = false;

  // Dispose only after the old platform widgets have detached.
  void releaseTabs(Iterable<_SchoolTab> removed) {
    for (final tab in removed) {
      tab.loadTimer?.cancel();
    }
    final handles = removed.map((tab) => tab.retained).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final handle in handles) {
        cache.release(handle);
      }
    });
  }

  void clearTabs() {
    releaseTabs(tabs);
    tabs.clear();
  }

  void trimTabs(int length) {
    releaseTabs(tabs.skip(length));
    tabs.removeRange(length, tabs.length);
  }

  bool get synthetic => localCourse.dataSource == 'synthetic';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    scroll.addListener(() {
      if (scroll.hasClients) lastOffset = scroll.offset;
    });
    importCoordinator = ClassroomImportCoordinator(library: library);
    if (bulk) {
      importProgress.update(0, ImportTaskStatus.running);
      final workspace = cache.takeWorkspace();
      cache.clear();
      cacheRevision = cache.revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(startWorkspace(workspace));
      });
      return;
    }
    cacheRevision = cache.revision;
    final recent = synthetic ? null : cache.take(localCourse);
    if (recent != null) {
      entry = recent.entry;
      recordings = recent.records;
      selected = recent.records.course;
      fetchedAt = recent.fetchedAt;
      livePage = recent.documentPage ?? recent.records.page;
      liveCourse = recent.records.course.id;
      restored = true;
      validateRestored = true;
      rememberedAttempted = true;
      tabs.add(
        _SchoolTab(purpose: _Purpose.records, retained: recent.view)
          ..routed = true,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.jumpTo(
            recent.offset.clamp(0.0, scroll.position.maxScrollExtent),
          );
        }
      });
      unawaited(loadArchive(keepLive: true));
      return;
    }
    if (!synthetic) {
      busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(loadArchive());
      });
    }
  }

  Future<void> loadArchive({bool keepLive = false}) async {
    ClassroomArchive? saved;
    try {
      saved = await library.lookup(localCourse);
    } catch (_) {
      /* Official fetch remains available. */
    }
    if (!mounted) return;
    if (saved != null &&
        (!keepLive || saved.courses.any((c) => c.id == selected?.id))) {
      setState(() {
        archive = saved;
        if (!keepLive) {
          recordings = saved!.pages.first;
          selected = saved.course;
          busy = false;
        }
      });
    } else if (!keepLive) {
      await connect();
    }
  }

  Future<void> startWorkspace(ClassroomSession? workspace) async {
    if (!mounted) {
      if (workspace != null) cache.release(workspace.view);
      return;
    }
    if (workspace == null) {
      await connect();
      return;
    }
    setState(() {
      entry = workspace.entry;
      active = recordTab = catalogTab = 0;
      selected = null;
      needsCatalog = true;
      busy = true;
      loading = false;
      connectionPhase = ClassroomConnectionPhase.reading;
      showWeb = true;
      tabs.add(_SchoolTab(purpose: _Purpose.browse, retained: workspace.view));
      message = '正在读取学校课程目录…';
    });
  }

  Future<void> nextImport(_SchoolTab tab) async {
    if (!mounted || !tabs.contains(tab)) return;
    collection.reset();
    if (!bulk) {
      setState(() {
        autoCollecting = false;
        recordings = archive!.pages.first;
        selected = recordings!.course;
        busy = showWeb = false;
        connectionPhase = ClassroomConnectionPhase.updated;
        message = null;
      });
      return;
    }
    if (retryQueue != null
        ? retryQueue!.isEmpty
        : importIndex + 1 == importProgress.items.length) {
      setState(() {
        importFinished = true;
        busy = false;
        showWeb = false;
        message = null;
        connectionPhase = ClassroomConnectionPhase.updated;
      });
      connection.cancelPoll();
      return;
    }
    setState(() {
      importIndex = retryQueue == null
          ? importIndex + 1
          : retryQueue!.removeAt(0);
      importProgress.update(importIndex, ImportTaskStatus.running);
      selected = null;
      recordings = null;
      catalog = null;
      rememberedAttempted = false;
      fetchedAt = null;
    });
    await navigateOfficial(tab, {'action': 'catalogRoute'}, _Purpose.browse);
  }

  Future<void> importRecordPage(_SchoolTab tab, RecordingPage page) async {
    if (!mounted || importingPage || importFinished) return;
    importingPage = true;
    try {
      final nextPage = collection.addPage(page, DateTime.now());
      if (nextPage != null) {
        await changePage(nextPage);
        return;
      }
      if (!collection.complete) {
        await navigateOfficial(tab, {
          'action': 'catalogRoute',
        }, _Purpose.browse);
      } else {
        await finishNameImport(tab);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          fetchedAt = null;
          busy = false;
          connectionPhase = ClassroomConnectionPhase.failed;
          message = '本门课程未能完整导入，已完成的课程保留。可重试当前课程。';
          if (bulk) {
            importProgress.update(
              importIndex,
              ImportTaskStatus.failed,
              message,
            );
          }
        });
      }
    } finally {
      importingPage = false;
    }
  }

  Future<void> finishNameImport(_SchoolTab tab) async {
    final saved = await importCoordinator.commit(
      localCourse,
      active: () => mounted,
    );
    if (!mounted || saved == null) return;
    if (!bulk) archive = saved;
    imported++;
    if (bulk) importProgress.update(importIndex, ImportTaskStatus.completed);
    await nextImport(tab);
  }

  Future<void> collectNameMatches(
    _SchoolTab tab,
    List<ClassroomCourse> matches,
  ) async {
    if (matches.isEmpty) {
      TestDiagnostics.shared.record(TestEvent.unmatched);
      if (bulk) {
        importProgress.update(
          importIndex,
          ImportTaskStatus.unmatched,
          '学校该学期未找到精确同名课程',
        );
        skipped.add(localCourse.name);
        await nextImport(tab);
      }
      return;
    }
    collection.prepare(matches);
    if (!collection.complete && AppFeatures.directCatalog) {
      final ticket = generation;
      bool activeRead() =>
          mounted &&
          foreground &&
          connectionPhase != ClassroomConnectionPhase.authentication &&
          ticket == generation &&
          tabs.contains(tab) &&
          libraryRevision == library.revision;
      try {
        final outcome = await importCoordinator.readDirect(
          semester: localCourse.semester,
          courses: matches,
          call: (command) => scripts.directory(tab.controller!, command),
          active: activeRead,
        );
        if (!activeRead()) return;
        if (outcome == DirectoryCollectionResult.ready) {
          assert(() {
            debugPrint('CampusDirectoryTransport=direct');
            return true;
          }());
          // Commit only after the entire name group was verified. The official
          // page stays at the catalog; playback must restore its own source.
          livePage = null;
          liveCourse = null;
          await finishNameImport(tab);
          return;
        }
        assert(() {
          debugPrint('CampusDirectoryTransport=fallback');
          return true;
        }());
      } on ClassroomApiFailure catch (error) {
        if (!activeRead()) return;
        if (error.state == 'authentication') {
          requireAuthentication(tab);
          return;
        }
        setState(() {
          busy = false;
          fetchedAt = null;
          connectionPhase = error.state == 'forbidden'
              ? ClassroomConnectionPhase.forbidden
              : ClassroomConnectionPhase.failed;
          message = '学校录播目录未能完整读取，原目录保留。请重新连接后重试。';
          if (bulk) {
            importProgress.update(
              importIndex,
              ImportTaskStatus.failed,
              message,
            );
          }
        });
        return;
      }
    }
    if (collection.complete) {
      await finishNameImport(tab);
    } else {
      await choose(tab, importMatches![sourceIndex]);
    }
  }

  Future<void> refreshRecordings() async {
    final revision = library.revision;
    bool discardClearedDirectory() {
      if (revision == library.revision) return false;
      setState(() {
        clearTabs();
        active = recordTab = catalogTab = 0;
        archive = null;
        recordings = null;
        selected = null;
        catalog = null;
        fetchedAt = null;
        showWeb = busy = false;
        connectionPhase = ClassroomConnectionPhase.paused;
        message = '学校会话或目录已清除，请重新连接并导入。';
      });
      return true;
    }

    queuedPlayback = null;
    queuedCourseId = null;
    if (archive == null) {
      await changePage(recordings!.page);
      return;
    }
    ClassroomConnectionStatus? outcome;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClassroomCoursePage(
          course: localCourse,
          onDetails: (_) {},
          importCourses: [localCourse],
          library: library,
          links: links,
          probe: widget.probe,
          onImportResult: (value) => outcome = value,
          progressStore: widget.progressStore,
        ),
      ),
    );
    if (!mounted) return;
    if (discardClearedDirectory()) return;
    setState(() {
      clearTabs();
      active = recordTab = catalogTab = 0;
      fetchedAt = null;
      restored = false;
      busy = false;
      showWeb = false;
      cacheRevision = cache.revision;
      connectionPhase = outcome?.phase ?? ClassroomConnectionPhase.paused;
      message = outcome?.detail;
    });
    // Keep the readable old archive if the task was cancelled or re-reading
    // storage fails. The route owns its WebView; no new connection is implied.
    try {
      final saved = await library.lookup(localCourse);
      if (!mounted) return;
      if (discardClearedDirectory()) return;
      if (saved != null) {
        setState(() {
          archive = saved;
          recordings = saved.pages.first;
          selected = recordings!.course;
        });
      }
    } catch (_) {
      if (!mounted || discardClearedDirectory()) return;
      if (mounted) {
        setState(() {
          connectionPhase = ClassroomConnectionPhase.failed;
          message = '未能重新读取目录，继续显示此前的本地列表。';
        });
      }
    }
  }

  void reportImportResult() {
    if (bulk) {
      widget.onImportResult?.call(
        importProgress.count(ImportTaskStatus.completed) ==
                importProgress.items.length
            ? const ClassroomConnectionStatus(ClassroomConnectionPhase.updated)
            : connectionStatus.needsRecovery
            ? connectionStatus
            : const ClassroomConnectionStatus(
                ClassroomConnectionPhase.paused,
                '导入未完成，已导入目录保留。',
              ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final tab in tabs) {
      tab.loadTimer?.cancel();
    }
    connection.dispose();
    playbackGeneration++;
    unawaited(
      classroomPlaybackChannel
          .invokeMethod<void>('cancel')
          .catchError((Object _) {}),
    );
    connection.cancelPoll();
    final index = recordTab;
    _SchoolTab? retained;
    if (!bulk &&
        !synthetic &&
        !busy &&
        !loading &&
        !showWeb &&
        (archive == null || archive!.courses.length == 1) &&
        recordings != null &&
        selected != null &&
        fetchedAt != null &&
        entry != null &&
        index < tabs.length &&
        tabs[index].purpose == _Purpose.records) {
      retained = tabs[index];
      final saved = ClassroomSession(
        view: retained.retained,
        records: recordings!,
        entry: entry!,
        fetchedAt: fetchedAt!,
        offset: lastOffset,
        documentPage: livePage,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        cache.put(localCourse, saved, revision: cacheRevision);
      });
    }
    if (bulk &&
        importFinished &&
        !busy &&
        retained == null &&
        tabs.isNotEmpty &&
        entry != null &&
        completedArchives.isNotEmpty) {
      retained = tabs[active];
      final saved = completedArchives.values.last;
      final session = ClassroomSession(
        view: retained.retained,
        records: saved.pages.first,
        entry: entry!,
        fetchedAt: saved.importedAt,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        cache.putWorkspace(session, revision: cacheRevision);
      });
    }
    releaseTabs(tabs.where((tab) => tab != retained));
    scroll.dispose();
    super.dispose();
  }

  Future<void> openSchoolPage() async {
    if (tabs.isEmpty) {
      // A failed route probe creates no WebView. An explicit user action may
      // still open the fixed official HTTPS entry with normal TLS validation.
      await connect(ClassroomAccess.vpn);
    } else {
      setState(() => authVisible = showWeb = true);
    }
  }

  Future<void> connect([
    ClassroomAccess mode = ClassroomAccess.automatic,
  ]) async {
    fetchedAt = null;
    readProgress.reset();
    livePage = null;
    liveCourse = null;
    freshReadPending = true;
    restored = false;
    authVisible = false;
    automaticEntry = true;
    automaticPath = mode == ClassroomAccess.automatic;
    playbackGeneration++;
    unawaited(
      classroomPlaybackChannel
          .invokeMethod<void>('cancel')
          .catchError((Object _) {}),
    );
    final ticket = connection.advance();
    connection.cancelPoll();
    setState(() {
      // A new selection must not display or keep callbacks from the old login.
      showWeb = loading = false;
      if (tabs.isNotEmpty) clearTabs();
      active = 0;
      busy = true;
      connectionPhase = ClassroomConnectionPhase.connecting;
      message = '正在检查学校服务访问路径…';
    });
    final decision = await connection.select(mode, ticket: ticket);
    if (!mounted || decision == null || ticket != generation) return;
    setState(() {
      clearTabs();
      catalog = null;
      recordings = queuedPlayback == null
          ? null
          : archive?.sourcePage(queuedCourseId ?? '', queuedPlayback!.id);
      selected = null;
      rememberedAttempted = false;
      active = recordTab = catalogTab = 0;
      busy = false;
      automaticPath =
          mode == ClassroomAccess.automatic &&
          decision.mode == ClassroomAccess.direct;
      entry =
          mode == ClassroomAccess.automatic &&
              decision.mode == ClassroomAccess.direct
          ? classroomProbe
          : decision.url;
      message = decision.message;
      showWeb = entry != null;
      // WebVPN may present its sign-in inside an iframe without reporting the
      // classroom authentication state. Keep a new connection visible until a
      // verified school catalog/record page can resume the native workflow.
      authVisible = showWeb;
      busy = showWeb;
      loading = showWeb;
      if (showWeb) tabs.add(_SchoolTab(purpose: _Purpose.browse));
    });
  }

  Future<bool> fallbackToVpn() async {
    if (!automaticPath ||
        (recordings != null && queuedPlayback == null) ||
        catalog != null ||
        selected != null) {
      return false;
    }
    automaticPath = false;
    await connect(ClassroomAccess.vpn);
    return true;
  }

  void requireAuthentication(_SchoolTab tab) {
    if (connectionPhase != ClassroomConnectionPhase.authentication) {
      // Login completing quickly must not reactivate a pre-login read.
      connection.advance();
    }
    TestDiagnostics.shared.record(TestEvent.authenticationNeeded);
    authVisible = true;
    fetchedAt = null;
    freshReadPending = false;
    restored = false;
    setState(() {
      // Authentication is evidence that the selected route is reachable.
      // Keep that route while the user signs in; it is not a VPN fallback.
      automaticPath = false;
      recordings = null;
      catalog = null;
      selected = null;
      rememberedAttempted = false;
      tab.purpose = _Purpose.browse;
      tab.routed = false;
      showWeb = true;
      busy = false;
      connectionPhase = ClassroomConnectionPhase.authentication;
      message = '请在学校官方页面完成认证；登录成功后将继续自动获取录播。';
    });
    readProgress.advance(ClassroomReadStage.authentication);
    scheduleRead(tab);
  }

  Future<Map<String, dynamic>> advanceEntry(_SchoolTab tab) async {
    if (!automaticEntry || tab.navigationStopped || tab.advancing) {
      return {'state': 'waiting'};
    }
    if (tab.entryHops >= ClassroomLimits.entryHops) {
      tab.navigationStopped = true;
      return {'state': 'blocked'};
    }
    tab.advancing = true;
    try {
      final data = await scripts.entry(tab.controller!);
      final state = data['state'] as String;
      if (state == 'opening') {
        tab.entryHops++;
      } else {
        tab.advancing = false;
      }
      if (state == 'blocked') tab.navigationStopped = true;
      return Map<String, dynamic>.from(data);
    } catch (_) {
      tab.advancing = false;
      return {'state': 'waiting'};
    }
  }

  Future<Map<String, dynamic>> script(
    _SchoolTab tab,
    Map<String, dynamic> command,
  ) => scripts.command(tab.controller!, command);

  void scheduleRead(_SchoolTab tab, {bool restart = false}) {
    connection.cancelPoll();
    if (restart) {
      attempts = 0;
      readProgress.reset();
    }
    if (!mounted ||
        !foreground ||
        tab.loadTimedOut ||
        tab.purpose == _Purpose.playback) {
      return;
    }
    connection.schedulePoll(readProgress.stage, () => inspect(tab));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      connection.advance();
      connection.cancelPoll();
      for (final tab in tabs) {
        tab.loadTimer?.cancel();
        tab.loadTimer = null;
      }
    } else if (tabs.isNotEmpty && automaticEntry) {
      final tab = tabs[active];
      if (loading) {
        armPageLoadTimeout(tab);
      }
      scheduleRead(tabs[active], restart: true);
    }
  }

  bool allowRead(ClassroomReadStage stage) {
    if (readProgress.advance(stage)) {
      attempts = readProgress.attempts;
      return true;
    }
    setState(() {
      authVisible = true;
      showWeb = true;
      busy = false;
      connectionPhase = ClassroomConnectionPhase.failed;
      message = readProgress.timeoutMessage;
      if (bulk) {
        importProgress.update(importIndex, ImportTaskStatus.failed, message);
      }
    });
    return false;
  }

  Future<void> retryCurrent() async {
    if (bulk) importProgress.update(importIndex, ImportTaskStatus.running);
    collection.reset();
    if (tabs.isEmpty) {
      await connect();
      return;
    }
    final tab = tabs[active];
    if (tab.loadTimedOut) {
      automaticEntry = true;
      tab.loadTimedOut = false;
      tab.navigationStopped = false;
      readProgress.reset();
      setState(() {
        busy = true;
        connectionPhase = ClassroomConnectionPhase.connecting;
        message = '正在重新加载学校页面…';
      });
      try {
        await tab.controller?.reload();
      } catch (_) {
        if (mounted) {
          setState(() {
            busy = false;
            connectionPhase = ClassroomConnectionPhase.failed;
            message = '页面重新加载未完成，请重新连接学校入口。';
          });
        }
      }
      return;
    }
    automaticEntry = true;
    tab.navigationStopped = tab.advancing = false;
    tab.entryHops = 0;
    final ticket = connection.advance();
    connection.cancelPoll();
    readProgress.reset();
    setState(() {
      authVisible = showWeb = true;
      busy = true;
      connectionPhase = ClassroomConnectionPhase.reading;
      message = '正在识别当前学校页面并继续导入…';
    });
    try {
      final data = await script(tab, {'action': 'snapshot'});
      if (!mounted || ticket != generation || !tabs.contains(tab)) return;
      // catalogRoute exists only inside the classroom SPA. A portal/login
      // document must re-enter through the entry coordinator instead.
      if (data['state'] == 'catalog' || data['state'] == 'records') {
        selected = null;
        rememberedAttempted = false;
        await navigateOfficial(tab, {
          'action': 'catalogRoute',
        }, _Purpose.browse);
      } else {
        tab.purpose = _Purpose.browse;
        tab.routed = false;
        scheduleRead(tab, restart: true);
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          busy = false;
          connectionPhase = ClassroomConnectionPhase.failed;
          message = '当前学校页面未能读取，请重新加载页面后点击继续导入。';
        });
      }
    }
  }

  void watchPageLoad(_SchoolTab tab, String address) {
    tab.dedicatedTarget = dedicatedClassroomEntry(address);
    if (tab.dedicatedTarget == null) {
      tab.ccLoads = 0;
    } else if (++tab.ccLoads >= 6 && !tab.dedicatedRecovered) {
      recoverPageLoad(tab);
      return;
    }
    armPageLoadTimeout(tab);
  }

  void armPageLoadTimeout(_SchoolTab tab) {
    tab.loadTimer ??= Timer(ClassroomLimits.documentTimeout, () {
      tab.loadTimer = null;
      unawaited(checkPageLoadTimeout(tab));
    });
  }

  bool pageLoadPending(_SchoolTab tab) =>
      mounted &&
      foreground &&
      tabs.contains(tab) &&
      tabs[active] == tab &&
      loading &&
      !tab.loadTimedOut;

  void completeDocumentLoad(_SchoolTab tab) {
    tab.loadTimer?.cancel();
    tab.loadTimer = null;
    tab.ccLoads = 0;
    if (loading) setState(() => loading = false);
  }

  Future<void> checkPageLoadTimeout(_SchoolTab tab) async {
    if (!pageLoadPending(tab)) return;
    final ticket = generation;
    try {
      // A slow optional resource may keep WebView's load-stop pending after
      // the official SPA is already usable. Check its bounded state once.
      final data = await script(tab, {
        'action': 'snapshot',
      }).timeout(ClassroomLimits.readyTimeout);
      if (!pageLoadPending(tab) || ticket != generation) return;
      if (const {
        'catalog',
        'records',
        'authentication',
        'forbidden',
        'error',
        'serviceUnavailable',
      }.contains(data['state'])) {
        await inspect(tab, snapshot: data);
        return;
      }
    } catch (_) {
      // A stalled or unreadable document still uses the existing recovery UI.
    }
    if (pageLoadPending(tab) && ticket == generation) recoverPageLoad(tab);
  }

  void recoverPageLoad(_SchoolTab tab) {
    if (!mounted || !foreground || !tabs.contains(tab) || tabs[active] != tab) {
      return;
    }
    tab.loadTimer?.cancel();
    tab.loadTimer = null;
    connection.cancelPoll();
    final target = tab.dedicatedTarget;
    if (target != null && !tab.dedicatedRecovered) {
      connection.advance();
      automaticEntry = true;
      automaticPath = automaticPath && !target.startsWith(vpnEntry);
      readProgress.reset();
      collection.clearPages();
      setState(() {
        // Replace the looping document rather than competing with its script
        // redirects. WebView keeps its normal shared school session.
        clearTabs();
        active = recordTab = catalogTab = 0;
        entry = target;
        catalog = null;
        selected = null;
        rememberedAttempted = false;
        tabs.add(
          _SchoolTab(purpose: _Purpose.browse)..dedicatedRecovered = true,
        );
        authVisible = showWeb = true;
        busy = loading = true;
        connectionPhase = ClassroomConnectionPhase.platform;
        message = '学校首页加载未完成，正在通过专用课程入口继续导入…';
      });
    } else {
      tab.loadTimedOut = true;
      tab.navigationStopped = true;
      setState(() {
        authVisible = showWeb = true;
        busy = loading = false;
        connectionPhase = ClassroomConnectionPhase.failed;
        message = '学校页面加载超时。点击继续导入可重新加载，已完成的导入保留。';
      });
    }
  }

  void reportServiceUnavailable(_SchoolTab tab) {
    TestDiagnostics.shared.record(TestEvent.upstreamConnectionFailed);
    connection.cancelPoll();
    tab.loadTimer?.cancel();
    tab.loadTimer = null;
    // Explicit retry reloads the failed proxy document. Keep archived data and
    // do not misclassify an upstream failure as an expired school session.
    tab.loadTimedOut = true;
    tab.advancing = false;
    freshReadPending = false;
    setState(() {
      busy = false;
      authVisible = showWeb = true;
      connectionPhase = ClassroomConnectionPhase.unavailable;
      message = '学校服务暂时无法连接。可稍后点击继续导入重新加载，或返回学校入口检查；已导入内容保留。';
      if (bulk) {
        importProgress.update(importIndex, ImportTaskStatus.failed, message);
      }
    });
  }

  Future<void> inspect(_SchoolTab tab, {Map<String, dynamic>? snapshot}) async {
    if (!mounted ||
        !foreground ||
        !tabs.contains(tab) ||
        tabs[active] != tab ||
        tab.controller == null) {
      return;
    }
    attempts++;
    final ticket = generation;
    try {
      final data = snapshot ?? await script(tab, {'action': 'snapshot'});
      if (!mounted || ticket != generation || !tabs.contains(tab)) return;
      if (const {
        'catalog',
        'records',
        'authentication',
        'forbidden',
        'error',
        'serviceUnavailable',
      }.contains(data['state'])) {
        completeDocumentLoad(tab);
      }
      if (data['state'] == 'serviceUnavailable') {
        reportServiceUnavailable(tab);
        return;
      }
      if (data['state'] == 'authentication') {
        requireAuthentication(tab);
        return;
      }
      if (data['state'] == 'forbidden' || data['state'] == 'error') {
        TestDiagnostics.shared.failure(data['state'] as String?);
        fetchedAt = null;
        freshReadPending = false;
        if (bulk) {
          importProgress.update(
            importIndex,
            ImportTaskStatus.failed,
            '学校请求失败或当前账号没有权限',
          );
        }
        setState(() {
          busy = false;
          connectionPhase = data['state'] == 'forbidden'
              ? ClassroomConnectionPhase.forbidden
              : ClassroomConnectionPhase.failed;
          message = data['state'] == 'forbidden'
              ? '学校提示当前账号没有查看权限。'
              : '学校请求失败，请检查官方页面或稍后重试。';
        });
        return;
      }
      if (data['state'] != 'navigate' && !allowRead(ClassroomReadStage.data)) {
        return;
      }
      if (needsCatalog &&
          (data['state'] == 'catalog' || data['state'] == 'records')) {
        needsCatalog = false;
        await navigateOfficial(tab, {
          'action': 'catalogRoute',
        }, _Purpose.browse);
        return;
      }
      if (data['state'] == 'catalog' && tab.purpose != _Purpose.records) {
        authVisible = false;
        final courses = (data['courses'] as List)
            .map(
              (v) =>
                  ClassroomCourse.fromJson(Map<String, dynamic>.from(v as Map)),
            )
            .where((v) => v.semester == localCourse.semester)
            .toList();
        if (courses.isEmpty && attempts < 4) {
          scheduleRead(tab);
          return;
        }
        if (!mounted ||
            ticket != generation ||
            tab.purpose == _Purpose.records) {
          return;
        }
        setState(() {
          catalog = courses;
          catalogTab = tabs.indexOf(tab);
          showWeb = false;
          busy = false;
          connectionPhase = ClassroomConnectionPhase.reading;
          final sameNames = courses
              .where((course) => course.matches(localCourse))
              .length;
          message = courses.isEmpty
              ? '当前页面没有该学期的课程。请在官方平台切换学期后重新读取。'
              : sameNames > 1
              ? '已按课程名称匹配 $sameNames 门学校课程，正在汇总全部回放…'
              : sameNames == 0
              ? '未找到该学期的同名课程，请检查课程名称或学校学期。'
              : rememberedAttempted
              ? '请选择与课表对应的学校课程。'
              : '已按课程名称匹配，正在获取录播…';
        });
        final matches = matchingClassroomCourses(localCourse, courses);
        if ((bulk && !importFinished) ||
            (queuedPlayback == null && !rememberedAttempted)) {
          if (courses.isEmpty || importingPage) return;
          importingPage = true;
          try {
            autoCollecting = !bulk && matches.isNotEmpty;
            await collectNameMatches(tab, matches);
          } finally {
            importingPage = false;
            // A poll may have seen the authenticated catalog while the old
            // read still held the collection lock. Resume after releasing it.
            if (mounted &&
                foreground &&
                ticket != generation &&
                tabs.contains(tab) &&
                !importFinished) {
              scheduleRead(tab);
            }
          }
          return;
        }
        final match = matches.where((c) => c.id == queuedCourseId).firstOrNull;
        if (!rememberedAttempted && match != null) {
          rememberedAttempted = true;
          await choose(tab, match);
        } else if (queuedPlayback != null && match == null) {
          setState(() {
            queuedPlayback = null;
            busy = false;
            connectionPhase = ClassroomConnectionPhase.forbidden;
            message = '原回放所属的同名课程已不可访问，请刷新回放目录后重试。';
          });
        }
        return;
      }
      if (data['state'] == 'records') {
        if (selected == null && busy && tab.purpose == _Purpose.browse) {
          scheduleRead(tab);
          return;
        }
        final page = RecordingPage.fromJson(data);
        if (selected == null ||
            page.course.id != selected!.id ||
            page.course.semester != localCourse.semester) {
          setState(() {
            fetchedAt = null;
            message = '请先返回选择课表对应的学校课程。';
            busy = false;
          });
          return;
        }
        if (page.records.isEmpty && page.total == 0 && attempts < 4) {
          scheduleRead(tab);
          return;
        }
        setState(() {
          if (bulk || archive == null || recordings == null) recordings = page;
          livePage = page.page;
          liveCourse = page.course.id;
          if (freshReadPending) {
            fetchedAt = DateTime.now();
            freshReadPending = false;
          }
          recordTab = tabs.indexOf(tab);
          showWeb = false;
          busy = collecting;
          connectionPhase = collecting
              ? ClassroomConnectionPhase.reading
              : ClassroomConnectionPhase.updated;
          message = null;
        });
        if (collecting) {
          await importRecordPage(tab, page);
          return;
        }
        if (queuedPlayback != null) {
          if (page.page != queuedPage) {
            await changePage(queuedPage);
            return;
          }
          final candidates = page.records
              .where((r) => r.id == queuedPlayback!.id && r.published)
              .toList();
          queuedPlayback = null;
          if (candidates.length == 1) {
            unawaited(
              playNative(candidates.single, sourceCourseId: page.course.id),
            );
          } else {
            setState(() => message = '录播列表已变化，请刷新后重新选择。');
          }
        }
        try {
          await links.bind(localCourse, page.course.id);
        } catch (_) {
          if (mounted) setState(() => message = '本次可继续查看，但课程关联未保存成功。');
        }
        return;
      }
      if (data['state'] == 'navigate' && tab.purpose == _Purpose.browse) {
        final entryResult = await advanceEntry(tab);
        final state = entryResult['state'];
        if (!mounted || ticket != generation || !tabs.contains(tab)) return;
        if (state == 'serviceUnavailable') {
          reportServiceUnavailable(tab);
          return;
        }
        if (state == 'authentication') {
          completeDocumentLoad(tab);
          requireAuthentication(tab);
          return;
        }
        if (state == 'blocked' || state == 'untrusted') {
          if (bulk) {
            importProgress.update(
              importIndex,
              ImportTaskStatus.failed,
              '学校入口路径或跳转未通过校验',
            );
          }
          setState(() {
            busy = false;
            authVisible = showWeb = true;
            connectionPhase = ClassroomConnectionPhase.failed;
            message = state == 'untrusted'
                ? '当前页面不属于已支持的学校入口路径。请在官方页面进入教学平台后点击继续导入。'
                : '平台入口跳转未通过校验。请在官方页面手动进入，或切换学校 WebVPN 后继续导入。';
          });
          return;
        }
        final stage = entryResult['stage'] == 'platform'
            ? ClassroomReadStage.platform
            : ClassroomReadStage.portal;
        if (!allowRead(stage)) return;
        connectionPhase = stage == ClassroomReadStage.portal
            ? ClassroomConnectionPhase.portal
            : ClassroomConnectionPhase.platform;
        if (state == 'opening') {
          setState(() {
            busy = true;
            message = '正在自动进入学校课程平台…';
          });
        } else {
          setState(() {
            busy = true;
            message = entryResult['reason'] == 'modal'
                ? '学校页面有弹窗，请处理后继续导入。'
                : stage == ClassroomReadStage.portal
                ? '正在等待 WebVPN 门户入口；可在官方页面手动进入教学平台。'
                : '正在等待课程平台入口；可在官方页面手动进入课程平台。';
          });
        }
      }
      if (tab.purpose == _Purpose.records && !tab.routed) {
        final result = await script(tab, {'action': 'recordsRoute'});
        if (result['state'] == 'opening') tab.routed = true;
      }
      scheduleRead(tab);
    } catch (_) {
      if (mounted && ticket == generation) {
        fetchedAt = null;
        freshReadPending = false;
        setState(() {
          busy = false;
          connectionPhase = ClassroomConnectionPhase.failed;
          message = '学校页面结构暂不支持读取，请在官方页面检查登录、权限及当前学期后重试。';
          if (bulk) {
            importProgress.update(
              importIndex,
              ImportTaskStatus.failed,
              message,
            );
          }
        });
      }
    }
  }

  Future<void> navigateOfficial(
    _SchoolTab tab,
    Map<String, dynamic> command,
    _Purpose purpose,
  ) async {
    connection.cancelPoll();
    setState(() {
      showWeb = true;
      busy = true;
      message = '正在打开学校官方页面…';
    });
    try {
      tab.purpose = purpose;
      final result = await script(tab, command);
      if (command['action'] == 'catalogRoute' &&
          const {
            'navigate',
            'authentication',
            'loading',
          }.contains(result['state'])) {
        if (!mounted || !tabs.contains(tab)) return;
        needsCatalog = true;
        automaticEntry = true;
        tab.routed = false;
        setState(() {
          authVisible = showWeb = true;
          message = '正在恢复学校课程页面，请在需要时完成官方认证。';
        });
        if (result['state'] == 'authentication') {
          requireAuthentication(tab);
        } else {
          scheduleRead(tab, restart: true);
        }
        return;
      }
      if (result['state'] != 'opening') throw const FormatException();
      if (!mounted || !tabs.contains(tab)) return;
      if (purpose == _Purpose.playback) {
        setState(() {
          busy = false;
          loading = false;
          message = '正在使用学校官方播放器。';
        });
      } else {
        scheduleRead(tab, restart: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          showWeb = false;
          message = '学校数据已变化，请刷新列表后重试。';
        });
      }
    }
  }

  Future<void> choose(_SchoolTab tab, ClassroomCourse course) async {
    if (!mounted || !tabs.contains(tab)) return;
    freshReadPending = true;
    fetchedAt = null;
    final index = tabs.indexOf(tab);
    trimTabs(index + 1);
    active = index;
    selected = course;
    await navigateOfficial(tab, {
      'action': 'choose',
      'id': course.id,
      'semester': course.semester,
    }, _Purpose.records);
  }

  Future<void> changeCourse() async {
    queuedPlayback = null;
    await refreshRecordings();
  }

  Future<void> changePage(int page) async {
    if (!mounted || (tabs.isEmpty && archive == null)) return;
    if (!bulk && archive != null && queuedPlayback == null) {
      if (page >= 1 && page <= archive!.pages.length) {
        setState(() => recordings = archive!.pages[page - 1]);
      }
      return;
    }
    if (tabs[recordTab].controller == null) return;
    fetchedAt = null;
    freshReadPending = true;
    restored = false;
    final tab = tabs[recordTab];
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final value = await script(tab, {'action': 'page', 'page': page});
      if (value['state'] != 'opening') throw const FormatException();
      active = recordTab;
      scheduleRead(tab, restart: true);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = '录播分页未能加载，请重新读取。';
        });
      }
    }
  }

  Future<void> playNative(
    ClassroomRecording record, {
    String? sourceCourseId,
    GlobalKey? button,
  }) async {
    if (busy || !record.published) return;
    if (button != null) {
      playbackButton = button;
      playbackReducedMotion =
          MediaQuery.disableAnimationsOf(context) ||
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    }
    final targetCourse =
        sourceCourseId ?? recordings?.course.id ?? selected?.id;
    final sourcePage = targetCourse == null
        ? null
        : archive?.sourcePage(targetCourse, record.id);
    final targetPage = sourcePage?.page ?? recordings?.page ?? 1;
    if (archive != null &&
        tabs.isNotEmpty &&
        (livePage != targetPage || liveCourse != targetCourse)) {
      queuedPlayback = record;
      queuedCourseId = targetCourse;
      queuedPage = targetPage;
      if (liveCourse == targetCourse) {
        selected = sourcePage?.course ?? recordings?.course;
        await changePage(queuedPage);
      } else {
        selected = null;
        rememberedAttempted = false;
        await navigateOfficial(tabs[recordTab], {
          'action': 'catalogRoute',
        }, _Purpose.browse);
      }
      return;
    }
    if (tabs.isEmpty) {
      queuedPlayback = record;
      queuedCourseId = targetCourse;
      queuedPage = targetPage;
      if (queuedPage < 1) {
        queuedPlayback = null;
        return;
      }
      await startWorkspace(cache.takeWorkspace());
      return;
    }
    final tab = tabs[recordTab];
    final view = tab.controller?.getViewId();
    if (view is! int && view is! String) return;
    selected = sourcePage?.course ?? recordings?.course ?? selected;
    final operation = ++playbackGeneration;
    connection.cancelPoll();
    final preparation = ClassroomPlaybackPreparation(
      command: (command) => script(tab, command),
      active: () => mounted && operation == playbackGeneration,
    );
    var handedToPlayer = false;
    tab.purpose = _Purpose.playback;
    setState(() {
      busy = true;
      connectionPhase = ClassroomConnectionPhase.media;
      message = '正在准备课堂视频…';
    });
    try {
      final prepared = await preparation.prepare(view, record.id);
      if (prepared == null || !mounted || operation != playbackGeneration) {
        return;
      }
      await script(tab, {'action': 'returnRecords'});
      livePage = null;
      tab.purpose = _Purpose.records;
      if (!mounted || operation != playbackGeneration) return;
      setState(() {
        showWeb = false;
        connectionPhase = ClassroomConnectionPhase.idle;
        message = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || operation != playbackGeneration || !foreground) return;
      final navigator = Navigator.of(context);
      final colors = Theme.of(context).colorScheme;
      final origin = playbackButtonRect(playbackButton, navigator);
      playbackButton = null;
      handedToPlayer = true;
      preparation.handoff();
      final controller = ClassroomPlayerController(prepared);
      await navigator.push(
        ClassroomPlayerRoute(
          origin: origin,
          color: colors.primary,
          iconColor: colors.onPrimary,
          reducedMotion:
              playbackReducedMotion || MediaQuery.disableAnimationsOf(context),
          builder: (_) => ClassroomPlayerPage(
            title: record.label,
            controller: controller,
            identity: ClassroomPlaybackIdentity(
              semester: localCourse.semester,
              courseId: selected!.id,
              recordId: record.id,
            ),
            progressStore: widget.progressStore,
          ),
        ),
      );
      if (controller.state.error != null || controller.failure != null) {
        fetchedAt = null;
      }
    } catch (error) {
      TestDiagnostics.shared.mediaFailure(
        error is PlatformException ? error.code : null,
      );
      fetchedAt = null;
      freshReadPending = false;
      if (mounted && operation == playbackGeneration) {
        final detail = ClassroomPlaybackPreparation.failureMessage(error);
        setState(() {
          busy = false;
          connectionPhase = ClassroomConnectionPhase.failed;
          message = detail;
        });
      }
    } finally {
      await preparation.release();
      if (mounted && operation == playbackGeneration && tabs.contains(tab)) {
        if (tab.purpose == _Purpose.playback) {
          try {
            await script(tab, {'action': 'returnRecords'});
          } catch (_) {
            /* Visible reconnection remains available. */
          }
          tab.purpose = _Purpose.records;
        }
        if (mounted) {
          setState(() => busy = false);
          if (handedToPlayer && fetchedAt != null) {
            scheduleRead(tab, restart: true);
          }
        }
      }
    }
  }

  Future<void> closeWeb() async {
    connection.advance();
    automaticEntry = false;
    automaticPath = false;
    connection.cancelPoll();
    if (tabs.isNotEmpty && tabs[active].purpose == _Purpose.playback) {
      final tab = tabs[active];
      try {
        final result = await script(tab, {'action': 'returnRecords'});
        if (result['state'] != 'opening') throw const FormatException();
        tab.purpose = _Purpose.records;
        scheduleRead(tab, restart: true);
      } catch (_) {
        clearTabs();
        recordings = null;
        catalog = null;
        selected = null;
      }
      if (!mounted) return;
    }
    if (recordings == null && archive != null) {
      recordings = archive!.pages.first;
      selected = recordings!.course;
    }
    if (recordings != null) {
      trimTabs((recordTab + 1).clamp(0, tabs.length));
      active = recordTab;
    } else {
      clearTabs();
      active = 0;
      catalog = null;
      selected = null;
    }
    setState(() {
      showWeb = false;
      busy = false;
      if (!connectionStatus.needsRecovery) {
        connectionPhase = ClassroomConnectionPhase.paused;
        message = '已返回课程，可继续查看本地目录。';
      }
    });
  }

  Future<void> webBack() async {
    automaticEntry = false;
    automaticPath = false;
    rememberedAttempted = true;
    if (tabs[active].purpose != _Purpose.playback &&
        await tabs[active].controller?.canGoBack() == true) {
      await tabs[active].controller?.goBack();
    } else {
      await closeWeb();
    }
  }

  Widget browser() => Scaffold(
    appBar: AppBar(
      title: const Text('学校官方页面'),
      leading: IconButton(
        onPressed: webBack,
        icon: const AppIcon(AppIcons.arrowBack),
      ),
      actions: [
        PopupMenuButton<ClassroomAccess>(
          icon: const AppIcon(AppIcons.moreVertical),
          tooltip: '学校访问方式',
          onSelected: connect,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: ClassroomAccess.automatic,
              child: Text('自动选择（重新检测）'),
            ),
            PopupMenuItem(
              value: ClassroomAccess.vpn,
              child: Text('校外访问（学校 WebVPN）'),
            ),
            PopupMenuItem(
              value: ClassroomAccess.direct,
              child: Text('数字北中医（直接访问）'),
            ),
          ],
        ),
        IconButton(
          tooltip: '继续导入',
          onPressed: busy || tabs[active].purpose == _Purpose.playback
              ? null
              : retryCurrent,
          icon: const AppIcon(AppIcons.refresh),
        ),
        IconButton(
          tooltip: '返回课程',
          onPressed: closeWeb,
          icon: const AppIcon(AppIcons.close),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (loading || busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Text(
              message ??
                  '请在官方页面完成认证并进入课程平台。WebVPN 中可打开“智慧教学平台”；也可从数字北中医应用中心进入。',
            ),
          ),
          if (!busy && tabs[active].purpose != _Purpose.playback)
            TextButton.icon(
              onPressed: retryCurrent,
              icon: const AppIcon(AppIcons.refresh),
              label: const Text('继续导入'),
            ),
          Expanded(
            child: Stack(
              children: [
                for (final tab in tabs)
                  Positioned.fill(
                    key: ObjectKey(tab),
                    child: Offstage(
                      offstage: tabs[active] != tab,
                      child: InAppWebView(
                        keepAlive: tab.retained,
                        windowId: tab.windowId,
                        initialUrlRequest: tab.windowId == null
                            ? URLRequest(url: WebUri(entry!))
                            : null,
                        initialSettings: InAppWebViewSettings(
                          preferredContentMode:
                              UserPreferredContentMode.DESKTOP,
                          javaScriptEnabled: true,
                          domStorageEnabled: true,
                          supportMultipleWindows: true,
                          javaScriptCanOpenWindowsAutomatically: false,
                          useShouldOverrideUrlLoading: true,
                          useOnDownloadStart: true,
                          thirdPartyCookiesEnabled: false,
                          saveFormData: false,
                          isInspectable: false,
                          allowFileAccess: false,
                          allowContentAccess: false,
                          allowFileAccessFromFileURLs: false,
                          allowUniversalAccessFromFileURLs: false,
                          mixedContentMode:
                              MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                        ),
                        onWebViewCreated: (web) async {
                          tab.controller = web;
                          if (needsCatalog) {
                            // A retained view can have returned to an entry or
                            // authentication page. Wait for a verified SPA
                            // snapshot before issuing its router command.
                            scheduleRead(tab, restart: true);
                            return;
                          }
                          if (!validateRestored) return;
                          validateRestored = false;
                          final ticket = generation;
                          var valid = false;
                          try {
                            final data = await script(tab, {
                              'action': 'snapshot',
                            });
                            final page = data['state'] == 'records'
                                ? RecordingPage.fromJson(data)
                                : null;
                            if (page != null) {
                              livePage = page.page;
                              liveCourse = page.course.id;
                            }
                            valid =
                                page != null &&
                                page.course.id == selected?.id &&
                                page.course.semester == localCourse.semester;
                          } catch (_) {
                            /* Reconnect if the retained document was lost. */
                          }
                          if (mounted && ticket == generation && !valid) {
                            await connect();
                          }
                        },
                        shouldOverrideUrlLoading: (_, action) async {
                          if (tab.loadTimedOut && action.hasGesture != true) {
                            return NavigationActionPolicy.CANCEL;
                          }
                          final target = action.request.url?.toString() ?? '';
                          final allowed = classroomNavigation(target);
                          if (!allowed &&
                              mounted &&
                              tabs.contains(tab) &&
                              tabs[active] == tab) {
                            final uri = Uri.tryParse(target);
                            if (automaticPath &&
                                recordings == null &&
                                catalog == null &&
                                selected == null &&
                                uri?.scheme == 'http' &&
                                const {
                                  'i.bucm.edu.cn',
                                  'qhz.bucm.edu.cn',
                                  'cas.bucm.edu.cn',
                                }.contains(uri?.host)) {
                              unawaited(fallbackToVpn());
                              return NavigationActionPolicy.CANCEL;
                            }
                            setState(() {
                              loading = false;
                              busy = false;
                              connectionPhase = ClassroomConnectionPhase.failed;
                              message = '已阻止非学校或非 HTTPS 跳转，请切换学校 WebVPN。';
                            });
                          }
                          return allowed
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL;
                        },
                        onLoadStart: (_, url) {
                          tab.advancing = false;
                          tab.loadTimedOut = false;
                          if (mounted &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab) {
                            connection.advance();
                            connection.cancelPoll();
                            setState(() => loading = true);
                            watchPageLoad(tab, url?.toString() ?? '');
                          }
                        },
                        onPageCommitVisible: (_, _) {
                          if (mounted &&
                              foreground &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab &&
                              !tab.loadTimedOut &&
                              tab.purpose != _Purpose.playback) {
                            // Read the committed document without waiting for
                            // every stylesheet/image/analytics request to end.
                            scheduleRead(tab, restart: true);
                          }
                        },
                        onLoadStop: (_, _) {
                          if (mounted &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab) {
                            tab.loadTimer?.cancel();
                            tab.loadTimer = null;
                            tab.ccLoads = 0;
                            if (tab.loadTimedOut) return;
                            setState(() => loading = false);
                            scheduleRead(tab, restart: true);
                          }
                        },
                        onUpdateVisitedHistory: (_, _, _) {
                          if (mounted &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab &&
                              tab.purpose != _Purpose.playback) {
                            scheduleRead(tab, restart: true);
                          }
                        },
                        onTitleChanged: (_, _) {
                          if (mounted &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab &&
                              tab.purpose == _Purpose.browse) {
                            scheduleRead(tab, restart: true);
                          }
                        },
                        onCreateWindow: (_, action) async {
                          if (tabs.length >= 9 || action.hasGesture != true) {
                            return false;
                          }
                          setState(() {
                            tabs.add(
                              _SchoolTab(
                                windowId: action.windowId,
                                purpose: _Purpose.browse,
                              ),
                            );
                            active = tabs.length - 1;
                            showWeb = true;
                            busy = false;
                          });
                          return true;
                        },
                        onCloseWindow: (_) {
                          if (mounted) closeWeb();
                        },
                        onReceivedServerTrustAuthRequest: (_, _) async {
                          if (mounted) {
                            setState(() {
                              loading = false;
                              busy = false;
                              connectionPhase = ClassroomConnectionPhase.failed;
                              message = '学校连接证书校验失败，已停止加载。';
                            });
                          }
                          return ServerTrustAuthResponse(
                            action: ServerTrustAuthResponseAction.CANCEL,
                          );
                        },
                        onPermissionRequest: (_, request) async =>
                            PermissionResponse(
                              resources: request.resources,
                              action: PermissionResponseAction.DENY,
                            ),
                        onDownloadStartRequest: (_, _) async {
                          if (mounted) {
                            setState(() => message = '这里只支持在线观看，不下载课程资料。');
                          }
                        },
                        onReceivedError: (_, request, error) {
                          if (mounted &&
                              tabs.contains(tab) &&
                              tabs[active] == tab &&
                              request.isForMainFrame == true) {
                            if (error.type !=
                                    WebResourceErrorType.FAILED_SSL_HANDSHAKE &&
                                automaticPath &&
                                recordings == null &&
                                catalog == null &&
                                selected == null) {
                              unawaited(fallbackToVpn());
                              return;
                            }
                            setState(() {
                              loading = false;
                              busy = false;
                              connectionPhase = ClassroomConnectionPhase.failed;
                              message = '学校页面未能加载，请检查网络或切换 WebVPN。';
                            });
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget native() {
    if (bulk) return importNative();
    final local = localCourse;
    final candidates = (catalog ?? []).where((c) => c.matches(local)).toList()
      ..sort(
        (a, b) =>
            (b.matches(local) ? 1 : 0).compareTo(a.matches(local) ? 1 : 0),
      );
    return QuietBackdrop(
      tab: 1,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          key: const ValueKey('course-detail-list'),
          controller: scroll,
          slivers: [
            QuietSliverAppBar(
              scroll: scroll,
              title: const Text('课程课堂'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
            SliverSafeArea(
              top: false,
              sliver: SliverPadding(
                padding: const EdgeInsets.all(AppSpace.lg),
                sliver: SliverList.list(
                  children: [
                    CourseCardHero(
                      tag: widget.transitionTag,
                      child: QuietCard(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                local.name,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                local.teacher.isEmpty
                                    ? '学校未提供教师'
                                    : local.teacher,
                              ),
                              Text(local.semester),
                              Material(
                                type: MaterialType.transparency,
                                child: AppExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text('课程信息'),
                                  children: [
                                    Text(
                                      local.segments
                                          .map(
                                            (segment) =>
                                                '${segment.start}–${segment.end}',
                                          )
                                          .join(' · '),
                                    ),
                                    Text(
                                      local.place.isEmpty
                                          ? '学校未提供地点'
                                          : local.place,
                                    ),
                                    Text(
                                      '第${local.weeks}周 · 第${local.periods.join('、')}节',
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          widget.onDetails(context),
                                      child: const Text('查看完整课程信息'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClassroomSectionSwitch(
                      tabs: const ['录播', '直播'],
                      selectedIndex: section,
                      onSelected: (i) => setState(() => section = i),
                    ),
                    const SizedBox(height: 16),
                    if (section == 1)
                      QuietCard(
                        cornerRadius: 22,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.comfortable),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppIcon(
                                AppIcons.mediaLibrary,
                                size: 22,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text('学校直播暂未开放\n开放后将在这里提供有权限的课堂直播。'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      if (!synthetic)
                        ClassroomConnectionCard(
                          status: connectionStatus,
                          directoryLabel: archive != null
                              ? '已导入的录播列表 · 更新于 ${schoolTimestamp(archive!.importedAt)} · 可刷新'
                              : recordings != null
                              ? '本次读取的录播列表 · 尚未保存完整目录'
                              : '尚未导入录播目录',
                          busy: busy,
                          summaryLabel: recordings == null
                              ? null
                              : archive != null
                              ? (archive!.nameMatched
                                    ? '已按名称合并 ${archive!.courses.length} 门学校课程（按日期汇总）'
                                    : '旧目录尚未汇总同名课程，请刷新录播或统一导入。')
                              : '当前回放来源：${recordings!.course.name} · ${recordings!.course.teacher}',
                          dateHintLabel:
                              recordings != null &&
                                  widget.date != null &&
                                  archive == null
                              ? (recordings!.records.any(
                                      (v) =>
                                          isoDate(v.date) ==
                                          isoDate(widget.date!),
                                    )
                                    ? '已标记 ${shortDate(widget.date!)} 的授课记录'
                                    : '本页没有 ${shortDate(widget.date!)} 的录播，可查看其他记录或翻页。')
                              : null,
                          onRetry: archive != null
                              ? refreshRecordings
                              : retryCurrent,
                          onOpenSchool: openSchoolPage,
                          onRefresh: recordings != null
                              ? refreshRecordings
                              : null,
                          onRematch: recordings != null ? changeCourse : null,
                        ),
                      if (synthetic && message != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpace.md,
                          ),
                          child: Text(message!),
                        ),
                      if (synthetic)
                        QuietCard(
                          cornerRadius: 20,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.lg,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                AppIcon(
                                  AppIcons.info,
                                  size: 18,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text('合成示例不连接学校；请使用本人导入的课程。'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (collecting) ...[
                        const SizedBox(height: 12),
                        QuietCard(
                          cornerRadius: 20,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.lg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const ClipRRect(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(4),
                                  ),
                                  child: LinearProgressIndicator(minHeight: 3),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '正在汇总同名课程：$sourceIndex / ${importMatches?.length ?? 0}',
                                ),
                                if (!busy) ...[
                                  const SizedBox(height: 10),
                                  FilledButton.tonalIcon(
                                    onPressed: retryCurrent,
                                    icon: const AppIcon(
                                      AppIcons.refresh,
                                      size: 17,
                                    ),
                                    label: const Text('继续导入'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (!synthetic && recordings != null) ...[
                        const SizedBox(height: 12),
                        if (archive != null)
                          ClassroomRecordingTimeline(
                            archive: archive!,
                            date: widget.date,
                            busy: busy,
                            page: timelinePage,
                            lessonPage: lessonPage,
                            onPage: (value) =>
                                setState(() => timelinePage = value),
                            onLessonPage: (value) =>
                                setState(() => lessonPage = value),
                            onPlay: (record, courseId, button) => playNative(
                              record,
                              sourceCourseId: courseId,
                              button: button,
                            ),
                          )
                        else ...[
                          if (recordings!.records.isEmpty)
                            QuietCard(
                              cornerRadius: 20,
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  AppSpace.comfortable,
                                ),
                                child: Text(
                                  '学校当前没有可显示的录播记录。',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          for (final record in recordings!.records)
                            ClassroomRecordingTile(
                              key: ValueKey((recordings!.course.id, record.id)),
                              selected:
                                  widget.date != null &&
                                  isoDate(widget.date!) == isoDate(record.date),
                              title: record.label,
                              placeLabel: record.place.isEmpty
                                  ? '学校未提供地点'
                                  : record.place,
                              published: record.published,
                              subtitle:
                                  '${record.place.isEmpty ? '学校未提供地点' : record.place}\n${record.published ? '已发布' : '未发布或暂不可观看'}',
                              onPlay: busy || !record.published
                                  ? null
                                  : (button) => playNative(
                                      record,
                                      sourceCourseId: recordings!.course.id,
                                      button: button,
                                    ),
                            ),
                          ClassroomPaginationBar(
                            currentPage: displayPage,
                            totalItems: archive?.total ?? recordings!.total,
                            previousLabel: '上一页',
                            nextLabel: '下一页',
                            onPrevious: busy || displayPage == 1
                                ? null
                                : () => changePage(displayPage - 1),
                            onNext:
                                busy ||
                                    (archive != null
                                        ? displayPage >= archive!.pages.length
                                        : !recordings!.hasNext)
                                ? null
                                : () => changePage(displayPage + 1),
                          ),
                        ],
                      ] else if (catalog != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          '选择匹配的学校课程',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '按同学期课程名称汇总全部回放，教师和班级仅用于显示来源。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        for (final course in candidates)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpace.control,
                            ),
                            child: QuietCard(
                              cornerRadius: 22,
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(22),
                                  onTap: busy ? null : retryCurrent,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpace.lg,
                                      14,
                                      14,
                                      14,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                course.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                course.teacher.isEmpty
                                                    ? '学校未提供教师'
                                                    : course.teacher,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                              if (course.code.isNotEmpty ||
                                                  course.group.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  [
                                                    if (course.code.isNotEmpty)
                                                      course.code,
                                                    if (course.group.isNotEmpty)
                                                      course.group,
                                                  ].join(' · '),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        AppIcon(
                                          AppIcons.chevronRight,
                                          size: 20,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(48, 46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() {
                                      active = catalogTab;
                                      showWeb = true;
                                    });
                                    scheduleRead(
                                      tabs[catalogTab],
                                      restart: true,
                                    );
                                  },
                            icon: const AppIcon(AppIcons.arrowBack, size: 17),
                            label: const Text('返回官方页面切换学期'),
                          ),
                        ),
                      ] else if (!synthetic) ...[
                        const SizedBox(height: 12),
                        MiuixButton(
                          onPressed: busy ? null : () => connect(),
                          child: const Text('重新获取学校录播'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> retryFailedImports() async {
    final failed = importProgress.failures;
    if (failed.isEmpty) return;
    retryQueue = [...failed];
    setState(() {
      importIndex = retryQueue!.removeAt(0);
      importFinished = false;
    });
    await retryCurrent();
  }

  Future<void> skipFailedImport() async {
    if (tabs.isEmpty) return;
    connection.advance();
    connection.cancelPoll();
    await nextImport(tabs[active]);
  }

  Widget importNative() => Scaffold(
    appBar: AppBar(title: const Text('统一导入录播')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.comfortable),
        children: [
          Text(
            localCourse.semester,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            importFinished
                ? (importProgress.failures.isEmpty ? '导入完成' : '本轮处理结束')
                : '当前课程：${localCourse.name}',
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: importFinished
                ? 1
                : importIndex / importProgress.items.length,
          ),
          const SizedBox(height: 12),
          Text(
            '已完成 ${importProgress.count(ImportTaskStatus.completed)} / 共 ${importProgress.items.length} 组同名课程 · 共 ${importProgress.totalLocalItems} 个课表项',
          ),
          Text(
            '已取得 ${completedArchives.length} 个学校来源 · 未匹配 ${importProgress.count(ImportTaskStatus.unmatched)} 组 · 失败 ${importProgress.failures.length} 组',
          ),
          if (importFinished &&
              importProgress.count(ImportTaskStatus.completed) > 0)
            TextButton(
              onPressed: () {
                final target = completedTasksKey.currentContext;
                if (target != null) {
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 200),
                  );
                }
              },
              child: const Text('查看已导入课程'),
            ),
          if (!importFinished && importPages.isNotEmpty)
            Text('已取得 ${importPages.length} 页录播'),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Text(message!),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Text('同学期同名课程的回放全部汇总，教师仅用于展示来源。未匹配项请检查课程名称或学校学期。'),
          ),
          for (final status in [
            ImportTaskStatus.running,
            ImportTaskStatus.failed,
            ImportTaskStatus.unmatched,
            ImportTaskStatus.pending,
            ImportTaskStatus.completed,
          ])
            if (importProgress.count(status) > 0) ...[
              Padding(
                key: status == ImportTaskStatus.completed
                    ? completedTasksKey
                    : null,
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Text(
                  '${importTaskStatusLabel(status)}（${importProgress.count(status)}）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final item in importProgress.items.where(
                (item) => item.status == status,
              ))
                ListTile(
                  title: Text(item.course.name),
                  subtitle: Text(
                    '${item.courses.length}个课表项 · ${item.reason ?? (status == ImportTaskStatus.running && !busy ? '已暂停，可继续导入' : importTaskStatusLabel(status))}',
                  ),
                  trailing:
                      importFinished && status == ImportTaskStatus.completed
                      ? const AppIcon(AppIcons.chevronRight)
                      : null,
                  onTap: !importFinished || status != ImportTaskStatus.completed
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClassroomCoursePage(
                              course: item.course,
                              library: library,
                              onDetails: (context) =>
                                  showCourseInformation(context, item.course),
                            ),
                          ),
                        ),
                ),
            ],
          if (importFinished && importProgress.failures.isNotEmpty)
            OutlinedButton(
              onPressed: retryFailedImports,
              child: const Text('只重试失败项'),
            ),
          if (importFinished &&
              importProgress.count(ImportTaskStatus.completed) > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Text('点击上方已完成课程可查看已导入录播。'),
            ),
          if (importFinished)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成'),
            )
          else ...[
            if (!busy)
              OutlinedButton(
                onPressed: retryCurrent,
                child: const Text('继续导入'),
              ),
            if (importProgress.items[importIndex].status ==
                ImportTaskStatus.failed)
              TextButton(
                onPressed: skipFailedImport,
                child: const Text('保留失败项，继续其他课程'),
              ),
            TextButton(onPressed: openSchoolPage, child: const Text('打开学校页面')),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('停止并返回'),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !browserVisible,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) reportImportResult();
      if (!didPop) unawaited(webBack());
    },
    child: Stack(
      children: [
        if (tabs.isNotEmpty)
          Positioned.fill(
            key: const ValueKey('school-browser-layer'),
            child: Offstage(offstage: !browserVisible, child: browser()),
          ),
        Positioned.fill(
          key: const ValueKey('recording-native-position'),
          child: Offstage(
            offstage: browserVisible,
            child: TickerMode(
              enabled: !browserVisible,
              child: ExcludeFocus(
                excluding: browserVisible,
                child: KeyedSubtree(
                  key: const ValueKey('recording-native-layer'),
                  child: native(),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
