import 'dart:io';

import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'book_cover.dart';
import 'bounded_asset_read.dart';
import 'layout_paragraph.dart';

/// A native reading preview of the current session's model. It intentionally
/// excludes arbitrary export CSS and reader-specific pagination.
class ReadingPreview extends StatefulWidget {
  const ReadingPreview({
    super.key,
    required this.book,
    this.chapter,
    this.coverFile,
    this.fontFile,
    this.fontMime,
  });

  final Book book;
  final Chapter? chapter;
  final File? coverFile;
  final File? fontFile;
  final String? fontMime;

  @override
  State<ReadingPreview> createState() => _ReadingPreviewState();
}

class _ReadingPreviewState extends State<ReadingPreview> {
  String? _loadedFontFamily;
  String? _fontStatus;
  int _fontRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  @override
  void didUpdateWidget(covariant ReadingPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontFile?.path != widget.fontFile?.path ||
        oldWidget.fontMime != widget.fontMime ||
        oldWidget.book.id != widget.book.id ||
        oldWidget.book.layout.embeddedFontAssetId !=
            widget.book.layout.embeddedFontAssetId) {
      _loadFont();
    }
  }

  Future<void> _loadFont() async {
    final request = ++_fontRequest;
    final file = widget.fontFile;
    final mime = widget.fontMime;
    _loadedFontFamily = null;
    _fontStatus = null;
    if (file == null || mime == null) {
      if (widget.book.layout.embeddedFontAssetId != null) {
        _fontStatus = 'missing';
        if (mounted) setState(() {});
      }
      return;
    }
    if (mime == 'font/woff' || mime == 'font/woff2') {
      _fontStatus = 'woff';
      if (mounted) setState(() {});
      return;
    }
    if (mime != 'font/ttf' && mime != 'font/otf') {
      _fontStatus = 'unsupported';
      if (mounted) setState(() {});
      return;
    }
    try {
      final bytes = await readBoundedAssetFile(file, ImportLimits.maxFontBytes);
      final family =
          'bookloom-preview-${widget.book.id}-${widget.book.layout.embeddedFontAssetId}';
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      if (mounted && request == _fontRequest) {
        setState(() => _loadedFontFamily = family);
      }
    } on Object {
      if (mounted && request == _fontRequest) {
        setState(() => _fontStatus = 'failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final layout = widget.book.layout;
    final chapter = widget.chapter;
    final textStyle = TextStyle(
      fontSize: 16.5,
      height: layout.lineHeight,
      color: colors.ink,
      fontFamily: _loadedFontFamily ?? _family(layout.font),
    );
    final blocks = chapter?.blocks ?? const <Block>[];
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: blocks.length + 3,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, maxHeight: 330),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: BookCover(
                  book: widget.book,
                  imageFile: widget.coverFile,
                ),
              ),
            ),
          );
        }
        if (index == 1) {
          final heading = chapter?.title ?? widget.book.meta.title;
          final chapterNumber = layout.separateChapterNumber
              ? RegExp(r'^(第[^\s　]{1,12}[章回节卷])[\s　]*(.*)$').firstMatch(heading)
              : null;
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child:
                chapterNumber != null &&
                    (chapterNumber.group(2)?.isNotEmpty ?? false)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapterNumber.group(1)!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        chapterNumber.group(2)!,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ],
                  )
                : Text(
                    heading,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
          );
        }
        if (index == 2) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (layout.customCss.isNotEmpty)
                  Text(
                    l10n.bookWorkbenchPreviewCss,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_fontStatus != null)
                  Text(switch (_fontStatus) {
                    'woff' => l10n.bookWorkbenchPreviewWoff,
                    'missing' => l10n.bookWorkbenchPreviewFontMissing,
                    'failed' => l10n.bookWorkbenchPreviewFontFailed,
                    _ => l10n.bookWorkbenchPreviewFontUnsupported,
                  }, style: Theme.of(context).textTheme.bodySmall),
                if (_loadedFontFamily != null)
                  Text(
                    l10n.bookWorkbenchPreviewFontLoaded,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  l10n.bookWorkbenchPreviewLimits,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        }
        final block = blocks[index - 3];
        if (block is DividerBlock) return const Divider();
        if (block is ImageBlock) {
          return Text(
            l10n.bookWorkbenchPreviewIllustration(block.caption ?? block.alt),
            style: textStyle,
          );
        }
        final text = block.plainText;
        return LayoutParagraph(text: text, layout: layout, style: textStyle);
      },
    );
  }

  String _family(LayoutFont font) => switch (font) {
    LayoutFont.serif => 'Noto Serif CJK SC',
    LayoutFont.sans => 'Noto Sans CJK SC',
    LayoutFont.kai => 'KaiTi',
  };
}
