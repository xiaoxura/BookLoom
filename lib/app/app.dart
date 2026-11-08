import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/appearance.dart';
import '../design/components/app_canvas.dart';
import '../design/components/app_notice_layout.dart';
import '../design/theme/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'providers.dart';
import 'router.dart';

/// Root widget: theme, locale, router and the paper canvas.
class BookloomApp extends ConsumerWidget {
  const BookloomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Appearance appearance = ref.watch(appearanceProvider);

    return MaterialApp.router(
      onGenerateTitle: (BuildContext context) =>
          AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(glass: appearance.glass),
      darkTheme: AppTheme.dark(glass: appearance.glass),
      themeMode: switch (appearance.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: ref.watch(routerProvider),
      localeResolutionCallback: _resolveLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: const AppScrollBehavior(),
      builder: (BuildContext context, Widget? child) => AppNoticeLayout(
        child: AppCanvas(child: child ?? const SizedBox.shrink()),
      ),
    );
  }

  /// Chinese wins whenever the system asks for Chinese; everything else falls
  /// back to Simplified Chinese for now (English is a later milestone).
  static Locale _resolveLocale(Locale? locale, Iterable<Locale> supported) {
    if (locale?.languageCode == 'zh') return const Locale('zh');
    if (locale?.languageCode == 'en') return const Locale('en');
    return const Locale('zh');
  }
}

/// Desktop-friendly scrolling: mouse drag works, and the overscroll glow is
/// disabled so the paper canvas never flashes a tinted edge.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

/// Shown when bootstrap fails before the router exists.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.failure});

  final Object failure;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: (BuildContext context, Widget? child) =>
          AppNoticeLayout(child: child ?? const SizedBox.shrink()),
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
      home: Builder(
        builder: (BuildContext context) {
          final AppLocalizations l10n = AppLocalizations.of(context);
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.sd_card_alert_outlined,
                        size: 34,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.bootstrapFailureTitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.bootstrapFailureBody,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
