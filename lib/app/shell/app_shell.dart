import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design/components/app_mark.dart';
import '../../design/components/glass_surface.dart';
import '../../design/theme/app_tokens.dart';
import '../../design/tokens/app_metrics.dart';
import '../../l10n/app_localizations.dart';
import '../window/window_controls.dart';
import 'window_caption.dart';

/// Floating chrome around the routed pages: a glass sidebar on desktop and a
/// glass navigation bar on narrow screens.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      _Destination(
        icon: Icons.info_outline,
        selectedIcon: Icons.info_outline,
        label: l10n.navAbout,
      ),
    ];

    void select(int index) => navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );

    return DesktopWindowFrame(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= AppLayout.railBreakpoint;
          if (!wide) {
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
          return Padding(
            padding: const EdgeInsets.all(AppLayout.shellGutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Sidebar(
                  destinations: destinations,
                  currentIndex: navigationShell.currentIndex,
                  onSelect: select,
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
  });

  final List<_Destination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      width: AppLayout.sidebarWidth,
      child: GlassSurface(
        radius: AppRadius.xl,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: _Brand(),
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

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        AppMark(),
        SizedBox(width: AppSpacing.md - 2),
        Expanded(child: AppWordmark(compact: true)),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;
    final Color foreground = selected ? colors.accent : colors.inkSecondary;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          // No cross-fade here: the page swaps in a single frame, so the
          // indicator must land in the same frame. A 120ms fade left the pill
          // trailing behind the content and read as a flicker.
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md - 2),
            decoration: BoxDecoration(
              color: selected ? colors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: foreground,
                ),
                const SizedBox(width: AppSpacing.md - 2),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 14.5,
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md + safeBottom,
      ),
      child: GlassSurface(
        radius: AppRadius.xl,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          child: NavigationBar(
            selectedIndex: currentIndex < destinations.length
                ? currentIndex
                : destinations.length - 1,
            onDestinationSelected: onSelect,
            destinations: <Widget>[
              for (final _Destination destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                  tooltip: destination.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
