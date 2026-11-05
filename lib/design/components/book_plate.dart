import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';

/// A small, layered book illustration for an empty shelf.
/// Drawn with theme colors so it stays crisp at every scale and brightness.
class BookPlate extends StatelessWidget {
  const BookPlate({super.key, this.width = 152, this.showShadow = true});

  final double width;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 1.16,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Positioned(
              left: width * 0.31,
              top: width * 0.14,
              width: width * 0.62,
              height: width * 0.88,
              child: Transform.rotate(
                angle: 0.10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: colors.hairline),
                  ),
                ),
              ),
            ),
            Positioned(
              left: width * 0.12,
              top: width * 0.04,
              width: width * 0.70,
              height: width,
              child: Transform.rotate(
                angle: -0.10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: colors.hairline),
                    boxShadow: showShadow
                        ? <BoxShadow>[
                            BoxShadow(
                              color: colors.shadow.withValues(alpha: 0.16),
                              blurRadius: 24,
                              spreadRadius: -6,
                              offset: const Offset(0, 12),
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        left: 8,
                        right: 4,
                        bottom: 4,
                        child: Container(height: 1, color: colors.hairline),
                      ),
                      Positioned.fill(
                        right: 3,
                        bottom: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              colors.accent,
                              colors.surface,
                              0.12,
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Stack(
                            children: <Widget>[
                              Positioned(
                                left: 0,
                                top: 0,
                                bottom: 0,
                                width: width * 0.075,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.shadow.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(AppRadius.sm),
                                    ),
                                    border: Border(
                                      right: BorderSide(
                                        color: colors.accentContrast.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: width * 0.10,
                                child: Icon(
                                  Icons.bookmark,
                                  size: width * 0.18,
                                  color: colors.canvasBloom,
                                ),
                              ),
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.only(left: width * 0.06),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.auto_stories_outlined,
                                        size: width * 0.25,
                                        color: colors.accentContrast,
                                      ),
                                      SizedBox(height: width * 0.09),
                                      Container(
                                        width: width * 0.19,
                                        height: 1,
                                        color: colors.accentContrast.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
