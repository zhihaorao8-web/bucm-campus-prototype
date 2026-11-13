import 'app_icons.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../platform/classroom_player.dart';
import '../data/classroom_playback_progress.dart';
import '../application/classroom_playback_progress_session.dart';
import 'classroom_small_window.dart';
import 'classroom_seek_surface.dart';

/// Original MIUIX-aligned controls. Interaction reference: fluttercommunity/chewie
/// (MIT), https://github.com/fluttercommunity/chewie. No upstream code copied.
class ClassroomPlayerPage extends StatefulWidget {
  const ClassroomPlayerPage({
    super.key,
    required this.title,
    required this.controller,
    this.identity,
    this.progressStore,
  });
  final String title;
  final ClassroomPlayerController controller;
  final ClassroomPlaybackIdentity? identity;
  final ClassroomPlaybackProgressStore? progressStore;
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
  int? draggingDuration;
  String? lastSmall;
  final smallPlacement = ClassroomSmallWindowPlacement();
  ClassroomPlaybackProgressSession? progress;
  bool resumeDialogOpen = false;
  Animation<double>? entryAnimation;
  ClassroomPlayerController get player => widget.controller;
  bool get canScrub =>
      foreground &&
      player.state.duration > 0 &&
      player.state.error == null &&
      player.failure == null &&
      !(progress?.blocked ?? false);

  void invalidateSliderDrag() {
    if (!canScrub || draggingDuration != player.state.duration) {
      dragging = null;
      draggingDuration = null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    player.addListener(changed);
    player.start();
    if (widget.identity != null) {
      progress =
          ClassroomPlaybackProgressSession(
              player: player,
              identity: widget.identity!,
              store:
                  widget.progressStore ?? ClassroomPlaybackProgressStore.shared,
              canPlay: () => foreground,
            )
            ..addListener(progressChanged)
            ..start();
    }
  }

  void progressChanged() {
    if (!mounted) return;
    setState(invalidateSliderDrag);
    updateControls();
    if (progress?.choicePosition == null ||
        resumeDialogOpen ||
        progress!.invalidated) {
      return;
    }
    resumeDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(offerResume()),
    );
  }

