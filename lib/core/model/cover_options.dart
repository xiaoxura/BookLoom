/// Parameters for a generated cover, independent of the current cover source.
class CoverOptions {
  CoverOptions({
    this.template = CoverTemplate.vertical,
    String palette = 'auto',
    double titleScale = 1,
    this.authorPosition = AuthorPosition.bottom,
  }) : palette = _palettes.contains(palette) ? palette : 'auto',
       titleScale = titleScale.isFinite
           ? ((titleScale.clamp(0.8, 1.3) * 100).round() / 100)
           : 1;

  static const Set<String> _palettes = <String>{
    'auto',
    'sand',
    'ink',
    'sea',
    'wine',
    'forest',
  };

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
    template: CoverTemplate.fromWire(
      json['template'] is String ? json['template']! as String : '',
    ),
    palette: json['palette'] is String ? json['palette']! as String : 'auto',
    titleScale: json['titleScale'] is num
        ? (json['titleScale']! as num).toDouble()
        : 1,
    authorPosition: AuthorPosition.fromWire(
      json['authorPosition'] is String ? json['authorPosition']! as String : '',
    ),
  );
}

enum CoverTemplate {
  vertical('vertical'),
  blocks('blocks');

  const CoverTemplate(this.wire);
  final String wire;

  static CoverTemplate fromWire(String value) {
    if (value == 'block') return blocks;
    return CoverTemplate.values.firstWhere(
      (CoverTemplate template) => template.wire == value,
      orElse: () => vertical,
    );
  }
}

enum AuthorPosition {
  top('top'),
  bottom('bottom'),
  hidden('hidden');

  const AuthorPosition(this.wire);
  final String wire;

  static AuthorPosition fromWire(String value) =>
      AuthorPosition.values.firstWhere(
        (AuthorPosition position) => position.wire == value,
        orElse: () => bottom,
      );
}
