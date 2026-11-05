import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/io/safe_xml.dart';
import 'package:bookloom/core/io/safe_zip_archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('bookloom-io-'));
  tearDown(() => directory.deleteSync(recursive: true));

  File zipOf(Map<String, String> contents) {
    final data = archive.Archive();
    for (final entry in contents.entries) {
      data.add(archive.ArchiveFile.string(entry.key, entry.value));
    }
    final file = File('${directory.path}/input.zip');
    file.writeAsBytesSync(archive.ZipEncoder().encode(data));
    return file;
  }

  File alteredZip(Map<String, String> contents, void Function(Uint8List) edit) {
    final bytes = Uint8List.fromList(zipOf(contents).readAsBytesSync());
    edit(bytes);
    final file = File('${directory.path}/altered.zip');
    file.writeAsBytesSync(bytes);
    return file;
  }

  int centralOffset(Uint8List bytes) {
    for (var i = 0; i <= bytes.length - 4; i++) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x01 &&
          bytes[i + 3] == 0x02) {
        return i;
      }
    }
    throw StateError('central directory missing');
  }

  void uint32(Uint8List bytes, int offset, int value) {
    for (var i = 0; i < 4; i++) {
      bytes[offset + i] = (value >> (8 * i)) & 0xff;
    }
  }

  test('rejects unsafe, normalized duplicate, and colliding ZIP paths', () {
    for (final path in ['../escape', '/absolute', 'C:/drive', 'a/./b']) {
      expect(
        () => SafeZipArchive.open(
          zipOf({path: 'x'}).path,
          limits: const ImportLimits(),
        ),
        throwsA(isA<ImportFailure>()),
        reason: path,
      );
    }
    // ZipEncoder normalizes backslashes, so mutate an otherwise valid ZIP.
    final backslash = alteredZip({'a/b': 'x'}, (bytes) {
      for (var i = 0; i < bytes.length - 2; i++) {
        if (bytes[i] == 0x61 && bytes[i + 1] == 0x2f && bytes[i + 2] == 0x62) {
          bytes[i + 1] = 0x5c;
        }
      }
    });
    expect(
      () => SafeZipArchive.open(backslash.path, limits: const ImportLimits()),
      throwsA(isA<ImportFailure>()),
    );
    expect(
      () => SafeZipArchive.open(
        zipOf({'a': 'one', 'A': 'two'}).path,
        limits: const ImportLimits(),
      ),
      throwsA(isA<ImportFailure>()),
    );
    expect(
      () => SafeZipArchive.open(
        zipOf({'a': 'file', 'a/b': 'child'}).path,
        limits: const ImportLimits(),
      ),
      throwsA(isA<ImportFailure>()),
    );
  });

  test('rejects Unix symbolic link before opening entry data', () {
    final file = alteredZip({'link': '../outside'}, (bytes) {
      final at = centralOffset(bytes);
      bytes[at + 5] = 3; // version made by Unix
      uint32(bytes, at + 38, 0xa1ff << 16);
    });
    expect(
      () => SafeZipArchive.open(file.path, limits: const ImportLimits()),
      throwsA(isA<ImportFailure>()),
    );
  });

  test('checks count, declared entry and total budgets before extraction', () {
    final file = zipOf({'a.xml': '<a/>', 'b.xml': '<b/>'});
    expect(
      () => SafeZipArchive.open(
        file.path,
        limits: const InputLimits(
          maxEntries: 1,
          maxOutputBytes: 100,
          maxXmlBytes: 100,
          maxXmlDepth: 8,
          maxXmlContentCharacters: 100,
        ),
      ),
      throwsA(isA<ImportFailure>()),
    );
    expect(
      () => SafeZipArchive.open(
        file.path,
        limits: const InputLimits(
          maxEntries: 2,
          maxEntryBytes: 3,
          maxOutputBytes: 100,
          maxXmlBytes: 100,
          maxXmlDepth: 8,
          maxXmlContentCharacters: 100,
        ),
      ),
      throwsA(isA<ImportFailure>()),
    );
    expect(
      () => SafeZipArchive.open(
        file.path,
        limits: const InputLimits(
          maxEntries: 2,
          maxOutputBytes: 7,
          maxXmlBytes: 100,
          maxXmlDepth: 8,
          maxXmlContentCharacters: 100,
        ),
      ),
      throwsA(isA<ImportFailure>()),
    );
  });

  test('rejects false sizes and CRC, removes failed partial output', () {
    for (final offset in [24, 16]) {
      final file = alteredZip({'chapter.xml': '<chapter>正文</chapter>'}, (
        bytes,
      ) {
        final at = centralOffset(bytes);
        uint32(bytes, at + offset, 1);
      });
      final zip = SafeZipArchive.open(file.path, limits: const ImportLimits());
      final output = File('${directory.path}/chapter-$offset.xml');
      try {
        expect(
          () => zip.extractToFile('chapter.xml', output),
          throwsA(isA<ImportFailure>()),
        );
        expect(output.existsSync(), isFalse);
      } finally {
        zip.close();
      }
    }
  });

  test('streams one entry, verifies digest and cumulative actual budget', () {
    final file = zipOf({'a.xml': '<a/>', 'b.xml': '<b/>'});
    final zip = SafeZipArchive.open(
      file.path,
      limits: const InputLimits(
        maxEntries: 2,
        maxOutputBytes: 8,
        maxXmlBytes: 8,
        maxXmlDepth: 8,
        maxXmlContentCharacters: 8,
      ),
    );
    try {
      final extracted = zip.extractToFile(
        'a.xml',
        File('${directory.path}/a.xml'),
      );
      expect(extracted.bytesWritten, 4);
      expect(extracted.sha256, sha256.convert('<a/>'.codeUnits).toString());
      expect(zip.actualOutputBytes, 4);
      expect(zip.readXml('b.xml').rootElement.name.local, 'b');
      expect(zip.actualOutputBytes, 8);
      expect(() => zip.readXmlBytes('a.xml'), throwsA(isA<ImportFailure>()));
      expect(
        () => zip.readXmlBytes('manifest.json'),
        throwsA(isA<ImportFailure>()),
      );
    } finally {
      zip.close();
    }
  });

  test('safeXml rejects DTD, external entities, malformed and deep XML', () {
    const limits = InputLimits(
      maxEntries: 1,
      maxOutputBytes: 1024,
      maxXmlBytes: 1024,
      maxXmlDepth: 3,
      maxXmlContentCharacters: 1024,
    );
    for (final source in [
      '<!DOCTYPE book [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><book>&xxe;</book>',
      '<book><a></book>',
      '<a><b><c><d/></c></b></a>',
    ]) {
      expect(
        () => safeXml(source, limits: limits),
        throwsA(isA<ImportFailure>()),
      );
    }
    expect(
      safeXml('<a><b>ok</b></a>', limits: limits).rootElement.name.local,
      'a',
    );
  });

  test('ZIP XML read rejects DTD and accepts UTF-16 BOM', () {
    final malicious = zipOf({
      'evil.xml':
          '<!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/passwd">]><a>&x;</a>',
    });
    final unsafe = SafeZipArchive.open(
      malicious.path,
      limits: const ImportLimits(),
    );
    try {
      expect(() => unsafe.readXml('evil.xml'), throwsA(isA<ImportFailure>()));
    } finally {
      unsafe.close();
    }

    final utf16 = <int>[
      0xff,
      0xfe,
      for (final unit
          in '<?xml version="1.0" encoding="UTF-16"?><a>汉</a>'.codeUnits) ...[
        unit & 0xff,
        unit >> 8,
      ],
    ];
    final data = archive.Archive()
      ..add(archive.ArchiveFile.bytes('book.xml', utf16));
    final file = File('${directory.path}/utf16.zip')
      ..writeAsBytesSync(archive.ZipEncoder().encode(data));
    final zip = SafeZipArchive.open(file.path, limits: const ImportLimits());
    try {
      expect(zip.readXml('book.xml').rootElement.innerText, '汉');
    } finally {
      zip.close();
    }

    final unsupported = zipOf({
      'book.xml': '<?xml version="1.0" encoding="ISO-8859-1"?><a/>',
    });
    final wrongDeclaration = SafeZipArchive.open(
      unsupported.path,
      limits: const ImportLimits(),
    );
    try {
      expect(
        () => wrongDeclaration.readXml('book.xml'),
        throwsA(isA<ImportFailure>()),
      );
    } finally {
      wrongDeclaration.close();
    }
  });

  test('backup source above 32 MiB uses its separate streaming budget', () {
    final source = Uint8List(33 * ImportLimits.mebibyte);
    final data = archive.Archive()
      ..add(archive.ArchiveFile.bytes('sources/book.txt', source));
    final file = File('${directory.path}/backup.bookloom')
      ..writeAsBytesSync(archive.ZipEncoder().encode(data));
    expect(
      () => SafeZipArchive.open(file.path, limits: const ImportLimits()),
      throwsA(isA<ImportFailure>()),
    );
    final zip = SafeZipArchive.open(
      file.path,
      limits: const BackupLimits(maxOutputBytes: 300 * ImportLimits.mebibyte),
    );
    try {
      final output = File('${directory.path}/restored.txt');
      final result = zip.extractToFile('sources/book.txt', output);
      expect(result.bytesWritten, source.length);
      expect(output.lengthSync(), source.length);
      expect(zip.actualOutputBytes, source.length);
    } finally {
      zip.close();
    }
  });
}
