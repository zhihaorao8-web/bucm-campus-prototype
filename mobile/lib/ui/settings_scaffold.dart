import '../design/app_tokens.dart';
import 'visual_policy.dart';
import 'app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import 'quiet_backdrop.dart';
import 'course_surface.dart';

class SettingsScaffold extends ConsumerStatefulWidget {
  const SettingsScaffold({
    super.key,
    required this.title,
    required this.children,
  });
  final String title;
  final List<Widget> children;
  @override
  ConsumerState<SettingsScaffold> createState() => _SettingsScaffoldState();
}

class _SettingsScaffoldState extends ConsumerState<SettingsScaffold> {
  final behavior = miuixScrollBehavior(snapOnRelease: false);
  final scroll = ScrollController();
  double drag = 0;
  @override
  void dispose() {
    scroll.dispose();
    behavior.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentAppearanceProvider);
    return Scaffold(
      body: Stack(
        children: [
          QuietBackdrop(
            tab: 2,
            child: MiuixScaffold(
              containerColor: Colors.transparent,
              topBar: ListenableBuilder(
                listenable: scroll,
                builder: (context, _) => MiuixTopAppBar(
                  title: widget.title,
                  color: Theme.of(context).colorScheme.surface,
                  scrollBehavior: behavior,
                  blurred: AppVisualPolicy.of(context, settings).translucent,
                  blurRadius: AppHeader.blur,
                  blurTintAlpha: AppHeader.tint(
                    scroll.hasClients ? scroll.offset : 0,
                  ),
                  navigationIcon: IconButton(
                    tooltip: '返回',
                    icon: const AppIcon(AppIcons.arrowBack),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ),
              ),
              content: (insets) => FocusTraversalGroup(
                child: MiuixScrollBehaviorListener(
                  behavior: behavior,
                  child: CustomScrollView(
                    key: ValueKey('settings-route-${widget.title}'),
                    controller: scroll,
                    slivers: [
                      // The externally painted bar must count as viewport obstruction.
                      PinnedHeaderSliver(child: SizedBox(height: insets.top)),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          16 + insets.left,
                          16,
                          16 + insets.right,
                          insets.bottom + 32,
                        ),
                        sliver: SliverList.list(children: widget.children),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (settings.swipeBack && Navigator.canPop(context))
            Positioned(
              left: 0,
              top: MediaQuery.paddingOf(context).top + 64,
              bottom: 0,
              width: 18,
              child: GestureDetector(
                key: const ValueKey('edge-back-gesture'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => drag = 0,
                onHorizontalDragUpdate: (value) => drag += value.delta.dx,
                onHorizontalDragEnd: (value) {
                  if (drag > 64 || (value.primaryVelocity ?? 0) > 450) {
                    Navigator.maybePop(context);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

Widget settingsGroup(List<Widget> children) => Padding(
  padding: const EdgeInsets.only(bottom: 16),
  child: QuietCard(
    cornerRadius: 24,
    insideMargin: EdgeInsets.zero,
    child: Column(children: children),
  ),
);
