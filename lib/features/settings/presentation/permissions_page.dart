import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../app/workbench_providers.dart';
import '../../../core/platform/files.dart';
import '../../../core/platform/permission_access.dart';
import '../../../design/components/app_page.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';

class PermissionsPage extends ConsumerStatefulWidget {
  const PermissionsPage({super.key, this.access});

  final PermissionAccess? access;

  @override
  ConsumerState<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends ConsumerState<PermissionsPage>
    with WidgetsBindingObserver {
  late final PermissionAccess _access = widget.access ?? PermissionAccess();
  List<DirectoryAccessCheck>? _directories;
  PlatformPermissionReport? _system;
  bool _busy = false;
  bool _checkFailed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _checkFailed = false;
      _directories = null;
      _system = null;
    });
    final paths = ref.read(appPathsProvider);
    try {
      final (directories, system) = await (
        _access.checkDirectories(paths),
        _access.inspectSystemPermissions(),
      ).wait;
      if (mounted) {
        setState(() {
          _directories = directories;
          _system = system;
        });
      }
    } on Object {
      if (mounted) setState(() => _checkFailed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkRead() async {
    final l10n = AppLocalizations.of(context);
    final files = ref.read(fileServiceProvider);
    setState(() {
      _busy = true;
      _message = null;
    });
    var message = l10n.permissionsReadFailure;
    final inputs = <PickedInput>[];
    try {
      inputs.addAll(await files.pickImports(multiple: false));
      if (inputs.isEmpty) {
        message = l10n.permissionsCancelled;
      } else {
        // One stream event proves access without reading an entire large book.
        await inputs.first.openRead().take(1).drain<void>();
        message = l10n.permissionsReadSuccess;
      }
    } on Object {
      message = l10n.permissionsReadFailure;
    } finally {
      for (final input in inputs) {
        try {
          await input.release();
        } on Object {
          message = l10n.permissionsReadFailure;
        }
      }
      try {
        await files.clearTemporaryFiles();
      } on Object {
        message = l10n.permissionsReadFailure;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _message = message;
        });
      }
    }
  }

  Future<void> _checkSave() async {
    final l10n = AppLocalizations.of(context);
    final files = ref.read(fileServiceProvider);
    final cache = ref.read(appPathsProvider).cache;
    Directory? temporary;
    setState(() {
      _busy = true;
      _message = null;
    });
    var message = l10n.permissionsSaveFailure;
    try {
      temporary = await cache.createTemp('bookloom-access-save-');
      final file = File(p.join(temporary.path, 'access-check.txt'));
      await file.writeAsString('Bookloom file access check.\n');
      final result = await files.savePreparedFile(
        file,
        suggestedName: 'Bookloom-access-check.txt',
        mimeType: 'text/plain',
      );
      message = result is SaveSaved
          ? l10n.permissionsSaveSuccess
          : l10n.permissionsCancelled;
    } on Object {
      message = l10n.permissionsSaveFailure;
    } finally {
      try {
        await temporary?.delete(recursive: true);
      } on Object {
        message = l10n.permissionsSaveFailure;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _message = message;
        });
      }
    }
  }

  Future<void> _openSystemSettings() async {
    final failed = AppLocalizations.of(context).permissionsSettingsFailed;
    final opened = await _access.openSystemSettings();
    if (!opened && mounted) setState(() => _message = failed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final system = _system;
    final android = system?.android ?? Platform.isAndroid;
    return AppPage(
      title: l10n.settingsPermissions,
      leading: BackButton(onPressed: () => context.pop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.permissionsIntro),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.permissionsRefresh),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_checkFailed) Text(l10n.permissionsCheckFailed),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Semantics(liveRegion: true, child: Text(_message!)),
            ),
          const SizedBox(height: AppSpacing.lg),
          _AccessCard(
            title: l10n.permissionsStorageTitle,
            description: l10n.permissionsStorageHelp,
            children: [
              for (final check in _directories ?? <DirectoryAccessCheck>[])
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (check.target) {
                        AccessDirectory.support => l10n.permissionsSupport,
                        AccessDirectory.books => l10n.permissionsBooks,
                        AccessDirectory.cache => l10n.permissionsCache,
                      }, style: Theme.of(context).textTheme.titleSmall),
                      Wrap(
                        spacing: AppSpacing.lg,
                        children: [
                          Text(
                            check.readable
                                ? l10n.permissionsReadReady
                                : l10n.permissionsReadFailed,
                          ),
                          Text(
                            check.writable
                                ? l10n.permissionsWriteReady
                                : l10n.permissionsWriteFailed,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          _AccessCard(
            title: l10n.permissionsSystemTitle,
            description: !android
                ? l10n.permissionsDesktopSystem
                : system == null || !system.systemCheckAvailable
                ? l10n.permissionsSystemUnavailable
                : system.runtimePermissions.isEmpty &&
                      !system.declaresBroadStorage
                ? l10n.permissionsNoRuntime
                : l10n.permissionsRuntimePolicy,
            children: [
              if (system != null && system.systemCheckAvailable) ...[
                for (final permission in system.runtimePermissions)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${permission.label} · ${permission.granted ? l10n.permissionsGranted : l10n.permissionsNotGranted}',
                        ),
                        Text(
                          l10n.permissionsRuntimeNotRequired,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                if (system.declaresInternet)
                  Text(l10n.permissionsInternetDeclared),
                if (system.declaresBroadStorage)
                  Text(l10n.permissionsStorageDeclared),
              ],
              if (android)
                TextButton.icon(
                  onPressed: _busy ? null : _openSystemSettings,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(l10n.permissionsOpenSystemSettings),
                ),
            ],
          ),
          _AccessCard(
            title: l10n.permissionsImportTitle,
            description: android
                ? l10n.permissionsImportAndroid
                : l10n.permissionsImportDesktop,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _checkRead,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(l10n.permissionsReadAction),
              ),
            ],
          ),
          _AccessCard(
            title: l10n.permissionsExportTitle,
            description: android
                ? l10n.permissionsExportAndroid
                : l10n.permissionsExportDesktop,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _checkSave,
                icon: const Icon(Icons.save_outlined),
                label: Text(l10n.permissionsSaveAction),
              ),
            ],
          ),
          _AccessCard(
            title: l10n.permissionsShareTitle,
            description: android
                ? l10n.permissionsShareAndroid
                : l10n.permissionsShareDesktop,
          ),
          Text(l10n.permissionsScopeNote),
        ],
      ),
    );
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.title,
    this.description,
    this.children = const [],
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Material(
        color: context.colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: context.colors.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (description != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(description!),
              ],
              if (children.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                ...children,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
