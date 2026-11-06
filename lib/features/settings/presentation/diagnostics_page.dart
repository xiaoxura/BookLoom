import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_info.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_widgets.dart';

/// Live process footprint, so the reader can answer "why is it slow?" without a
/// profiler. Sampled once a second from `dart:io`; nothing leaves the device.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Timer? _timer;
  int _rss = 0;
  int _peak = 0;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sample() {
    int rss = 0;
    int peak = 0;
    try {
      rss = ProcessInfo.currentRss;
      peak = ProcessInfo.maxRss;
    } catch (_) {
      // Platforms without process stats simply report zero.
    }
    if (!mounted) return;
    setState(() {
      _rss = rss;
      _peak = peak;
    });
  }

  String _mb(int bytes) =>
      bytes <= 0 ? '—' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String get _uptime {
    // Counted from the process start, not from when this page was opened, so
    // leaving and re-entering the page does not reset it.
    final Duration elapsed = DateTime.now().difference(AppInfo.startedAt);
    final int minutes = elapsed.inMinutes;
    final int seconds = elapsed.inSeconds % 60;
    if (minutes >= 60) {
      return '${elapsed.inHours}h ${minutes % 60}m';
    }
    return minutes == 0 ? '${seconds}s' : '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool statsAvailable = _rss > 0;
    final int peak = _peak > _rss ? _peak : _rss;
    final String version = Platform.operatingSystemVersion
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final String osName = _prettyOs(Platform.operatingSystem);
    final String platform = version.toLowerCase().contains(
      osName.toLowerCase(),
    )
        ? version
        : '$osName · $version';

    return AppPage(
      title: l10n.settingsDiagnostics,
      leading: BackButton(onPressed: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SettingsSectionTitle(l10n.settingsDiagnostics),
          _StatGrid(
            children: <Widget>[
              _StatCard(
                icon: Icons.memory,
                label: l10n.settingsRuntimeMemory,
                value: statsAvailable
                    ? _mb(_rss)
                    : l10n.settingsRuntimeUnavailable,
              ),
              _StatCard(
                icon: Icons.trending_up,
                label: l10n.settingsRuntimePeak,
                value: statsAvailable
                    ? _mb(peak)
                    : l10n.settingsRuntimeUnavailable,
              ),
              _StatCard(
                icon: Icons.schedule,
                label: l10n.settingsRuntimeUptime,
                value: _uptime,
              ),
              _StatCard(
                icon: Icons.fingerprint,
                label: l10n.settingsRuntimePid,
                value: '$pid',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.settingsRuntimeRefresh,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.colors.inkMuted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _StatCard(
            icon: Icons.desktop_windows_outlined,
            label: l10n.settingsRuntimePlatform,
            value: platform,
            wide: true,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// `windows` reads better as `Windows`; the version string already carries the
  /// product name, so the card shows one line instead of repeating it.
  String _prettyOs(String os) {
    if (os == 'windows') return 'Windows';
    if (os == 'macos') return 'macOS';
    if (os.isEmpty) return os;
    return os[0].toUpperCase() + os.substring(1);
  }
}

/// Reflows stat cards: four across on a wide page, two on a narrow one, one on
/// a phone. Cards in the same row stretch to a common height so the row reads as
/// one band instead of four blocks of different heights.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int columns = width >= 860
            ? 4
            : width >= 520
            ? 2
            : 1;
        const double gap = AppSpacing.md;

        final List<Widget> rows = <Widget>[];
        for (int start = 0; start < children.length; start += columns) {
          final List<Widget> slice = children.sublist(
            start,
            (start + columns).clamp(0, children.length),
          );
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int column = 0; column < columns; column++) ...<Widget>[
                    if (column > 0) const SizedBox(width: gap),
                    Expanded(
                      child: column < slice.length
                          ? slice[column]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          children: <Widget>[
            for (int i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: gap),
              rows[i],
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.colors;

    final Widget card = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 15, color: colors.inkMuted),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: wide ? 3 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.ink,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    if (!wide) return card;
    return SizedBox(width: double.infinity, child: card);
  }
}

