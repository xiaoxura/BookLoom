/// Bibliographic metadata shown on the shelf, in the editor and in exports.
class BookMeta {
  BookMeta({
    required this.title,
    this.author = '',
    this.language = 'zh-CN',
    this.description = '',
    this.series,
    this.publisher,
    List<String> tags = const <String>[],
    this.publishedAt,
  }) : tags = List<String>.unmodifiable(_normalizeTags(tags));

  final String title;
  final String author;
  final String language;
  final String description;
  final String? series;
  final String? publisher;
  final List<String> tags;

  /// The year/month/day are calendar fields, irrespective of [DateTime] zone.
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

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'author': author,
    'language': language,
    'description': description,
    'series': series,
    'publisher': publisher,
    'tags': tags,
    'publishedAt': switch (publishedAt) {
      final DateTime date =>
        '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
      null => null,
    },
  };

  static BookMeta fromJson(Map<String, Object?> json) => BookMeta(
    title: json['title'] is String ? json['title']! as String : '',
    author: json['author'] is String ? json['author']! as String : '',
    language: json['language'] is String
        ? json['language']! as String
        : 'zh-CN',
    description: json['description'] is String
        ? json['description']! as String
        : '',
    series: json['series'] is String ? json['series']! as String : null,
    publisher: json['publisher'] is String
        ? json['publisher']! as String
        : null,
    tags: switch (json['tags']) {
      final List<Object?> values => values.whereType<String>().toList(),
      _ => const <String>[],
    },
    publishedAt: _parseCalendarDate(json['publishedAt']),
  );

  static List<String> _normalizeTags(List<String> tags) {
    final Set<String> seen = <String>{};
    for (final String tag in tags) {
      final String trimmed = tag.trim();
      if (trimmed.isNotEmpty) seen.add(trimmed);
    }
    return seen.toList();
  }

  static DateTime? _parseCalendarDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final int year = int.parse(value.substring(0, 4));
    final int month = int.parse(value.substring(5, 7));
    final int day = int.parse(value.substring(8, 10));
    if (year == 0 || month == 0 || day == 0) return null;
    final DateTime date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}
