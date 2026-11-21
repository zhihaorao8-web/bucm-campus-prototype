import '../design/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';
import 'app_icons.dart';

/// MIUIX row behavior with the same locally bundled chevron as the rest of UI.
class AppArrowPreference extends StatelessWidget {
  const AppArrowPreference({
    super.key,
    required this.title,
    this.summary,
    this.startAction,
    this.onClick,
    this.enabled = true,
    this.destructive = false,
  });
  final String title;
  final String? summary;
  final Widget? startAction;
  final VoidCallback? onClick;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final error = Theme.of(context).colorScheme.error;
    return MiuixBasicComponent(
      title: title,
      titleColor: destructive
          ? MiuixBasicComponentColors(
              color: error,
              disabledColor: colors.disabledOnSecondaryVariant,
            )
          : null,
      summary: summary,
      startAction: startAction,
      onClick: onClick,
      enabled: enabled,
      endActions: [
        AppIcon(
          AppIcons.chevronRight,
          size: 20,
          color: enabled
              ? (destructive ? error : colors.onSurfaceVariantActions)
              : colors.disabledOnSecondaryVariant,
        ),
      ],
    );
  }
}

/// Preserve ExpansionTile behavior while replacing its implicit Material glyph.
class AppExpansionTile extends StatefulWidget {
  const AppExpansionTile({
    super.key,
    required this.title,
    required this.children,
    this.tilePadding,
  });
  final Widget title;
  final List<Widget> children;
  final EdgeInsetsGeometry? tilePadding;

  @override
  State<AppExpansionTile> createState() => _AppExpansionTileState();
}

class _AppExpansionTileState extends State<AppExpansionTile> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: widget.title,
    tilePadding: widget.tilePadding,
    onExpansionChanged: (value) => setState(() => expanded = value),
    trailing: AnimatedRotation(
      turns: expanded ? .5 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.contentEnter,
      child: const AppIcon(AppIcons.chevronDown),
    ),
    children: widget.children,
  );
}
