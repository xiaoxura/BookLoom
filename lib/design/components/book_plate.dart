import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';
import '../tokens/app_typography.dart';

/// A quiet stand-in for a book cover: paper gradient, hairline border, spine.
/// Used by the empty shelf now and by cover-less books later.
class BookPlate extends StatelessWidget {
  const BookPlate({
    super.key,
    this.glyph = '书',
    this.width = 118,
    this.showShadow = true,
  });

  final String glyph;
  final double width;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final double height = width * 1.5;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.surfaceRaised,
            Color.lerp(colors.surfaceRaised, colors.canvas, 0.55)!,
          ],
        ),
        border: Border.all(color: colors.hairline),
        boxShadow: showShadow
            ? <BoxShadow>[
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.14),
                  blurRadius: 28,
                  spreadRadius: -10,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: <Widget>[
          // Spine: a soft vertical band on the left edge.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.xs),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    colors.accent.withValues(alpha: 0.16),
                    colors.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 8.5,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: colors.hairline),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                glyph,
                style: TextStyle(
                  fontFamily: AppTypography.serif,
                  fontFamilyFallback: AppTypography.serifFallback,
                  fontSize: width * 0.34,
                  height: 1,
                  fontWeight: FontWeight.w500,
                  color: colors.ink.withValues(alpha: 0.82),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
