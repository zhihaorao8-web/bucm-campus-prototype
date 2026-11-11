import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../data/classroom_links.dart';
import '../data/classroom_library.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';
import '../platform/classroom_access.dart';
import '../platform/classroom_policy.dart';
import '../platform/classroom_player.dart';
import '../platform/classroom_session_cache.dart';
import 'classroom_player_page.dart';

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
  });
  final Course course;
  final DateTime? date;
  final void Function(BuildContext) onDetails;
  final ClassroomLinks? links;
  final ProbeEndpoint? probe;
  final ClassroomLibrary? library;
  final List<Course>? importCourses;
  @override
  State<ClassroomCoursePage> createState() => _ClassroomCoursePageState();
}

class _ClassroomCoursePageState extends State<ClassroomCoursePage> {
  final tabs = <_SchoolTab>[];
  final scroll = ScrollController();
  late final links = widget.links ?? ClassroomLinks.shared;
  List<ClassroomCourse>? catalog;
  ClassroomCourse? selected;
  RecordingPage? recordings;
  int active = 0,
      recordTab = 0,
      catalogTab = 0,
      section = 0,
      generation = 0,
      attempts = 0;
  int playbackGeneration = 0;
  bool showWeb = false,
      busy = false,
      loading = false,
      rememberedAttempted = false;
  String? entry, message, source;
  String? entrySource;
  bool automaticEntry = true, automaticPath = false;
  Timer? poll;
  final cache = ClassroomSessionCache.shared;
  late int cacheRevision;
  late final library = widget.library ?? ClassroomLibrary.shared;
  late final int libraryRevision;
  ClassroomArchive? archive;
  ClassroomRecording? queuedPlayback;
  int queuedPage = 1;
  int? livePage;
  String? liveCourse;
  bool needsCatalog = false, authVisible = false;
  int importIndex = 0, imported = 0;
  bool importFinished = false, importingPage = false;
  final importPages = <RecordingPage>[];
  final skipped = <String>[];
  final completedArchives = <String, ClassroomArchive>{};
  bool get bulk => widget.importCourses != null;
  Course get localCourse =>
      bulk ? widget.importCourses![importIndex] : widget.course;
  bool get browserVisible =>
      showWeb && (authVisible || (!bulk && queuedPlayback == null));

  DateTime? fetchedAt;
  double lastOffset = 0;
  bool restored = false, validateRestored = false, freshReadPending = false;

  // Dispose only after the old platform widgets have detached.
  void releaseTabs(Iterable<_SchoolTab> removed) {
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
    scroll.addListener(() {
      if (scroll.hasClients) lastOffset = scroll.offset;
    });
    libraryRevision = library.revision;
    if (bulk) {
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
    if (saved != null && (!keepLive || saved.course.id == selected?.id)) {
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
      showWeb = true;
      tabs.add(_SchoolTab(purpose: _Purpose.browse, retained: workspace.view));
      message = '正在读取学校课程目录…';
    });
  }