  Future<void> offerResume() async {
    final current = progress;
    if (!mounted ||
        current == null ||
        current.invalidated ||
        current.choicePosition == null) {
      resumeDialogOpen = false;
      return;
    }
    final route = ModalRoute.of(context);
    if (!foreground ||
        (route != null &&
            (!route.isCurrent ||
                route.offstage ||
                !(route.animation?.isCompleted ?? true)))) {
      resumeDialogOpen = false;
      return;
    }
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ListenableBuilder(
        listenable: current,
        builder: (context, _) => AlertDialog(
          title: const Text('继续观看？'),
          content: Text(
            current.invalidated
                ? '学校会话已清除，请返回录播列表重新连接。'
                : '本机上次播放到 ${time(current.choicePosition ?? 0)}。\n本机进度不代表学校观看记录。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回列表'),
            ),
            TextButton(
              onPressed: current.invalidated
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('从头播放'),
            ),
            FilledButton(
              onPressed: current.invalidated
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('继续观看'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == null) {
      Navigator.pop(context);
    } else {
      await current.choose(resume: choice);
    }
    resumeDialogOpen = false;
  }

  void entryStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) progressChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation != entryAnimation) {
      entryAnimation?.removeStatusListener(entryStatusChanged);
      entryAnimation = animation;
      entryAnimation?.addStatusListener(entryStatusChanged);
    }
    accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    updateControls();
  }

  bool get canHideControls =>
      fullscreen &&
      foreground &&
      !accessibleNavigation &&
      !(progress?.blocked ?? false) &&
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
      setState(invalidateSliderDrag);
      updateControls();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) progressChanged();
    if (!foreground) setState(invalidateSliderDrag);
    updateControls();
    if (state != AppLifecycleState.resumed) unawaited(player.command('pause'));
    if (state != AppLifecycleState.resumed) {
      unawaited(progress?.save() ?? Future<void>.value());
    }
  }

  @override
  void dispose() {
    entryAnimation?.removeStatusListener(entryStatusChanged);
    controlsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(changed);
    progress?.removeListener(progressChanged);
    progress?.dispose();
    player.dispose();
    unawaited(restoreSystemUi().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> restoreSystemUi({bool portrait = false}) async {
    await SystemChrome.setPreferredOrientations(
      portrait ? [DeviceOrientation.portraitUp] : [],
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> toggleFullscreen() async {
    if (changingFullscreen) return;
    changingFullscreen = true;
    final next = !fullscreen;
    setState(() {
      dragging = null;
      draggingDuration = null;
      fullscreen = next;
    });
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
        await restoreSystemUi(portrait: true);
      }
      if (!mounted) await restoreSystemUi();
    } catch (_) {
      if (mounted) setState(() => fullscreen = !next);
      try {
        if (!next && mounted) {
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } else {
          await restoreSystemUi(portrait: mounted);
        }
      } catch (_) {
        // A platform restriction must not leave the transition locked.
      }
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

  Future<void> showViewDrawer() async {
    setMenuOpen(true);
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭画面设置',
        barrierColor: Colors.black38,
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        transitionBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
        pageBuilder: (context, _, _) => SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: math.min(360.0, constraints.maxWidth * .5),
                height: constraints.maxHeight,
                child: Material(
                  key: const ValueKey('classroom-view-drawer'),
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: ListenableBuilder(
                            listenable: player,
                            builder: (context, _) {
                              final current = player.state;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '切换课堂画面',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('主画面'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final kind in current.available)
                                        ChoiceChip(
                                          key: ValueKey('main-view-$kind'),
                                          label: Text(classroomViewName(kind)),
                                          selected: current.main == kind,
                                          onSelected: (selected) {
                                            if (!selected) return;
                                            layout(
                                              kind,
                                              kind == current.small
                                                  ? current.main
                                                  : current.small,
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('小窗'),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      ChoiceChip(
                                        key: const ValueKey('small-view-off'),
                                        label: const Text('关闭'),
                                        selected: current.small == null,
                                        onSelected: (selected) {
                                          if (selected) closeSmall();
                                        },
                                      ),
                                      for (final kind
                                          in current.available.where(
                                            (kind) => kind != current.main,
                                          ))
                                        ChoiceChip(
                                          key: ValueKey('small-view-$kind'),
                                          label: Text(classroomViewName(kind)),
                                          selected: current.small == kind,
                                          onSelected: (selected) {
                                            if (selected) {
                                              layout(current.main, kind);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  TextButton.icon(
                                    onPressed: current.small == null
                                        ? null
                                        : () => layout(
                                            current.small!,
                                            current.main,
                                          ),
                                    icon: const AppIcon(
                                      AppIcons.swapHorizontal,
                                    ),
                                    label: const Text('交换主画面与小窗'),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('完成'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setMenuOpen(false);
    }
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

  Widget viewport({double reservedBottom = 0}) {
    final state = player.state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final watermarkLeft = fullscreen ? 72.0 : 16.0;
        var reservedTop = fullscreen && controlsVisible ? 64.0 : 12.0;
        if (state.watermark.isNotEmpty) {
          final painter =
              TextPainter(
                text: TextSpan(
                  text: state.watermark,
                  style: DefaultTextStyle.of(
                    context,
                  ).style.merge(const TextStyle(fontSize: 12)),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 4,
                ellipsis: '…',
              )..layout(
                maxWidth: math.max(
                  0,
                  constraints.maxWidth - watermarkLeft - (fullscreen ? 72 : 16),
                ),
              );
          reservedTop = math.max(reservedTop, 12 + painter.height + 8);
          painter.dispose();
        }
        final smallViewport = Size(
          constraints.maxWidth,
          math.max(0, constraints.maxHeight - reservedBottom),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label: '${classroomViewName(state.main)}主画面',
              hint: '左右滑动调整进度，松手跳转',
              child: ClassroomSeekSurface(
                position: state.position,
                duration: state.duration,
                enabled:
                    foreground &&
                    state.error == null &&
                    player.failure == null &&
                    !(progress?.blocked ?? false),
                formatTime: time,
                onSeek: (position) =>
                    unawaited(player.command('seek', {'position': position})),
                onInteraction: () => updateControls(interacted: true),
                previewBottomInset: reservedBottom,
                previewTopInset: reservedTop,
                previewExclusion: state.small == null
                    ? null
                    : smallPlacement.resolve(smallViewport, reservedTop),
                child: picture(state.main),
              ),
            ),
            if (state.small != null)
              ClassroomSmallWindow(
                placement: smallPlacement,
                viewport: smallViewport,
                reservedTop: reservedTop,
                label: classroomViewName(state.small!),
                picture: picture(state.small!),
                onSwap: () => layout(state.small!, state.main),
                onClose: closeSmall,
                onInteraction: () => updateControls(interacted: true),
                showControls: !fullscreen || controlsVisible,
              ),
            if (dragging != null && canScrub)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: ClassroomSeekPreview(
                      key: const ValueKey('classroom-slider-seek-preview'),
                      target: dragging!.toInt().clamp(0, state.duration),
                      duration: state.duration,
                      formatTime: time,
                    ),
                  ),
                ),
              ),
            if (state.watermark.isNotEmpty)
              Positioned(
                top: 12,
                left: watermarkLeft,
                right: fullscreen ? 72 : 16,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${small ? '小窗' : '主画面'} · ${small && state.small == null ? '已关闭' : classroomViewName(small ? state.small! : state.main)}',
            ),
            const SizedBox(width: 4),
            const AppIcon(AppIcons.chevronDown, size: 16),
          ],
        ),
      ),
    );
  }

  Widget controls({bool overlay = false}) {
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
    final canControl = error == null && !(progress?.blocked ?? false);
    final notices = <Widget>[
      if (progress != null &&
          progress!.blocked &&
          !progress!.invalidated &&
          progress!.choicePosition == null)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('正在核对本机进度与视频时长…'),
        ),
      if (progress?.warning != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(progress!.warning!),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(error, semanticsLabel: error),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!overlay) ...notices,
        Slider(
          semanticFormatterCallback: (value) => time(value.toInt()),
          value: (dragging ?? state.position.toDouble()).clamp(
            0.0,
            state.duration > 0 ? state.duration.toDouble() : 1.0,
          ),
          max: state.duration > 0 ? state.duration.toDouble() : 1,
          onChanged: canScrub
              ? (value) {
                  if (draggingDuration != player.state.duration) return;
                  setState(() => dragging = value);
                  updateControls(interacted: true);
                }
              : null,
          onChangeStart: canScrub
              ? (value) {
                  setState(() {
                    draggingDuration = player.state.duration;
                    dragging = value;
                  });
                  updateControls(interacted: true);
                }
              : null,
          onChangeEnd: (value) {
            final valid =
                dragging != null &&
                draggingDuration == player.state.duration &&
                canScrub;
            setState(() {
              dragging = null;
              draggingDuration = null;
            });
            updateControls(interacted: true);
            if (valid) {
              unawaited(
                player.command('seek', {
                  'position': value.toInt().clamp(0, player.state.duration),
                }),
              );
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                tooltip: state.wanted ? '暂停' : '播放',
                onPressed: canControl
                    ? () => player.command(state.wanted ? 'pause' : 'play')
                    : null,
                icon: AppIcon(state.wanted ? AppIcons.pause : AppIcons.play),
              ),
              Expanded(
                child: Text(
                  '${time(state.position)} / ${time(state.duration)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: overlay ? Colors.white : null,
                  ),
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
                onPressed: changingFullscreen ? null : toggleFullscreen,
                icon: AppIcon(
                  fullscreen ? AppIcons.fullscreenExit : AppIcons.fullscreen,
                ),
              ),
            ],
          ),
        ),
        if (overlay) ...notices,
        if (!overlay)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: '后退10秒',
                onPressed: canControl && state.duration > 0
                    ? () => player.command('seek', {
                        'position': (state.position - 10000).clamp(
                          0,
                          state.duration,
                        ),
                      })
                    : null,
                icon: const AppIcon(AppIcons.back10),
              ),
              IconButton(
                tooltip: '前进10秒',
                onPressed: canControl && state.duration > 0
                    ? () => player.command('seek', {
                        'position': (state.position + 10000).clamp(
                          0,
                          state.duration,
                        ),
                      })
                    : null,
                icon: const AppIcon(AppIcons.forward10),
              ),
              viewMenu(small: false),
              viewMenu(small: true),
              if (state.small == null)
                TextButton.icon(
                  onPressed: state.available.any((kind) => kind != state.main)
                      ? showSmall
                      : null,
                  icon: const AppIcon(AppIcons.pictureInPicture),
                  label: const Text('显示小窗'),
                ),
              IconButton(
                tooltip: '交换主画面与小窗',
                onPressed: state.small == null
                    ? null
                    : () => layout(state.small!, state.main),
                icon: const AppIcon(AppIcons.swapHorizontal),
              ),
            ],
          ),
      ],
    );
  }

  Widget fullscreenBody() => LayoutBuilder(
    builder: (context, constraints) {
      final panelLimit = math.min(160.0, constraints.maxHeight * .45);
      final overlayTheme = Theme.of(context).copyWith(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: Theme.of(context).colorScheme.primary,
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
          shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            label: '轻点显示播放控制',
            button: true,
            onTap: () => updateControls(interacted: true),
            child: GestureDetector(
              key: const ValueKey('fullscreen-playback-surface'),
              behavior: HitTestBehavior.opaque,
              onTap: () => updateControls(interacted: true),
              child: viewport(reservedBottom: controlsVisible ? panelLimit : 0),
            ),
          ),
          if (controlsVisible) ...[
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                tooltip: '返回竖屏',
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: changingFullscreen ? null : toggleFullscreen,
                icon: const AppIcon(AppIcons.arrowBack),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                tooltip: '切换画面',
                color: Colors.white,
                onPressed: showViewDrawer,
                icon: const AppIcon(
                  AppIcons.videoSettings,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelLimit),
                child: Theme(
                  data: overlayTheme,
                  child: Material(
                    key: const ValueKey('fullscreen-transparent-controls'),
                    type: MaterialType.transparency,
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          overlayColor: Colors.transparent,
                          trackHeight: 3,
                          activeTrackColor: overlayTheme.colorScheme.primary,
                          inactiveTrackColor: Colors.white54,
                          thumbColor: Colors.white,
                        ),
                        child: SingleChildScrollView(
                          key: const ValueKey('fullscreen-controls-panel'),
                          child: controls(overlay: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !fullscreen && !changingFullscreen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(toggleFullscreen());
    },
    child: Scaffold(
      appBar: fullscreen
          ? null
          : AppBar(
              title: Text(widget.title),
              actions: [
                TextButton.icon(
                  onPressed: changingFullscreen ? null : toggleFullscreen,
                  icon: const AppIcon(AppIcons.fullscreen),
                  label: const Text('横屏'),
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                ),
              ],
            ),
      body: SafeArea(
        child: Listener(
          onPointerDown: (_) {
            pointersDown++;
            updateControls(interacted: true);
          },
          onPointerUp: (_) => endPointer(),
          onPointerCancel: (_) {
            setState(() {
              dragging = null;
              draggingDuration = null;
            });
            endPointer();
          },
          child: fullscreen
              ? fullscreenBody()
              : ListView(
                  children: [
                    AspectRatio(aspectRatio: 16 / 9, child: viewport()),
                    controls(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '左右滑动主画面调整进度，松手跳转；单指拖动、双指缩放小窗，点按可交换主画面。学校观看记录尚未接入，本地播放不代表学校记录已更新。',
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}
