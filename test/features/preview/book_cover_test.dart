import 'dart:async';
import 'dart:typed_data';

import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/platform/files.dart';
import 'package:bookloom/features/preview/book_cover.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  testWidgets('template and uploaded cover share the 1200×1800 JPEG contract', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 1, 1);
    final book = Book(
      id: 'book',
      meta: BookMeta(title: '一段很长的中文书名与 English title 📚', author: '作者 Writer'),
      coverOptions: CoverOptions(authorPosition: AuthorPosition.hidden),
      createdAt: now,
      updatedAt: now,
    );
    final template = (await tester.runAsync(
      () => BookCoverRenderer.renderJpeg(book),
    ))!;
    expect(template.sublist(0, 2), [0xff, 0xd8]);
    final rendered = image.decodeJpg(template)!;
    expect((rendered.width, rendered.height), (1200, 1800));

    final source = image.Image(width: 6, height: 4);
    image.fill(source, color: image.ColorRgb8(32, 80, 120));
    final png = image.encodePng(source);
    final prepared = (await tester.runAsync(
      () => BookCoverRenderer.prepareUpload(
        PickedInput(
          name: 'cover.png',
          size: png.length,
          openRead: () => Stream<List<int>>.value(Uint8List.fromList(png)),
        ),
      ),
    ))!;
    expect((prepared.sourceWidth, prepared.sourceHeight), (6, 4));
    final cover = image.decodeJpg(prepared.jpeg)!;
    final thumbnail = image.decodeJpg(prepared.thumbnail)!;
    expect((cover.width, cover.height), (1200, 1800));
    expect((thumbnail.width, thumbnail.height), (240, 360));
  });
}