  Future<void> nextImport(_SchoolTab tab) async {
    if (!mounted || !tabs.contains(tab)) return;
    importPages.clear();
    if (importIndex + 1 == widget.importCourses!.length) {
      setState(() {
        importFinished = true;
        busy = false;
        showWeb = false;
        message = null;
      });
      poll?.cancel();
      return;
    }
    setState(() {
      importIndex++;
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
      if (page.page != importPages.length + 1) {
        await changePage(importPages.length + 1);
        return;
      }
      if (page.total > 10000 || importPages.length >= 1000) {
        throw const FormatException();
      }
      importPages.add(page);
      if (page.hasNext) {
        await changePage(page.page + 1);
        return;
      }
      final saved = ClassroomArchive(
        List.unmodifiable(importPages),
        DateTime.now(),
      );
      await library.save(localCourse, saved, revision: libraryRevision);
      if (!mounted) return;
      if (libraryRevision != library.revision) throw const FormatException();
      completedArchives[page.course.id] = saved;
      imported++;
      await nextImport(tab);
    } catch (_) {
      if (mounted) {
        setState(() {
          fetchedAt = null;
          busy = false;
          message = '本门课程未能完整导入，已完成的课程保留。可重试当前课程。';
        });
      }
    } finally {
      importingPage = false;
    }
  }

  Future<void> refreshRecordings() async {
    if (archive == null) {
      await changePage(recordings!.page);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClassroomCoursePage(
          course: localCourse,
          onDetails: (_) {},
          importCourses: [localCourse],
          library: library,
          links: links,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      clearTabs();
      active = recordTab = catalogTab = 0;
      archive = null;
      recordings = null;
      selected = null;
      fetchedAt = null;
      restored = false;
      busy = true;
      showWeb = false;
      cacheRevision = cache.revision;
    });
    await loadArchive();
  }

  @override
  void dispose() {
    generation++;
    playbackGeneration++;
    unawaited(
      classroomPlaybackChannel
          .invokeMethod<void>('cancel')
          .catchError((Object _) {}),
    );
    poll?.cancel();
    final index = recordTab;
    _SchoolTab? retained;
    if (!bulk &&
        !synthetic &&
        !busy &&
        !loading &&
        !showWeb &&
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

  Future<void> connect([
    ClassroomAccess mode = ClassroomAccess.automatic,
  ]) async {
    fetchedAt = null;
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
    final ticket = ++generation;
    poll?.cancel();
    setState(() {
      busy = true;
      message = '正在检查学校服务访问路径…';
    });
    final decision = mode == ClassroomAccess.automatic
        ? await chooseClassroomAccess(widget.probe ?? probeClassroomEndpoint)
        : AccessDecision(
            mode,
            mode == ClassroomAccess.vpn ? '已选择学校 WebVPN。' : '已选择直接访问。',
          );
    if (!mounted || ticket != generation) return;
    setState(() {
      clearTabs();
      catalog = null;
      recordings = queuedPlayback == null
          ? null
          : archive?.pages[queuedPage - 1];
      selected = null;
      rememberedAttempted = false;
      active = 0;
      busy = false;
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
    authVisible = true;
    fetchedAt = null;
    freshReadPending = false;
    restored = false;
    setState(() {
      recordings = null;
      catalog = null;
      selected = null;
      rememberedAttempted = false;
      tab.purpose = _Purpose.browse;
      tab.routed = false;
      showWeb = true;
      busy = false;
      message = '请在学校官方页面完成认证；登录成功后将继续自动获取录播。';
    });
  }

  Future<String> advanceEntry(_SchoolTab tab) async {
    if (!automaticEntry || tab.navigationStopped || tab.advancing) {
      return 'waiting';
    }
    if (tab.entryHops >= 4) {
      tab.navigationStopped = true;
      return 'blocked';
    }
    entrySource ??= await rootBundle.loadString('assets/classroom-entry.js');
    tab.advancing = true;
    try {
      final value = await tab.controller!.evaluateJavascript(
        source: entrySource!,
      );
      if (value is! String || value.length > 512) throw const FormatException();
      final data = jsonDecode(value) as Map;
      final state = data['state'] as String;
      if (state == 'opening') {
        tab.entryHops++;
      } else {
        tab.advancing = false;
      }
      if (state == 'blocked') tab.navigationStopped = true;
      return state;
    } catch (_) {
      tab.advancing = false;
      return 'waiting';
    }
  }

  Future<Map<String, dynamic>> script(
    _SchoolTab tab,
    Map<String, dynamic> command,
  ) async {
    source ??= await rootBundle.loadString('assets/classroom.js');
    final value = await tab.controller!.evaluateJavascript(
      source: source!.replaceFirst(
        '__CLASSROOM_COMMAND__',
        jsonEncode(command),
      ),
    );
    if (value is! String || value.length > 1024 * 1024) {
      throw const FormatException('学校页面读取结果不支持');
    }
    return Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  void scheduleRead(_SchoolTab tab, {bool restart = false}) {
    poll?.cancel();
    if (restart) attempts = 0;
    if (!mounted || tab.purpose == _Purpose.playback) return;
    poll = Timer(const Duration(milliseconds: 900), () => inspect(tab));
  }

  Future<void> inspect(_SchoolTab tab) async {
    if (!mounted ||
        !tabs.contains(tab) ||
        tabs[active] != tab ||
        tab.controller == null) {
      return;
    }
    if (++attempts > 20) {
      if (busy) {
        setState(() {
          busy = false;
          message = '学校数据暂未完成加载，可重新读取或返回官方页面检查。';
        });
      }
      return;
    }
    final ticket = generation;
    try {
      final data = await script(tab, {'action': 'snapshot'});
      if (!mounted || ticket != generation || !tabs.contains(tab)) return;
      if (data['state'] == 'authentication') {
        if (await fallbackToVpn()) return;
        if (!mounted || ticket != generation || !tabs.contains(tab)) return;
        requireAuthentication(tab);
        return;
      }
      if (data['state'] == 'forbidden' || data['state'] == 'error') {
        fetchedAt = null;
        freshReadPending = false;
        setState(() {
          busy = false;
          message = data['state'] == 'forbidden'
              ? '学校提示当前账号没有查看权限。'
              : '学校请求失败，请检查官方页面或稍后重试。';
        });
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
        String? previous;
        try {
          previous = await links.lookup(localCourse);
        } catch (_) {
          /* Keep the current official catalog usable if local preferences are damaged. */
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
          final sameNames = courses
              .where((course) => course.matches(localCourse))
              .length;
          message = courses.isEmpty
              ? '当前页面没有该学期的课程。请在官方平台切换学期后重新读取。'
              : sameNames > 1
              ? '该学期有多门同名课程，请确认班级后选择一次。'
              : sameNames == 0
              ? '未找到该学期的同名课程，可手动关联或在官方平台切换学期。'
              : rememberedAttempted
              ? '请选择与课表对应的学校课程。'
              : '已按课程名称匹配，正在获取录播…';
        });
        final match = matchClassroomCourse(
          localCourse,
          courses,
          confirmedId: previous,
        );
        if (bulk && !importFinished) {
          if (courses.isEmpty || importingPage) return;
          importingPage = true;
          try {
            if (match == null) {
              skipped.add(localCourse.name);
              await nextImport(tab);
            } else if (completedArchives.containsKey(match.id)) {
              await library.save(
                localCourse,
                completedArchives[match.id]!,
                revision: libraryRevision,
              );
              if (!mounted) return;
              if (libraryRevision != library.revision) {
                throw const FormatException();
              }
              await links.bind(localCourse, match.id);
              imported++;
              await nextImport(tab);
            } else {
              rememberedAttempted = true;
              await choose(tab, match);
            }
          } finally {
            importingPage = false;
          }
          return;
        }
        if (!rememberedAttempted && match != null) {
          rememberedAttempted = true;
          await choose(tab, match);
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
          busy = false;
          message = null;
        });
        if (bulk) {
          await links.bind(localCourse, page.course.id);
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
            unawaited(playNative(candidates.single));
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
        final state = await advanceEntry(tab);
        if (!mounted || ticket != generation || !tabs.contains(tab)) return;
        if (state == 'authentication') {
          if (await fallbackToVpn()) return;
          if (!mounted || ticket != generation || !tabs.contains(tab)) return;
          requireAuthentication(tab);
          return;
        }
        if (state == 'blocked') {
          setState(() {
            busy = false;
            message = '自动进入学校平台暂未完成，请在官方页面继续或重新获取。';
          });
          return;
        }
        if (state == 'opening') {
          setState(() {
            busy = true;
            message = '正在自动进入学校课程平台…';
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
          message = '学校页面结构暂不支持读取，请在官方页面检查登录、权限及当前学期后重试。';
        });
      }
    }
  }

  Future<void> navigateOfficial(
    _SchoolTab tab,
    Map<String, dynamic> command,
    _Purpose purpose,
  ) async {
    poll?.cancel();
    setState(() {
      showWeb = true;
      busy = true;
      message = '正在打开学校官方页面…';
    });
    try {
      tab.purpose = purpose;
      final result = await script(tab, command);
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
    archive = null;
    await library.remove(localCourse);
    if (!mounted) return;
    if (tabs.isEmpty) {
      await connect();
      rememberedAttempted = true;
      return;
    }
    fetchedAt = null;
    freshReadPending = true;
    restored = false;
    final tab = tabs[recordTab];
    active = recordTab;
    recordings = null;
    catalog = null;
    selected = null;
    rememberedAttempted = true;
    tab.routed = false;
    await navigateOfficial(tab, {'action': 'catalogRoute'}, _Purpose.browse);
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

  Future<void> playNative(ClassroomRecording record) async {
    if (busy || !record.published) return;
    final targetPage = archive?.pageOf(record.id) ?? 1;
    final targetCourse = selected?.id ?? archive?.course.id;
    if (archive != null &&
        tabs.isNotEmpty &&
        (livePage != targetPage || liveCourse != targetCourse)) {
      queuedPlayback = record;
      queuedPage = targetPage;
      if (liveCourse == targetCourse) {
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
      queuedPage = archive?.pageOf(record.id) ?? 1;
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
    final operation = ++playbackGeneration;
    poll?.cancel();
    ClassroomPlayerState? prepared;
    var handedToPlayer = false;
    tab.purpose = _Purpose.playback;
    setState(() {
      busy = true;
      message = '正在准备课堂视频…';
    });
    try {
      await classroomPlaybackChannel.invokeMethod<void>('begin', {
        'view': view,
        'record': record.id,
      });
      if (!mounted || operation != playbackGeneration) return;
      final response = await script(tab, {'action': 'play', 'id': record.id});
      if (response['state'] != 'opening') throw const FormatException();
      final data = await classroomPlaybackChannel
          .invokeMapMethod<Object?, Object?>('prepare')
          .timeout(const Duration(seconds: 25));
      prepared = ClassroomPlayerState(data!);
      if (!mounted || operation != playbackGeneration) return;
      await script(tab, {'action': 'returnRecords'});
      livePage = null;
      tab.purpose = _Purpose.records;
      if (!mounted || operation != playbackGeneration) return;
      setState(() {
        busy = false;
        showWeb = false;
        message = null;
      });
      handedToPlayer = true;
      final controller = ClassroomPlayerController(prepared);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ClassroomPlayerPage(title: record.label, controller: controller),
        ),
      );
      if (controller.state.error != null || controller.failure != null) {
        fetchedAt = null;
      }
    } catch (error) {
      fetchedAt = null;
      freshReadPending = false;
      if (mounted && operation == playbackGeneration) {
        final detail = error is TimeoutException
            ? '学校视频加载超时，请稍后重试。'
            : switch (error is PlatformException ? error.code : '') {
                'NO_VIEW' => '未能读取当前学校页面，请重新打开课程页面。',
                'UNTRUSTED_PAGE' => '请先在官方页面进入学校课程平台。',
                'PREPARE' => '学校播放页面尚未就绪，请刷新录播列表后重试。',
                'POLICY' => '学校媒体或水印配置未能完整读取，请检查官方登录状态。',
                'WATERMARK' => '学校水印配置未能完整读取，请稍后重试。',
                'MEDIA_BOUNDARY' => '学校媒体的访问路径尚未匹配，请返回后重试。',
                'MEDIA_NETWORK' => '学校媒体请求失败，请检查网络后重试。',
                'OFFICIAL_STOP' => '学校页面未能停止播放，请关闭后重新连接。',
                'SCRIPT' => '当前学校页面暂不支持读取播放信息，请刷新后重试。',
                'MEDIA' => '学校媒体暂时无法初始化，请返回后重试。',
                _ => '未能准备课堂视频，请检查官方登录状态后重试。',
              };
        setState(() {
          busy = false;
          message = detail;
        });
      }
    } finally {
      if (!handedToPlayer && prepared != null) {
        await classroomPlaybackChannel
            .invokeMethod<void>('dispose', {'session': prepared.session})
            .catchError((Object _) {});
      }
      await classroomPlaybackChannel
          .invokeMethod<void>('cancel')
          .catchError((Object _) {});
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
    automaticEntry = false;
    automaticPath = false;
    poll?.cancel();
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
    if (recordings != null) {
      trimTabs(recordTab + 1);
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
      message = null;
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
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        PopupMenuButton<ClassroomAccess>(
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
          tooltip: '读取当前课程页面',
          onPressed: busy || tabs[active].purpose == _Purpose.playback
              ? null
              : () => scheduleRead(tabs[active], restart: true),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: '返回课程',
          onPressed: closeWeb,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (loading || busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              message ??
                  '请在官方页面完成认证并进入课程平台。WebVPN 中可打开“智慧教学平台”；也可从数字北中医应用中心进入。',
            ),
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
                            needsCatalog = false;
                            await navigateOfficial(tab, {
                              'action': 'catalogRoute',
                            }, _Purpose.browse);
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
                              message = '已阻止非学校或非 HTTPS 跳转，请切换学校 WebVPN。';
                            });
                          }
                          return allowed
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL;
                        },
                        onLoadStart: (_, _) {
                          tab.advancing = false;
                          if (mounted &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab) {
                            generation++;
                            poll?.cancel();
                            setState(() => loading = true);
                          }
                        },
                        onLoadStop: (_, _) {
                          if (mounted &&
                              tabs.isNotEmpty &&
                              tabs[active] == tab) {
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
    final candidates = (catalog ?? []).toList()
      ..sort(
        (a, b) =>
            (b.matches(local) ? 1 : 0).compareTo(a.matches(local) ? 1 : 0),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程课堂'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [
            MiuixCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      local.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(local.teacher.isEmpty ? '学校未提供教师' : local.teacher),
                    Text(
                      local.segments
                          .map((s) => '${s.start}–${s.end}')
                          .join('\n'),
                    ),
                    Text(local.semester),
                    TextButton(
                      onPressed: () => widget.onDetails(context),
                      child: const Text('查看完整课程信息'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            MiuixTabRow(
              tabs: const ['录播', '直播'],
              selectedTabIndex: section,
              onTabSelected: (i) => setState(() => section = i),
            ),
            const SizedBox(height: 16),
            if (section == 1)
              const MiuixCard(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('学校直播暂未开放\n开放后将在这里提供有权限的课堂直播。'),
                ),
              )
            else ...[
              if (busy) const LinearProgressIndicator(),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message!),
                ),
              if (synthetic)
                const Text('合成示例不连接学校；请使用本人导入的课程。')
              else if (recordings != null) ...[
                Text(
                  '已关联：${recordings!.course.name} · ${recordings!.course.teacher}',
                ),
                if (widget.date != null)
                  Text(
                    recordings!.records.any(
                          (v) => isoDate(v.date) == isoDate(widget.date!),
                        )
                        ? '已标记 ${shortDate(widget.date!)} 的授课记录'
                        : '本页没有 ${shortDate(widget.date!)} 的录播，可查看其他记录或翻页。',
                  ),
                Text(
                  archive != null
                      ? '已导入的录播列表 · 可刷新'
                      : restored
                      ? '已使用缓存 · 可刷新'
                      : '已更新列表 · 可刷新',
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: busy ? null : refreshRecordings,
                      child: const Text('刷新录播'),
                    ),
                    TextButton(
                      onPressed: busy ? null : changeCourse,
                      child: const Text('更换关联'),
                    ),
                  ],
                ),
                if (recordings!.records.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('学校当前没有可显示的录播记录。'),
                  ),
                for (final record in recordings!.records)
                  MiuixCard(
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        selected:
                            widget.date != null &&
                            isoDate(widget.date!) == isoDate(record.date),
                        title: Text(record.label),
                        subtitle: Text(
                          '${record.place.isEmpty ? '学校未提供地点' : record.place}\n${record.published ? '已发布' : '未发布或暂不可观看'}',
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.play_circle_outline),
                        onTap: busy || !record.published
                            ? null
                            : () => playNative(record),
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: busy || recordings!.page == 1
                          ? null
                          : () => changePage(recordings!.page - 1),
                      child: const Text('上一页'),
                    ),
                    Text('第 ${recordings!.page} 页 · 共 ${recordings!.total} 条'),
                    TextButton(
                      onPressed: busy || !recordings!.hasNext
                          ? null
                          : () => changePage(recordings!.page + 1),
                      child: const Text('下一页'),
                    ),
                  ],
                ),
              ] else if (catalog != null) ...[
                const Text('选择关联课程；请核对教师、课程序号和班级。'),
                for (final course in candidates)
                  MiuixCard(
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListTile(
                        title: Text(course.name),
                        subtitle: Text(
                          '${course.teacher}\n${course.code} · ${course.group}',
                        ),
                        isThreeLine: true,
                        onTap: busy
                            ? null
                            : () => choose(tabs[catalogTab], course),
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() {
                            active = catalogTab;
                            showWeb = true;
                          });
                          scheduleRead(tabs[catalogTab], restart: true);
                        },
                  child: const Text('返回官方页面切换学期'),
                ),
              ] else
                MiuixButton(
                  onPressed: busy ? null : () => connect(),
                  child: const Text('重新获取学校录播'),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget importNative() => Scaffold(
    appBar: AppBar(title: const Text('统一导入录播')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            localCourse.semester,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(importFinished ? '导入完成' : '正在导入：${localCourse.name}'),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: importFinished
                ? 1
                : importIndex / widget.importCourses!.length,
          ),
          const SizedBox(height: 12),
          Text('已关联 $imported / 共 ${widget.importCourses!.length} 个课表课程项'),
          Text(
            '已导入 ${completedArchives.length} 门学校课程 · 待确认 ${skipped.length} 项',
          ),
          if (!importFinished && importPages.isNotEmpty)
            Text('已取得 ${importPages.length} 页录播'),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(message!),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('导入后，点击课表课程即可查看录播列表。同名或未匹配的课程可进入课程页手动关联。'),
          ),
          if (skipped.isNotEmpty) ...[
            const Text('以下课程需要手动确认：'),
            ...skipped.toSet().map((name) => Text('• $name')),
          ],
          if (importFinished)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成'),
            )
          else ...[
            if (!busy)
              OutlinedButton(
                onPressed: () async {
                  importPages.clear();
                  if (tabs.isNotEmpty) {
                    selected = null;
                    rememberedAttempted = false;
                    await navigateOfficial(tabs[active], {
                      'action': 'catalogRoute',
                    }, _Purpose.browse);
                  } else {
                    await connect();
                  }
                },
                child: const Text('重试当前课程'),
              ),
            TextButton(
              onPressed: () => setState(() {
                authVisible = true;
                showWeb = tabs.isNotEmpty;
              }),
              child: const Text('打开学校页面'),
            ),
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
      if (!didPop) unawaited(webBack());
    },
    child: Stack(
      children: [
        if (tabs.isNotEmpty)
          Positioned.fill(
            key: const ValueKey('school-browser-layer'),
            child: Offstage(offstage: !browserVisible, child: browser()),
          ),
        if (!browserVisible)
          Positioned.fill(
            key: const ValueKey('recording-native-layer'),
            child: native(),
          ),
      ],
    ),
  );
}
