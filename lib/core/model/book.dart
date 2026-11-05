import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';

/// A book loaded for editing: metadata plus the chapter tree.
///
/// Chapter bodies are loaded lazily by the editor; [chapters] here is the
/// structural list (ids, titles, order) and may carry blocks when already read.
class Book {
  Book({
    required this.id,
    required this.meta,
    this.chapters = const <Chapter>[],
    CoverOptions? coverOptions,
    LayoutOptions? layout,
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
    this.wordCount = 0,
    this.revision = 0,
    this.parseOptions = const ParseOptions(),
    this.coverMode = CoverMode.template,
    this.coverAssetId,
  }) : coverOptions = coverOptions ?? CoverOptions(),
       layout = layout ?? LayoutOptions();

  final String id;
  final BookMeta meta;
  final List<Chapter> chapters;
  final CoverOptions coverOptions;
  final LayoutOptions layout;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final int wordCount;

  /// Incremented for current-content concurrency checks; not a history index.
  final int revision;
  final ParseOptions parseOptions;
  final CoverMode coverMode;
  final String? coverAssetId;

  int get chapterCount => chapters.length;

  Book copyWith({
    BookMeta? meta,
    List<Chapter>? chapters,
    CoverOptions? coverOptions,
    LayoutOptions? layout,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
    int? wordCount,
    int? revision,
    ParseOptions? parseOptions,
    CoverMode? coverMode,
    String? coverAssetId,
    bool clearCoverAssetId = false,
  }) => Book(
    id: id,
    meta: meta ?? this.meta,
    chapters: chapters ?? this.chapters,
    coverOptions: coverOptions ?? this.coverOptions,
    layout: layout ?? this.layout,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    wordCount: wordCount ?? this.wordCount,
    revision: revision ?? this.revision,
    parseOptions: parseOptions ?? this.parseOptions,
    coverMode: coverMode ?? this.coverMode,
    coverAssetId: clearCoverAssetId
        ? null
        : (coverAssetId ?? this.coverAssetId),
  );
}

enum CoverMode {
  template('template'),
  image('image');

  const CoverMode(this.wire);
  final String wire;

  static CoverMode fromWire(String value) => CoverMode.values.firstWhere(
    (CoverMode mode) => mode.wire == value,
    orElse: () => template,
  );
}
