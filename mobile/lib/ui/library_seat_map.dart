import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/app_palette.dart';
import '../design/app_tokens.dart';
import '../domain/library_seats.dart';
import 'app_icons.dart';
import 'app_theme.dart';
import 'course_surface.dart';

@immutable
class LibrarySeatTone {
  const LibrarySeatTone({
    required this.foreground,
    required this.background,
    required this.border,
    required this.dot,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final Color dot;
}

abstract final class LibrarySeatPalette {
  static String statusLabel(LibrarySeatStatus status) => switch (status) {
    LibrarySeatStatus.available => '空闲',
    LibrarySeatStatus.partial => '半空闲',
    LibrarySeatStatus.occupied => '使用中',
    LibrarySeatStatus.closed => '不开放',
    LibrarySeatStatus.viewOnly => '仅查看',
  };

  static LibrarySeatTone toneOf(
    BuildContext context,
    LibrarySeatStatus status, {
    bool selected = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);

    if (selected) {
      return LibrarySeatTone(
        foreground: colors.onPrimary,
        background: colors.primary,
        border: highContrast ? colors.onPrimary : colors.primary,
        dot: colors.onPrimary,
      );
    }

    if (highContrast) {
      final dot = switch (status) {
        LibrarySeatStatus.available =>
          dark ? const Color(0xFF5EE0A8) : AppPalette.success,
        LibrarySeatStatus.partial =>
          dark ? const Color(0xFFF6BD60) : const Color(AppPalette.amberValue),
        LibrarySeatStatus.occupied => colors.error,
        LibrarySeatStatus.closed ||
        LibrarySeatStatus.viewOnly => colors.onSurfaceVariant,
      };
      return LibrarySeatTone(
        foreground: colors.onSurface,
        background: colors.surface,
        border: colors.outline,
        dot: dot,
      );
    }

    return switch (status) {
      LibrarySeatStatus.available => LibrarySeatTone(
        foreground: dark ? const Color(0xFF5EE0A8) : AppPalette.success,
        background: dark ? const Color(0xFF1A2E25) : const Color(0xFFEFF8F3),
        border: (dark ? const Color(0xFF5EE0A8) : AppPalette.success)
            .withValues(alpha: dark ? .35 : .28),
        dot: dark ? const Color(0xFF5EE0A8) : AppPalette.success,
      ),
      LibrarySeatStatus.partial => LibrarySeatTone(
        foreground: dark
            ? const Color(0xFFF6BD60)
            : const Color(AppPalette.amberValue),
        background: dark ? const Color(0xFF312719) : const Color(0xFFFAF5EE),
        border:
            (dark
                    ? const Color(0xFFF6BD60)
                    : const Color(AppPalette.amberValue))
                .withValues(alpha: dark ? .38 : .32),
        dot: dark
            ? const Color(0xFFF6BD60)
            : const Color(AppPalette.amberValue),
      ),
      LibrarySeatStatus.occupied => LibrarySeatTone(
        foreground: colors.onSurfaceVariant,
        background: dark
            ? const Color(0xFF232830)
            : colors.surfaceContainerHighest.withValues(alpha: .65),
        border: dark
            ? Colors.white.withValues(alpha: .12)
            : colors.outlineVariant,
        dot: colors.error,
      ),
      LibrarySeatStatus.closed || LibrarySeatStatus.viewOnly => LibrarySeatTone(
        foreground: colors.onSurfaceVariant.withValues(alpha: .85),
        background: dark
            ? const Color(0xFF1A1E24)
            : colors.surfaceContainerLow.withValues(alpha: .70),
        border: dark
            ? Colors.white.withValues(alpha: .08)
            : colors.outlineVariant.withValues(alpha: .75),
        dot: colors.outline,
      ),
    };
  }
}

bool canUseLibraryFloorMap(List<LibrarySeat>? seats) =>
    seats != null && seats.any((seat) => seat.hasCoordinates);

class LibrarySeatFloorMap extends StatefulWidget {
  const LibrarySeatFloorMap({
    super.key,
    required this.allSeats,
    required this.visibleSeats,
    required this.selectedSeatId,
    required this.busy,
    required this.onSelectSeat,
    required this.onInspectPartial,
    required this.onUnavailableTap,
  });

  final List<(LibrarySeat, LibrarySeatStatus)> allSeats;
  final List<(LibrarySeat, LibrarySeatStatus)> visibleSeats;
  final String? selectedSeatId;
  final bool busy;
  final ValueChanged<LibrarySeat> onSelectSeat;
  final ValueChanged<LibrarySeat> onInspectPartial;
  final void Function(LibrarySeat seat, LibrarySeatStatus status)
  onUnavailableTap;

  @override
  State<LibrarySeatFloorMap> createState() => _LibrarySeatFloorMapState();
}

class _LibrarySeatFloorMapState extends State<LibrarySeatFloorMap> {
  static const double _minScale = 1.0, _maxScale = 6.0;
  final TransformationController _controller = TransformationController();
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onMatrixChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onMatrixChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onMatrixChanged() {
    final next = _controller.value.getMaxScaleOnAxis();
    if ((next - _scale).abs() > 0.02 && mounted) {
      setState(() => _scale = next);
    }
  }

  void _zoomBy(double factor, Size viewport) {
    final current = _controller.value;
    final currentScale = current.getMaxScaleOnAxis();
    final nextScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final applied = nextScale / currentScale;
    if ((applied - 1).abs() < 0.01) return;

    final fx = viewport.width / 2;
    final fy = viewport.height / 2;
    final tx = fx - (fx - current.storage[12]) * applied;
    final ty = fy - (fy - current.storage[13]) * applied;
    final minTx = viewport.width * (1 - nextScale);
    final minTy = viewport.height * (1 - nextScale);
    _controller.value = Matrix4.diagonal3Values(nextScale, nextScale, 1)
      ..setTranslationRaw(
        tx.clamp(minTx, 0.0).toDouble(),
        ty.clamp(minTy, 0.0).toDouble(),
        0,
      );
  }

  void _resetZoom() {
    _controller.value = Matrix4.identity();
  }

  List<Size> _computeNodeSizes(
    List<Offset> centers,
    double usableW,
    double usableH,
  ) {
    final count = centers.length;
    if (count == 0) return const [];
    if (count == 1) return const [Size(52.0, 32.0)];

    final rowTol = math.max(6.0, usableH * 0.025);
    final colTol = math.max(6.0, usableW * 0.025);
    final sameRowDx = <double>[];
    final sameColDy = <double>[];

    for (var i = 0; i < count; i++) {
      var bestDx = double.infinity;
      var bestDy = double.infinity;
      for (var j = 0; j < count; j++) {
        if (i == j) continue;
        final dx = (centers[i].dx - centers[j].dx).abs();
        final dy = (centers[i].dy - centers[j].dy).abs();
        if (dy <= rowTol && dx > 0.5 && dx < bestDx) bestDx = dx;
        if (dx <= colTol && dy > 0.5 && dy < bestDy) bestDy = dy;
      }
      if (bestDx.isFinite) sameRowDx.add(bestDx);
      if (bestDy.isFinite) sameColDy.add(bestDy);
    }

    sameRowDx.sort();
    sameColDy.sort();
    final typicalDx = sameRowDx.isEmpty
        ? 48.0
        : sameRowDx[(sameRowDx.length * 0.35).floor()];
    final typicalDy = sameColDy.isEmpty
        ? 34.0
        : sameColDy[(sameColDy.length * 0.35).floor()];

    var targetW = (typicalDx * 0.88).clamp(8.0, 52.0);
    var targetH = (typicalDy * 0.84).clamp(8.0, 32.0);
    targetW = math.min(targetW, targetH * 1.9);
    targetH = math.min(targetH, targetW * 1.35);

    final widths = List<double>.filled(count, targetW);
    final heights = List<double>.filled(count, targetH);
    const gap = 1.6;

    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final dx = (centers[i].dx - centers[j].dx).abs();
        final dy = (centers[i].dy - centers[j].dy).abs();
        if (dx < (widths[i] + widths[j]) / 2 + gap &&
            dy < (heights[i] + heights[j]) / 2 + gap) {
          if (dx / targetW >= dy / targetH) {
            final maxW = math.max(4.5, dx - gap);
            widths[i] = math.min(widths[i], maxW);
            widths[j] = math.min(widths[j], maxW);
          } else {
            final maxH = math.max(4.5, dy - gap);
            heights[i] = math.min(heights[i], maxH);
            heights[j] = math.min(heights[j], maxH);
          }
        }
      }
    }

    return [for (var i = 0; i < count; i++) Size(widths[i], heights[i])];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final visibleIds = {for (final (seat, _) in widget.visibleSeats) seat.id};
    final coordEntries = widget.allSeats
        .where((item) => item.$1.hasCoordinates)
        .toList();

    var minX = double.infinity,
        maxX = -double.infinity,
        minY = double.infinity,
        maxY = -double.infinity;
    for (final (seat, _) in coordEntries) {
      minX = math.min(minX, seat.x!);
      maxX = math.max(maxX, seat.x!);
      minY = math.min(minY, seat.y!);
      maxY = math.max(maxY, seat.y!);
    }
    final spanX = math.max(maxX - minX, 1.0);
    final spanY = math.max(maxY - minY, 1.0);
    final roomAspect = (spanX / spanY).clamp(0.90, 1.70);

    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final canvasWidth = constraints.maxWidth;
            final canvasHeight = (canvasWidth / roomAspect).clamp(250.0, 390.0);
            final padX = coordEntries.length > 16 ? 14.0 : 28.0;
            final padY = coordEntries.length > 16 ? 14.0 : 20.0;
            final usableW = math.max(1.0, canvasWidth - padX * 2);
            final usableH = math.max(1.0, canvasHeight - padY * 2);

            final positions = <Offset>[];
            for (final (seat, _) in coordEntries) {
              final nx = maxX == minX ? 0.5 : (seat.x! - minX) / spanX;
              final ny = maxY == minY ? 0.5 : (seat.y! - minY) / spanY;
              positions.add(Offset(padX + nx * usableW, padY + ny * usableH));
            }
            final sizes = _computeNodeSizes(positions, usableW, usableH);
            final viewportSize = Size(canvasWidth, canvasHeight);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(
                      _scale > 1.05
                          ? '平面分布 · 缩放 ${(_scale * 100).round()}%'
                          : '平面分布 · 双指缩放或点选座位',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: tabularTime,
                      ),
                    ),
                    CourseSurface(
                      dense: true,
                      radius: AppRadius.input,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const ValueKey('library-map-zoom-in'),
                            tooltip: '放大平面图',
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const AppIcon(
                              AppIcons.zoomIn,
                              size: AppControl.icon,
                            ),
                            onPressed: _scale >= _maxScale - 0.05
                                ? null
                                : () => _zoomBy(1.5, viewportSize),
                          ),
                          IconButton(
                            key: const ValueKey('library-map-zoom-out'),
                            tooltip: '缩小平面图',
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const AppIcon(
                              AppIcons.zoomOut,
                              size: AppControl.icon,
                            ),
                            onPressed: _scale <= _minScale + 0.05
                                ? null
                                : () => _zoomBy(1 / 1.5, viewportSize),
                          ),
                          IconButton(
                            key: const ValueKey('library-map-zoom-fit'),
                            tooltip: '重置视图',
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 40,
                            ),
                            padding: EdgeInsets.zero,
                            icon: const AppIcon(
                              AppIcons.zoomFit,
                              size: AppControl.icon,
                            ),
                            onPressed: _scale <= _minScale + 0.05
                                ? null
                                : _resetZoom,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.inset),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow.withValues(
                        alpha: highContrast ? 1.0 : 0.65,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.inset),
                      border: Border.all(
                        width: highContrast ? 1.2 : 0.7,
                        color: highContrast
                            ? colors.outline
                            : colors.outlineVariant.withValues(alpha: .75),
                      ),
                    ),
                    child: SizedBox(
                      key: const ValueKey('library-floor-map-viewport'),
                      width: canvasWidth,
                      height: canvasHeight,
                      child: InteractiveViewer(
                        key: const ValueKey('library-floor-map-viewer'),
                        transformationController: _controller,
                        minScale: _minScale,
                        maxScale: _maxScale,
                        boundaryMargin: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 12,
                        ),
                        child: SizedBox(
                          width: canvasWidth,
                          height: canvasHeight,
                          child: Stack(
                            children: [
                              for (var i = 0; i < coordEntries.length; i++)
                                _buildSeatNode(
                                  context,
                                  seat: coordEntries[i].$1,
                                  status: coordEntries[i].$2,
                                  visible: visibleIds.contains(
                                    coordEntries[i].$1.id,
                                  ),
                                  center: positions[i],
                                  width: sizes[i].width,
                                  height: sizes[i].height,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSeatNode(
    BuildContext context, {
    required LibrarySeat seat,
    required LibrarySeatStatus status,
    required bool visible,
    required Offset center,
    required double width,
    required double height,
  }) {
    final colors = Theme.of(context).colorScheme;
    final highContrast = MediaQuery.highContrastOf(context);
    final selected =
        widget.selectedSeatId == seat.id &&
        status == LibrarySeatStatus.available &&
        visible;

    final radius = (math.min(width, height) * 0.24).clamp(2.0, 7.0);
    if (!visible) {
      return Positioned(
        left: center.dx - width / 2,
        top: center.dy - height / 2,
        width: width,
        height: height,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  width: width < 12 ? 0.55 : 0.7,
                  color: colors.outlineVariant.withValues(alpha: .35),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final tone = LibrarySeatPalette.toneOf(
      context,
      status,
      selected: selected,
    );
    final statusText = LibrarySeatPalette.statusLabel(status);
    final showLabel = width * _scale >= 9.5;
    final borderWidth = selected
        ? (width < 12 ? 1.0 : 1.5)
        : (highContrast ? 1.0 : (width < 12 ? 0.55 : 0.8));

    return Positioned(
      left: center.dx - width / 2,
      top: center.dy - height / 2,
      width: width,
      height: height,
      child: Semantics(
        button: true,
        selected: selected,
        label: '${seat.label}，$statusText',
        child: Material(
          color: tone.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(width: borderWidth, color: tone.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.busy
                ? null
                : () {
                    if (status == LibrarySeatStatus.available) {
                      widget.onSelectSeat(seat);
                    } else if (status == LibrarySeatStatus.partial) {
                      widget.onInspectPartial(seat);
                    } else {
                      widget.onUnavailableTap(seat, status);
                    }
                  },
            child: showLabel
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: (width * 0.08).clamp(0.5, 3.0),
                        vertical: (height * 0.06).clamp(0.5, 2.0),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          seat.label,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: tone.foreground,
                            fontFeatures: tabularTime,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class LibrarySeatGridControls extends StatelessWidget {
  const LibrarySeatGridControls({
    super.key,
    required this.searchController,
    required this.query,
    required this.totalFilteredCount,
    required this.segmentIndex,
    required this.segmentCount,
    required this.segmentLabels,
    required this.onQueryChanged,
    required this.onSegmentSelected,
  });

  final TextEditingController searchController;
  final String query;
  final int totalFilteredCount;
  final int segmentIndex;
  final int segmentCount;
  final List<String> segmentLabels;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<int> onSegmentSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CourseSurface(
          dense: true,
          radius: AppRadius.input,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppLayout.minTap),
            child: TextField(
              key: const ValueKey('library-seat-search'),
              controller: searchController,
              onChanged: onQueryChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索座位号，如 2N018',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.md,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: AppIcon(AppIcons.search, size: AppControl.icon),
                ),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空搜索',
                        icon: const AppIcon(
                          AppIcons.close,
                          size: AppControl.icon,
                        ),
                        onPressed: () {
                          searchController.clear();
                          onQueryChanged('');
                        },
                      ),
              ),
            ),
          ),
        ),
        if (query.isEmpty && segmentCount > 1) ...[
          const SizedBox(height: AppSpace.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: ChoiceChip(
                    label: Text('全部 ($totalFilteredCount)'),
                    selected: segmentIndex < 0,
                    onSelected: (_) => onSegmentSelected(-1),
                  ),
                ),
                for (var i = 0; i < segmentLabels.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.xs),
                    child: ChoiceChip(
                      label: Text(segmentLabels[i]),
                      selected: segmentIndex == i,
                      onSelected: (_) => onSegmentSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class LibrarySeatGridRow extends StatelessWidget {
  const LibrarySeatGridRow({
    super.key,
    required this.items,
    required this.columns,
    required this.date,
    required this.start,
    required this.end,
    required this.hasValidRange,
    required this.selectedSeatId,
    required this.busy,
    required this.onSelectSeat,
    required this.onInspectPartial,
    required this.onUnavailableTap,
  });

  final List<(LibrarySeat, LibrarySeatStatus)> items;
  final int columns;
  final DateTime date;
  final TimeOfDay? start;
  final TimeOfDay? end;
  final bool hasValidRange;
  final String? selectedSeatId;
  final bool busy;
  final ValueChanged<LibrarySeat> onSelectSeat;
  final ValueChanged<LibrarySeat> onInspectPartial;
  final void Function(LibrarySeat seat, LibrarySeatStatus status)
  onUnavailableTap;

  static int columnsFor(BuildContext context, double width) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (width < 340 || scale >= 1.8) return 2;
    if (width < 460 && scale >= 1.35) return 3;
    return width >= 600 ? 5 : 4;
  }

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns; i++) ...[
            if (i > 0) const SizedBox(width: AppSpace.sm),
            Expanded(
              child: i < items.length
                  ? _tile(context, items[i].$1, items[i].$2)
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    LibrarySeat seat,
    LibrarySeatStatus status,
  ) {
    final theme = Theme.of(context);
    final selected =
        selectedSeatId == seat.id && status == LibrarySeatStatus.available;
    final tone = LibrarySeatPalette.toneOf(
      context,
      status,
      selected: selected,
    );
    final label = LibrarySeatPalette.statusLabel(status);
    final highContrast = MediaQuery.highContrastOf(context);
    final canSelect = status == LibrarySeatStatus.available;

    String? subText;
    if (hasValidRange &&
        (status == LibrarySeatStatus.partial ||
            status == LibrarySeatStatus.occupied)) {
      final overlaps = seat.overlappingReservations(
        date,
        start!.hour * 60 + start!.minute,
        end!.hour * 60 + end!.minute,
      );
      if (overlaps.isNotEmpty) {
        subText = '已约 ${overlaps.map(formatLibraryInterval).join('、')}';
      }
    }

    return Semantics(
      button: true,
      selected: selected,
      label: '${seat.label}，$label${subText == null ? '' : '，$subText'}',
      child: Material(
        color: tone.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.small),
          side: BorderSide(
            width: selected ? 1.5 : (highContrast ? 1.2 : 0.7),
            color: tone.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy
              ? null
              : () {
                  if (canSelect) {
                    onSelectSeat(seat);
                  } else if (status == LibrarySeatStatus.partial) {
                    onInspectPartial(seat);
                  } else {
                    onUnavailableTap(seat, status);
                  }
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: AppSpace.sm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          seat.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: selected
                                ? tone.foreground
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabularTime,
                          ),
                        ),
                      ),
                      if (selected)
                        AppIcon(
                          AppIcons.check,
                          size: 14,
                          color: tone.foreground,
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tone.dot,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: AppType.caption,
                            color: tone.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (subText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: AppType.micro,
                        color: tone.foreground.withValues(alpha: .88),
                        fontFeatures: tabularTime,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LibrarySeatLoadingSkeleton extends StatelessWidget {
  const LibrarySeatLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tint = colors.surfaceContainerHighest.withValues(alpha: .42);
    return QuietCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 16,
              width: 140,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(AppSpace.sm),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(AppRadius.inset),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
