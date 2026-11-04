import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design/components/app_page.dart';
import '../design/components/app_surface.dart';
import '../design/components/empty_state.dart';
import '../design/tokens/app_metrics.dart';
import '../features/design_system/presentation/design_system_page.dart';
import '../features/import/presentation/import_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../l10n/app_localizations.dart';
import 'shell/app_shell.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/library',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) => AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/library',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadePage(const LibraryPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/import',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadePage(const ImportPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _fadePage(const SettingsPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/design',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _fadePage(const DesignSystemPage()),
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        const NotFoundPage(),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Short cross-fade with a 1% rise: enough to signal navigation, never showy.
CustomTransitionPage<void> _fadePage(Widget page) {
  return CustomTransitionPage<void>(
    child: AppSurface(child: page),
    transitionDuration: AppMotion.page,
    reverseTransitionDuration: AppMotion.page,
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final Animation<double> curved = CurvedAnimation(
            parent: animation,
            curve: AppMotion.enter,
            reverseCurve: AppMotion.exit,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.012),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
  );
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppPage(
      title: l10n.notFoundTitle,
      child: EmptyState(
        illustration: const Icon(Icons.explore_off_outlined, size: 40),
        title: l10n.notFoundTitle,
        message: l10n.notFoundBack,
        actions: <Widget>[
          FilledButton(
            onPressed: () => context.go('/library'),
            child: Text(l10n.navLibrary),
          ),
        ],
      ),
    );
  }
}
