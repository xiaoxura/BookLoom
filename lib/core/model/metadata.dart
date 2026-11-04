import 'package:flutter/foundation.dart';

/// Bibliographic metadata shown on the shelf, in the editor and in every
/// export. Kept separate from [Book] so exporters can take just the meta.
@immutable
class BookMeta {
  const BookMeta({
    required this.title,
    this.author = '',
    this.language = 'zh-CN',
    this.description = '',
    this.series,
    this.publisher,
    this.tags = const <String>[],
    this.publishedAt,
  });

  final String title;
  final String author;
  final String language;
  final String description;
  final String? series;
  final String? publisher;
  final List<String> tags;

  /// Publication date as `YYYY-MM-DD`, or null when unknown.
  final DateTime? publishedAt;

  BookMeta copyWith({
    String? title,
    String? author,
    String? language,
    String? description,
    String? series,
    String? publisher,
    List<String>? tags,
    DateTime? publishedAt,
    bool clearSeries = false,
    bool clearPublisher = false,
    bool clearPublishedAt = false,
  }) => BookMeta(
    title: title ?? this.title,
    author: author ?? this.author,
    language: language ?? this.language,
    description: description ?? this.description,
    series: clearSeries ? null : (series ?? this.series),
    publisher: clearPublisher ? null : (publisher ?? this.publisher),
    tags: tags ?? this.tags,
    publishedAt: clearPublishedAt ? null : (publishedAt ?? this.publishedAt),
  );
}
