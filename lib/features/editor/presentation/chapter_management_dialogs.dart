import 'package:flutter/material.dart';

import '../../../core/model/chapter.dart';
import '../../../design/components/app_select_field.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';

typedef NewChapterRequest = ({
  String title,
  String? volumeId,
  String? beforeChapterId,
  String? afterChapterId,
});

typedef MoveChaptersRequest = ({Set<String> chapterIds, String? volumeId});

Future<String?> showNewVolumeDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  var draft = '';
  return await showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: Text(l10n.editorNewVolume),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.editorVolumeTitle),
          onChanged: (value) => update(() => draft = value),
          onSubmitted: (title) {
            if (title.trim().isNotEmpty) Navigator.pop(dialog, title.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: draft.trim().isEmpty
                ? null
                : () => Navigator.pop(dialog, draft.trim()),
            child: Text(l10n.editorCreate),
          ),
        ],
      ),
    ),
  );
}

Future<NewChapterRequest?> showNewChapterDialog(
  BuildContext context, {
  required List<Chapter> chapters,
  String? activeChapterId,
  String? initialVolumeId,

  /// Presets the insert position relative to this chapter (must be a
  /// non-volume chapter). The volume and position stay adjustable.
  String? anchorChapterId,
  bool anchorAfter = true,
}) => showDialog<NewChapterRequest>(
  context: context,
  builder: (_) => _NewChapterDialog(
    chapters: chapters,
    activeChapterId: activeChapterId,
    initialVolumeId: initialVolumeId,
    anchorChapterId: anchorChapterId,
    anchorAfter: anchorAfter,
  ),
);

class _NewChapterDialog extends StatefulWidget {
  const _NewChapterDialog({
    required this.chapters,
    this.activeChapterId,
    this.initialVolumeId,
    this.anchorChapterId,
    this.anchorAfter = true,
  });
  final List<Chapter> chapters;
  final String? activeChapterId;
  final String? initialVolumeId;
  final String? anchorChapterId;
  final bool anchorAfter;

  @override
  State<_NewChapterDialog> createState() => _NewChapterDialogState();
}

class _NewChapterDialogState extends State<_NewChapterDialog> {
  final _title = TextEditingController();
  late String _volume;
  late String _after;

  List<Chapter> get _siblings => widget.chapters
      .where((chapter) => (chapter.parentId ?? '') == _volume)
      .toList();

  @override
  void initState() {
    super.initState();
    final active = widget.chapters
        .where((chapter) => chapter.id == widget.activeChapterId)
        .firstOrNull;
    _volume = widget.initialVolumeId ?? active?.parentId ?? '';
    _after = _siblings.any((chapter) => chapter.id == active?.id)
        ? active!.id
        : _siblings.lastOrNull?.id ?? '';
    final anchor = widget.anchorChapterId == null
        ? null
        : widget.chapters
              .where((chapter) => chapter.id == widget.anchorChapterId)
              .firstOrNull;
    if (anchor != null && !anchor.isVolume) {
      _volume = anchor.parentId ?? '';
      if (widget.anchorAfter) {
        _after = anchor.id;
      } else {
        final index = _siblings.indexWhere((item) => item.id == anchor.id);
        _after = index > 0 ? _siblings[index - 1].id : '';
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _create() {
    if (_title.text.trim().isEmpty) return;
    Navigator.pop(context, (
      title: _title.text.trim(),
      volumeId: _volume.isEmpty ? null : _volume,
      beforeChapterId: _after.isEmpty ? _siblings.firstOrNull?.id : null,
      afterChapterId: _after.isEmpty ? null : _after,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.editorNewChapter),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.editorChapterTitle),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSelectField<String>(
              label: l10n.editorTargetVolume,
              initialSelection: _volume,
              entries: _volumeEntries(widget.chapters, l10n),
              onSelected: (value) => setState(() {
                _volume = value ?? '';
                _after = _siblings.lastOrNull?.id ?? '';
              }),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppSelectField<String>(
              key: ValueKey(_volume),
              label: l10n.editorInsertPosition,
              initialSelection: _after,
              entries: [
                DropdownMenuEntry(value: '', label: l10n.editorBeforeFirst),
                for (final chapter in _siblings)
                  DropdownMenuEntry(
                    value: chapter.id,
                    label: l10n.editorAfterChapter(chapter.title),
                  ),
              ],
              onSelected: (value) => setState(() => _after = value ?? ''),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _title.text.trim().isEmpty ? null : _create,
          child: Text(l10n.editorCreate),
        ),
      ],
    );
  }
}

List<DropdownMenuEntry<String>> _volumeEntries(
  List<Chapter> chapters,
  AppLocalizations l10n,
) => [
  DropdownMenuEntry(value: '', label: l10n.editorUnassigned),
  for (final volume in chapters.where((chapter) => chapter.isVolume))
    DropdownMenuEntry(value: volume.id, label: volume.title),
];

Future<MoveChaptersRequest?> showMoveChaptersDialog(
  BuildContext context, {
  required List<Chapter> chapters,
  String? initialVolumeId,
}) => showDialog<MoveChaptersRequest>(
  context: context,
  builder: (_) =>
      _MoveChaptersDialog(chapters: chapters, initialVolumeId: initialVolumeId),
);

class _MoveChaptersDialog extends StatefulWidget {
  const _MoveChaptersDialog({required this.chapters, this.initialVolumeId});
  final List<Chapter> chapters;
  final String? initialVolumeId;

  @override
  State<_MoveChaptersDialog> createState() => _MoveChaptersDialogState();
}

class _MoveChaptersDialogState extends State<_MoveChaptersDialog> {
  final _selected = <String>{};
  late String _volume = widget.initialVolumeId ?? '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chapters = widget.chapters
        .where((chapter) => !chapter.isVolume)
        .toList();
    final volumes = {
      for (final chapter in widget.chapters.where(
        (chapter) => chapter.isVolume,
      ))
        chapter.id: chapter.title,
    };
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.editorMoveChapters),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSelectField<String>(
              label: l10n.editorTargetVolume,
              initialSelection: _volume,
              entries: _volumeEntries(widget.chapters, l10n),
              onSelected: (value) => setState(() => _volume = value ?? ''),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.editorSelectChapters),
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(
                    () =>
                        _selected.addAll(chapters.map((chapter) => chapter.id)),
                  ),
                  child: Text(l10n.editorSelectAll),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: Text(l10n.editorClearSelection),
                ),
                Text('${_selected.length} / ${chapters.length}'),
              ],
            ),
            SizedBox(
              height: MediaQuery.sizeOf(context).height / 3,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chapters.length,
                itemBuilder: (_, index) {
                  final chapter = chapters[index];
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(chapter.id),
                    title: Text(chapter.title),
                    subtitle: Text(
                      volumes[chapter.parentId] ?? l10n.editorUnassigned,
                    ),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        _selected.add(chapter.id);
                      } else {
                        _selected.remove(chapter.id);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  chapterIds: Set<String>.of(_selected),
                  volumeId: _volume.isEmpty ? null : _volume,
                )),
          child: Text(l10n.editorMove),
        ),
      ],
    );
  }
}
