import 'package:flutter/foundation.dart';

import 'chapter.dart';
import 'cover_options.dart';
import 'layout_options.dart';
import 'metadata.dart';

/// A book loaded for editing: metadata plus the chapter tree.
///
/// Chapter bodies are loaded lazily by the editor; [chapters] here is the
/// structural list (ids, titles, order) and may carry blocks when already read.
@immutable
class Book {
  const Book({
    required this.id,
    required this.meta,
    this.chapters = const <Chapter>[],
    this.coverOptions = const CoverOptions(),
    this.layout = const LayoutOptions(),
    required this.createdAt,
    required this.updatedAt,
    this.lastOpenedAt,
    this.wordCount = 0,
  });

  final String id;
  final BookMeta meta;
  final List<Chapter> chapters;
  final CoverOptions coverOptions;
  final LayoutOptions layout;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastOpenedAt;
  final int wordCount;

  int get chapterCount => chapters.length;

  Book copyWith({
    BookMeta? meta,
    List<Chapter>? chapters,
    CoverOptions? coverOptions,
    LayoutOptions? layout,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
    int? wordCount,
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
  );
}
