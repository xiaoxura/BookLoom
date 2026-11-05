import 'dart:convert';

import 'package:path/path.dart' as p;

/// One place for names shown to native save dialogs and used by batch export.
abstract final class FileNames {
  static const int _maxBytes = 240;
  static final RegExp _invalid = RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]');
  static final RegExp _reserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])$',
    caseSensitive: false,
  );

  /// Removes path components and characters illegal on Windows too.
  static String sanitize(String suggested) {
    final String leaf = suggested.split(RegExp(r'[/\\]')).last;
    String name = leaf.replaceAll(_invalid, '_').trim();
    name = name.replaceFirst(RegExp(r'[. ]+$'), '');
    if (name.isEmpty || name == '.' || name == '..') return 'bookloom';

    final String extension = p.extension(name);
    String stem = extension.isEmpty
        ? name
        : name.substring(0, name.length - extension.length);
    final String normalizedStem = stem.replaceFirst(RegExp(r'[. ]+$'), '');
    if (_reserved.hasMatch(normalizedStem)) stem = '${normalizedStem}_';
    final String safeExtension = _truncate(extension, _maxBytes ~/ 2);
    stem = _truncate(stem, _maxBytes - utf8.encode(safeExtension).length);
    return '$stem$safeExtension';
  }

  /// Returns a suffix name without colliding even on case-insensitive volumes.
  static String unique(String suggested, Iterable<String> existingNames) {
    final String safe = sanitize(suggested);
    final Set<String> used = {
      for (final String name in existingNames) name.toLowerCase(),
    };
    if (!used.contains(safe.toLowerCase())) return safe;

    final String extension = p.extension(safe);
    final String stem = safe.substring(0, safe.length - extension.length);
    for (int sequence = 2; ; sequence++) {
      final String suffix = ' ($sequence)';
      final String trimmedStem = _truncate(
        stem,
        _maxBytes - utf8.encode('$suffix$extension').length,
      );
      final String candidate = '$trimmedStem$suffix$extension';
      if (!used.contains(candidate.toLowerCase())) return candidate;
    }
  }

  static String _truncate(String value, int maxBytes) {
    final StringBuffer result = StringBuffer();
    int size = 0;
    for (final int rune in value.runes) {
      final String char = String.fromCharCode(rune);
      final int charBytes = utf8.encode(char).length;
      if (size + charBytes > maxBytes) break;
      result.write(char);
      size += charBytes;
    }
    return result.toString();
  }
}
