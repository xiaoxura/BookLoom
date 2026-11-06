import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../tokens/app_metrics.dart';

/// Standard page frame: eyebrow + serif title + subtitle + actions, then a
/// scrollable body. The body scrolls at the page's outer edge while its content
/// stays in a readable measure, so the scrollbar never hugs the cards.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    this.title,
    this.subtitle,
    this.eyebrow,
    this.actions = const <Widget>[],
    required this.child,
    this.scrollable = true,
    this.leading,
  });

  /// Page heading. When null (and no [actions] or [leading] are given) the page
  /// renders only its content — menu pages rely on the sidebar for context.
  final String? title;
  final String? subtitle;
  final String? eyebrow;
  final List<Widget> actions;
  final Widget child;
  final bool scrollable;

  /// Optional control rendered before the title (e.g. a back button on pages
  /// pushed above the shell).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 720;
        // A page with only a leading control (the About page's hero already
        // carries its own heading) gets a slim toolbar instead of a full header
        // row followed by the usual 24px gap, which used to leave a dead band
        // of empty space at the top.
        final bool leadingOnly =
            leading != null &&
            title == null &&
            subtitle == null &&
            eyebrow == null &&
            actions.isEmpty;
        final double horizontal = compact ? 20 : AppLayout.pagePadding;
        final double top = leadingOnly ? AppSpacing.md : (compact ? 20 : 28);

        final List<Widget> header = <Widget>[
          if (leadingOnly) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 40, child: leading),
            ),
            const SizedBox(height: AppSpacing.xs),
          ] else if (title != null ||
              subtitle != null ||
              eyebrow != null ||
              actions.isNotEmpty ||
              leading != null) ...<Widget>[
            _PageHeader(
              eyebrow: eyebrow,
              title: title,
              subtitle: subtitle,
              actions: actions,
              compact: compact,
              leading: leading,
            ),
            SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
          ],
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (header.isNotEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 0),
                child: _measure(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: header,
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                // A page without a header keeps its top inset here instead, so
                // the body still starts below the floating window caption.
                padding: EdgeInsets.only(top: header.isEmpty ? top : 0),
                child: scrollable
                    // The scroll view spans the whole page, not the narrow
                    // content column, so the scrollbar rides the outer page
                    // edge instead of hugging the cards.
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: horizontal),
                          child: _measure(child: child),
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontal),
                        child: _measure(child: child, fillHeight: true),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Centres page content in the readable measure.
  ///
  /// The child is stretched to the resulting width (and, for non-scrolling
  /// pages, to the body height) so pages see the same content constraints as
  /// they did when the scroll view itself was width-limited.
  Widget _measure({required Widget child, bool fillHeight = false}) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
        child: SizedBox(
          width: double.infinity,
          height: fillHeight ? double.infinity : null,
          child: child,
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.compact,
    this.leading,
  });

  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final bool compact;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null) ...<Widget>[
          Text(
            eyebrow!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.accent,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 2),
        ],
        if (title != null)
          Text(
            title!,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontSize: compact ? 24 : 27,
            ),
          ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
        ],
      ],
    );

    // A back/leading control sits beside the title on every size.
    final Widget headingWithLeading = leading == null
        ? heading
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: AppSpacing.md),
                child: leading,
              ),
              Expanded(child: heading),
            ],
          );

    if (actions.isEmpty) return headingWithLeading;

    final Widget actionRow = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: actions,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          headingWithLeading,
          const SizedBox(height: AppSpacing.md),
          actionRow,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: headingWithLeading),
        const SizedBox(width: AppSpacing.lg),
        actionRow,
      ],
    );
  }
}
