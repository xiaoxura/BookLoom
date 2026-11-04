import 'package:flutter/foundation.dart';

/// Cover designer parameters. Stored as `books.cover_options_json`.
@immutable
class CoverOptions {
  const CoverOptions({
    this.template = CoverTemplate.vertical,
    this.palette = 'sea',
    this.titleScale = 1,
    this.authorPosition = AuthorPosition.bottom,
  });

  final CoverTemplate template;
  final String palette;
  final double titleScale;
  final AuthorPosition authorPosition;

  CoverOptions copyWith({
    CoverTemplate? template,
    String? palette,
    double? titleScale,
    AuthorPosition? authorPosition,
  }) => CoverOptions(
    template: template ?? this.template,
    palette: palette ?? this.palette,
    titleScale: titleScale ?? this.titleScale,
    authorPosition: authorPosition ?? this.authorPosition,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'template': template.wire,
    'palette': palette,
    'titleScale': titleScale,
    'authorPosition': authorPosition.wire,
  };

  static CoverOptions fromJson(Map<String, Object?> json) => CoverOptions(
    template: CoverTemplate.fromWire(json['template'] as String? ?? ''),
    palette: json['palette'] as String? ?? 'sea',
    titleScale: (json['titleScale'] as num?)?.toDouble() ?? 1,
    authorPosition: AuthorPosition.fromWire(
      json['authorPosition'] as String? ?? '',
    ),
  );
}

enum CoverTemplate {
  vertical('vertical'),
  blocks('blocks');

  const CoverTemplate(this.wire);

  final String wire;

  static CoverTemplate fromWire(String value) => CoverTemplate.values
      .firstWhere((CoverTemplate t) => t.wire == value, orElse: () => vertical);
}

enum AuthorPosition {
  top('top'),
  bottom('bottom');

  const AuthorPosition(this.wire);

  final String wire;

  static AuthorPosition fromWire(String value) => AuthorPosition.values
      .firstWhere((AuthorPosition p) => p.wire == value, orElse: () => bottom);
}
