import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/parsing/rules.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/platform/job_cache.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Options apply to the next parse; invalid JSON never replaces valid rules.
class ParseOptionsFields extends StatefulWidget {
  const ParseOptionsFields({
    required this.options,
    required this.onChanged,
    required this.files,
    required this.cacheDirectory,
    this.isTxt = true,
    this.enabled = true,
    super.key,
  });
  final ParseOptions options;
  final ValueChanged<ParseOptions> onChanged;
  final FileService files;
  final Directory cacheDirectory;
  final bool isTxt;
  final bool enabled;

  @override
  State<ParseOptionsFields> createState() => _ParseOptionsFieldsState();
}

class _ParseOptionsFieldsState extends State<ParseOptionsFields> {
  String? _error;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = widget.options;
    final enabled = widget.enabled && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.isTxt) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('encoding-${options.encoding}'),
            initialValue: options.encoding,
            decoration: InputDecoration(
              labelText: l10n.editorWorkbenchOptionsFileEncoding,
            ),
            items: [
              DropdownMenuItem(
                value: 'auto',
                child: Text(l10n.editorWorkbenchOptionsAuto),
              ),
              for (final entry in const {
                'utf-8': 'UTF-8',
                'gb18030': 'GB18030 / GBK',
                'big5': 'Big5',
                'utf-16le': 'UTF-16 LE',
                'utf-16be': 'UTF-16 BE',
              }.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: enabled
                ? (value) => widget.onChanged(options.copyWith(encoding: value))
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('rule-${options.rulePreset}'),
            initialValue: options.rulePreset,
            decoration: InputDecoration(
              labelText: l10n.editorWorkbenchOptionsChapterRules,
            ),
            items: [
              for (final entry in {
                'auto': l10n.importEncodingAuto,
                'ixdzs': l10n.editorWorkbenchRulePresetIxdzs,
                'biquge': l10n.editorWorkbenchRulePresetBiquge,
                'numbered': l10n.editorWorkbenchRulePresetNumbered,
                'bare-number': l10n.editorWorkbenchRulePresetBareNumber,
                'english': l10n.editorWorkbenchRulePresetEnglish,
              }.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: enabled
                ? (value) =>
                      widget.onChanged(options.copyWith(rulePreset: value))
                : null,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.editorWorkbenchOptionsFilterAds),
            value: options.filterAds,
            onChanged: enabled
                ? (value) =>
                      widget.onChanged(options.copyWith(filterAds: value))
                : null,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: enabled ? _editRule : null,
                child: Text(l10n.editorWorkbenchOptionsEditRules),
              ),
              TextButton(
                onPressed: enabled ? _importRule : null,
                child: Text(l10n.editorWorkbenchOptionsImportRules),
              ),
              if (options.ruleSpec != null) ...[
                TextButton(
                  onPressed: enabled ? _exportRule : null,
                  child: Text(l10n.editorWorkbenchOptionsExportRules),
                ),
                TextButton(
                  onPressed: enabled
                      ? () => widget.onChanged(
                          options.copyWith(clearRuleSpec: true),
                        )
                      : null,
                  child: Text(l10n.editorWorkbenchOptionsRemoveRules),
                ),
              ],
            ],
          ),
          if (options.ruleSpec != null)
            Text(
              l10n.editorWorkbenchOptionsCurrentRules(
                RuleSpec.fromMap(options.ruleSpec).name,
              ),
            ),
          const SizedBox(height: 12),
        ],
        DropdownButtonFormField<ConvertMode>(
          key: ValueKey('convert-${options.convertMode.name}'),
          initialValue: options.convertMode,
          decoration: InputDecoration(
            labelText: l10n.editorWorkbenchOptionsConvertAtImport,
          ),
          items: [
            DropdownMenuItem(
              value: ConvertMode.none,
              child: Text(l10n.editorWorkbenchOptionsKeepOriginal),
            ),
            DropdownMenuItem(
              value: ConvertMode.simplified,
              child: Text(l10n.editorWorkbenchOptionsToSimplified),
            ),
            DropdownMenuItem(
              value: ConvertMode.taiwan,
              child: Text(l10n.editorWorkbenchOptionsToTaiwan),
            ),
          ],
          onChanged: enabled
              ? (value) =>
                    widget.onChanged(options.copyWith(convertMode: value))
              : null,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Future<void> _editRule() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(
      text: widget.options.ruleSpec == null
          ? r'{"name":"Custom","chapter":"^Chapter [0-9]+.*$"}'
          : const JsonEncoder.withIndent('  ').convert(widget.options.ruleSpec),
    );
    String? error;
    final route = DialogRoute<RuleSpec>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(l10n.editorWorkbenchOptionsRulesTitle),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.editorWorkbenchOptionsRulesHelp),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    minLines: 6,
                    maxLines: 12,
                    maxLength: maxRuleJsonBytes,
                    decoration: InputDecoration(errorText: error),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    context,
                    RuleSpec.fromJsonString(controller.text),
                  );
                } on Object catch (failure) {
                  update(() => error = '$failure');
                }
              },
              child: Text(l10n.editorWorkbenchOptionsValidateApply),
            ),
          ],
        ),
      ),
    );
    final rule = await Navigator.of(context).push(route);
    unawaited(route.completed.then((_) => controller.dispose()));
    if (rule != null && mounted) {
      widget.onChanged(widget.options.copyWith(ruleSpec: rule.toMap()));
    }
  }

  Future<void> _importRule() {
    final l10n = AppLocalizations.of(context);
    return _run(() async {
      final inputs = await widget.files.pickImports(
        multiple: false,
        extensions: const ['json'],
      );
      if (inputs.isEmpty) return;
      final input = inputs.single;
      try {
        final bytes = <int>[];
        await for (final chunk in input.openRead()) {
          if (bytes.length + chunk.length > maxRuleJsonBytes) {
            throw RuleValidationException(
              r'$',
              l10n.editorWorkbenchRuleTooLarge,
            );
          }
          bytes.addAll(chunk);
        }
        final rule = RuleSpec.fromJsonString(utf8.decode(bytes));
        if (mounted) {
          widget.onChanged(widget.options.copyWith(ruleSpec: rule.toMap()));
        }
      } finally {
        await input.release();
      }
    });
  }

  Future<void> _exportRule() => _run(() async {
    final rule = RuleSpec.fromMap(widget.options.ruleSpec);
    final lease = await JobCache(widget.cacheDirectory).create('export');
    try {
      final file = File(p.join(lease.directory.path, 'rules.json'));
      await file.writeAsString(rule.toJsonString());
      await widget.files.savePreparedFile(
        file,
        suggestedName: '${rule.name}.json',
        mimeType: 'application/json',
      );
    } finally {
      await lease.dispose();
    }
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
