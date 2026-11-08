import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookloom/core/model/block.dart' as model;
import 'package:bookloom/core/model/book.dart' as model;
import 'package:bookloom/core/model/chapter.dart' as model;
import 'package:bookloom/core/model/metadata.dart' as model;
import 'package:bookloom/core/storage/app_database.dart' show AppDatabase;
import 'package:bookloom/core/storage/book_repository.dart' show BookRepository;
import 'package:bookloom/core/text/word_count.dart' show WordCount;
import 'package:path/path.dart' as p;

const String _runVariable = 'BOOKLOOM_RUN_IMPORT_SAVE_BENCHMARK';
const String _directoryVariable = 'BOOKLOOM_IMPORT_SAVE_BENCHMARK_DIR';
const String _labelVariable = 'BOOKLOOM_IMPORT_SAVE_BENCHMARK_LABEL';
const String _bookId = 'import-save-benchmark';
const int _chapterCount = 1282;
const int _blockCount = 70495;
const int _nonWhitespaceCharacterCount = 2588611;
const int _baseCharacterCount = 2537801;
const int _extraLongParagraphCount =
    _nonWhitespaceCharacterCount - _baseCharacterCount;
const Duration _rssSampleInterval = Duration(milliseconds: 25);
const List<int> _paragraphLengthPattern = <int>[
  18,
  29,
  37,
  45,
  32,
  54,
  24,
  41,
  36,
  44,
];
const List<String> _syntheticSentences = <String>[
  '清晨的潮声沿着旧港缓缓传来，远处的灯塔仍亮着。',
  '雨水落在街巷尽头，窗边的纸页被风轻轻翻动。',
  '列车穿过平原时，天边的云影慢慢移向山后。',
  '石阶旁的新草沾着露水，院门里传来几声鸟鸣。',
  '夜色落下以后，河面映着稀疏的灯火与星光。',
  '旧地图摊在桌上，沿岸的小镇仍标着熟悉的名字。',
];

