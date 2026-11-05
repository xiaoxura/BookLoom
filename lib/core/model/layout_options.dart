/// Typographic parameters for rendering and export.
class LayoutOptions {
  LayoutOptions({
    double lineHeight = 1.75,
    this.indent = true,
    double paragraphSpacing = 0,
    this.font = LayoutFont.serif,
    this.justify = true,
    this.separateChapterNumber = false,
    String customCss = '',
    this.embeddedFontAssetId,
  }) : lineHeight = _clamp(lineHeight, 1.3, 2.4, 1.75),
       paragraphSpacing = _clamp(paragraphSpacing, 0, 1, 0),
       customCss = _validatedCss(customCss);

  final double lineHeight;
  final bool indent;

  /// Paragraph spacing in em.
  final double paragraphSpacing;
  final LayoutFont font;
  final bool justify;
  final bool separateChapterNumber;

  /// Appended to EPUB/HTML exports, never executed by the native preview.
  final String customCss;
  final String? embeddedFontAssetId;

  LayoutOptions copyWith({
    double? lineHeight,
    bool? indent,
    double? paragraphSpacing,
    LayoutFont? font,
    bool? justify,
    bool? separateChapterNumber,
    String? customCss,
    String? embeddedFontAssetId,
    bool clearEmbeddedFontAssetId = false,
  }) => LayoutOptions(
    lineHeight: lineHeight ?? this.lineHeight,
    indent: indent ?? this.indent,
    paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
    font: font ?? this.font,
    justify: justify ?? this.justify,
    separateChapterNumber: separateChapterNumber ?? this.separateChapterNumber,
    customCss: customCss ?? this.customCss,
    embeddedFontAssetId: clearEmbeddedFontAssetId
        ? null
        : (embeddedFontAssetId ?? this.embeddedFontAssetId),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'lineHeight': lineHeight,
    'indent': indent,
    'paragraphSpacing': paragraphSpacing,
    'font': font.wire,
    'justify': justify,
    'separateChapterNumber': separateChapterNumber,
    'customCss': customCss,
    'embeddedFontAssetId': embeddedFontAssetId,
  };

  static LayoutOptions fromJson(Map<String, Object?> json) => LayoutOptions(
    lineHeight: json['lineHeight'] is num
        ? (json['lineHeight']! as num).toDouble()
        : 1.75,
    indent: json['indent'] is bool ? json['indent']! as bool : true,
    paragraphSpacing: json['paragraphSpacing'] is num
        ? (json['paragraphSpacing']! as num).toDouble()
        : 0,
    font: LayoutFont.fromWire(
      json['font'] is String ? json['font']! as String : '',
    ),
    justify: json['justify'] is bool ? json['justify']! as bool : true,
    separateChapterNumber: json['separateChapterNumber'] is bool
        ? json['separateChapterNumber']! as bool
        : false,
    customCss: json['customCss'] is String ? json['customCss']! as String : '',
    embeddedFontAssetId: json['embeddedFontAssetId'] is String
        ? json['embeddedFontAssetId']! as String
        : null,
  );

  static double _clamp(double value, double min, double max, double fallback) =>
      value.isFinite ? value.clamp(min, max).toDouble() : fallback;

  static String _validatedCss(String value) {
    // CSS escapes can disguise function names such as url(), while '<' can
    // break out of an HTML style element in single-file export.
    if (value.codeUnits.contains(0x5c) ||
        value.contains('<') ||
        value.contains('>') ||
        RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value)) {
      throw ArgumentError.value(value, 'customCss', 'Unsafe CSS characters');
    }
    final String withoutComments = value.replaceAll(
      RegExp(r'/\*[\s\S]*?\*/'),
      '',
    );
    if (value.length > 20000 ||
        RegExp(
          r'@import\b|url\s*\(|image-set\s*\(|expression\s*\(|'
          r'-moz-binding\s*:|(?:https?|file|data|javascript)\s*:|//',
          caseSensitive: false,
        ).hasMatch(withoutComments)) {
      throw ArgumentError.value(
        value,
        'customCss',
        'External resources and executable CSS are not allowed',
      );
    }
    return value;
  }
}

enum LayoutFont {
  serif('serif'),
  sans('sans'),
  kai('kai');

  const LayoutFont(this.wire);
  final String wire;

  static LayoutFont fromWire(String value) => LayoutFont.values.firstWhere(
    (LayoutFont font) => font.wire == value,
    orElse: () => serif,
  );
}
