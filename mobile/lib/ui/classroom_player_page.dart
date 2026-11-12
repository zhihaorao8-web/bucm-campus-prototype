import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/classroom_player.dart';

/// Original MIUIX-aligned controls. Interaction reference: fluttercommunity/chewie
/// (MIT), https://github.com/fluttercommunity/chewie. No upstream code copied.
class ClassroomPlayerPage extends StatefulWidget {
  const ClassroomPlayerPage({
    super.key,
    required this.title,
    required this.controller,
  });
  final String title;
  final ClassroomPlayerController controller;
  @override
  State<ClassroomPlayerPage> createState() => _ClassroomPlayerPageState();
}

class _ClassroomPlayerPageState extends State<ClassroomPlayerPage>
    with WidgetsBindingObserver {
  bool fullscreen = false;
  bool changingFullscreen = false;
  bool controlsVisible = true, menuOpen = false;
  bool foreground = true, accessibleNavigation = false;
  int pointersDown = 0;
  Timer? controlsTimer;
  double? dragging;
  String? lastSmall;
  ClassroomPlayerController get player => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    player.addListener(changed);
    player.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    updateControls();
  }

  bool get canHideControls =>
      fullscreen &&
      foreground &&
      !accessibleNavigation &&
      player.state.playing &&
      player.state.wanted &&
      !player.state.buffering &&
      player.state.error == null &&
      player.failure == null &&
      dragging == null &&
      !menuOpen &&
      pointersDown == 0;

  void updateControls({bool interacted = false}) {
    if (!mounted) return;
    if (interacted || !canHideControls) {
      controlsTimer?.cancel();
      controlsTimer = null;
      if (!controlsVisible) setState(() => controlsVisible = true);
    }
    // Periodic native position updates must not restart the idle deadline.
    if (canHideControls && controlsVisible && controlsTimer == null) {
      controlsTimer = Timer(const Duration(seconds: 3), () {
        controlsTimer = null;
        if (mounted && canHideControls) {
          setState(() => controlsVisible = false);
        }
      });
    }
  }

  void setMenuOpen(bool value) {
    menuOpen = value;
    updateControls(interacted: true);
  }

  void endPointer() {
    if (pointersDown > 0) pointersDown--;
    updateControls(interacted: true);
  }

  void changed() {
    if (mounted) {
      setState(() {});
      updateControls();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    updateControls();
    if (state != AppLifecycleState.resumed) unawaited(player.command('pause'));
  }

  @override
  void dispose() {
    controlsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(changed);
    player.dispose();
    unawaited(restoreSystemUi().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> restoreSystemUi() async {
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> toggleFullscreen() async {
    if (changingFullscreen) return;
    changingFullscreen = true;
    final next = !fullscreen;
    setState(() => fullscreen = next);
    updateControls(interacted: true);
    try {
      if (next) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        if (!mounted) {
          await restoreSystemUi();
          return;
        }
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        await restoreSystemUi();
      }
      if (!mounted) await restoreSystemUi();
    } catch (_) {
      if (mounted) setState(() => fullscreen = !next);
    } finally {
      changingFullscreen = false;
      updateControls();
    }
  }

  String time(int ms) {
    final seconds = ms ~/ 1000;
    final hour = seconds ~/ 3600;
    return '${hour > 0 ? '$hour:' : ''}${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void layout(String main, String? small) {
    unawaited(player.command('layout', {'main': main, 'small': small}));
  }

  void closeSmall() {
    lastSmall = player.state.small;
    layout(player.state.main, null);
  }

  void showSmall() {
    final state = player.state;
    final choices = state.available
        .where((kind) => kind != state.main)
        .toList();
    if (choices.isEmpty) return;
    final kind = choices.contains(lastSmall)
        ? lastSmall!
        : choices.contains('teacher')
        ? 'teacher'
        : choices.first;
    layout(state.main, kind);
  }

  Widget picture(String kind) {
    final texture = player.state.texture(kind);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: (texture?['ratio'] as num?)?.toDouble() ?? 16 / 9,
          child: texture == null
              ? const SizedBox.shrink()
              : Texture(textureId: texture['texture'] as int),
        ),
      ),
    );
  }

  Widget viewport() {
    final state = player.state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maximum = math.max(
          0.0,
          math.min(
            200.0,
            math.min(
              constraints.maxWidth - 24,
              (constraints.maxHeight - 24) * 16 / 9,
            ),
          ),
        );
        final width = (constraints.maxWidth * .34)
            .clamp(math.min(96.0, maximum), maximum)
            .toDouble();
        return Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label: '${classroomViewName(state.main)}主画面',
              child: picture(state.main),
            ),
            if (state.small != null && width >= 48)
              Positioned(
                right: 12,
                bottom: 12,
                width: width,
                height: width * 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white54, width: 2),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Semantics(
                          button: true,
                          label: '${classroomViewName(state.small!)}小窗，点击交换主画面',
                          child: InkWell(
                            onTap: () => layout(state.small!, state.main),
                            child: picture(state.small!),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          top: 4,
                          child: IgnorePointer(
                            child: Text(
                              classroomViewName(state.small!),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                backgroundColor: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            tooltip: '关闭小窗',
                            onPressed: closeSmall,
                            color: Colors.white,
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (state.watermark.isNotEmpty)
              Positioned(
                top: 12,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  child: Text(
                    state.watermark,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                    ),
                  ),
                ),
              ),
            if (state.buffering)
              const Center(
                child: CircularProgressIndicator(semanticsLabel: '正在缓冲课堂视频'),
              ),
          ],
        );
      },
    );
  }

  Widget viewMenu({required bool small}) {
    final state = player.state;
    return PopupMenuButton<String>(
      tooltip: small ? '选择小窗画面' : '选择主画面',
      onOpened: () => setMenuOpen(true),
      onCanceled: () => setMenuOpen(false),
      onSelected: (kind) {
        setMenuOpen(false);
        if (small) {
          if (kind == state.main) {
            if (state.small != null) layout(state.small!, state.main);
          } else {
            layout(state.main, kind);
          }
        } else if (kind == state.small) {
          layout(kind, state.main);
        } else {
          layout(kind, state.small);
        }
      },
      itemBuilder: (_) => [
        for (final kind in state.available)
          PopupMenuItem(value: kind, child: Text(classroomViewName(kind))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Text(
          '${small ? '小窗' : '主画面'} · ${small && state.small == null ? '已关闭' : classroomViewName(small ? state.small! : state.main)} ▾',
        ),
      ),
    );
  }

  Widget controls() {
    final state = player.state;
    final error =
        player.failure ??
        (state.error == null
            ? null
            : switch (state.error) {
                'AUTHENTICATION' => '学校会话已失效，请返回并重新登录。',
                'FORBIDDEN' => '学校暂未允许观看该录播。',
                'CERTIFICATE' => '学校媒体的安全连接未通过校验。',
                'UNTRUSTED' => '媒体地址超出已验证的学校范围，请返回重试。',
                _ => '课堂视频未能播放，请检查网络后返回重试。',
              });
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error, semanticsLabel: error),
          ),
        Slider(
          semanticFormatterCallback: (value) => time(value.toInt()),
          value: (dragging ?? state.position.toDouble()).clamp(
            0.0,
            state.duration > 0 ? state.duration.toDouble() : 1.0,
          ),
          max: state.duration > 0 ? state.duration.toDouble() : 1,
          onChanged: state.duration > 0 && error == null
              ? (value) {
                  setState(() => dragging = value);
                  updateControls(interacted: true);
                }
              : null,
          onChangeStart: state.duration > 0 && error == null
              ? (value) {
                  setState(() => dragging = value);
                  updateControls(interacted: true);
                }
              : null,
          onChangeEnd: (value) {
            setState(() => dragging = null);
            updateControls(interacted: true);
            unawaited(player.command('seek', {'position': value.toInt()}));
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                tooltip: state.wanted ? '暂停' : '播放',
                onPressed: error == null
                    ? () => player.command(state.wanted ? 'pause' : 'play')
                    : null,
                icon: Icon(
                  state.wanted ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              Expanded(
                child: Text(
                  '${time(state.position)} / ${time(state.duration)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              PopupMenuButton<double>(
                tooltip: '播放速度',
                initialValue: state.speed,
                onOpened: () => setMenuOpen(true),
                onCanceled: () => setMenuOpen(false),
                onSelected: (speed) {
                  setMenuOpen(false);
                  player.command('speed', {'speed': speed});
                },
                itemBuilder: (_) => [
                  for (final speed in [.75, 1.0, 1.25, 1.5, 2.0])
                    PopupMenuItem(value: speed, child: Text('$speed×')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('${state.speed}×'),
                ),
              ),
              IconButton(
                tooltip: fullscreen ? '退出全屏' : '全屏',
                onPressed: toggleFullscreen,
                icon: Icon(
                  fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: '后退10秒',
              onPressed: error == null && state.duration > 0
                  ? () => player.command('seek', {
                      'position': (state.position - 10000).clamp(
                        0,
                        state.duration,
                      ),
                    })
                  : null,
              icon: const Icon(Icons.replay_10),
            ),
            IconButton(
              tooltip: '前进10秒',
              onPressed: error == null && state.duration > 0
                  ? () => player.command('seek', {
                      'position': (state.position + 10000).clamp(
                        0,
                        state.duration,
                      ),
                    })
                  : null,
              icon: const Icon(Icons.forward_10),
            ),
            viewMenu(small: false),
            viewMenu(small: true),
            if (state.small == null)
              TextButton.icon(
                onPressed: state.available.any((kind) => kind != state.main)
                    ? showSmall
                    : null,
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
                label: const Text('显示小窗'),
              ),
            IconButton(
              tooltip: '交换主画面与小窗',
              onPressed: state.small == null
                  ? null
                  : () => layout(state.small!, state.main),
              icon: const Icon(Icons.swap_horiz),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !fullscreen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(toggleFullscreen());
    },
    child: Scaffold(
      appBar: fullscreen ? null : AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Listener(
          onPointerDown: (_) {
            pointersDown++;
            updateControls(interacted: true);
          },
          onPointerUp: (_) => endPointer(),
          onPointerCancel: (_) => endPointer(),
          child: fullscreen
              ? Column(
                  children: [
                    Expanded(
                      child: Semantics(
                        label: '轻点显示播放控制',
                        button: true,
                        onTap: () => updateControls(interacted: true),
                        child: GestureDetector(
                          key: const ValueKey('fullscreen-playback-surface'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => updateControls(interacted: true),
                          child: viewport(),
                        ),
                      ),
                    ),
                    if (controlsVisible) controls(),
                  ],
                )
              : ListView(
                  children: [
                    AspectRatio(aspectRatio: 16 / 9, child: viewport()),
                    controls(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('点按小窗可交换主画面。学校观看记录尚未接入，本地播放不代表学校记录已更新。'),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
