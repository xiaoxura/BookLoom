/// Last successfully applied settings for parsing a book's source file.
class ParseOptions {
  const ParseOptions({
    this.encoding = 'auto',
    this.filterAds = true,
    this.rulePreset = 'auto',
    this.ruleSpec,
    this.convertMode = ConvertMode.none,
  });

  final String encoding;
  final bool filterAds;
  final String rulePreset;
  final Map<String, Object?>? ruleSpec;
  final ConvertMode convertMode;

  /// Value equality across all fields, including a deep compare of the
  /// optional rule JSON. Used to ignore no-op option changes so a re-selected
  /// dropdown value never triggers a needless re-parse.
  bool sameAs(ParseOptions other) =>
      encoding == other.encoding &&
      filterAds == other.filterAds &&
      rulePreset == other.rulePreset &&
      convertMode == other.convertMode &&
      _sameJson(ruleSpec, other.ruleSpec);

  ParseOptions copyWith({
    String? encoding,
    bool? filterAds,
    String? rulePreset,
    Map<String, Object?>? ruleSpec,
    bool clearRuleSpec = false,
    ConvertMode? convertMode,
  }) => ParseOptions(
    encoding: encoding ?? this.encoding,
    filterAds: filterAds ?? this.filterAds,
    rulePreset: rulePreset ?? this.rulePreset,
    ruleSpec: clearRuleSpec ? null : (ruleSpec ?? this.ruleSpec),
    convertMode: convertMode ?? this.convertMode,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'encoding': encoding,
    'filterAds': filterAds,
    'rulePreset': rulePreset,
    'ruleSpec': ruleSpec,
    'convertMode': convertMode.wire,
  };

  static ParseOptions fromJson(Map<String, Object?> json) => ParseOptions(
    encoding: _safeName(json['encoding'], 'auto', 64),
    filterAds: json['filterAds'] is bool ? json['filterAds']! as bool : true,
    rulePreset: _safeName(json['rulePreset'], 'auto', 128),
    ruleSpec: _safeRuleSpec(json['ruleSpec']),
    convertMode: ConvertMode.fromWire(
      json['convertMode'] is String ? json['convertMode']! as String : '',
    ),
  );

  static String _safeName(Object? value, String fallback, int maxLength) {
    if (value is! String) return fallback;
    final String name = value.trim();
    return name.isNotEmpty && name.length <= maxLength ? name : fallback;
  }

  static Map<String, Object?>? _safeRuleSpec(Object? value) {
    if (value is! Map<String, Object?> || !_isJsonValue(value)) return null;
    return Map<String, Object?>.unmodifiable(value);
  }

  static bool _sameJson(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map<String, Object?> && b is Map<String, Object?>) {
      return a.length == b.length &&
          a.entries.every(
            (entry) =>
                b.containsKey(entry.key) &&
                _sameJson(entry.value, b[entry.key]),
          );
    }
    if (a is List<Object?> && b is List<Object?>) {
      return a.length == b.length &&
          a.indexed.every((e) => _sameJson(e.$2, b[e.$1]));
    }
    return a == b;
  }

  static bool _isJsonValue(Object? value) {
    if (value == null || value is String || value is bool) return true;
    if (value is num) return value.isFinite;
    if (value is List<Object?>) return value.every(_isJsonValue);
    if (value is Map<String, Object?>) {
      return value.values.every(_isJsonValue);
    }
    return false;
  }
}

enum ConvertMode {
  none('none'),
  simplified('simplified'),
  taiwan('taiwan');

  const ConvertMode(this.wire);
  final String wire;

  static ConvertMode fromWire(String value) => ConvertMode.values.firstWhere(
    (ConvertMode mode) => mode.wire == value,
    orElse: () => none,
  );
}
