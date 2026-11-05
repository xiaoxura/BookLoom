import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';

/// Parsed content held temporarily until import validation and commit succeed.
class ParseResult {
  const ParseResult({
    required this.format,
    required this.suggestedMeta,
    required this.chapters,
    this.actualEncoding,
    this.encodingConfidence,
    this.coverAssetId,
    this.warnings = const <ParseWarning>[],
    this.sourceLocations = const <String, ParseSourceLocation>{},
  });

  final ImportFormat format;
  final String? actualEncoding;

  /// A value from zero to one when encoding detection was needed.
  final double? encodingConfidence;
  final BookMeta suggestedMeta;
  final List<Chapter> chapters;
  final String? coverAssetId;
  final List<ParseWarning> warnings;

  /// Chapter or block ID to location in the original source.
  final Map<String, ParseSourceLocation> sourceLocations;
}

enum ImportFormat {
  txt('txt'),
  epub('epub'),
  docx('docx');

  const ImportFormat(this.wire);
  final String wire;

  static ImportFormat fromWire(String value) => ImportFormat.values.firstWhere(
    (ImportFormat format) => format.wire == value,
    orElse: () => txt,
  );
}

class ParseWarning {
  const ParseWarning({
    required this.code,
    required this.message,
    this.chapterId,
    this.blockId,
    this.sourcePath,
    this.line,
  });

  final String code;
  final String message;
  final String? chapterId;
  final String? blockId;
  final String? sourcePath;
  final int? line;
}

class ParseSourceLocation {
  const ParseSourceLocation({this.sourcePath, this.line, this.column});

  final String? sourcePath;
  final int? line;
  final int? column;
}
