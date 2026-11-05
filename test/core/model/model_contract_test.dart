import 'dart:convert';

import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/model/parse_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'book revisions and cover source survive copies and can clear image',
    () {
      final Book book = Book(
        id: 'b',
        meta: BookMeta(title: '书'),
        createdAt: DateTime.utc(2025),
        updatedAt: DateTime.utc(2025),
        coverMode: CoverMode.image,
        coverAssetId: 'cover-1',
      );
      final Book revised = book.copyWith(revision: 1);
      expect(revised.coverMode, CoverMode.image);
      expect(revised.coverAssetId, 'cover-1');
      expect(revised.copyWith(clearCoverAssetId: true).coverAssetId, isNull);
      expect(revised.copyWith(coverAssetId: 'cover-2').coverAssetId, 'cover-2');
      expect(book.revision, 0);
    },
  );

  test('front matter flag survives chapter copies', () {
    const Chapter chapter = Chapter(
      id: 'c',
      bookId: 'b',
      title: '',
      frontMatter: true,
    );
    expect(chapter.copyWith(title: '序').frontMatter, isTrue);
    expect(chapter.copyWith(frontMatter: false).frontMatter, isFalse);
  });

  test('parse options round trip and reject malformed persisted fields', () {
    const ParseOptions options = ParseOptions(
      encoding: 'gb18030',
      filterAds: false,
      rulePreset: 'custom',
      ruleSpec: <String, Object?>{'name': '我的规则'},
      convertMode: ConvertMode.taiwan,
    );
    final ParseOptions restored = ParseOptions.fromJson(
      (jsonDecode(jsonEncode(options.toJson())) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    expect(restored.encoding, 'gb18030');
    expect(restored.filterAds, isFalse);
    expect(restored.ruleSpec?['name'], '我的规则');
    expect(restored.convertMode, ConvertMode.taiwan);
    final ParseOptions bad = ParseOptions.fromJson(<String, Object?>{
      'encoding': 7,
      'filterAds': 'false',
      'rulePreset': <String>[],
      'ruleSpec': <String, Object?>{'chapter': DateTime.utc(2020)},
      'convertMode': 'unexpected',
    });
    expect(bad.encoding, 'auto');
    expect(bad.filterAds, isTrue);
    expect(bad.rulePreset, 'auto');
    expect(bad.ruleSpec, isNull);
    expect(bad.convertMode, ConvertMode.none);
  });

  test('parse result carries suggested content and source diagnostics', () {
    final ParseResult result = ParseResult(
      format: ImportFormat.txt,
      actualEncoding: 'utf-8',
      encodingConfidence: 0.95,
      suggestedMeta: BookMeta(title: '建议书名'),
      chapters: const <Chapter>[Chapter(id: 'c', bookId: 'b', title: '第一章')],
      warnings: const <ParseWarning>[
        ParseWarning(code: 'lowConfidence', message: '检查编码', line: 12),
      ],
      sourceLocations: const <String, ParseSourceLocation>{
        'c': ParseSourceLocation(line: 10, column: 1),
      },
    );
    expect(result.format.wire, 'txt');
    expect(result.chapters.single.title, '第一章');
    expect(result.warnings.single.line, 12);
    expect(result.sourceLocations['c']?.line, 10);
  });

  test('metadata dates stay calendar dates and tags normalize', () {
    final BookMeta meta = BookMeta(
      title: '书',
      tags: <String>[' 诗歌 ', '', '诗歌', ' 散文'],
      publishedAt: DateTime(2025, 1, 2, 23, 45),
    );
    expect(meta.tags, <String>['诗歌', '散文']);
    expect(meta.toJson()['publishedAt'], '2025-01-02');
    final BookMeta restored = BookMeta.fromJson(
      (jsonDecode(jsonEncode(meta.toJson())) as Map<String, dynamic>)
          .cast<String, Object?>(),
    );
    expect(restored.publishedAt?.year, 2025);
    expect(restored.publishedAt?.month, 1);
    expect(restored.publishedAt?.day, 2);
    expect(restored.tags, meta.tags);
    expect(
      BookMeta.fromJson(<String, Object?>{
        'title': '书',
        'publishedAt': '2025-02-30',
        'tags': <Object?>[1, ' A ', 'A'],
      }).publishedAt,
      isNull,
    );
  });

  test('cover options normalize scale and legacy template wire', () {
    final CoverOptions cover = CoverOptions.fromJson(<String, Object?>{
      'template': 'block',
      'palette': 'invalid',
      'titleScale': 9,
      'authorPosition': 'hidden',
    });
    expect(cover.template, CoverTemplate.blocks);
    expect(cover.toJson()['template'], 'blocks');
    expect(cover.palette, 'auto');
    expect(cover.titleScale, 1.3);
    expect(cover.authorPosition, AuthorPosition.hidden);
    expect(CoverOptions(titleScale: double.nan).titleScale, 1);
  });

  test('layout range and CSS policy apply to direct and JSON values', () {
    expect(
      LayoutOptions.fromJson(<String, Object?>{
        'lineHeight': 100,
        'paragraphSpacing': -1,
        'font': 'kai',
      }).lineHeight,
      2.4,
    );
    expect(
      LayoutOptions.fromJson(<String, Object?>{
        'lineHeight': 100,
        'paragraphSpacing': -1,
      }).paragraphSpacing,
      0,
    );
    expect(
      LayoutOptions.fromJson(<String, Object?>{'font': 'kai'}).font,
      LayoutFont.kai,
    );
    expect(
      () => LayoutOptions(customCss: '@import "https://a.css";'),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions(customCss: 'p{background:url(https://a)}'),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions.fromJson(<String, Object?>{
        'customCss': '@import "evil.css";',
      }),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions(customCss: r'@\69mport "evil.css";'),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions(customCss: r'p{background:u\72l(evil.css)}'),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions(customCss: '@/**/import "evil.css";'),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions(customCss: '</style><script>alert(1)</script>'),
      throwsArgumentError,
    );
    expect(
      () => LayoutOptions(customCss: 'p { color: red; }\u0000'),
      throwsArgumentError,
    );
    final LayoutOptions layout = LayoutOptions(
      customCss: 'p { color: red; }',
      embeddedFontAssetId: 'font-1',
    );
    expect(
      LayoutOptions.fromJson(layout.toJson()).embeddedFontAssetId,
      'font-1',
    );
    expect(
      layout.copyWith(clearEmbeddedFontAssetId: true).embeddedFontAssetId,
      isNull,
    );
  });
}
