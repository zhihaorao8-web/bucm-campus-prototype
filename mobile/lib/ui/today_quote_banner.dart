import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/appearance_controller.dart';
import '../application/quote_service.dart';
import 'app_icons.dart';

/// Airy editorial quote strip displayed at the top of the Today page.
class TodayQuoteBanner extends ConsumerStatefulWidget {
  const TodayQuoteBanner({super.key});

  @override
  ConsumerState<TodayQuoteBanner> createState() => _TodayQuoteBannerState();
}

class _TodayQuoteBannerState extends ConsumerState<TodayQuoteBanner> {
  late DailyQuote quote;
  bool loading = false;
  int requestTicket = 0;

  @override
  void initState() {
    super.initState();
    final service = ref.read(quoteServiceProvider);
    quote = service.pickLocal();
    final allowOnline = ref.read(currentAppearanceProvider).onlineQuotes;
    if (allowOnline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(allowOnline: true);
      });
    }
  }

  Future<void> _refresh({
    required bool allowOnline,
    bool userTriggered = false,
  }) async {
    final ticket = ++requestTicket;
    final service = ref.read(quoteServiceProvider);
    if (!allowOnline) {
      setState(() {
        loading = false;
        quote = service.pickLocal(excludeText: quote.text);
      });
      return;
    }
    if (userTriggered) {
      setState(() => loading = true);
    }
    final next = await service.nextQuote(
      allowOnline: true,
      excludeText: quote.text,
    );
    if (!mounted || ticket != requestTicket) return;
    final stillEnabled = ref.read(currentAppearanceProvider).onlineQuotes;
    if (!stillEnabled && next.isOnline) {
      setState(() => loading = false);
      return;
    }
    setState(() {
      loading = false;
      quote = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(currentAppearanceProvider);
    ref.listen<bool>(
      currentAppearanceProvider.select((s) => s.onlineQuotes),
      (previous, next) {
        if (previous != next) {
          _refresh(allowOnline: next);
        }
      },
    );
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final opaque =
        MediaQuery.highContrastOf(context) ||
        appearance.contrast > 0 ||
        !appearance.blur ||
        !appearance.glass;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final background = opaque
        ? colors.surfaceContainer
        : dark
        ? Colors.white.withValues(alpha: .07)
        : Colors.white.withValues(alpha: .54);
    final border = opaque
        ? colors.outlineVariant
        : dark
        ? Colors.white.withValues(alpha: .11)
        : Colors.white.withValues(alpha: .72);

    return Semantics(
      container: true,
      label: '今日语录：${quote.text}，${quote.attribution}',
      child: Material(
        key: const ValueKey('today-quote-strip'),
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _refresh(
            allowOnline: appearance.onlineQuotes,
            userTriggered: true,
          ),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 3,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: opaque ? 1 : .68),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                    child: Column(
                      key: ValueKey('${quote.text}|${quote.source}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          quote.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.48,
                            fontWeight: FontWeight.w500,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '—— ${quote.attribution}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (quote.isOnline) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '一言',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Tooltip(
                  message: '换一句语录',
                  child: MiuixIconButton(
                    key: const ValueKey('today-quote-refresh'),
                    minWidth: 48,
                    minHeight: 48,
                    onPressed: () => _refresh(
                      allowOnline: appearance.onlineQuotes,
                      userTriggered: true,
                    ),
                    child: Opacity(
                      opacity: loading ? .45 : .78,
                      child: const AppIcon(AppIcons.refresh, size: 17),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
