import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/errors/app_failure.dart';
import '../core/platform/files.dart';
import '../core/platform/sharing.dart';
import '../core/settings/workbench_preferences.dart';
import '../design/components/app_canvas.dart';
import '../design/components/app_page.dart';
import '../design/components/app_surface.dart';
import '../design/components/empty_state.dart';
import '../design/tokens/app_metrics.dart';
import '../features/about/presentation/about_page.dart';
import '../features/design_system/presentation/design_system_page.dart';
import '../features/editor/presentation/editor_page.dart';
import '../features/export/presentation/export_options.dart';
import '../features/import/presentation/batch_page.dart';
import '../features/import/presentation/import_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/settings/presentation/ai_settings_page.dart';
import '../features/settings/presentation/appearance_page.dart';
import '../features/settings/presentation/book_data_page.dart';
import '../features/settings/presentation/defaults_page.dart';
import '../features/settings/presentation/diagnostics_page.dart';
import '../features/settings/presentation/permissions_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/storage_page.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'shell/app_shell.dart';
import 'shell/window_caption.dart';
import 'workbench_providers.dart';

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
            // Tabs are preloaded so the first switch never pays the build cost
            // of a page that has never been laid out (fonts, layout, painters).
            preload: true,
            routes: <RouteBase>[
              GoRoute(
                path: '/library',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _tabPage(const LibraryPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: <RouteBase>[
              GoRoute(
                path: '/import',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _tabPage(const ImportPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            preload: true,
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                pageBuilder: (BuildContext context, GoRouterState state) =>
                    _tabPage(const SettingsPage()),
                // Settings sections are nested in this branch so the sidebar
                // stays visible while reading them; they used to be root-level
                // pages with the shell hidden, which left wide empty margins.
                routes: <RouteBase>[
                  GoRoute(
                    path: 'appearance',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const AppearancePage()),
                  ),
                  GoRoute(
                    path: 'ai',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const AiSettingsPage()),
                  ),
                  GoRoute(
                    path: 'defaults',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const DefaultsPage()),
                  ),
                  GoRoute(
                    path: 'storage',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const StoragePage()),
                  ),
                  GoRoute(
                    path: 'diagnostics',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const DiagnosticsPage()),
                  ),
                  GoRoute(
                    path: 'permissions',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const PermissionsPage()),
                  ),
                  GoRoute(
                    path: 'about',
                    pageBuilder: (BuildContext context, GoRouterState state) =>
                        _shellPage(const AboutPage(showBackButton: true)),
                  ),
                ],
              ),
            ],
          ),
          // The About page has no tab of its own: it lives under
          // /settings/about, which keeps the sidebar down to three entries.
        ],
      ),
      GoRoute(
        path: '/books/:bookId',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (BuildContext context, GoRouterState state) => _fadePage(
          EditorPage(
            bookId: state.pathParameters['bookId']!,
            onShare: (String bookId) async {
              final store = ref.read(settingsStoreProvider);
              final defaults = await WorkbenchPreferences.read(store);
              final dialogContext = _rootNavigatorKey.currentContext;
              if (dialogContext == null || !dialogContext.mounted) return;
              final format = await chooseExportFormat(
                dialogContext,
                initialFormat: defaults.exportFormat,
                forSharing: true,
              );
              if (format == null) return;
              final outcome = await ref
                  .read(exportServiceProvider)
                  .withPreparedExport<ShareOutcome>(
                    bookId,
                    format: format,
                    submit: NativeSharingService().sharePreparedFile,
                  );
              if (outcome case ShareFailed(:final message)) {
                throw ExportFailure(message);
              }
              if (dialogContext.mounted && outcome is SharePanelOpened) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(dialogContext).workbenchSharingOpened,
                    ),
                  ),
                );
              }
            },
            onExport: (String bookId) async {
              final store = ref.read(settingsStoreProvider);
              final defaults = await WorkbenchPreferences.read(store);
              final dialogContext = _rootNavigatorKey.currentContext;
              if (dialogContext == null || !dialogContext.mounted) {
                return const SaveCancelled();
              }
              final format = await chooseExportFormat(
                dialogContext,
                initialFormat: defaults.exportFormat,
              );
              if (format == null) return const SaveCancelled();
              await WorkbenchPreferences(
                layout: defaults.layout,
                exportFormat: format,
              ).write(store);
              return ref
                  .read(exportServiceProvider)
                  .exportBook(bookId, format: format);
            },
          ),
        ),
      ),
      GoRoute(
        path: '/batch',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(BatchPage(service: ref.read(batchServiceProvider))),
      ),
      GoRoute(
        path: '/data',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => _fadePage(const BookDataPage()),
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

/// Tab switches are instant. A cross-fade here costs a full repaint per frame,
/// which reads as a hitch on the very first switch. Tabs are not a place for
/// choreography.
NoTransitionPage<void> _tabPage(Widget page) =>
    NoTransitionPage<void>(child: AppSurface(child: page));

/// Pushes a page inside the current shell branch: the sidebar and bottom bar
/// stay put, so settings sections read as part of the app instead of taking the
/// whole window and leaving empty margins on both sides.
CustomTransitionPage<void> _shellPage(Widget page) {
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
          return AppCanvas(
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.012),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            ),
          );
        },
  );
}

/// Short cross-fade with a 1% rise for pushed pages (e.g. /design).
CustomTransitionPage<void> _fadePage(Widget page) {
  return CustomTransitionPage<void>(
    // Pushed pages replace the shell, so they carry their own window caption;
    // otherwise the frameless window could not be dragged or closed there.
    // The invisible hit surface is part of the page: without it a click on a
    // gap around the caption reaches the route's non-dismissible ModalBarrier,
    // which plays the Windows alert sound.
    child: ColoredBox(
      color: Colors.transparent,
      child: Column(
        children: <Widget>[
          const WindowCaption(),
          Expanded(child: AppSurface(child: page)),
        ],
      ),
    ),
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
          // The outgoing route remains painted while a route animates. Keep
          // an opaque, stationary canvas above it so transparent page margins
          // never reveal the previous page's text or navigation.
          return AppCanvas(
            child: FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.012),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
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
