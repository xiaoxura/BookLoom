import 'package:bookloom/core/platform/external_links.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Offline guidance. Official pages open only after the reader taps a link.
Future<void> showDeviceHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => const DeviceHelpSheet(),
);

class DeviceHelpSheet extends StatelessWidget {
  const DeviceHelpSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final double height = MediaQuery.sizeOf(context).height * 0.85;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          height: height,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.exportWorkbenchDeviceHelpTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.windowClose,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l10n.exportWorkbenchDeviceHelpIntro),
              const SizedBox(height: 12),
              for (final device in _devices(l10n))
                Card(
                  child: ExpansionTile(
                    title: Text(device.name),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(device.steps),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => ExternalLinks.open(device.officialUrl),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(l10n.exportWorkbenchOfficialInfoAction),
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

class _DeviceGuide {
  const _DeviceGuide(this.name, this.steps, this.officialUrl);

  final String name;
  final String steps;
  final String officialUrl;
}

List<_DeviceGuide> _devices(AppLocalizations l10n) => <_DeviceGuide>[
  _DeviceGuide(
    l10n.exportWorkbenchKindleName,
    l10n.exportWorkbenchKindleSteps,
    'https://www.amazon.com/sendtokindle',
  ),
  _DeviceGuide(
    l10n.exportWorkbenchKoboName,
    l10n.exportWorkbenchKoboSteps,
    'https://help.kobo.com/hc/en-us/articles/360024775093-Add-non-protected-PDF-and-ePub-files-to-your-Kobo-eReader-using-your-computer',
  ),
  _DeviceGuide(
    l10n.exportWorkbenchBooxName,
    l10n.exportWorkbenchBooxSteps,
    'https://shop.boox.com/blogs/news/booxdrop',
  ),
  _DeviceGuide(
    l10n.exportWorkbenchHanvonName,
    l10n.exportWorkbenchHanvonSteps,
    'https://www.hanvontouch.com/index.php-126.html?a=show&c=index&catid=74&id=21&m=content',
  ),
  _DeviceGuide(
    l10n.exportWorkbenchIreaderName,
    l10n.exportWorkbenchIreaderSteps,
    'https://www.ireader.com/',
  ),
];
