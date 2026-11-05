import 'dart:io';
import 'dart:typed_data';

import 'package:bookloom/core/io/input_limits.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/core/storage/app_database.dart' show Asset;
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/features/preview/book_cover.dart';
import 'package:path/path.dart' as p;

/// Imports resources into one book. A cancelled pick or validation failure
/// returns without changing the current Book in the editing session.
class BookAssets {
  BookAssets({required this.repository, required this.files});

  final BookRepository repository;
  final FileService files;

  static const int maxFontBytes = ImportLimits.maxFontBytes;

  Future<StoredFile?> pickCover(String bookId) async {
    List<PickedInput> picked = const [];
    try {
      picked = await files.pickImports(
        multiple: false,
        extensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (picked.isEmpty) return null;
      return await importCover(bookId, picked.single);
    } finally {
      await _releasePicked(picked);
      await _clearPickerCache();
    }
  }

  Future<StoredFile> importCover(String bookId, PickedInput input) async {
    final prepared = await BookCoverRenderer.prepareUpload(input);
    final id = repository.files.newId();
    final cover = await repository.addAsset(
      bookId,
      AssetImport(
        id: id,
        kind: 'cover',
        mime: 'image/jpeg',
        extension: 'jpg',
        width: BookCoverRenderer.width,
        height: BookCoverRenderer.height,
        maxBytes: BookCoverRenderer.maxInputBytes,
        openRead: () => Stream<List<int>>.value(prepared.jpeg),
      ),
    );
    try {
      await repository.addAsset(
        bookId,
        AssetImport(
          id: '$id-thumb',
          kind: 'image',
          mime: 'image/jpeg',
          extension: 'jpg',
          width: 240,
          height: 360,
          maxBytes: BookCoverRenderer.maxInputBytes,
          openRead: () => Stream<List<int>>.value(prepared.thumbnail),
        ),
      );
      return cover;
    } on Object {
      try {
        await repository.removeUnusedAsset(bookId, id);
      } on Object {
        // The primary import failure remains the useful error. The orphan can
        // be removed by cleanupUnreferenced after the session closes.
      }
      rethrow;
    }
  }

  Future<void> discardUnusedCover(String bookId, String assetId) async {
    await repository.removeUnusedAsset(bookId, '$assetId-thumb');
    await repository.removeUnusedAsset(bookId, assetId);
  }

  Future<void> discardUnusedFont(String bookId, String assetId) async {
    await repository.removeUnusedAsset(bookId, assetId);
  }

  Future<StoredFile?> pickFont(String bookId) async {
    List<PickedInput> picked = const [];
    try {
      picked = await files.pickImports(
        multiple: false,
        extensions: const ['ttf', 'otf', 'woff', 'woff2'],
      );
      if (picked.isEmpty) return null;
      return await importFont(bookId, picked.single);
    } finally {
      await _releasePicked(picked);
      await _clearPickerCache();
    }
  }

  Future<StoredFile> importFont(String bookId, PickedInput input) async {
    final extension = p
        .extension(input.name)
        .replaceFirst('.', '')
        .toLowerCase();
    if (input.size != null && input.size! > maxFontBytes) {
      throw const FormatException('字体文件超过 20 MiB。');
    }
    final mime = await _fontMime(input, extension);
    return repository.addAsset(
      bookId,
      AssetImport(
        kind: 'font',
        mime: mime,
        extension: extension,
        maxBytes: maxFontBytes,
        openRead: input.openRead,
      ),
    );
  }

  Future<Asset?> findAsset(String bookId, String assetId) async {
    final assets = await repository.loadAssets(bookId);
    for (final asset in assets) {
      if (asset.id == assetId && asset.bookId == bookId) return asset;
    }
    return null;
  }

  Future<File?> coverFile(String bookId, String? assetId) async {
    if (assetId == null) return null;
    final asset = await findAsset(bookId, assetId);
    if (asset == null || asset.kind != 'cover') return null;
    return repository.resolveAsset(asset);
  }

  /// Run only after the editing session and its undo history are closed.
  /// An active undo stack may still legitimately reference an old asset.
  Future<int> cleanupUnreferenced(String bookId) async {
    final book = await repository.loadBook(bookId);
    if (book == null) return 0;
    final referenced = <String>{
      if (book.coverAssetId != null) book.coverAssetId!,
      if (book.layout.embeddedFontAssetId != null)
        book.layout.embeddedFontAssetId!,
    };
    var removed = 0;
    for (final asset in await repository.loadAssets(bookId)) {
      if (asset.kind == 'image' && asset.id.endsWith('-thumb')) {
        final coverId = asset.id.substring(0, asset.id.length - 6);
        if (!referenced.contains(coverId) &&
            await repository.removeUnusedAsset(bookId, asset.id)) {
          removed++;
        }
        continue;
      }
      if (asset.kind != 'cover' && asset.kind != 'font') continue;
      if (referenced.contains(asset.id)) continue;
      if (await repository.removeUnusedAsset(bookId, asset.id)) removed++;
    }
    return removed;
  }

  Future<void> _clearPickerCache() async {
    try {
      await files.clearTemporaryFiles();
    } on Object {
      // A failed cache cleanup does not turn a committed asset into failure.
    }
  }

  static Future<void> _releasePicked(List<PickedInput> picked) async {
    for (final input in picked) {
      try {
        await input.release();
      } on Object {
        // An asset already committed to book storage remains usable.
      }
    }
  }

  static Future<String> _fontMime(PickedInput input, String extension) async {
    if (!const {'ttf', 'otf', 'woff', 'woff2'}.contains(extension)) {
      throw const FormatException('字体仅支持 TTF、OTF、WOFF 和 WOFF2。');
    }
    final header = BytesBuilder(copy: false);
    await for (final chunk in input.openRead()) {
      header.add(chunk.length <= 16 ? chunk : chunk.sublist(0, 16));
      if (header.length >= 16) break;
    }
    final bytes = header.takeBytes();
    if (bytes.length < 4) throw const FormatException('字体文件头不完整。');
    final signature = String.fromCharCodes(bytes.take(4));
    final valid = switch (extension) {
      'ttf' =>
        (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0) ||
            signature == 'true',
      'otf' => signature == 'OTTO',
      'woff' => signature == 'wOFF',
      'woff2' => signature == 'wOF2',
      _ => false,
    };
    if (!valid) throw const FormatException('字体扩展名与文件签名不一致。');
    return switch (extension) {
      'ttf' => 'font/ttf',
      'otf' => 'font/otf',
      'woff' => 'font/woff',
      _ => 'font/woff2',
    };
  }
}
