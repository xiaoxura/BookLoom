import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_colors.dart';
import '../tokens/app_metrics.dart';

/// An opaque paper panel: solid surface fill + 1px hairline + soft shadow.
///
/// This is the only panel chrome needs — sidebar, bottom bar, popovers,
/// dialogs all sit on real paper. There is deliberately no translucent
/// variant: blur costs GPU time on every resize and repaint, lowers text
/// contrast, and reads as decoration rather than structure. See the "为什么
/// 不做磨砂" section in `docs/07-design-system.md`.
class PaperSurface extends StatelessWidget {
  const PaperSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.showShadow = true,
    this.radius,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool showShadow;

  /// Convenience for uniform radii.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final AppColors colors = context.colors;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final BorderRadius shape =
        borderRadius ?? BorderRadius.circular(radius ?? AppRadius.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: colors.surface,
        border: Border.all(color: colors.hairline),
        boxShadow: showShadow
            ? <BoxShadow>[
                BoxShadow(
                  color: colors.shadow.withValues(alpha: dark ? 0.30 : 0.12),
                  blurRadius: 32,
                  spreadRadius: -10,
                  offset: const Offset(0, 12),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );
  }
}
