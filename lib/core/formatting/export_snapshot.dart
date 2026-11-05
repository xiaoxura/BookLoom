import 'dart:typed_data';

import 'package:bookloom/core/model/book.dart';

/// The task-local, read-only input shared by format exporters.
///
/// The caller must load every chapter's blocks before constructing this value.
/// Asset bytes belong to the export task and are never written back to [book].
class ExportSnapshot {
  const ExportSnapshot({
    required this.book,
    this.coverBytes,
    this.coverMime = 'image/jpeg',
    this.fonts = const <ExportFont>[],
  });

  final Book book;
  final Uint8List? coverBytes;
  final String coverMime;
  final List<ExportFont> fonts;
}

class ExportFont {
  const ExportFont({
    required this.assetId,
    required this.fileName,
    required this.bytes,
  });

  final String assetId;
  final String fileName;
  final Uint8List bytes;
}
