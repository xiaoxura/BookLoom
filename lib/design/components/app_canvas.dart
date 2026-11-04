import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// The paper backdrop: a warm vertical wash plus two soft ink glows.
///
/// The glows exist so frosted chrome has something worth blurring; they stay
/// extremely low contrast so text contrast is unaffected.
class AppCanvas extends StatelessWidget {
  const AppCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[colors.canvasAlt, colors.canvas],
            ),
          ),
        ),
        // Layered washes: the sidebar frost needs something to pick up, and
        // the page should never look like flat gray paper.
        IgnorePointer(
          child: _InkWash(
            alignment: const Alignment(-1, -0.55),
            color: colors.accent.withValues(alpha: 0.16),
            size: 1150,
          ),
        ),
        IgnorePointer(
          child: _InkWash(
            alignment: const Alignment(-1.05, 1.15),
            color: colors.warning.withValues(alpha: 0.12),
            size: 700,
          ),
        ),
        IgnorePointer(
          child: _InkWash(
            alignment: const Alignment(1.25, -1.35),
            color: colors.accent.withValues(alpha: 0.12),
            size: 700,
          ),
        ),
        child,
      ],
    );
  }
}

class _InkWash extends StatelessWidget {
  const _InkWash({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[color, color.withValues(alpha: 0)],
              stops: const <double>[0, 1],
            ),
          ),
        ),
      ),
    );
  }
}
