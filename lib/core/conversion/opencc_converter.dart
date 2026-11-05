import 'package:bookloom/core/model/parse_options.dart';

/// Offline OpenCC ver.1.4.2 t2s / s2twp conversion over bundled text lexicons.
///
/// The caller loads [requiredDictionaryFiles] from [assetPrefix] and may build
/// this object inside a background isolate. No Flutter or file access is needed
/// by the conversion algorithm.
class OpenCcConverter {
  OpenCcConverter._({
    required this._normalization,
    required this._tsPhrases,
    required this._tsCharactersExt,
    required this._tsCharacters,
    required this._stPhrases,
    required this._stCharacters,
    required this._twPhrases,
    required this._twVariantsPhrases,
    required this._twVariants,
  });

  static const String assetPrefix = 'assets/opencc/';

  static const List<String> requiredDictionaryFiles = <String>[
    'CJK_Compatibility_Ideographs.txt',
    'TSPhrases.txt',
    'TSCharactersExt.txt',
    'TSCharacters.txt',
    'STPhrases.txt',
    'STPhrases_GeneratedFromRegionalPhrases.txt',
    'STCharacters.txt',
    'TWPhrases.txt',
    'TWVariantsPhrases.txt',
    'TWVariants.txt',
  ];

  final _Trie _normalization;
  final _Trie _tsPhrases;
  final _Trie _tsCharactersExt;
  final _Trie _tsCharacters;
  final _Trie _stPhrases;
  final _Trie _stCharacters;
  final _Trie _twPhrases;
  final _Trie _twVariantsPhrases;
  final _Trie _twVariants;

  /// Build the official dictionary chain from UTF-8 decoded text resources.
  ///
  /// Keys are bare filenames from [requiredDictionaryFiles]. The first
  /// candidate of an OpenCC multi-value entry is its default conversion.
  factory OpenCcConverter.loadData(Map<String, String> dictionaries) {
    final Map<String, Map<String, String>> parsed =
        <String, Map<String, String>>{};
    for (final String file in requiredDictionaryFiles) {
      final String? contents = dictionaries[file];
      if (contents == null) {
        throw FormatException('Missing OpenCC dictionary: $file');
      }
      parsed[file] = _parseDictionary(file, contents);
    }

    _Trie trie(String file) => _Trie.fromEntries(parsed[file]!);
    final _Trie stPhrases = trie('STPhrases.txt')
      ..addEntries(parsed['STPhrases_GeneratedFromRegionalPhrases.txt']!);
    return OpenCcConverter._(
      normalization: trie('CJK_Compatibility_Ideographs.txt'),
      tsPhrases: trie('TSPhrases.txt'),
      tsCharactersExt: trie('TSCharactersExt.txt'),
      tsCharacters: trie('TSCharacters.txt'),
      stPhrases: stPhrases,
      stCharacters: trie('STCharacters.txt'),
      twPhrases: trie('TWPhrases.txt'),
      twVariantsPhrases: trie('TWVariantsPhrases.txt'),
      twVariants: trie('TWVariants.txt'),
    );
  }

  String convertText(String text, ConvertMode mode) {
    if (mode == ConvertMode.none || text.isEmpty) return text;
    final String normalized = _convertWithPriority(text, <_Trie>[
      _normalization,
    ]);
    if (mode == ConvertMode.simplified) {
      // t2s.json: TSPhrases -> TSCharactersExt -> TSCharacters.
      return _convertWithPriority(normalized, <_Trie>[
        _tsPhrases,
        _tsCharactersExt,
        _tsCharacters,
      ]);
    }

    // s2twp.json uses mmseg over the union of STPhrases and generated
    // regional keys. Conversion stages run within each resulting segment,
    // so Taiwan phrase matching cannot cross its segmentation boundaries.
    final StringBuffer result = StringBuffer();
    var cursor = 0;
    var unmatchedStart = 0;
    while (cursor < normalized.length) {
      final _Match? phrase = _stPhrases.longestAt(normalized, cursor);
      if (phrase == null) {
        cursor += _unmatchedWidth(normalized, cursor);
        continue;
      }
      if (unmatchedStart < cursor) {
        result.write(
          _convertTaiwanSegment(normalized.substring(unmatchedStart, cursor)),
        );
      }
      result.write(
        _convertTaiwanSegment(
          normalized.substring(cursor, cursor + phrase.length),
        ),
      );
      cursor += phrase.length;
      unmatchedStart = cursor;
    }
    if (unmatchedStart < normalized.length) {
      result.write(_convertTaiwanSegment(normalized.substring(unmatchedStart)));
    }
    return result.toString();
  }

  String _convertTaiwanSegment(String segment) {
    final String traditional = _convertWithPriority(segment, <_Trie>[
      _stPhrases,
      _stCharacters,
    ]);
    return _convertWithPriority(traditional, <_Trie>[
      _twPhrases,
      _twVariantsPhrases,
      _twVariants,
    ]);
  }