Future<void> main() async {
  if (Platform.environment[_runVariable] != '1') {
    stderr.writeln('Set $_runVariable=1 to run this bounded benchmark.');
    exitCode = 64;
    return;
  }

  final Directory root = await _createBenchmarkDirectory();
  AppDatabase? database;
  try {
    final File databaseFile = File(p.join(root.path, 'library.sqlite'));
    database = AppDatabase.openAt(databaseFile);
    final BookRepository repository = BookRepository(
      database,
      Directory(p.join(root.path, 'support')),
    );
    final _BenchmarkInput input = _buildBenchmarkBook();
    _require(
      input.nonWhitespaceCharacterCount == _nonWhitespaceCharacterCount,
      'Synthetic input character count does not match its contract.',
    );

    final int rssAtStart = ProcessInfo.currentRss;
    var sampledPeakRss = rssAtStart;
    void sampleRss() {
      final int rss = ProcessInfo.currentRss;
      if (rss > sampledPeakRss) sampledPeakRss = rss;
    }

    final Timer sampler = Timer.periodic(
      _rssSampleInterval,
      (_) => sampleRss(),
    );
    final Stopwatch stopwatch = Stopwatch()..start();
    late final model.Book created;
    try {
      created = await repository.createBook(input.book);
    } finally {
      stopwatch.stop();
      sampler.cancel();
      sampleRss();
    }

    final rowCounts = await database.customSelect('''
          SELECT COUNT(*) AS block_count,
                 COALESCE(SUM(length(text)), 0) AS text_character_count
          FROM blocks
        ''').getSingle();
    final int persistedBlockCount = rowCounts.read<int>('block_count');
    final int persistedTextCharacterCount = rowCounts.read<int>(
      'text_character_count',
    );
    final chapterCounts = await database.customSelect('''
          SELECT COUNT(*) AS chapter_count,
                 COALESCE(SUM(word_count), 0) AS chapter_word_count
          FROM chapters
        ''').getSingle();
    final int persistedChapterCount = chapterCounts.read<int>('chapter_count');
    final int persistedChapterWordCount = chapterCounts.read<int>(
      'chapter_word_count',
    );
    final summaries = await repository.listSummaries();
    final summary = summaries.length == 1 ? summaries.single : null;
    final model.Book? loadedBook = await repository.loadBook(_bookId);
    final String? firstParagraph = _boundaryParagraph(
      await repository.loadChapter(_bookId, _chapterId(0)),
      last: false,
    );
    final String? lastParagraph = _boundaryParagraph(
      await repository.loadChapter(_bookId, _chapterId(_chapterCount - 1)),
      last: true,
    );
    final List<String> loadedChapterIds =
        loadedBook?.chapters
            .map((chapter) => chapter.id)
            .toList(growable: false) ??
        const <String>[];
    final Map<String, bool> checks = <String, bool>{
      'returnedChapterCount': created.chapters.length == _chapterCount,
      'returnedWordCount': created.wordCount == _nonWhitespaceCharacterCount,
      'persistedChapterCount': persistedChapterCount == _chapterCount,
      'persistedBlockCount': persistedBlockCount == _blockCount,
      'persistedTextCharacterCount':
          persistedTextCharacterCount == _nonWhitespaceCharacterCount,
      'persistedChapterWordCount':
          persistedChapterWordCount == _nonWhitespaceCharacterCount,
      'summaryChapterCount': summary?.chapterCount == _chapterCount,
      'summaryWordCount': summary?.wordCount == _nonWhitespaceCharacterCount,
      'chapterOrder': _sameStrings(loadedChapterIds, input.chapterIds),
      'firstAndLastParagraphs':
          firstParagraph == input.firstParagraph &&
          lastParagraph == input.lastParagraph,
    };
    final Map<String, Object?> report = <String, Object?>{
      'benchmark': 'bookloom_import_save',
      'label': Platform.environment[_labelVariable] ?? 'unspecified',
      'runtime': <String, Object>{
        'dartVmProduct': const bool.fromEnvironment('dart.vm.product'),
        'dartVmProfile': const bool.fromEnvironment('dart.vm.profile'),
      },
      'input': <String, int>{
        'chapters': _chapterCount,
        'textBlocks': _blockCount,
        'nonWhitespaceCharacters': input.nonWhitespaceCharacterCount,
      },
      'databasePath': p.normalize(p.absolute(databaseFile.path)),
      'createBookWallClockMilliseconds': stopwatch.elapsedMicroseconds / 1000,
      'memory': <String, Object>{
        'measurement': 'sampled process RSS during createBook',
        'sampleIntervalMilliseconds': _rssSampleInterval.inMilliseconds,
        'rssAtCreateStartBytes': rssAtStart,
        'sampledPeakRssBytes': sampledPeakRss,
        'sampledPeakRssGrowthBytes': sampledPeakRss - rssAtStart,
      },
      'observed': <String, Object?>{
        'returnedChapters': created.chapters.length,
        'returnedWordCount': created.wordCount,
        'persistedChapters': persistedChapterCount,
        'persistedBlocks': persistedBlockCount,
        'persistedTextCharacters': persistedTextCharacterCount,
        'persistedChapterWordCount': persistedChapterWordCount,
        'summaryChapterCount': summary?.chapterCount,
        'summaryWordCount': summary?.wordCount,
        'loadedChapterCount': loadedChapterIds.length,
      },
      'checks': checks,
    };
    stdout.writeln(jsonEncode(report));
    _require(
      checks.values.every((passed) => passed),
      'One or more persistence or order checks failed.',
    );
  } finally {
    try {
      await database?.close();
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  }
}

Future<Directory> _createBenchmarkDirectory() async {
  final String? configuredPath = Platform.environment[_directoryVariable];
  if (configuredPath == null || configuredPath.trim().isEmpty) {
    return Directory.systemTemp.createTemp('bookloom-import-save-');
  }
  if (!p.isAbsolute(configuredPath)) {
    throw ArgumentError.value(
      configuredPath,
      _directoryVariable,
      'must be an absolute path under the system temporary directory',
    );
  }

  final String path = p.normalize(configuredPath);
  final String tempPath = p.normalize(p.absolute(Directory.systemTemp.path));
  if (path == tempPath || !p.isWithin(tempPath, path)) {
    throw ArgumentError.value(
      configuredPath,
      _directoryVariable,
      'must be a child of ${Directory.systemTemp.path}',
    );
  }

  final Directory directory = Directory(path);
  if (await directory.exists()) {
    throw StateError(
      'Benchmark directory already exists; refusing to reuse or delete it: $path',
    );
  }
  await directory.create();
  return directory;
}

_BenchmarkInput _buildBenchmarkBook() {
  final List<model.Chapter> chapters = <model.Chapter>[];
  final List<String> chapterIds = <String>[];
  var globalBlockIndex = 0;
  var nonWhitespaceCharacterCount = 0;
  String? firstParagraph;
  String? lastParagraph;
  final DateTime timestamp = DateTime.utc(2026, 1, 1);

  for (var chapterIndex = 0; chapterIndex < _chapterCount; chapterIndex++) {
    final String chapterId = _chapterId(chapterIndex);
    final int chapterBlockCount =
        _blockCount ~/ _chapterCount +
        (_hasDistributedExtra(
              chapterIndex,
              _blockCount % _chapterCount,
              _chapterCount,
            )
            ? 1
            : 0);
    final List<model.Block> blocks = <model.Block>[];
    for (var blockIndex = 0; blockIndex < chapterBlockCount; blockIndex++) {
      final int paragraphLength = _paragraphLength(globalBlockIndex);
      final String text = _syntheticParagraph(
        globalBlockIndex,
        paragraphLength,
      );
      blocks.add(
        model.TextBlock(
          id: '$_bookId-block-${globalBlockIndex.toString().padLeft(6, '0')}',
          text: text,
        ),
      );
      nonWhitespaceCharacterCount += WordCount.ofText(text);
      firstParagraph ??= text;
      lastParagraph = text;
      globalBlockIndex++;
    }
    chapters.add(
      model.Chapter(
        id: chapterId,
        bookId: _bookId,
        title: '第 ${chapterIndex + 1} 章',
        order: chapterIndex,
        blocks: blocks,
      ),
    );
    chapterIds.add(chapterId);
  }

  return _BenchmarkInput(
    book: model.Book(
      id: _bookId,
      meta: model.BookMeta(title: 'Synthetic import benchmark'),
      chapters: chapters,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    chapterIds: chapterIds,
    firstParagraph: firstParagraph!,
    lastParagraph: lastParagraph!,
    nonWhitespaceCharacterCount: nonWhitespaceCharacterCount,
  );
}

int _paragraphLength(int blockIndex) {
  final int baseLength =
      _paragraphLengthPattern[blockIndex % _paragraphLengthPattern.length];
  return baseLength +
      (_hasDistributedExtra(blockIndex, _extraLongParagraphCount, _blockCount)
          ? 1
          : 0);
}

bool _hasDistributedExtra(int index, int extraCount, int itemCount) =>
    (index + 1) * extraCount ~/ itemCount != index * extraCount ~/ itemCount;

String _syntheticParagraph(int index, int length) {
  final List<int> runes =
      _syntheticSentences[index % _syntheticSentences.length].runes.toList();
  return String.fromCharCodes(
    List<int>.generate(length, (offset) => runes[offset % runes.length]),
  );
}

String _chapterId(int index) =>
    '$_bookId-chapter-${index.toString().padLeft(4, '0')}';

String? _boundaryParagraph(model.Chapter? chapter, {required bool last}) {
  if (chapter == null || chapter.blocks.isEmpty) return null;
  final model.Block block = last ? chapter.blocks.last : chapter.blocks.first;
  return block is model.TextBlock ? block.text : null;
}

bool _sameStrings(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) return false;
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) return false;
  }
  return true;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class _BenchmarkInput {
  const _BenchmarkInput({
    required this.book,
    required this.chapterIds,
    required this.firstParagraph,
    required this.lastParagraph,
    required this.nonWhitespaceCharacterCount,
  });

  final model.Book book;
  final List<String> chapterIds;
  final String firstParagraph;
  final String lastParagraph;
  final int nonWhitespaceCharacterCount;
}
