import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/rules.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/import/application/import_service.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Explicitly prepares a TXT source parse, then asks before replacing the
/// current chapter tree. The parsed result never enters the library as a book.
class ReparsePanel extends StatefulWidget {
  const ReparsePanel({
    super.key,
    required this.session,
    required this.service,
    required this.files,
  });

  final EditorSession session;
  final ImportService service;
  final FileService files;

  @override
  State<ReparsePanel> createState() => _ReparsePanelState();
}

class _ReparsePanelState extends State<ReparsePanel> {
  late String _encoding;
  late bool _filterAds;
  late String _rulePreset;
  late final TextEditingController _customRule;
  PickedInput? _replacementInput;
  PreparedImport? _prepared;
  Completer<void>? _prepareStopped;
  int? _preparedAtSeq;
  bool _busy = false;
  bool _applied = false;
  double? _progress;
  String? _stage;
  String? _error;

  @override
  void initState() {
    super.initState();
    final options = widget.session.book!.parseOptions;
    _encoding =
        const {
          'auto',
          'utf-8',
          'gb18030',
          'big5',
          'utf-16le',
          'utf-16be',
        }.contains(options.encoding)
        ? options.encoding
        : 'auto';
    _filterAds = options.filterAds;
    _rulePreset = [...rulePresetIds, 'custom'].contains(options.rulePreset)
        ? options.rulePreset
        : 'auto';
    _customRule = TextEditingController(
      text: options.ruleSpec == null ? '' : jsonEncode(options.ruleSpec),
    );
  }

  @override
  void dispose() {
    final preparing = _prepareStopped?.future;
    if (preparing != null) widget.service.cancel();
    final prepared = _prepared;
    final replacement = _replacementInput;
    _prepared = null;
    _replacementInput = null;
    unawaited(_disposeResources(preparing, prepared, replacement));
    _customRule.dispose();
    super.dispose();
  }

  Future<void> _releasePicked(PickedInput? input) async {
    if (input == null) return;
    try {
      await input.release();
    } finally {
      await widget.files.clearTemporaryFiles();
    }
  }

  Future<void> _disposeResources(
    Future<void>? preparing,
    PreparedImport? prepared,
    PickedInput? replacement,
  ) async {
    try {
      // Cancellation may arrive while the picker stream is being copied.
      // Its lease remains valid until the prepare Future has fully unwound.
      if (preparing != null) await preparing;
      if (prepared != null) await widget.service.discard(prepared);
    } on Object {
      // Disposing the panel cannot report errors through its former context.
    } finally {
      try {
        await _releasePicked(replacement);
      } on Object {
        // The picker owns its cache; no live panel remains to show this error.
      }
    }
  }

  Future<void> _releaseReplacement() async {
    final input = _replacementInput;
    _replacementInput = null;
    await _releasePicked(input);
  }

  String _failure(Object error) {
    if (error is RuleValidationException) return error.toString();
    if (error is FormatException) {
      return AppLocalizations.of(context).editorWorkbenchReparseInvalidRuleUtf8;
    }
    if (error is AppFailure) {
      return [error.message, if (error.hint != null) error.hint!].join(' ');
    }
    return AppLocalizations.of(context).editorWorkbenchReparseFailed;
  }

  Future<void> _discardPreview() async {
    final previous = _prepared;
    _prepared = null;
    _preparedAtSeq = null;
    if (previous != null) await widget.service.discard(previous);
  }

  void _changeOptions(VoidCallback update) {
    setState(() {
      update();
      _error = null;
    });
    unawaited(_discardPreview().catchError((Object _) {}));
  }

  ParseOptions _options() {
    Map<String, Object?>? spec;
    if (_rulePreset == 'custom') {
      spec = RuleSpec.fromJsonString(_customRule.text).toMap();
    }
    return widget.session.book!.parseOptions.copyWith(
      encoding: _encoding,
      filterAds: _filterAds,
      rulePreset: _rulePreset,
      ruleSpec: spec,
      clearRuleSpec: spec == null,
    );
  }

  Future<void> _pickOriginal() async {
    PickedInput? selected;
    try {
      final files = await widget.files.pickImports(
        multiple: false,
        extensions: const ['txt'],
      );
      if (files.isEmpty) return;
      selected = files.single;
      if (!mounted) return;
      await _discardPreview();
      if (!mounted) return;
      final previous = _replacementInput;
      setState(() {
        _replacementInput = selected;
        _error = null;
      });
      selected = null;
      await _releasePicked(previous);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      try {
        await _releasePicked(selected);
      } on Object {
        if (mounted) {
          setState(
            () =>
                _error = AppLocalizations.of(context)
                    .editorWorkbenchOriginalCacheFailed,
          );
        }
      }
    }
  }

