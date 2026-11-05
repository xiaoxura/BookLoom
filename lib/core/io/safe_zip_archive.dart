import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:crypto/crypto.dart' as crypto;
import 'package:xml/xml.dart';

import '../errors/app_failure.dart';
import 'input_limits.dart';
import 'safe_xml.dart';

/// An indexed ZIP entry. The size is a claim until extraction succeeds.
class SafeZipEntry {
  const SafeZipEntry(this.name, this.declaredSize, this.isDirectory);

  final String name;
  final int declaredSize;
  final bool isDirectory;
}

class ExtractedEntry {
  const ExtractedEntry(this.bytesWritten, this.sha256);

  final int bytesWritten;
  final String sha256;
}

/// Reads ZIP metadata from a file without loading the whole container.
///
/// Each requested entry is decompressed into a bounded output stream. The
/// caller owns the archive and must close it after use. Extraction is meant
/// for a private staging directory; target files must not already exist.
class SafeZipArchive {
  SafeZipArchive._(
    this._input,
    this.limits,
    List<SafeZipEntry> entries,
    this._headers,
  ) : entries = List.unmodifiable(entries),
      _entriesByName = {for (final entry in entries) entry.name: entry};

  final archive.InputFileStream _input;
  final InputLimits limits;
  final List<SafeZipEntry> entries;
  final Map<String, archive.ZipFileHeader> _headers;
  final Map<String, SafeZipEntry> _entriesByName;
  int _actualOutputBytes = 0;
  bool _closed = false;

  int get actualOutputBytes => _actualOutputBytes;

