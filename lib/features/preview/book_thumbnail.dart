import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/storage/app_database.dart' show Asset;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/design/theme/app_tokens.dart';
import 'package:bookloom/design/tokens/app_colors.dart';
import 'package:bookloom/design/tokens/app_metrics.dart';
import 'package:bookloom/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'book_cover.dart';
import 'bounded_asset_read.dart';

/// A lazy shelf image. Template covers paint directly; uploaded covers resolve
/// only this book's cached thumbnail and never load its chapter structure.
class BookThumbnail extends StatefulWidget {
  const BookThumbnail({
    super.key,
    required this.summary,
    required this.repository,
    this.width = 72,
  });

  final BookSummary summary;
  final BookRepository repository;
  final double width;

  @override
  State<BookThumbnail> createState() => _BookThumbnailState();
}

class _BookThumbnailState extends State<BookThumbnail> {
  Future<Uint8List?>? _imageBytes;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant BookThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.summary.id != widget.summary.id ||
        oldWidget.summary.revision != widget.summary.revision ||
        oldWidget.summary.updatedAt != widget.summary.updatedAt ||
        oldWidget.summary.coverAssetId != widget.summary.coverAssetId ||
        oldWidget.summary.coverMode != widget.summary.coverMode) {
      _refresh();
    }
  }

  void _refresh() {
    _imageBytes = widget.summary.coverMode == CoverMode.image
        ? _readCover(widget.summary, widget.repository)
        : null;
  }

  static Future<Uint8List?> _readCover(
    BookSummary book,
    BookRepository repository,
  ) async {
    final id = book.coverAssetId;
    if (id == null) return null;
    try {
      Asset? thumbnail;
      Asset? original;
      for (final asset in await repository.loadAssets(book.id)) {
        if (asset.bookId != book.id) continue;
        if (asset.id == '$id-thumb' && asset.kind == 'image') {
          thumbnail = asset;
        } else if (asset.id == id && asset.kind == 'cover') {
          original = asset;
        }
      }
      for (final asset in [thumbnail, original]) {
        if (asset == null) continue;
        try {
          final file = await repository.resolveAsset(asset);
          final bytes = await readBoundedAssetFile(
            file,
            ImportLimits.maxEncodedCoverBytes,
          );
          await _checkDimensions(bytes);
          return bytes;
        } on Object {
          // A broken cached thumbnail may still have a usable original.
        }
      }
    } on Object {
      // A broken or missing asset must not prevent opening the book.
    }
    return null;
  }

  static Future<void> _checkDimensions(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > ImportLimits.maxCoverPixels) {
        throw const FormatException('Cover dimensions exceed the limit.');
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.summary;
    final colors = context.colors;
    final l10n = AppLocalizations.of(context);
    final content = book.coverMode == CoverMode.template
        ? CustomPaint(
            painter: _TemplateThumbnailPainter(
              title: book.title,
              author: book.author,
              options: book.coverOptions,
            ),
          )
        : FutureBuilder<Uint8List?>(
            future: _imageBytes,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: Icon(Icons.image_outlined, color: colors.inkSecondary),
                );
              }
              if (snapshot.hasError || snapshot.data == null) {
                return _UnavailableThumbnail(colors: colors);
              }
              return Image.memory(
                snapshot.data!,
                width: widget.width,
                height: widget.width * 1.5,
                fit: BoxFit.cover,
                cacheWidth: 120,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) =>
                    _UnavailableThumbnail(colors: colors),
              );
            },
          );
    return Semantics(
      label: l10n.bookWorkbenchCoverSemantics(book.title),
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: widget.width,
          height: widget.width * 1.5,
          child: content,
        ),
      ),
    );
  }
}

class _TemplateThumbnailPainter extends CustomPainter {
  const _TemplateThumbnailPainter({
    required this.title,
    required this.author,
    required this.options,
  });

  final String title;
  final String author;
  final CoverOptions options;

  @override
  void paint(Canvas canvas, Size size) {
    BookCoverRenderer.paintTemplate(
      canvas,
      title: title,
      author: author,
      options: options,
      size: size,
    );
  }

  @override
  bool shouldRepaint(covariant _TemplateThumbnailPainter oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.author != author ||
      oldDelegate.options.template != options.template ||
      oldDelegate.options.palette != options.palette ||
      oldDelegate.options.titleScale != options.titleScale ||
      oldDelegate.options.authorPosition != options.authorPosition;
}

class _UnavailableThumbnail extends StatelessWidget {
  const _UnavailableThumbnail({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: AppLocalizations.of(context).bookWorkbenchCoverUnavailable,
      child: ColoredBox(
        color: colors.surfaceSunken,
        child: Center(
          child: Icon(Icons.hide_image_outlined, color: colors.inkSecondary),
        ),
      ),
    );
  }
}
