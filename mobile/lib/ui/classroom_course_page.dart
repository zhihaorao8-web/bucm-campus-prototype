import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../data/classroom_links.dart';
import '../domain/classroom.dart';
import '../domain/schedule.dart';
import '../platform/classroom_access.dart';
import '../platform/classroom_policy.dart';
import '../platform/classroom_player.dart';
import 'classroom_player_page.dart';

enum _Purpose { browse, records, playback }

class _SchoolTab {
  _SchoolTab({this.windowId, required this.purpose});
  final int? windowId;
  _Purpose purpose;
  InAppWebViewController? controller;
  bool routed = false;
}

/// Native course UI and visible official authentication/playback share one
/// route. Covered parent WebViews retain opener context; no hidden login runs.
class ClassroomCoursePage extends StatefulWidget {
  const ClassroomCoursePage({
    super.key,
    required this.course,
    this.date,
    required this.onDetails,
    this.links,
    this.probe,
  });
  final Course course;
  final DateTime? date;
  final void Function(BuildContext) onDetails;
  final ClassroomLinks? links;
  final ProbeEndpoint? probe;
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
  Timer? poll;
  bool get synthetic => widget.course.dataSource == 'synthetic';

  @override
  void initState() {
    super.initState();
    if (!synthetic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(connect());
      });
    }
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
    scroll.dispose();
    super.dispose();
  }

  Future<void> connect([
    ClassroomAccess mode = ClassroomAccess.automatic,
  ]) async {
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
      tabs.clear();
      catalog = null;
      recordings = null;
      selected = null;
      rememberedAttempted = false;
      active = 0;
      busy = false;
      entry = decision.url;
      message = decision.message;
      showWeb = entry != null;
      loading = showWeb;
      if (showWeb) tabs.add(_SchoolTab(purpose: _Purpose.browse));
    });
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
        setState(() {
          recordings = null;
          catalog = null;
          selected = null;
          showWeb = true;
          busy = false;
          message = '学校会话已失效，请在官方页面重新认证；可从右上角重新连接。';
        });
        return;
      }
      if (data['state'] == 'forbidden' || data['state'] == 'error') {
        setState(() {
          busy = false;
          message = data['state'] == 'forbidden'
              ? '学校提示当前账号没有查看权限。'
              : '学校请求失败，请检查官方页面或稍后重试。';
        });
        return;
      }
      if (data['state'] == 'catalog' && tab.purpose != _Purpose.records) {
        final courses = (data['courses'] as List)
            .map(
              (v) =>
                  ClassroomCourse.fromJson(Map<String, dynamic>.from(v as Map)),
            )
            .where((v) => v.semester == widget.course.semester)
            .toList();
        if (courses.isEmpty && attempts < 4) {
          scheduleRead(tab);
          return;
        }
        String? previous;
        try {
          previous = await links.lookup(widget.course);
        } catch (_) {
          /* Keep the current official catalog usable if local preferences are damaged. */
        }
        if (!mounted || ticket != generation) return;
        setState(() {
          catalog = courses;
          catalogTab = tabs.indexOf(tab);
          showWeb = false;
          busy = false;
          final sameNames = courses
              .where((course) => course.matches(widget.course))
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
          widget.course,
          courses,
          confirmedId: previous,
        );
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
            page.course.semester != widget.course.semester) {
          setState(() {
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
          recordings = page;
          recordTab = tabs.indexOf(tab);
          showWeb = false;
          busy = false;
          message = null;
        });
        try {
          await links.bind(widget.course, page.course.id);
        } catch (_) {
          if (mounted) setState(() => message = '本次可继续查看，但课程关联未保存成功。');
        }
        return;
      }
      if (tab.purpose == _Purpose.records && !tab.routed) {
        final result = await script(tab, {'action': 'recordsRoute'});
        if (result['state'] == 'opening') tab.routed = true;
      }
      scheduleRead(tab);
    } catch (_) {
      if (mounted && ticket == generation) {
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
    final index = tabs.indexOf(tab);
    while (tabs.length > index + 1) {
      tabs.removeLast();
    }
    active = index;
    selected = course;
    await navigateOfficial(tab, {
      'action': 'choose',
      'id': course.id,
      'semester': course.semester,
    }, _Purpose.records);
  }

  Future<void> changeCourse() async {
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
    if (busy || !record.published || tabs.isEmpty) return;
    final tab = tabs[recordTab];
    final view = tab.controller?.getViewId();
    if (view is! int) return;
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
    } catch (error) {
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
          if (handedToPlayer) scheduleRead(tab, restart: true);
        }
      }
    }
  }

  Future<void> closeWeb() async {
    poll?.cancel();
    if (tabs.isNotEmpty && tabs[active].purpose == _Purpose.playback) {
      final tab = tabs[active];
      try {
        final result = await script(tab, {'action': 'returnRecords'});
        if (result['state'] != 'opening') throw const FormatException();
        tab.purpose = _Purpose.records;
        scheduleRead(tab, restart: true);
      } catch (_) {
        tabs.clear();
        recordings = null;
        catalog = null;
        selected = null;
      }
      if (!mounted) return;
    }
    if (recordings != null) {
      while (tabs.length > recordTab + 1) {
        tabs.removeLast();
      }
      active = recordTab;
    } else {
      tabs.clear();
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
                        onWebViewCreated: (web) => tab.controller = web,
                        shouldOverrideUrlLoading: (_, action) async {
                          final allowed = classroomNavigation(
                            action.request.url?.toString() ?? '',
                          );
                          if (!allowed && mounted) {
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
                        onReceivedError: (_, request, _) {
                          if (mounted && request.isForMainFrame == true) {
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
    final local = widget.course;
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
                Row(
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => changePage(recordings!.page),
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !showWeb,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(webBack());
    },
    child: Stack(
      children: [
        if (tabs.isNotEmpty)
          Positioned.fill(
            child: Offstage(offstage: !showWeb, child: browser()),
          ),
        if (!showWeb) Positioned.fill(child: native()),
      ],
    ),
  );
}