  static SafeZipArchive open(String path, {required InputLimits limits}) {
    if (limits.maxEntries <= 0 ||
        limits.maxOutputBytes <= 0 ||
        limits.maxXmlBytes <= 0) {
      throw ArgumentError('ZIP budgets must be positive');
    }
    final archive.InputFileStream input;
    try {
      input = archive.InputFileStream(path);
    } catch (error, stackTrace) {
      throw ImportFailure('无法读取 ZIP 文件。', cause: error, stackTrace: stackTrace);
    }
    try {
      if (limits.maxArchiveBytes case final int maxBytes) {
        if (input.totalLength > maxBytes) {
          throw const ImportFailure('输入文件超过允许大小。');
        }
      }
      final directory = archive.ZipDirectory();
      final headers = <String, archive.ZipFileHeader>{};
      final entries = <SafeZipEntry>[];
      final seen = <String>{};
      var declaredTotal = 0;
      var metadataBytes = 0;
      for (final header in directory.headers(input, verify: true)) {
        if (entries.length >= limits.maxEntries) {
          throw const ImportFailure('压缩包条目数超过允许范围。');
        }
        final name = _safeName(header.filename);
        metadataBytes +=
            header.filename.length * 2 +
            (header.extraField?.length ?? 0) +
            header.fileComment.length * 2 +
            256;
        if (metadataBytes > limits.maxMetadataBytes) {
          throw const ImportFailure('压缩包目录元数据超过允许大小。');
        }
        final type = (header.externalFileAttributes >> 16) & 0xf000;
        if (type != 0 && type != 0x8000 && type != 0x4000) {
          throw const ImportFailure('压缩包包含符号链接或特殊文件。');
        }
        final isDirectory = header.filename.endsWith('/') || type == 0x4000;
        final key = name.toLowerCase();
        if (!seen.add(key)) {
          throw const ImportFailure('压缩包包含重复路径。');
        }
        if ((header.generalPurposeBitFlag & 1) != 0 ||
            header.compressionMethod == 99 ||
            (header.compressionMethod != 0 && header.compressionMethod != 8)) {
          throw const ImportFailure('压缩包包含不支持的加密或压缩条目。');
        }
        if (header.uncompressedSize < 0 || header.compressedSize < 0) {
          throw const ImportFailure('压缩包条目大小无效。');
        }
        final entryMax = limits.entryLimit(name);
        if (entryMax != null && header.uncompressedSize > entryMax) {
          throw const ImportFailure('压缩包单个条目超过允许大小。');
        }
        if (isDirectory && header.uncompressedSize != 0) {
          throw const ImportFailure('压缩包目录条目大小无效。');
        }
        declaredTotal += header.uncompressedSize;
        if (declaredTotal > limits.maxOutputBytes) {
          throw const ImportFailure('压缩包解压总量超过允许范围。');
        }
        headers[name] = header;
        entries.add(SafeZipEntry(name, header.uncompressedSize, isDirectory));
      }
      if (directory.filePosition < 0) {
        throw const ImportFailure('ZIP 目录无效。');
      }
      final files = <String>{
        for (final entry in entries)
          if (!entry.isDirectory) entry.name.toLowerCase(),
      };
      for (final entry in entries) {
        final parts = entry.name.toLowerCase().split('/');
        for (var i = 1; i < parts.length; i++) {
          if (files.contains(parts.take(i).join('/'))) {
            throw const ImportFailure('压缩包路径与文件冲突。');
          }
        }
      }
      return SafeZipArchive._(input, limits, entries, headers);
    } on ImportFailure {
      input.closeSync();
      rethrow;
    } catch (error, stackTrace) {
      input.closeSync();
      throw ImportFailure(
        'ZIP 文件无效或已损坏。',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Extracts one entry to a new file in a caller-owned staging directory.
  /// On failure the partial temporary output is removed.
  ExtractedEntry extractToFile(String name, File target, {int? maxBytes}) {
    _ensureOpen();
    if (maxBytes != null && maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }
    final header = _fileHeader(name);
    if (maxBytes != null && header.uncompressedSize > maxBytes) {
      throw const ImportFailure('压缩包单个条目超过允许大小。');
    }
    if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const ImportFailure('解压目标已存在。');
    }
    final temporaryDirectory = target.parent.createTempSync('.bookloom-zip-');
    final temporary = File('${temporaryDirectory.path}/entry');
    try {
      final output = archive.OutputFileStream(
        temporary.path,
        bufferSize: 64 * 1024,
      );
      late ExtractedEntry result;
      try {
        result = _extract(header, output, maxBytes: maxBytes);
      } finally {
        output.closeSync();
      }
      if (FileSystemEntity.typeSync(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const ImportFailure('解压目标已存在。');
      }
      temporary.renameSync(target.path);
      _actualOutputBytes += result.bytesWritten;
      return result;
    } finally {
      if (temporary.existsSync()) temporary.deleteSync();
      temporaryDirectory.deleteSync();
    }
  }

  /// Memory reads are restricted to a single XML entry under maxXmlBytes.
  Uint8List readXmlBytes(String name) {
    _ensureOpen();
    if (!_isXmlName(name)) {
      throw const ImportFailure('仅允许将受限 XML 条目读入内存。');
    }
    final header = _fileHeader(name);
    if (header.uncompressedSize > limits.maxXmlBytes) {
      throw const ImportFailure('XML 内容超过允许大小。');
    }
    final output = archive.OutputMemoryStream();
    final result = _extract(header, output, maxBytes: limits.maxXmlBytes);
    final bytes = output.getBytes();
    _actualOutputBytes += result.bytesWritten;
    return bytes;
  }

  /// Parses a bounded XML entry after rejecting DTD and external entities.
  XmlDocument readXml(String name) {
    final bytes = readXmlBytes(name);
    try {
      return safeXml(_decodeXml(bytes), limits: limits);
    } on FormatException catch (error, stackTrace) {
      throw ImportFailure('XML 编码无效。', cause: error, stackTrace: stackTrace);
    }
  }

  ExtractedEntry _extract(
    archive.ZipFileHeader header,
    archive.OutputStream output, {
    int? maxBytes,
  }) {
    final remaining = limits.maxOutputBytes - _actualOutputBytes;
    final entryLimit = limits.entryLimit(_safeName(header.filename));
    var maximum = remaining;
    if (entryLimit != null && entryLimit < maximum) maximum = entryLimit;
    if (maxBytes != null && maxBytes < maximum) maximum = maxBytes;
    if (maximum < 0 || header.uncompressedSize > maximum) {
      throw const ImportFailure('压缩包解压预算不足。');
    }
    try {
      final zipFile = header.file;
      if (zipFile == null) {
        throw const ImportFailure('压缩包条目无效。');
      }
      zipFile
        ..verify = true
        ..throwOnError = true;
      final bounded = _BoundedOutput(output, maximum);
      zipFile.decompress(bounded);
      bounded.flush();
      if (bounded.length != header.uncompressedSize ||
          bounded.crc32 != header.crc32) {
        throw const ImportFailure('压缩包条目大小或校验和不匹配。');
      }
      return ExtractedEntry(bounded.length, bounded.sha256);
    } on ImportFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw ImportFailure(
        '压缩包条目损坏或超出预算。',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  archive.ZipFileHeader _fileHeader(String name) {
    final header = _headers[name];
    if (header == null || _entriesByName[name]?.isDirectory != false) {
      throw const ImportFailure('压缩包中没有该文件。');
    }
    return header;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('SafeZipArchive is closed');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _input.closeSync();
  }

  static bool _isXmlName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.xml') ||
        lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm') ||
        lower.endsWith('.opf') ||
        lower.endsWith('.ncx') ||
        lower.endsWith('.rels') ||
        lower.endsWith('.svg');
  }

  static String _decodeXml(Uint8List bytes) {
    String source;
    String detectedEncoding;
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) {
        throw const FormatException('Odd UTF-16 XML byte count');
      }
      final littleEndian = bytes[0] == 0xff;
      detectedEncoding = littleEndian ? 'utf-16le' : 'utf-16be';
      final units = <int>[];
      for (var i = 2; i < bytes.length; i += 2) {
        units.add(
          littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
        );
      }
      source = String.fromCharCodes(units);
    } else {
      detectedEncoding = 'utf-8';
      final offset =
          bytes.length >= 3 &&
              bytes[0] == 0xef &&
              bytes[1] == 0xbb &&
              bytes[2] == 0xbf
          ? 3
          : 0;
      source = utf8.decode(
        Uint8List.sublistView(bytes, offset),
        allowMalformed: false,
      );
    }
    _validateXmlEncoding(source, detectedEncoding);
    return source;
  }

  static void _validateXmlEncoding(String source, String detectedEncoding) {
    if (source.contains('\u0000')) {
      throw const FormatException('NUL in XML');
    }
    if (!RegExp(r'^<\?xml\s').hasMatch(source)) return;
    final end = source.indexOf('?>');
    if (end < 0 || end > 512) {
      throw const FormatException('XML declaration is too long or incomplete');
    }
    final declaration = source.substring(0, end);
    final match = RegExp(
      r'''\bencoding\s*=\s*(['"])([^'"]+)\1''',
      caseSensitive: false,
    ).firstMatch(declaration);
    if (match == null) return;
    final declared = match.group(2)!.toLowerCase();
    final matches =
        declared == detectedEncoding ||
        (declared == 'utf-16' && detectedEncoding.startsWith('utf-16'));
    if (!matches) {
      throw const FormatException('Unsupported or conflicting XML encoding');
    }
  }

  static String _safeName(String raw) {
    if (raw.isEmpty ||
        raw.length > 1024 ||
        raw.startsWith('/') ||
        raw.contains('\\') ||
        raw.contains(':') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(raw)) {
      throw const ImportFailure('压缩包包含不安全路径。');
    }
    final name = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    final parts = name.split('/');
    if (parts.any(
      (part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.endsWith('.') ||
          part.endsWith(' ') ||
          RegExp(
            r'^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
            caseSensitive: false,
          ).hasMatch(part),
    )) {
      throw const ImportFailure('压缩包包含不安全路径。');
    }
    return name;
  }
}

class _BoundedOutput extends archive.OutputStream {
  _BoundedOutput(this.output, this.maximum)
    : super(byteOrder: output.byteOrder) {
    _sha = crypto.sha256.startChunkedConversion(_digest);
  }

  final archive.OutputStream output;
  final int maximum;
  int _length = 0;
  int crc32 = 0;
  final _DigestSink _digest = _DigestSink();
  late final ByteConversionSink _sha;

  String get sha256 {
    _sha.close();
    return _digest.value!.toString();
  }

  @override
  int get length => _length;

  void _write(List<int> bytes) {
    if (bytes.length > maximum - _length) {
      throw const ImportFailure('压缩包条目实际解压大小超过预算。');
    }
    output.writeBytes(bytes);
    crc32 = archive.getCrc32(bytes, crc32);
    _sha.add(bytes);
    _length += bytes.length;
  }

  @override
  void writeByte(int value) => _write([value]);

  @override
  void writeBytes(List<int> bytes, {int? length}) =>
      _write(length == null ? bytes : bytes.sublist(0, length));

  @override
  void writeRange(Uint8List bytes, int start, int end) =>
      _write(Uint8List.sublistView(bytes, start, end));

  @override
  void writeStream(archive.InputStream stream) {
    final chunk = Uint8List(64 * 1024);
    final position = stream.position;
    try {
      while (!stream.isEOS) {
        final read = stream.readInto(chunk, 0, chunk.length);
        if (read <= 0) break;
        writeRange(chunk, 0, read);
      }
    } finally {
      stream.setPosition(position);
    }
  }

  @override
  void writeBackReference(int distance, int count) =>
      throw const ImportFailure('不支持该压缩条目的输出方式。');

  @override
  Uint8List subset(int start, [int? end]) =>
      throw const ImportFailure('不支持回读解压输出。');

  @override
  void flush() => output.flush();

  @override
  void clear() => output.clear();
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}
