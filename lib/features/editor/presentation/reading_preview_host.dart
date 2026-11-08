import 'dart:async';
import 'dart:io';

import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/editor/application/book_assets.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/preview/reading_preview.dart';
import 'package:flutter/material.dart';

/// Session-backed host for [ReadingPreview]: keeps the cover and embedded font
/// files in sync with the book's assets and renders the **always-live session
/// model** — layout edits show up immediately, and the chapter follows the
/// editor's active chapter.
class ReadingPreviewHost extends StatefulWidget {
  const ReadingPreviewHost({
    super.key,
    required this.session,
    required this.repository,
    required this.assets,
  });

  final EditorSession session;
  final BookRepository repository;
  final BookAssets assets;

  @override
  State<ReadingPreviewHost> createState() => _ReadingPreviewHostState();
}

class _ReadingPreviewHostState extends State<ReadingPreviewHost> {
  String? _bookId;
  String? _coverId;
  String? _fontId;
  File? _coverFile;
  File? _fontFile;
  String? _fontMime;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    _sessionChanged();
  }

  @override
  void didUpdateWidget(covariant ReadingPreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_sessionChanged);
      widget.session.addListener(_sessionChanged);
    }
    _sessionChanged();
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    super.dispose();
  }

  void _sessionChanged() {
    if (!mounted) return;
    final book = widget.session.book;
    final (cover, font) = book == null
        ? (null, null)
        : (book.coverAssetId, book.layout.embeddedFontAssetId);
    if (book == null || book.id != _bookId || cover != _coverId || font != _fontId) {
      _bookId = book?.id;
      _coverId = cover;
      _fontId = font;
      _coverFile = null;
      _fontFile = null;
      _fontMime = null;
      if (book != null) unawaited(_loadFiles(book.id, cover, font));
      setState(() {});
      return;
    }
    // Edited layout or chapter content alone: just repaint with the live model.
    setState(() {});
  }

  Future<void> _loadFiles(
    String bookId,
    String? coverId,
    String? fontId,
  ) async {
    try {
      final cover = await widget.assets.coverFile(bookId, coverId);
      final fontAsset = fontId == null
          ? null
          : await widget.assets.findAsset(bookId, fontId);
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
    } on Object {
      if (mounted && _coverId == coverId && _fontId == fontId) {
        setState(() {
          _coverFile = null;
          _fontFile = null;
          _fontMime = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final book = session.book;
    if (book == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ReadingPreview(
      book: book,
      chapter: session.activeChapter,
      coverFile: _coverFile,
      fontFile: _fontFile,
      fontMime: _fontMime,
    );
  }
}