  Future<void> _forgetOriginal() async {
    if (_busy) return;
    try {
      await _discardPreview();
      await _releaseReplacement();
      if (mounted) setState(() => _error = null);
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    }
  }

  Future<void> _importRule() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    PickedInput? selected;
    try {
      final files = await widget.files.pickImports(
        multiple: false,
        extensions: const ['json'],
      );
      if (files.isEmpty) return;
      selected = files.single;
      final bytes = <int>[];
      await for (final chunk in selected.openRead()) {
        if (bytes.length + chunk.length > maxRuleJsonBytes) {
          throw RuleValidationException(r'$', l10n.editorWorkbenchRuleTooLarge);
        }
        bytes.addAll(chunk);
      }
      final rule = RuleSpec.fromJsonString(utf8.decode(bytes));
      if (!mounted) return;
      _customRule.text = rule.toJsonString();
      _changeOptions(() => _rulePreset = 'custom');
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      try {
        await _releasePicked(selected);
      } on Object {
        if (mounted) {
          setState(
            () =>
                _error = AppLocalizations.of(context)
                    .editorWorkbenchRuleCacheFailed,
          );
        }
      }
    }
  }

  Future<void> _exportRule() async {
    if (_busy) return;
    Directory? temporary;
    try {
      final rule = _rulePreset == 'custom'
          ? RuleSpec.fromJsonString(_customRule.text)
          : getRulePreset(_rulePreset)!;
      temporary = await Directory.systemTemp.createTemp('bookloom-rule-');
      final file = File('${temporary.path}/rule.json');
      await file.writeAsString(rule.toJsonString(), encoding: utf8);
      final outcome = await widget.files.savePreparedFile(
        file,
        suggestedName: 'bookloom-rule.json',
        mimeType: 'application/json',
      );
      if (mounted && outcome is SaveSaved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).editorWorkbenchRuleExported,
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  Future<void> _prepare() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    late final ParseOptions options;
    try {
      options = _options();
    } on Object catch (error) {
      setState(() => _error = _failure(error));
      return;
    }
    final stopped = Completer<void>();
    _prepareStopped = stopped;
    setState(() {
      _busy = true;
      _applied = false;
      _error = null;
      _progress = null;
      _stage = null;
    });
    try {
      await _discardPreview();
      if (!mounted) return;
      await widget.session.flush();
      if (!mounted) return;
      final seq = widget.session.saveSeq;
      final prepared = await widget.service.prepareReparse(
        widget.session.book!.id,
        options: options,
        replacementInput: _replacementInput,
        onProgress: (JobProgress progress) {
          if (mounted) {
            setState(() {
              _progress = progress.fraction;
              _stage = progress.stage;
            });
          }
        },
      );
      if (!mounted) {
        await widget.service.discard(prepared);
        return;
      }
      if (widget.session.saveSeq != seq) {
        await widget.service.discard(prepared);
        throw ValidationFailure(l10n.editorWorkbenchReparseChanged);
      }
      setState(() {
        _prepared = prepared;
        _preparedAtSeq = seq;
      });
    } on TaskCancelled {
      // Keep current chapters and selected source available for another try.
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      _prepareStopped = null;
      stopped.complete();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final prepared = _prepared;
    final seq = _preparedAtSeq;
    if (prepared == null || seq == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.editorWorkbenchReparseConfirmTitle),
        content: Text(
          l10n.editorWorkbenchReparseConfirmBody(
            prepared.result.chapters.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(l10n.editorWorkbenchReparseConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      widget.session.replaceAllChapters(
        prepared.result.chapters,
        prepared.options,
        expectedSaveSeq: seq,
      );
      _applied = true;
      await widget.session.flush();
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (_applied) {
        try {
          await _discardPreview();
        } on Object {
          if (mounted && _error == null) {
            setState(
              () =>
                  _error = AppLocalizations.of(context)
                      .editorWorkbenchPreparedCacheFailed,
            );
          }
        }
        try {
          await _releaseReplacement();
        } on Object {
          if (mounted && _error == null) {
            setState(
              () =>
                  _error = AppLocalizations.of(context)
                      .editorWorkbenchOriginalCacheFailed,
            );
          }
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prepared = _prepared;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        Text(
          l10n.editorWorkbenchReparse,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(l10n.editorWorkbenchReparseIntro),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickOriginal,
          icon: const Icon(Icons.file_open_outlined),
          label: Text(
            _replacementInput?.name ?? l10n.editorWorkbenchSelectOriginal,
          ),
        ),
        if (_replacementInput != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _forgetOriginal,
              child: Text(l10n.editorWorkbenchForgetOriginal),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _encoding,
          decoration: InputDecoration(
            labelText: l10n.editorWorkbenchSourceEncoding,
          ),
          items: [
            DropdownMenuItem(
              value: 'auto',
              child: Text(l10n.editorWorkbenchAutoDetect),
            ),
            DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
            DropdownMenuItem(value: 'gb18030', child: Text('GB18030 / GBK')),
            DropdownMenuItem(value: 'big5', child: Text('Big5')),
            DropdownMenuItem(value: 'utf-16le', child: Text('UTF-16 LE')),
            DropdownMenuItem(value: 'utf-16be', child: Text('UTF-16 BE')),
          ],
          onChanged: _busy
              ? null
              : (value) => _changeOptions(() => _encoding = value ?? 'auto'),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.editorWorkbenchFilterAds),
          value: _filterAds,
          onChanged: _busy
              ? null
              : (value) => _changeOptions(() => _filterAds = value),
        ),
        DropdownButtonFormField<String>(
          initialValue: _rulePreset,
          decoration: InputDecoration(labelText: l10n.editorWorkbenchRules),
          items: [
            for (final id in [...rulePresetIds, 'custom'])
              DropdownMenuItem(
                value: id,
                child: Text(switch (id) {
                  'auto' => l10n.importEncodingAuto,
                  'ixdzs' => l10n.editorWorkbenchRulePresetIxdzs,
                  'biquge' => l10n.editorWorkbenchReparsePresetBiquge,
                  'numbered' => l10n.editorWorkbenchRulePresetNumbered,
                  'bare-number' => l10n.editorWorkbenchReparsePresetBareNumber,
                  'english' => l10n.editorWorkbenchReparsePresetEnglish,
                  _ => l10n.editorWorkbenchCustomRules,
                }),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => _changeOptions(() => _rulePreset = value ?? 'auto'),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _importRule,
              icon: const Icon(Icons.file_open_outlined),
              label: Text(l10n.editorWorkbenchImportRulesJson),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _exportRule,
              icon: const Icon(Icons.save_alt_outlined),
              label: Text(l10n.editorWorkbenchExportRulesJson),
            ),
          ],
        ),
        if (_rulePreset == 'custom') ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _customRule,
            readOnly: _busy,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: l10n.editorWorkbenchRulesJsonFields,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _changeOptions(() {}),
          ),
          Text(l10n.editorWorkbenchRulesOnlyReparse),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.tonal(
          onPressed: _busy ? null : _prepare,
          child: Text(l10n.editorWorkbenchPrepareReparse),
        ),
        if (_busy) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: _progress),
          Text(_stage ?? l10n.editorWorkbenchPreparing),
          TextButton(
            onPressed: widget.service.cancel,
            child: Text(l10n.editorWorkbenchCancelTask),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_applied)
          ListTile(
            title: Text(
              widget.session.dirty
                  ? l10n.editorWorkbenchReparseAppliedUnsaved
                  : l10n.editorWorkbenchReparseAppliedSaved,
            ),
          ),
        if (prepared != null) ...[
          const Divider(height: AppSpacing.xxl),
          Text(
            l10n.editorWorkbenchReparsePreview,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ListTile(
            title: Text(
              l10n.editorWorkbenchReparseStats(
                prepared.result.chapters.length,
                prepared.wordCount,
              ),
            ),
            subtitle: Text(
              prepared.result.actualEncoding == null
                  ? l10n.editorWorkbenchSourceEncodingSelected
                  : l10n.editorWorkbenchSourceEncodingActual(
                      prepared.result.actualEncoding!,
                    ),
            ),
          ),
          for (final warning in prepared.result.warnings.take(20))
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(warning.message),
            ),
          if (prepared.result.warnings.length > 20)
            ListTile(title: Text(l10n.editorWorkbenchReparseWarningsLimit)),
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: Text(l10n.editorWorkbenchReparseApply),
          ),
        ],
      ],
    );
  }
}
