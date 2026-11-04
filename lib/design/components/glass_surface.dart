import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/settings/appearance.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';
import '../tokens/glass.dart';

/// A frosted pane: blurred backdrop + tint + 1px border + top highlight.
///
/// Rules of the house (see `docs/07-design-system.md`):
/// - Only floating chrome uses this: sidebar, bars, popovers, dialogs.
/// - Text is never placed directly on a translucent pane; the tint alpha is
///   kept high enough that body text stays above WCAG AA.
/// - [GlassQuality.off] degrades to opaque paper without any code change here.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.blurSigma,
    this.tintAlpha,
    this.showShadow = true,
    this.showHighlight = true,
    this.radius,
    this.quality,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Overrides the token blur radius (e.g. smaller popovers).
  final double? blurSigma;

  /// Overrides the token tint alpha for places that need more legibility.
  final double? tintAlpha;

  final bool showShadow;
  final bool showHighlight;

  /// Convenience for uniform radii.
  final double? radius;

  /// Forces a specific frost level regardless of the user preference. Used by
  /// the design-system page; production chrome follows the theme.
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final GlassTokens glass = quality == null
        ? context.glass
        : GlassTokens.forQuality(quality!, dark: dark);
    final BorderRadius shape =
        borderRadius ?? BorderRadius.circular(radius ?? AppRadius.lg);
    final double sigma = blurSigma ?? glass.blurSigma;
    final Color fill = tintAlpha == null
        ? glass.fill
        : glass.tint.withValues(alpha: tintAlpha!);

    final Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        border: Border.all(color: glass.border),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (showHighlight)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: shape,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        glass.highlight,
                        glass.highlight.withValues(alpha: 0),
                      ],
                      stops: const <double>[0, 0.42],
                    ),
                  ),
                ),
              ),
            ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );

    Widget surface = RepaintBoundary(
      child: ClipRRect(
        borderRadius: shape,
        child: glass.isBlurred && sigma > 0
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: pane,
              )
            : pane,
      ),
    );

    if (showShadow) {
      surface = DecoratedBox(
        decoration: BoxDecoration(borderRadius: shape, boxShadow: glass.shadow),
        child: surface,
      );
    }
    return surface;
  }
}
