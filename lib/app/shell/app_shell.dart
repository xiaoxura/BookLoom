import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/app_mark.dart';
import '../../design/components/paper_surface.dart';
import '../../design/theme/app_tokens.dart';
import '../../design/tokens/app_metrics.dart';
import '../../design/tokens/motion_spring.dart';
import '../../l10n/app_localizations.dart';
import '../window/window_controls.dart';
import 'window_caption.dart';

/// Lets widget tests exercise the phone shell without an Android device.
@visibleForTesting
bool debugForceMobileShell = false;

bool get _mobileShell =>
    debugForceMobileShell ||
    (!kIsWeb && (Platform.isAndroid || Platform.isIOS));

/// Floating chrome around the routed pages.
///
/// Desktop keeps the rail at every window width: shrinking the window narrows
/// the page, it does not move navigation to the bottom. The rail collapses to
/// its icon form on its own when the window gets tight and expands again when
/// there is room; only phones use the bottom bar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Manual override of the auto-collapse; `null` means "follow the width".
  /// Cleared whenever the window crosses the auto thresholds so the rail never
  /// ends up stuck in a state the window cannot show.
  bool? _manualCollapsed;
  bool _autoCollapsed = false;

  bool _autoFor(double width) {
    // Hysteresis: a razorthin window keeps its current state inside the band.
    if (_autoCollapsed) {
      return width < AppLayout.railAutoExpandWidth;
    }
    return width < AppLayout.railAutoCollapseWidth;
  }

  void _syncAuto(bool autoCollapsed) {
    if (autoCollapsed == _autoCollapsed) return;
    _autoCollapsed = autoCollapsed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _manualCollapsed = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final StatefulNavigationShell navigationShell = widget.navigationShell;
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<_Destination> destinations = <_Destination>[
      _Destination(
        icon: Icons.auto_stories_outlined,
        selectedIcon: Icons.auto_stories,
        label: l10n.navLibrary,
      ),
      _Destination(
        icon: Icons.library_add_outlined,
        selectedIcon: Icons.library_add,
        label: l10n.navImport,
      ),
      _Destination(
        icon: Icons.tune_outlined,
        selectedIcon: Icons.tune,
        label: l10n.navSettings,
      ),
    ];

    void select(int index) => navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );

    // The shell route needs the same invisible hit surface as a page: without
    // it, a click on the 16px gutter falls through to the route's colourless,
    // non-dismissible ModalBarrier, which answers with the Windows alert sound.
    return ColoredBox(
      color: Colors.transparent,
      child: DesktopWindowFrame(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (_mobileShell) {
              return Column(
                children: <Widget>[
                  const WindowCaption(),
                  Expanded(child: navigationShell),
                  _BottomBar(
                    destinations: destinations.take(3).toList(),
                    currentIndex: navigationShell.currentIndex,
                    onSelect: select,
                  ),
                ],
              );
            }
            final bool autoCollapsed = _autoFor(constraints.maxWidth);
            _syncAuto(autoCollapsed);
            final bool collapsed = _manualCollapsed ?? autoCollapsed;
            return Padding(
              padding: const EdgeInsets.all(AppLayout.shellGutter),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Sidebar(
                    destinations: destinations,
                    currentIndex: navigationShell.currentIndex,
                    onSelect: select,
                    collapsed: collapsed,
                    onToggle: () =>
                        setState(() => _manualCollapsed = !collapsed),
                  ),
                  const SizedBox(width: AppLayout.shellGutter),
                  // The caption sits above the page column only, so the sidebar
                  // keeps the full window height and the top-left corner is not
                  // an empty band.
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        const WindowCaption(),
                        Expanded(child: navigationShell),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Destinations above the divider; settings and about live below it.
const int _primaryCount = 2;

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
    required this.collapsed,
    required this.onToggle,
  });

  final List<_Destination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AnimatedContainer(
      duration: AppMotion.base,
      curve: AppMotion.emphasise,
      width: collapsed
          ? AppLayout.sidebarCollapsedWidth
          : AppLayout.sidebarWidth,
      child: PaperSurface(
        radius: AppRadius.xl,
        padding: EdgeInsets.fromLTRB(
          collapsed ? AppSpacing.sm : AppSpacing.md,
          AppSpacing.lg,
          collapsed ? AppSpacing.sm : AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 0 : AppSpacing.sm,
              ),
              // The rail width animates, so pick the header layout from the
              // live width rather than from `collapsed`: during the expand the
              // Row would otherwise be laid out inside a 72px pane and
              // overflow.
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints headerBox) {
                  final bool tight = headerBox.maxWidth < 150;
                  if (tight) {
                    // Collapsed rail: the mark doubles as the expand button, so
                    // the rail needs no separate toggle row.
                    return Center(child: _RailHeaderMark(onToggle: onToggle));
                  }
                  return Row(
                    children: <Widget>[
                      const AppMark(),
                      const SizedBox(width: AppSpacing.md - 2),
                      const Expanded(child: AppWordmark(compact: true)),
                      _RailToggle(collapsed: collapsed, onToggle: onToggle),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            for (int i = 0; i < destinations.length; i++) ...<Widget>[
              if (i == _primaryCount) ...<Widget>[
                const Spacer(),
                Divider(color: colors.hairline, height: 28),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs + 2),
                child: _NavTile(
                  destination: destinations[i],
                  selected: i == currentIndex,
                  compact: collapsed,
                  onTap: () => onSelect(i),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The brand mark in a collapsed rail doubles as the expand affordance: hovering
/// swaps the logo for the panel toggle in place, so the rail needs no extra
/// toggle row.
class _RailHeaderMark extends StatefulWidget {
  const _RailHeaderMark({required this.onToggle});

  final VoidCallback onToggle;

  @override
  State<_RailHeaderMark> createState() => _RailHeaderMarkState();
}

class _RailHeaderMarkState extends State<_RailHeaderMark> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final colors = context.colors;

    return Semantics(
      button: true,
      label: l10n.settingsExpandSidebar,
      child: Tooltip(
        message: l10n.settingsExpandSidebar,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            key: const Key('rail-expand'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggle,
            child: SizedBox(
              width: 40,
              height: 40,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: AppMotion.enter,
                switchOutCurve: AppMotion.exit,
                transitionBuilder: (Widget child, Animation<double> anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.86, end: 1).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: _hovered
                      ? _SidebarGlyph(
                          key: const ValueKey<String>('expand'),
                          expanded: false,
                          color: colors.inkMuted,
                        )
                      : const AppMark(key: ValueKey<String>('mark')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar-shaped toggle glyph, the same idea as FlClash's `Glyphs.sidebar`: a
/// panel with a divider that sits further in when the sidebar is expanded.
class _SidebarGlyph extends StatelessWidget {
  const _SidebarGlyph({super.key, required this.expanded, required this.color});

  final bool expanded;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(
        painter: _SidebarGlyphPainter(expanded: expanded, color: color),
      ),
    );
  }
}

class _SidebarGlyphPainter extends CustomPainter {
  _SidebarGlyphPainter({required this.expanded, required this.color});

  final bool expanded;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Authored on a 24x24 grid, scaled to the requested size.
    final double scale = size.width / 24;
    canvas.save();
    canvas.scale(scale);

    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(3, 4.5, 21, 19.5, const Radius.circular(3.5)),
      stroke,
    );

    final double divider = expanded ? 11.5 : 8.5;
    canvas.drawLine(
      const Offset(0, 4.5) + Offset(divider, 0),
      Offset(divider, 19.5),
      stroke,
    );
    for (final double y in const <double>[8.5, 11.0, 13.5]) {
      canvas.drawLine(Offset(5.5, y), Offset(divider - 2.2, y), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SidebarGlyphPainter oldDelegate) =>
      oldDelegate.expanded != expanded || oldDelegate.color != color;
}

/// Collapse/expand affordance in the rail header. One glyph with both
/// directions, like FlClash's sidebar toggle.
class _RailToggle extends StatelessWidget {
  const _RailToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Tooltip(
      message: collapsed
          ? l10n.settingsExpandSidebar
          : l10n.settingsCollapseSidebar,
      waitDuration: const Duration(milliseconds: 500),
      child: IconButton(
        key: const Key('rail-collapse'),
        onPressed: onToggle,
        iconSize: 18,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        color: context.colors.inkMuted,
        icon: _SidebarGlyph(
          expanded: !collapsed,
          color: context.colors.inkMuted,
        ),
      ),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  /// Icon-only rail mode; the label moves into a tooltip.
  final bool compact;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _pressed = false;

  /// The left rail marker springs in and out. The page still swaps in a single
  /// frame; only this marker animates, so nothing trails the content.
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 416),
  );
  late final Animation<double> _presenceCurve = CurvedAnimation(
    parent: _presence,
    curve: SpringCurve(presenceSpring, seconds: 0.416),
  );

  @override
  void initState() {
    super.initState();
    _presence.value = widget.selected ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _NavTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (widget.selected) {
        _presence.forward(from: 0);
      } else {
        _presence.reverse();
      }
    }
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final bool selected = widget.selected;
    final Color foreground = selected ? colors.accent : colors.inkSecondary;
    final BorderRadius shape = BorderRadius.circular(AppRadius.md);

    // Hover and press are the only animated states here. The selection
    // indicator still lands in the same frame as the page (see the comment
    // below), while hover fades in over `AppMotion.fast` and the tile dips
    // slightly under the finger, which reads as weight without delaying input.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints tileBounds) {
        // The rail width animates, so derive the compact layout from the live
        // width: mid-transition the label row would not fit.
        final bool compact = widget.compact || tileBounds.maxWidth < 90;
        const double side = 40;

        final Widget surface = Stack(
          children: <Widget>[
            if (!selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: AppMotion.fast,
                    curve: AppMotion.enter,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accentSoft.withValues(alpha: 0.55),
                        borderRadius: shape,
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedScale(
              scale: _pressed ? 0.985 : 1,
              duration: AppMotion.fast,
              curve: AppMotion.enter,
              // Collapsed rail items are squares: a 64x44 pill in a 72px rail
              // read as a stretched lozenge.
              child: Container(
                height: compact ? side : 44,
                width: compact ? side : null,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : AppSpacing.md - 2,
                ),
                decoration: BoxDecoration(
                  color: selected ? colors.accentSoft : Colors.transparent,
                  borderRadius: shape,
                ),
                child: compact
                    ? Center(
                        child: Tooltip(
                          message: widget.destination.label,
                          waitDuration: const Duration(milliseconds: 500),
                          child: Icon(
                            selected
                                ? widget.destination.selectedIcon
                                : widget.destination.icon,
                            size: 20,
                            color: foreground,
                          ),
                        ),
                      )
                    : Row(
                        children: <Widget>[
                          Icon(
                            selected
                                ? widget.destination.selectedIcon
                                : widget.destination.icon,
                            size: 20,
                            color: foreground,
                          ),
                          const SizedBox(width: AppSpacing.md - 2),
                          Expanded(
                            child: Text(
                              widget.destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontSize: 14.5,
                                color: foreground,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            // Rail marker: present in both states, like FlClash's rail. Painted
            // last so the selected fill cannot cover it; scales around its
            // centre so a thin bar overshoots without a layout pass.
            Positioned(
              left: compact ? 0 : 1,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _presenceCurve,
                    builder: (BuildContext context, Widget? child) {
                      final double v = _presenceCurve.value;
                      return Opacity(
                        opacity: v.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scaleY: v.clamp(0.0, 1.2),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: 3,
                      height: 22,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );

        return Semantics(
          selected: selected,
          button: true,
          child: Material(
            type: MaterialType.transparency,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: (bool value) =>
                    setState(() => _pressed = value),
                borderRadius: shape,
                // InkWell's own rectangular hover/highlight would paint a wide
                // bar behind a square rail tile; the layered overlay above is
                // the only hover feedback we want.
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                focusColor: Colors.transparent,
                child: compact
                    ? Center(
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: surface,
                        ),
                      )
                    : surface,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.destinations,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    final labelStyle = Theme.of(context).textTheme.labelSmall!;
    final labelSize = labelStyle.fontSize!;
    final extraLabelHeight =
        (MediaQuery.textScalerOf(context).scale(labelSize) - labelSize).clamp(
          0.0,
          double.infinity,
        ) *
        labelStyle.height!;
    final int index = currentIndex < destinations.length
        ? currentIndex
        : destinations.length - 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md + safeBottom,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.bottomBarMaxWidth,
          ),
          child: PaperSurface(
            radius: AppRadius.xl,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: SizedBox(
              key: const Key('bottom-navigation'),
              height: AppLayout.bottomBarHeight + extraLabelHeight,
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _BottomNavItem(
                        destination: destinations[i],
                        selected: i == index,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One bar item: icon over label, one tinted surface behind both (Material's
/// `NavigationBar` only tints the icon), and a spring rail under the label.
class _BottomNavItem extends StatefulWidget {
  const _BottomNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_BottomNavItem> createState() => _BottomNavItemState();
}

class _BottomNavItemState extends State<_BottomNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _presence = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 416),
  );
  late final Animation<double> _presenceCurve = CurvedAnimation(
    parent: _presence,
    curve: SpringCurve(presenceSpring, seconds: 0.416),
  );

  @override
  void initState() {
    super.initState();
    _presence.value = widget.selected ? 1 : 0;
  }

  @override
  void didUpdateWidget(covariant _BottomNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      if (widget.selected) {
        _presence.forward(from: 0);
      } else {
        _presence.reverse();
      }
    }
  }

  @override
  void dispose() {
    _presence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final bool selected = widget.selected;
    final Color foreground = selected ? colors.accent : colors.inkSecondary;
    final BorderRadius shape = BorderRadius.circular(AppRadius.md);

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: shape,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // The fill spans icon *and* label; the previous Material bar only
              // tinted the icon, which read as an unfinished selection. Inset a
              // little so the pill floats inside the panel instead of filling
              // the bar edge to edge.
              Positioned.fill(
                child: IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 3,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.accentSoft
                            : Colors.transparent,
                        borderRadius: shape,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xs,
                  horizontal: AppSpacing.xxs,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    Icon(
                      selected
                          ? widget.destination.selectedIcon
                          : widget.destination.icon,
                      size: AppLayout.bottomBarIconSize,
                      color: foreground,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Rail under the label, matching the desktop rail's spring.
                    SizedBox(
                      height: 3,
                      child: AnimatedBuilder(
                        animation: _presenceCurve,
                        builder: (BuildContext context, Widget? child) {
                          final double v = _presenceCurve.value;
                          return Opacity(
                            opacity: v.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scaleX: v.clamp(0.0, 1.2),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          width: 18,
                          height: 3,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
