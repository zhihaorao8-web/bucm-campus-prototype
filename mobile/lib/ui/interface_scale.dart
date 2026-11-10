import 'package:flutter/material.dart';

/// Scale layout and hit testing together; preserve the user's text scaler.
class InterfaceScale extends StatelessWidget {
  const InterfaceScale({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (scale == 1) return child;
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: constraints.maxWidth / scale,
          maxWidth: constraints.maxWidth / scale,
          minHeight: constraints.maxHeight / scale,
          maxHeight: constraints.maxHeight / scale,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: MediaQuery(
              data: media.copyWith(
                size: media.size / scale,
                devicePixelRatio: media.devicePixelRatio * scale,
                padding: media.padding / scale,
                viewPadding: media.viewPadding / scale,
                viewInsets: media.viewInsets / scale,
                systemGestureInsets: media.systemGestureInsets / scale,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