  static String _convertWithPriority(String text, List<_Trie> dictionaries) {
    final StringBuffer result = StringBuffer();
    var cursor = 0;
    while (cursor < text.length) {
      _Match? matched;
      for (final _Trie dictionary in dictionaries) {
        matched = dictionary.longestAt(text, cursor);
        if (matched != null) break;
      }
      if (matched == null) {
        final int width = _unmatchedWidth(text, cursor);
        result.write(text.substring(cursor, cursor + width));
        cursor += width;
      } else {
        result.write(matched.value);
        cursor += matched.length;
      }
    }
    return result.toString();
  }

  static int _runeWidth(String text, int index) {
    final int first = text.codeUnitAt(index);
    if (first >= 0xD800 && first <= 0xDBFF && index + 1 < text.length) {
      final int second = text.codeUnitAt(index + 1);
      if (second >= 0xDC00 && second <= 0xDFFF) return 2;
    }
    return 1;
  }

  // OpenCC treats a complete ideographic description sequence as one
  // unmatched unit. Its components must not be converted independently.
  static int _unmatchedWidth(String text, int index) {
    final int idsWidth = _ideographicDescriptionWidth(text, index);
    return idsWidth == 0 ? _runeWidth(text, index) : idsWidth;
  }

  static int _ideographicDescriptionWidth(String text, int index) {
    if (_idsArity(_codePointAt(text, index)) == 0) return 0;
    final _IdsCursor cursor = _IdsCursor(index);
    if (!_consumeIds(text, cursor, 16)) return 0;
    return cursor.index - index;
  }

  static bool _consumeIds(String text, _IdsCursor cursor, int depthLeft) {
    if (cursor.index >= text.length || depthLeft == 0 || cursor.count >= 64) {
      return false;
    }
    final int codePoint = _codePointAt(text, cursor.index);
    cursor.index += _runeWidth(text, cursor.index);
    cursor.count++;
    final int arity = _idsArity(codePoint);
    for (var operand = 0; operand < arity; operand++) {
      if (!_consumeIds(text, cursor, depthLeft - 1)) return false;
    }
    return true;
  }

  static int _codePointAt(String text, int index) {
    final int first = text.codeUnitAt(index);
    if (_runeWidth(text, index) == 1) return first;
    final int second = text.codeUnitAt(index + 1);
    return 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
  }

  static int _idsArity(int codePoint) {
    if (codePoint == 0x2FF2 || codePoint == 0x2FF3) return 3;
    if (codePoint == 0x2FFE || codePoint == 0x2FFF) return 1;
    if (codePoint == 0x2FF0 ||
        codePoint == 0x2FF1 ||
        (codePoint >= 0x2FF4 && codePoint <= 0x2FFD)) {
      return 2;
    }
    return 0;
  }

  static Map<String, String> _parseDictionary(String file, String contents) {
    final Map<String, String> entries = <String, String>{};
    for (final String rawLine in contents.split('\n')) {
      final String line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (line.isEmpty || line.startsWith('#')) continue;
      final int separator = line.indexOf('\t');
      if (separator <= 0 || separator == line.length - 1) {
        throw FormatException('Invalid OpenCC entry in $file');
      }
      final String key = line.substring(0, separator);
      final String firstCandidate = line.substring(separator + 1).split(' ')[0];
      if (firstCandidate.isEmpty || entries.containsKey(key)) {
        throw FormatException('Invalid or duplicate OpenCC entry in $file');
      }
      entries[key] = firstCandidate;
    }
    if (entries.isEmpty) {
      throw FormatException('Empty OpenCC dictionary: $file');
    }
    return entries;
  }
}

class _Trie {
  _Trie();

  factory _Trie.fromEntries(Map<String, String> entries) =>
      _Trie()..addEntries(entries);

  final _TrieNode _root = _TrieNode();

  void addEntries(Map<String, String> entries) {
    for (final MapEntry<String, String> entry in entries.entries) {
      _TrieNode node = _root;
      for (final int unit in entry.key.codeUnits) {
        node = node.children.putIfAbsent(unit, _TrieNode.new);
      }
      // Union ties use the first dictionary's value.
      node.value ??= entry.value;
    }
  }

  _Match? longestAt(String text, int start) {
    _TrieNode? node = _root;
    _Match? best;
    for (var cursor = start; cursor < text.length; cursor++) {
      node = node?.children[text.codeUnitAt(cursor)];
      if (node == null) break;
      if (node.value case final String value) {
        best = _Match(cursor - start + 1, value);
      }
    }
    return best;
  }
}

class _TrieNode {
  final Map<int, _TrieNode> children = <int, _TrieNode>{};
  String? value;
}

class _Match {
  const _Match(this.length, this.value);
  final int length;
  final String value;
}

class _IdsCursor {
  _IdsCursor(this.index);
  int index;
  int count = 0;
}
