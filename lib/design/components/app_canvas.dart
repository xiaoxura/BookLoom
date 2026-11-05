import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_colors.dart';

/// A quiet, neutral canvas with cool washes behind the floating chrome.
///
/// Washes follow the viewport instead of shrinking fixed-size circles into it.
/// The reading area stays calm while the sidebar and bottom bar pick up enough
/// variation to make their translucent material visible.
class AppCanvas extends StatelessWidget {
  const AppCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(painter: _CanvasPainter(context.colors)),
          ),
        ),
        child,
      ],
    );
  }
}

class _CanvasPainter extends CustomPainter {
  const _CanvasPainter(this.colors);

  final AppColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.canvasAlt, colors.canvas],
        ).createShader(bounds),
    );

    // Keep the strongest color near the navigation rather than across text.
    _wash(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 0.03, size.height * 0.30),
        width: size.width * 0.94,
        height: size.height * 1.35,
      ),
      colors.canvasMist,
      0.60,
    );
    _wash(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 0.23, size.height * 1.03),
        width: size.width * 1.06,
        height: size.height * 0.90,
      ),
      colors.canvasBloom,
      0.70,
    );
    _wash(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 1.02, size.height * 0.03),
        width: size.width * 0.82,
        height: size.height * 1.10,
      ),
      colors.canvasMist,
      0.30,
    );
  }

  void _wash(Canvas canvas, Rect bounds, Color color, double opacity) {
    const Rect unit = Rect.fromLTRB(-1, -1, 1, 1);
    canvas.save();
    canvas.translate(bounds.center.dx, bounds.center.dy);
    canvas.scale(bounds.width / 2, bounds.height / 2);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: opacity),
            color.withValues(alpha: opacity * 0.55),
            color.withValues(alpha: 0),
          ],
          stops: const <double>[0, 0.42, 1],
        ).createShader(unit),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CanvasPainter oldDelegate) =>
      oldDelegate.colors != colors;
}
