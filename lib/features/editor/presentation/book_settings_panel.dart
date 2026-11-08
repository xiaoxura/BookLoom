import 'dart:async';
import 'dart:io';

import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/features/editor/application/book_assets.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/preview/book_cover.dart';
import 'package:bookloom/features/preview/bounded_asset_read.dart';
import 'package:bookloom/features/preview/layout_paragraph.dart';
import 'package:bookloom/features/preview/reading_preview.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _Section { metadata, layout, cover, preview }

/// One compact settings surface for the editor side pane and narrow-screen
/// sheet. All edits target the EditorSession's single current Book.
class BookSettingsPanel extends StatefulWidget {
  const BookSettingsPanel({
    super.key,
    required this.session,
    required this.repository,
    required this.files,
  });

  final EditorSession session;
  final BookRepository repository;
  final FileService files;

  @override
  State<BookSettingsPanel> createState() => _BookSettingsPanelState();
}

class _BookSettingsPanelState extends State<BookSettingsPanel> {
  late BookAssets _assets;
  _Section _section = _Section.metadata;

  /// Extended metadata is collapsed by default; the description stays basic.
  bool _moreExpanded = false;
  File? _coverFile;
  File? _fontFile;
  String? _fontMime;
  String? _coverId;
  String? _fontId;
  String? _assetBookId;
  String? _sampleFontFamily;
  String? _sampleFontStatus;
  int _sampleFontRequest = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _assets = BookAssets(repository: widget.repository, files: widget.files);
    widget.session.addListener(_sessionChanged);
    _sessionChanged();
  }

  @override
  void didUpdateWidget(covariant BookSettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.files != widget.files) {
      _assets = BookAssets(repository: widget.repository, files: widget.files);
      _coverId = null;
      _fontId = null;
    }
    _sessionChanged();
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    final book = widget.session.book;
    if (book != null &&
        (_assetBookId != book.id ||
            book.coverAssetId != _coverId ||
            book.layout.embeddedFontAssetId != _fontId)) {
      final fontChanged =
          _assetBookId != book.id || book.layout.embeddedFontAssetId != _fontId;
      _assetBookId = book.id;
      _coverId = book.coverAssetId;
      _fontId = book.layout.embeddedFontAssetId;
      _coverFile = null;
      if (fontChanged) {
        _fontFile = null;
        _fontMime = null;
        _sampleFontFamily = null;
        _sampleFontStatus = null;
        _sampleFontRequest++;
      }
      _loadFiles(book.id, _coverId, _fontId);
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadFiles(
    String bookId,
    String? coverId,
    String? fontId,
  ) async {
    try {
      final cover = await _assets.coverFile(bookId, coverId);
      final fontAsset = fontId == null
          ? null
          : await _assets.findAsset(bookId, fontId);
      final font = fontAsset == null
          ? null
          : await widget.repository.resolveAsset(fontAsset);
      if (!mounted ||
          widget.session.book?.id != bookId ||
          _coverId != coverId ||
          _fontId != fontId) {
        return;
      }
      setState(() {
        _coverFile = cover;
        _fontFile = font;
        _fontMime = fontAsset?.mime;
      });
      unawaited(_loadSampleFont(bookId, fontId, font, fontAsset?.mime));
    } on Object {
      if (mounted && _coverId == coverId && _fontId == fontId) {
        setState(() {
          _coverFile = null;
          _fontFile = null;
          _fontMime = null;
        });
        unawaited(_loadSampleFont(bookId, fontId, null, null));
      }
    }
  }

  Future<void> _loadSampleFont(
    String bookId,
    String? fontId,
    File? file,
    String? mime,
  ) async {
    final request = ++_sampleFontRequest;
    if (fontId == null) return;
    if (file == null || mime == null) {
      setState(() => _sampleFontStatus = 'missing');
      return;
    }
    if (mime == 'font/woff' || mime == 'font/woff2') {
      setState(() => _sampleFontStatus = 'woff');
      return;
    }
    if (mime != 'font/ttf' && mime != 'font/otf') {
      setState(() => _sampleFontStatus = 'unsupported');
      return;
    }
    final family = 'bookloom-layout-sample-$bookId-$fontId';
    if (_sampleFontFamily == family) return;
    try {
      final bytes = await readBoundedAssetFile(file, ImportLimits.maxFontBytes);
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      if (mounted && request == _sampleFontRequest) {
        setState(() => _sampleFontFamily = family);
      }
    } on Object {
      if (mounted && request == _sampleFontRequest) {
        setState(() => _sampleFontStatus = 'failed');
      }
    }
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  void _editMeta(BookMeta Function(BookMeta) update) {
    final book = widget.session.book;
    if (book == null) return;
    widget.session.editBookMeta(update(book.meta));
  }

  void _notice(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _pickCover() async {
    final book = widget.session.book;
    if (book == null || _busy) return;
    final assets = _assets;
    setState(() => _busy = true);
    StoredFile? stored;
    var linked = false;
    try {
      stored = await assets.pickCover(book.id);
      if (stored == null || !mounted) return;
      if (widget.session.book?.id != book.id) return;
      widget.session.setCoverImage(stored.id);
      linked = true;
    } on Object catch (error) {
      _notice(error);
    } finally {
      if (stored != null && !linked) {
        try {
          await assets.discardUnusedCover(book.id, stored.id);
        } on Object {
          // A later post-session cleanup can remove an unreferenced asset.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFont() async {
    final book = widget.session.book;
    if (book == null || _busy) return;
    final assets = _assets;
    setState(() => _busy = true);
    StoredFile? stored;
    var linked = false;
    try {
      stored = await assets.pickFont(book.id);
      if (stored == null || !mounted) return;
      final current = widget.session.book;
      if (current?.id != book.id) return;
      widget.session.editLayout(
        current!.layout.copyWith(embeddedFontAssetId: stored.id),
      );
      linked = true;
    } on Object catch (error) {
      _notice(error);
    } finally {
      if (stored != null && !linked) {
        try {
          await assets.discardUnusedFont(book.id, stored.id);
        } on Object {
          // A later post-session cleanup can remove an unreferenced asset.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.session.book;
    final colors = context.colors;
    if (book == null) return const Center(child: CircularProgressIndicator());
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: DropdownButtonFormField<_Section>(
              initialValue: _section,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _l10n.bookWorkbenchSettings,
              ),
              items: [
                DropdownMenuItem(
                  value: _Section.metadata,
                  child: Text(_l10n.bookWorkbenchMetadata),
                ),
                DropdownMenuItem(
                  value: _Section.layout,
                  child: Text(_l10n.bookWorkbenchLayoutFonts),
                ),
                DropdownMenuItem(
                  value: _Section.cover,
                  child: Text(_l10n.bookWorkbenchCover),
                ),
                DropdownMenuItem(
                  value: _Section.preview,
                  child: Text(_l10n.bookWorkbenchReadingPreview),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _section = value ?? _section),
            ),
          ),
          Expanded(
            child: switch (_section) {
              _Section.metadata => _metadata(book),
              _Section.layout => _layout(book),
              _Section.cover => _cover(book),
              _Section.preview => ReadingPreview(
                book: book,
                chapter: widget.session.activeChapter,
                coverFile: _coverFile,
                fontFile: _fontFile,
                fontMime: _fontMime,
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _metadata(Book book) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _SettingField(
          label: _l10n.editorBookTitle,
          value: book.meta.title,
          maxLength: 200,
          validate: (value) =>
              value.trim().isEmpty ? _l10n.bookWorkbenchTitleRequired : null,
          onValid: (value) =>
              _editMeta((meta) => meta.copyWith(title: value.trim())),
        ),
        _SettingField(
          label: _l10n.editorBookAuthor,
          value: book.meta.author,
          maxLength: 160,
          onValid: (value) =>
              _editMeta((meta) => meta.copyWith(author: value.trim())),
        ),
        // The description is basic information: a recognized intro chapter
        // auto-fills it, so it no longer lives in the extended section below.
        _SettingField(
          label: _l10n.editorDescription,
          value: book.meta.description,
          maxLength: 10000,
          maxLines: 4,
          onValid: (value) =>
              _editMeta((meta) => meta.copyWith(description: value)),
        ),
        // Extended details stay available but collapsed until asked for.
        InkWell(
          key: const ValueKey('book-extended-header'),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => setState(() => _moreExpanded = !_moreExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _l10n.bookWorkbenchMoreInformation,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Icon(
                  _moreExpanded
                      ? Icons.expand_less_outlined
                      : Icons.expand_more_rounded,
                  size: 20,
                  color: colors.inkMuted,
                ),
              ],
            ),
          ),
        ),
        if (_moreExpanded) ...[
          _SettingField(
            label: _l10n.editorSeries,
            value: book.meta.series ?? '',
            maxLength: 200,
            onValid: (value) => _editMeta(
              (meta) => meta.copyWith(
                series: value.trim(),
                clearSeries: value.trim().isEmpty,
              ),
            ),
          ),
          _SettingField(
            label: _l10n.editorPublisher,
            value: book.meta.publisher ?? '',
            maxLength: 200,
            onValid: (value) => _editMeta(
              (meta) => meta.copyWith(
                publisher: value.trim(),
                clearPublisher: value.trim().isEmpty,
              ),
            ),
          ),
          _SettingField(
            label: _l10n.editorTags,
            value: book.meta.tags.join(', '),
            onValid: (value) => _editMeta(
              (meta) => meta.copyWith(
                tags: value
                    .split(RegExp(r'[,，]'))
                    .map((tag) => tag.trim())
                    .toList(),
              ),
            ),
          ),
          _SettingField(
            label: _l10n.editorLanguage,
            value: book.meta.language,
            maxLength: 35,
            validate: (value) =>
                RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$')
                    .hasMatch(value.trim())
                ? null
                : _l10n.bookWorkbenchLanguageCodeHint,
            onValid: (value) =>
                _editMeta((meta) => meta.copyWith(language: value.trim())),
          ),
          _SettingField(
            label: _l10n.bookWorkbenchPublicationDate,
            value: _date(book.meta.publishedAt),
            maxLength: 10,
            validate: (value) =>
                value.trim().isEmpty || _parseDate(value.trim()) != null
                ? null
                : _l10n.bookWorkbenchInvalidDate,
            onValid: (value) => _editMeta(
              (meta) => meta.copyWith(
                publishedAt: _parseDate(value.trim()),
                clearPublishedAt: value.trim().isEmpty,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _layout(Book book) {
    final layout = book.layout;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: SizedBox(
              height: (constraints.maxHeight * 0.4)
                  .clamp(0.0, AppSpacing.huge * 5)
                  .toDouble(),
              child: _layoutSample(layout),
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('layout-controls'),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  _l10n.bookWorkbenchLineHeight(
                    layout.lineHeight.toStringAsFixed(2),
                  ),
                ),
                Slider(
                  key: const ValueKey('layout-line-height'),
                  value: layout.lineHeight,
                  min: 1.3,
                  max: 2.4,
                  divisions: 22,
                  onChanged: (value) => widget.session.editLayout(
                    layout.copyWith(lineHeight: value),
                  ),
                ),
                Text(
                  _l10n.bookWorkbenchParagraphSpacing(
                    layout.paragraphSpacing.toStringAsFixed(2),
                  ),
                ),
                Slider(
                  key: const ValueKey('layout-paragraph-spacing'),
                  value: layout.paragraphSpacing,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (value) => widget.session.editLayout(
                    layout.copyWith(paragraphSpacing: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_l10n.bookWorkbenchTwoCharacterIndent),
                  value: layout.indent,
                  onChanged: (value) =>
                      widget.session.editLayout(layout.copyWith(indent: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_l10n.bookWorkbenchJustify),
                  value: layout.justify,
                  onChanged: (value) => widget.session.editLayout(
                    layout.copyWith(justify: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_l10n.bookWorkbenchSeparateChapterNumber),
                  value: layout.separateChapterNumber,
                  onChanged: (value) => widget.session.editLayout(
                    layout.copyWith(separateChapterNumber: value),
                  ),
                ),
                DropdownButtonFormField<LayoutFont>(
                  initialValue: layout.font,
                  decoration: InputDecoration(
                    labelText: _l10n.bookWorkbenchBodyFontStyle,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: LayoutFont.serif,
                      child: Text(_l10n.bookWorkbenchSerif),
                    ),
                    DropdownMenuItem(
                      value: LayoutFont.sans,
                      child: Text(_l10n.bookWorkbenchSans),
                    ),
                    DropdownMenuItem(
                      value: LayoutFont.kai,
                      child: Text(_l10n.bookWorkbenchKai),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.session.editLayout(layout.copyWith(font: value));
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _l10n.bookWorkbenchEmbeddedFontInfo,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (layout.embeddedFontAssetId != null)
                  Text(
                    _l10n.bookWorkbenchSelectedFont(
                      _fontMime ?? _l10n.bookWorkbenchLoading,
                    ),
                  ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : _pickFont,
                      child: Text(_l10n.bookWorkbenchImportFont),
                    ),
                    if (layout.embeddedFontAssetId != null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => widget.session.editLayout(
                                layout.copyWith(clearEmbeddedFontAssetId: true),
                              ),
                        child: Text(_l10n.bookWorkbenchRemoveFont),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _SettingField(
                  label: _l10n.bookWorkbenchCustomCssLabel,
                  value: layout.customCss,
                  maxLength: 20000,
                  maxLines: 5,
                  validate: (value) {
                    try {
                      layout.copyWith(customCss: value);
                      return null;
                    } on ArgumentError {
                      return _l10n.bookWorkbenchUnsafeCss;
                    }
                  },
                  onValid: (value) => widget.session.editLayout(
                    widget.session.book!.layout.copyWith(customCss: value),
                  ),
                ),
                Text(
                  _l10n.bookWorkbenchCssNativeNote,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _layoutSample(LayoutOptions layout) {
    final colors = context.colors;
    final textStyle = TextStyle(
      fontSize: 16.5,
      height: layout.lineHeight,
      color: colors.ink,
      fontFamily:
          _sampleFontFamily ??
          switch (layout.font) {
            LayoutFont.serif => 'Noto Serif CJK SC',
            LayoutFont.sans => 'Noto Sans CJK SC',
            LayoutFont.kai => 'KaiTi',
          },
    );
    return Material(
      key: const ValueKey('layout-sample-card'),
      color: colors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            _l10n.bookWorkbenchLayoutSampleTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (index, paragraph) in [
            _l10n.bookWorkbenchLayoutSampleFirst,
            _l10n.bookWorkbenchLayoutSampleSecond,
          ].indexed)
            LayoutParagraph(
              key: ValueKey('layout-sample-paragraph-$index'),
              text: paragraph,
              layout: layout,
              style: textStyle,
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _l10n.bookWorkbenchLayoutSampleScope,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_sampleFontStatus != null)
            Text(switch (_sampleFontStatus) {
              'woff' => _l10n.bookWorkbenchPreviewWoff,
              'missing' => _l10n.bookWorkbenchPreviewFontMissing,
              'failed' => _l10n.bookWorkbenchPreviewFontFailed,
              _ => _l10n.bookWorkbenchPreviewFontUnsupported,
            }, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _cover(Book book) {
    final options = book.coverOptions;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Center(
          child: SizedBox(
            width: 180,
            height: 270,
            child: BookCover(book: book, imageFile: _coverFile),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<CoverMode>(
          segments: [
            ButtonSegment(
              value: CoverMode.template,
              label: Text(_l10n.bookWorkbenchTemplate),
            ),
            ButtonSegment(
              value: CoverMode.image,
              label: Text(_l10n.bookWorkbenchImage),
            ),
          ],
          selected: {book.coverMode},
          onSelectionChanged: (selection) {
            if (selection.first == CoverMode.template) {
              widget.session.setCoverTemplate();
            } else if (book.coverAssetId != null) {
              widget.session.setCoverImage(book.coverAssetId!);
            } else {
              _notice(_l10n.bookWorkbenchChooseCoverFirst);
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: _busy ? null : _pickCover,
          child: Text(_l10n.bookWorkbenchChooseCoverImage),
        ),
        Text(
          _l10n.bookWorkbenchCoverLimits,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        DropdownButtonFormField<CoverTemplate>(
          initialValue: options.template,
          decoration: InputDecoration(labelText: _l10n.bookWorkbenchTemplate),
          items: [
            DropdownMenuItem(
              value: CoverTemplate.vertical,
              child: Text(_l10n.bookWorkbenchVertical),
            ),
            DropdownMenuItem(
              value: CoverTemplate.blocks,
              child: Text(_l10n.bookWorkbenchBlocks),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              widget.session.editCoverOptions(
                options.copyWith(template: value),
              );
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          initialValue: options.palette,
          decoration: InputDecoration(labelText: _l10n.bookWorkbenchPalette),
          items: [
            DropdownMenuItem(
              value: 'auto',
              child: Text(_l10n.bookWorkbenchAuto),
            ),
            DropdownMenuItem(
              value: 'sand',
              child: Text(_l10n.bookWorkbenchSand),
            ),
            DropdownMenuItem(value: 'ink', child: Text(_l10n.bookWorkbenchInk)),
            DropdownMenuItem(value: 'sea', child: Text(_l10n.bookWorkbenchSea)),
            DropdownMenuItem(
              value: 'wine',
              child: Text(_l10n.bookWorkbenchWine),
            ),
            DropdownMenuItem(
              value: 'forest',
              child: Text(_l10n.bookWorkbenchForest),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              widget.session.editCoverOptions(options.copyWith(palette: value));
            }
          },
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _l10n.bookWorkbenchTitleScale(options.titleScale.toStringAsFixed(2)),
        ),
        Slider(
          value: options.titleScale,
          min: 0.8,
          max: 1.3,
          divisions: 25,
          onChanged: (value) => widget.session.editCoverOptions(
            options.copyWith(titleScale: value),
          ),
        ),
        DropdownButtonFormField<AuthorPosition>(
          initialValue: options.authorPosition,
          decoration: InputDecoration(
            labelText: _l10n.bookWorkbenchAuthorPosition,
          ),
          items: [
            DropdownMenuItem(
              value: AuthorPosition.top,
              child: Text(_l10n.bookWorkbenchTop),
            ),
            DropdownMenuItem(
              value: AuthorPosition.bottom,
              child: Text(_l10n.bookWorkbenchBottom),
            ),
            DropdownMenuItem(
              value: AuthorPosition.hidden,
              child: Text(_l10n.bookWorkbenchHidden),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              widget.session.editCoverOptions(
                options.copyWith(authorPosition: value),
              );
            }
          },
        ),
        if (book.coverMode == CoverMode.image)
          Text(
            _l10n.bookWorkbenchImageModeNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }

  static String _date(DateTime? date) => date == null
      ? ''
      : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    if (year == 0 || month == 0 || day == 0) return null;
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }
}

class _SettingField extends StatefulWidget {
  const _SettingField({
    required this.label,
    required this.value,
    required this.onValid,
    this.validate,
    this.maxLength,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onValid;
  final String? Function(String)? validate;
  final int? maxLength;
  final int maxLines;

  @override
  State<_SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<_SettingField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void didUpdateWidget(covariant _SettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus &&
        _error == null &&
        widget.value != _controller.text) {
      _controller.text = widget.value;
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      // Counter silent: the "N/M" digits under every field took a
      // row each without helping; the limit itself is still enforced.
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: _error,
        counterText: '',
      ),
      onChanged: (value) {
        final error = widget.validate?.call(value);
        if (_error != error) setState(() => _error = error);
        if (error == null) widget.onValid(value);
      },
    ),
  );
}
