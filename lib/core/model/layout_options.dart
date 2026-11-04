import 'package:flutter/foundation.dart';

/// Typographic parameters for rendering and export. Stored as
/// `books.layout_json`; missing fields fall back to defaults.
@immutable
class LayoutOptions {
  const LayoutOptions({
    this.lineHeight = 1.75,
    this.indent = true,
    this.paragraphSpacing = 0,
    this.font = LayoutFont.serif,
    this.justify = true,
    this.separateChapterNumber = false,
  });

  final double lineHeight;
  final bool indent;
  final double paragraphSpacing;
  final LayoutFont font;
  final bool justify;
  final bool separateChapterNumber;

  LayoutOptions copyWith({
    double? lineHeight,
    bool? indent,
    double? paragraphSpacing,
    LayoutFont? font,
    bool? justify,
    bool? separateChapterNumber,
  }) => LayoutOptions(
    lineHeight: lineHeight ?? this.lineHeight,
    indent: indent ?? this.indent,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    font: font ?? this.font,
    justify: justify ?? this.justify,
    separateChapterNumber: separateChapterNumber ?? this.separateChapterNumber,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'lineHeight': lineHeight,
    'indent': indent,
    'paragraphSpacing': paragraphSpacing,
    'font': font.wire,
    'justify': justify,
    'separateChapterNumber': separateChapterNumber,
  };

  static LayoutOptions fromJson(Map<String, Object?> json) => LayoutOptions(
    lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.75,
    indent: json['indent'] as bool? ?? true,
    paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble() ?? 0,
    font: LayoutFont.fromWire(json['font'] as String? ?? ''),
    justify: json['justify'] as bool? ?? true,
    separateChapterNumber: json['separateChapterNumber'] as bool? ?? false,
  );
}

enum LayoutFont {
  serif('serif'),
  sans('sans');

  const LayoutFont(this.wire);

  final String wire;

  static LayoutFont fromWire(String value) => LayoutFont.values.firstWhere(
    (LayoutFont f) => f.wire == value,
    orElse: () => serif,
  );
}
