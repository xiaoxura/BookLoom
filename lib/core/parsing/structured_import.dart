import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/app_failure.dart';
import '../io/input_limits.dart';
import '../io/safe_zip_archive.dart';
import '../model/parse_options.dart';
import '../model/parse_result.dart';
import 'docx_parser.dart';
import 'epub_parser.dart';

class StagedCover {
  const StagedCover({
    required this.file,
    required this.mime,
    required this.bytes,
    required this.sha256,
    required this.width,
    required this.height,
  });

  final File file;
  final String mime;
  final int bytes;
  final String sha256;
  final int width;
  final int height;
}

class StructuredImport {
  const StructuredImport({required this.result, this.cover});

  final ParseResult result;
  final StagedCover? cover;
}

/// The caller owns [temporaryDirectory] and its lifecycle. This Future-shaped
/// entry point is convenient outside a worker; use [parseStructuredFileSync]
/// inside BackgroundJobs so the caller can cancel the owning isolate.
Future<StructuredImport> parseStructuredFile(
  String path, {
  required String bookId,
  required String filename,
  required Directory temporaryDirectory,
  ParseOptions options = const ParseOptions(),
}) async => parseStructuredFileSync(
  path,
  bookId: bookId,
  filename: filename,
  temporaryDirectory: temporaryDirectory,
  options: options,
);

StructuredImport parseStructuredFileSync(
  String path, {
  required String bookId,
  required String filename,
  required Directory temporaryDirectory,
  ParseOptions options = const ParseOptions(),
}) {
  if (options.encoding != 'auto') {
    throw const ImportFailure('EPUB 和 DOCX 不使用 TXT 编码重识别。');
  }
  if (options.ruleSpec != null ||
      options.rulePreset != 'auto' ||
      options.convertMode != ConvertMode.none) {
    throw const ImportFailure('当前无法应用所选规则或简繁转换，请先按原样导入。');
  }
  final extension = p.extension(filename).toLowerCase();
  if (extension != '.epub' && extension != '.docx') {
    throw const ImportFailure('请选择 EPUB 或 DOCX 文件。');
  }
  final zip = SafeZipArchive.open(
    path,
    limits: ImportLimits(isAndroid: Platform.isAndroid),
  );
  try {
    final parsed = extension == '.epub'
        ? parseEpubZip(zip, bookId: bookId, filename: filename)
        : parseDocxZip(zip, bookId: bookId, filename: filename);
    StagedCover? cover;
    if (parsed.coverEntryPath != null) {
      cover = _stageCover(zip, parsed.coverEntryPath!, temporaryDirectory);
    }
    return StructuredImport(result: parsed.result, cover: cover);
  } finally {
    zip.close();
  }
}

/// Shared return from format parsers; cover is only a ZIP entry suggestion.
class ParsedStructure {
  const ParsedStructure(this.result, {this.coverEntryPath});

  final ParseResult result;
  final String? coverEntryPath;
}

StagedCover _stageCover(
  SafeZipArchive zip,
  String entryPath,
  Directory temporaryDirectory,
) {
  if (!temporaryDirectory.existsSync()) {
    throw const ImportFailure('导入暂存目录不可用。');
  }
  final staged = File(p.join(temporaryDirectory.path, 'suggested-cover'));
  final extracted = zip.extractToFile(
    entryPath,
    staged,
    maxBytes: ImportLimits.maxEncodedCoverBytes,
  );
  try {
    final header = staged.openSync();
    late final List<int> prefix;
    try {
      prefix = header.readSync(512 * 1024);
    } finally {
      header.closeSync();
    }
    final image = _imageHeader(prefix);
    if (image == null ||
        image.width <= 0 ||
        image.height <= 0 ||
        image.width * image.height > ImportLimits.maxCoverPixels) {
      throw const ImportFailure('封面格式或像素尺寸超出支持范围。');
    }
    return StagedCover(
      file: staged,
      mime: image.mime,
      bytes: extracted.bytesWritten,
      sha256: extracted.sha256,
      width: image.width,
      height: image.height,
    );
  } catch (_) {
    if (staged.existsSync()) staged.deleteSync();
    rethrow;
  }
}

({String mime, int width, int height})? _imageHeader(List<int> b) {
  if (b.length >= 24 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4e &&
      b[3] == 0x47 &&
      b[4] == 0x0d &&
      b[5] == 0x0a &&
      b[6] == 0x1a &&
      b[7] == 0x0a &&
      b[12] == 0x49 &&
      b[13] == 0x48 &&
      b[14] == 0x44 &&
      b[15] == 0x52) {
    int be32(int i) =>
        (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    return (mime: 'image/png', width: be32(16), height: be32(20));
  }
  if (b.length >= 10 &&
      b[0] == 0x47 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x38 &&
      (b[4] == 0x37 || b[4] == 0x39) &&
      b[5] == 0x61) {
    return (
      mime: 'image/gif',
      width: b[6] | (b[7] << 8),
      height: b[8] | (b[9] << 8),
    );
  }
  if (b.length >= 30 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50) {
    if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x58) {
      final width = 1 + b[24] + (b[25] << 8) + (b[26] << 16);
      final height = 1 + b[27] + (b[28] << 8) + (b[29] << 16);
      return (mime: 'image/webp', width: width, height: height);
    }
    if (b[12] == 0x56 && b[13] == 0x50 && b[14] == 0x38 && b[15] == 0x4c) {
      final width = 1 + (b[21] | ((b[22] & 0x3f) << 8));
      final height = 1 + ((b[22] >> 6) | (b[23] << 2) | ((b[24] & 0xf) << 10));
      return (mime: 'image/webp', width: width, height: height);
    }
    if (b[12] == 0x56 &&
        b[13] == 0x50 &&
        b[14] == 0x38 &&
        b[15] == 0x20 &&
        b[23] == 0x9d &&
        b[24] == 0x01 &&
        b[25] == 0x2a) {
      return (
        mime: 'image/webp',
        width: (b[26] | (b[27] << 8)) & 0x3fff,
        height: (b[28] | (b[29] << 8)) & 0x3fff,
      );
    }
  }
  if (b.length >= 4 && b[0] == 0xff && b[1] == 0xd8) {
    var at = 2;
    while (at + 9 < b.length) {
      if (b[at] != 0xff) break;
      while (at < b.length && b[at] == 0xff) {
        at++;
      }
      if (at >= b.length) break;
      final marker = b[at++];
      if (marker == 0xd9 || marker == 0xda) break;
      if (at + 2 > b.length) break;
      final length = (b[at] << 8) | b[at + 1];
      if (length < 2 || at + length > b.length) break;
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb)) {
        if (length < 7) break;
        return (
          mime: 'image/jpeg',
          width: (b[at + 5] << 8) | b[at + 6],
          height: (b[at + 3] << 8) | b[at + 4],
        );
      }
      at += length;
    }
  }
  return null;
}
