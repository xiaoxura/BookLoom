import 'dart:async';
import 'dart:convert';

import 'package:bookloom/core/ai/ai_context.dart';
import 'package:bookloom/core/ai/ai_limits.dart';
import 'package:bookloom/core/conversion/opencc_converter.dart';
import 'package:bookloom/core/editing/ai_change_application.dart';
import 'package:bookloom/core/editing/ai_chapter_split_proposal.dart';
import 'package:bookloom/core/editing/ai_text_application.dart';
import 'package:bookloom/core/editing/ai_text_proposal.dart';
import 'package:bookloom/core/editing/book_intro.dart';
import 'package:bookloom/core/editing/chapter_edits.dart';
import 'package:bookloom/core/editing/proofreading.dart';
import 'package:bookloom/core/editing/proofreading_rule_scan.dart';
import 'package:bookloom/core/errors/app_failure.dart';
import 'package:bookloom/core/model/block.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/cover_options.dart';
import 'package:bookloom/core/model/layout_options.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/core/model/parse_options.dart';
import 'package:bookloom/core/platform/background_jobs.dart';
import 'package:bookloom/core/storage/book_repository.dart';
import 'package:bookloom/core/text/word_count.dart';
import 'package:bookloom/features/editor/application/ai_proofreading_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

const int _defaultHistoryByteBudget = 32 * 1024 * 1024;

/// Small store boundary so save races can be tested without a database.
abstract interface class EditorBookStore {
  Future<Book?> loadBook(String bookId);
  Future<Chapter?> loadChapter(String bookId, String chapterId);
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  });
}

class RepositoryEditorBookStore implements EditorBookStore {
  const RepositoryEditorBookStore(this.repository);
  final BookRepository repository;

  @override
  Future<Book?> loadBook(String bookId) => repository.loadBook(bookId);

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) =>
      repository.loadChapter(bookId, chapterId);

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const <String>{},
  }) => repository.saveBook(
    book,
    expectedRevision: expectedRevision,
    dirtyChapterIds: dirtyChapterIds,
    deletedChapterIds: deletedChapterIds,
  );
}

/// One in-memory editing session. Only the active chapter body is guaranteed
/// to be loaded; [book] always carries the complete structural chapter list.
class EditorSession extends ChangeNotifier {
  EditorSession({
    required BookRepository repository,
    BackgroundJobs? jobs,
    Duration debounce = const Duration(milliseconds: 1000),
    int historyByteBudget = _defaultHistoryByteBudget,
  }) : this.withStore(
         store: RepositoryEditorBookStore(repository),
         jobs: jobs,
         debounce: debounce,
         historyByteBudget: historyByteBudget,
       );

  @visibleForTesting
  EditorSession.withStore({
    required EditorBookStore store,
    BackgroundJobs? jobs,
    Duration debounce = const Duration(milliseconds: 1000),
    int historyByteBudget = _defaultHistoryByteBudget,
  }) : assert(debounce >= const Duration(milliseconds: 800)),
       assert(debounce <= const Duration(milliseconds: 1200)),
       assert(historyByteBudget > 0),
       // Keep the public test seam named `store`.
       // ignore: prefer_initializing_formals
       _store = store,
       _jobs = jobs ?? BackgroundJobs(),
       _ownsJobs = jobs == null,
       _debounce = debounce,
       _history = _EditHistory(historyByteBudget);

  final EditorBookStore _store;
  final BackgroundJobs _jobs;
  final bool _ownsJobs;
  final Duration _debounce;
  final _EditHistory _history;
  static const Uuid _uuid = Uuid();

  Book? _book;
  String? _activeChapterId;

  /// Chapter recognized as the book intro carrier, hidden from the chapter
  /// directory. Recomputed on open and reparse; null when nothing matches.
  String? _introChapterId;
  final Set<String> _loadedIds = <String>{};
  final Set<String> _persistedIds = <String>{};
  final Map<String, int> _dirtyChapterSeq = <String, int>{};
  final Map<String, int> _deletedChapterSeq = <String, int>{};
  Timer? _saveTimer;
  Future<void>? _saving;
  AppFailure? _saveError;
  int _saveSeq = 0;
  int _savedSeq = 0;
  int _openGeneration = 0;
  int _openingCount = 0;
  String? _sessionId;
  bool _closed = false;
  bool _closing = false;
  bool _structuralCommandRunning = false;
  bool _deferredBodyEviction = false;
  bool _aiTextCommandRunning = false;
  bool _aiTextCancelled = false;
  bool _toolRunning = false;
  bool _toolIsolateRunning = false;
  JobProgress? _toolProgress;

  Book? get book => _book;
  String? get activeChapterId => _activeChapterId;

  /// The chapter currently recognized as the intro carrier, or null.
  String? get introChapterId => _introChapterId;
  Chapter? get activeChapter {
    final id = _activeChapterId;
    if (id == null || !_loadedIds.contains(id)) return null;
    for (final chapter in _book?.chapters ?? const <Chapter>[]) {
      if (chapter.id == id) return chapter;
    }
    return null;
  }

  bool get dirty => _saveSeq != _savedSeq;
  bool get isSaving => _saving != null;
  int get saveSeq => _saveSeq;
  String? get sessionId =>
      _closed || _closing || _openingCount != 0 ? null : _sessionId;
  AppFailure? get saveError => _saveError;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  bool get isToolRunning => _toolRunning;
  JobProgress? get toolProgress => _toolProgress;

  Future<void> open(String bookId, {String? chapterId}) async {
    _requireOpen();
    _sessionId = null;
    _openingCount++;
    try {
      if (dirty) await flush();
      final loaded = await _readBook(bookId);
      if (loaded == null) {
        throw const ValidationFailure('书籍不存在，请从书架重新打开。');
      }
      // Recognition must run before the default selection so a recognized
      // intro chapter never becomes the automatically opened body.
      final intro = await _recognizeIntro(loaded);
      final introId = intro?.intro.chapterId;
      final selected =
          chapterId ??
          loaded.chapters
              .where(
                (chapter) =>
                    !chapter.isVolume && (introId == null || chapter.id != introId),
              )
              .firstOrNull
              ?.id;
      if (selected != null &&
          !loaded.chapters.any(
            (chapter) => chapter.id == selected && !chapter.isVolume,
          )) {
        throw const ValidationFailure('章节不存在，请从目录重新选择。');
      }
      Chapter? body;
      if (selected != null) {
        body = await _readChapter(bookId, selected);
        if (body == null) {
          throw const ValidationFailure('章节内容无法读取，请刷新书稿。');
        }
      }
      _saveTimer?.cancel();
      _book = body == null
          ? loaded
          : _withChapter(loaded, _bodyOnStructure(loaded, body));
      _activeChapterId = selected;
      _loadedIds
        ..clear()
        ..addAll(selected == null ? const <String>[] : <String>[selected]);
      _persistedIds
        ..clear()
        ..addAll(loaded.chapters.map((chapter) => chapter.id));
      _dirtyChapterSeq.clear();
      _deletedChapterSeq.clear();
      _saveError = null;
      // A preview from a previous open must never match this book merely
      // because both sessions happen to have the same edit sequence.
      _openGeneration++;
      _sessionId = _uuid.v4();
      _introChapterId = introId;
      _saveSeq++;
      _savedSeq = _saveSeq;
      _history.clear();
      final recognized = intro?.intro;
      if (recognized != null &&
          _requireBook().meta.description.trim().isEmpty) {
        // The recognized description is a real meta change; mark the change so
        // the debounced save persists it even when the book is closed at once.
        _book = _requireBook().copyWith(
          meta: _requireBook().meta.copyWith(description: recognized.description),
        );
        _markChange();
      }
    } finally {
      _openingCount--;
      if (_openingCount == 0 &&
          !_closed &&
          _sessionId == null &&
          _book != null) {
        _sessionId = _uuid.v4();
      }
      if (!_closed) notifyListeners();
    }
  }

  /// Saves before switching. A failed save leaves the current selection and
  /// dirty content intact so the UI can offer retry or cancel.
  Future<void> selectChapter(String chapterId) async {
    _requireBook();
    if (_activeChapterId == chapterId) return;
    if (!_book!.chapters.any(
      (chapter) => chapter.id == chapterId && !chapter.isVolume,
    )) {
      throw const ValidationFailure('章节不存在，请刷新书稿后重试。');
    }
    await flush();
    await _activate(chapterId);
  }

  void editChapterTitle(String chapterId, String title) {
    final book = _requireBook();
    final next = ChapterEdits.rename(book.chapters, chapterId, title);
    _commitStructure(next);
  }

  Future<String> createVolume(
    String title, {
    String? beforeChapterId,
    String? afterChapterId,
  }) => _runStructure(() async {
    final book = _requireBook();
    final id = _uuid.v4();
    final next = ChapterEdits.createVolume(
      book.chapters,
      Chapter(id: id, bookId: book.id, title: title.trim(), level: 1),
      beforeChapterId: beforeChapterId,
      afterChapterId: afterChapterId,
    );
    _commitStructure(next);
    return id;
  });

  Future<String> createChapter(
    String title, {
    String? volumeId,
    String? beforeChapterId,
    String? afterChapterId,
  }) => _runStructure(() async {
    final book = _requireBook();
    final id = _uuid.v4();
    final next = ChapterEdits.createChapter(
      book.chapters,
      Chapter(
        id: id,
        bookId: book.id,
        title: title.trim(),
        parentId: volumeId,
        blocks: <Block>[TextBlock(id: _uuid.v4(), text: '')],
      ),
      beforeChapterId: beforeChapterId,
      afterChapterId: afterChapterId,
    );
    _commitStructure(next, preferredChapterId: id);
    return id;
  });

  Future<void> moveChaptersToVolume(
    Set<String> chapterIds, {
    required String? volumeId,
  }) => _runStructure(() async {
    final next = ChapterEdits.moveChaptersToVolume(
      _requireBook().chapters,
      chapterIds,
      volumeId: volumeId,
    );
    _commitStructure(next);
  });

  void editBookMeta(BookMeta meta) {
    final book = _requireBook();
    if (jsonEncode(book.meta.toJson()) == jsonEncode(meta.toJson())) return;
    _history.recordMeta(_MetaEdit(book.meta, meta));
    _book = book.copyWith(meta: meta);
    _markChange();
  }

  void editLayout(LayoutOptions layout) {
    final book = _requireBook();
    if (jsonEncode(book.layout.toJson()) == jsonEncode(layout.toJson())) return;
    _history.recordOptions(_LayoutEdit(book.layout, layout));
    _book = book.copyWith(layout: layout);
    _markChange();
  }

  void editCoverOptions(CoverOptions options) {
    final book = _requireBook();
    if (jsonEncode(book.coverOptions.toJson()) ==
        jsonEncode(options.toJson())) {
      return;
    }
    _history.recordOptions(_CoverOptionsEdit(book.coverOptions, options));
    _book = book.copyWith(coverOptions: options);
    _markChange();
  }

  void setCoverImage(String assetId) {
    if (assetId.trim().isEmpty) {
      throw const ValidationFailure('请先选择封面图片。');
    }
    final book = _requireBook();
    if (book.coverMode == CoverMode.image && book.coverAssetId == assetId) {
      return;
    }
    _history.recordOptions(
      _CoverSourceEdit(
        beforeMode: book.coverMode,
        beforeAssetId: book.coverAssetId,
        afterMode: CoverMode.image,
        afterAssetId: assetId,
      ),
    );
    _book = book.copyWith(coverMode: CoverMode.image, coverAssetId: assetId);
    _markChange();
  }

  void setCoverTemplate() {
    final book = _requireBook();
    if (book.coverMode == CoverMode.template) return;
    _history.recordOptions(
      _CoverSourceEdit(
        beforeMode: book.coverMode,
        beforeAssetId: book.coverAssetId,
        afterMode: CoverMode.template,
        afterAssetId: book.coverAssetId,
      ),
    );
    _book = book.copyWith(coverMode: CoverMode.template);
    _markChange();
  }

  void editBlockText(String blockId, String text) {
    final chapter = activeChapter;
    if (chapter == null) {
      throw const ValidationFailure('请先打开章节正文。');
    }
    final index = chapter.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0 || chapter.blocks[index] is! TextBlock) {
      throw const ValidationFailure('段落不存在，请刷新章节后重试。');
    }
    final before = (chapter.blocks[index] as TextBlock).text;
    if (before == text) return;
    _replaceText(chapter.id, blockId, text);
    _history.recordText(chapter.id, blockId, before, text);
    _markChange(blockDirty: <String>{chapter.id});
  }

  Future<void> mergeWithPrevious(String chapterId) => _runStructure(() async {
    final chapters = _requireBook().chapters;
    final index = chapters.indexWhere((chapter) => chapter.id == chapterId);
    if (index < 0) throw const ValidationFailure('章节不存在，请刷新书稿。');
    var previous = index - 1;
    while (previous >= 0 && chapters[previous].isVolume) {
      previous--;
    }
    if (previous < 0) throw const ValidationFailure('首章不能并入上一章。');
    await _ensureLoaded(chapters[previous].id);
    await _ensureLoaded(chapterId);
    final next = ChapterEdits.mergeWithPrevious(
      _requireBook().chapters,
      chapterId,
    );
    _commitStructure(next, preferredChapterId: chapters[previous].id);
  });

  Future<void> deleteChapter(String chapterId) => _runStructure(() async {
    final chapters = _requireBook().chapters;
    final index = chapters.indexWhere((chapter) => chapter.id == chapterId);
    if (index < 0) {
      throw const ValidationFailure('章节不存在，请刷新书稿。');
    }
    if (!chapters[index].isVolume || _persistedIds.contains(chapterId)) {
      await _ensureLoaded(chapterId);
    }
    final next = ChapterEdits.delete(chapters, chapterId);
    final fallback =
        next
            .skip(index)
            .where((chapter) => !chapter.isVolume)
            .firstOrNull
            ?.id ??
        next.take(index).where((chapter) => !chapter.isVolume).lastOrNull?.id;
    _commitStructure(next, preferredChapterId: fallback);
    if (fallback != null && !_loadedIds.contains(fallback)) {
      await _activate(fallback);
    }
  });

  void promoteToVolume(String chapterId) {
    final next = ChapterEdits.promoteToVolume(
      _requireBook().chapters,
      chapterId,
    );
    _commitStructure(next);
  }

  void demoteToChapter(String chapterId) {
    final next = ChapterEdits.demoteToChapter(
      _requireBook().chapters,
      chapterId,
    );
    _commitStructure(next);
  }

  Future<String> splitAtParagraph(String chapterId, String blockId) =>
      _runStructure(() async {
        await _ensureLoaded(chapterId);
        final newId = _uuid.v4();
        final next = ChapterEdits.splitAtParagraph(
          _requireBook().chapters,
          chapterId,
          blockId,
          newId,
        );
        _commitStructure(next, preferredChapterId: newId);
        _loadedIds.add(newId);
        notifyListeners();
        return newId;
      });

  Future<void> setParagraphAsTitle(String chapterId, String blockId) =>
      _runStructure(() async {
        await _ensureLoaded(chapterId);
        final next = ChapterEdits.setParagraphAsTitle(
          _requireBook().chapters,
          chapterId,
          blockId,
        );
        _commitStructure(next, preferredChapterId: chapterId);
      });

  Future<AuditReport> auditBook() => _scan(_auditJob);

  Future<List<MissedChapterCandidate>> findMissedChapterCandidates() =>
      _scan(_missedChapterJob);

  Future<ToolPreview> previewReplace(ReplaceOptions options) =>
      _scan(_replaceJob, options: options);

  Future<ToolPreview> previewRenumber() => _scan(_renumberJob);

  Future<ToolPreview> previewConvert(
    ConvertMode mode,
    Map<String, String> dictionaries,
  ) => _scan(_convertJob, mode: mode, dictionaries: dictionaries);

  void cancelTool() {
    if (_aiTextCommandRunning) _aiTextCancelled = true;
    if (_toolIsolateRunning) _jobs.cancelActive();
  }

  Future<R> _scan<R>(
    R Function(_ProofreadingInput, void Function(double, String)) compute, {
    ReplaceOptions? options,
    ConvertMode? mode,
    Map<String, String>? dictionaries,
  }) async {
    _requireBook();
    if (_toolRunning || _jobs.isBusy) {
      throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
    }
    _toolRunning = true;
    _toolProgress = null;
    notifyListeners();
    try {
      await flush();
      final seq = _saveSeq;
      final fullBook = await _fullBookSnapshot(seq);
      _ensureToolCurrent(seq);
      final work = _jobs.run<_ProofreadingInput, R>(
        _ProofreadingInput(fullBook, seq, options, mode, dictionaries),
        compute,
        revision: seq,
        onProgress: (progress) {
          if (_closed || !_toolRunning || progress.revision != _saveSeq) {
            return;
          }
          _toolProgress = progress;
          notifyListeners();
        },
      );
      _toolIsolateRunning = true;
      final result = await work;
      _ensureToolCurrent(seq);
      return result;
    } finally {
      _toolIsolateRunning = false;
      _toolRunning = false;
      _toolProgress = null;
      if (!_closed) notifyListeners();
    }
  }

  Future<Book> _fullBookSnapshot(int seq) async {
    final source = _requireBook();
    final chapters = <Chapter>[];
    for (final chapter in source.chapters) {
      _ensureToolCurrent(seq);
      if (_loadedIds.contains(chapter.id)) {
        chapters.add(chapter);
      } else {
        final loaded = await _readChapter(source.id, chapter.id);
        if (loaded == null) {
          throw const ValidationFailure('章节内容无法读取，请刷新书稿。');
        }
        chapters.add(chapter.copyWith(blocks: loaded.blocks));
      }
    }
    _ensureToolCurrent(seq);
    return source.copyWith(chapters: chapters);
  }

  void _ensureToolCurrent(int seq) {
    if (_saveSeq != seq) {
      throw const ValidationFailure('书稿已改变，请重新检查或预览后再执行。');
    }
  }

  /// Applies a preview in one undoable command. Every patch is verified
  /// before the in-memory book is changed, including the actual byte budget.
  Future<void> applyToolPreview(
    ToolPreview preview, {
    String? expectedSessionId,
    bool Function()? isCancelled,
    Future<void> Function(void Function() commit)? commitGuard,
  }) async {
    final book = _requireBook();
    if (isCancelled?.call() ?? false) throw const TaskCancelled();
    if (expectedSessionId != null && sessionId != expectedSessionId) {
      throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
    }
    _ensureToolCurrent(preview.baseRevision);
    if (preview.patches.isEmpty) return;
    final bodyChangedIds = preview.patches
        .where((patch) => patch.blockId != null)
        .map((patch) => patch.chapterId)
        .toSet();
    for (final id in bodyChangedIds) {
      await _ensureLoaded(id);
    }
    _ensureToolCurrent(preview.baseRevision);
    final current = _requireBook();
    if (isCancelled?.call() ?? false) throw const TaskCancelled();
    if (expectedSessionId != null && sessionId != expectedSessionId) {
      throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
    }
    if (current.id != book.id) {
      throw const ValidationFailure('当前书籍已切换，请重新预览。');
    }
    final next = List<Chapter>.of(current.chapters);
    final indices = <String, int>{
      for (var i = 0; i < next.length; i++) next[i].id: i,
    };
    final seen = <String>{};
    var bytes = 0;
    for (final patch in preview.patches) {
      final key = '${patch.chapterId}\u0000${patch.blockId ?? ''}';
      if (!seen.add(key)) {
        throw const ValidationFailure('预览包含重复修改，请重新生成预览。');
      }
      final index = indices[patch.chapterId];
      if (index == null) {
        throw const ValidationFailure('章节已变化，请重新生成预览。');
      }
      final chapter = next[index];
      if (patch.blockId == null) {
        if (chapter.title != patch.before) {
          throw const ValidationFailure('章节标题已变化，请重新生成预览。');
        }
        next[index] = chapter.copyWith(title: patch.after);
      } else {
        final blockIndex = chapter.blocks.indexWhere(
          (block) => block.id == patch.blockId,
        );
        if (blockIndex < 0 || chapter.blocks[blockIndex] is! TextBlock) {
          throw const ValidationFailure('正文段落已变化，请重新生成预览。');
        }
        final block = chapter.blocks[blockIndex] as TextBlock;
        if (block.text != patch.before) {
          throw const ValidationFailure('正文段落已变化，请重新生成预览。');
        }
        final blocks = List<Block>.of(chapter.blocks);
        blocks[blockIndex] = TextBlock(id: block.id, text: patch.after);
        next[index] = chapter.copyWith(blocks: blocks);
      }
      bytes +=
          utf8.encode(patch.before).length +
          utf8.encode(patch.after).length +
          utf8.encode(patch.chapterId).length +
          utf8.encode(patch.blockId ?? '').length;
      if (bytes > _history.byteBudget) {
        throw const ValidationFailure('本次修改超过撤销内存预算，请缩小处理范围。');
      }
    }
    void commit() {
      _ensureToolCurrent(preview.baseRevision);
      if (isCancelled?.call() ?? false) throw const TaskCancelled();
      if (_requireBook().id != book.id ||
          expectedSessionId != null && sessionId != expectedSessionId) {
        throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
      }
      _commitStructure(next, requireUndoBudget: true);
    }

    if (commitGuard == null) {
      commit();
    } else {
      await commitGuard(commit);
    }
  }

  Future<Book> readRuleSnapshot({
    RuleScanLimits limits = const RuleScanLimits(),
    bool Function()? isCancelled,
  }) => _runStructure(() async {
    final source = _requireBook();
    final identity = sessionId;
    final revision = _saveSeq;
    if (identity == null || _toolRunning || _jobs.isBusy) {
      throw const ValidationFailure('另一项任务正在运行或书稿尚未就绪。');
    }
    if (!limits.isValid || source.chapters.length > limits.maxChapters) {
      throw const ValidationFailure('全书试跑超出章节预算。');
    }
    _toolRunning = true;
    _aiTextCommandRunning = true;
    _aiTextCancelled = false;
    notifyListeners();
    try {
      final chapters = <Chapter>[];
      var characters = 0;
      var blocks = 0;
      void ensureCurrent() {
        if (_aiTextCancelled || (isCancelled?.call() ?? false)) {
          throw const TaskCancelled();
        }
        if (sessionId != identity ||
            _book?.id != source.id ||
            _saveSeq != revision) {
          throw const ValidationFailure('书稿已变化，请重新试跑规则。');
        }
      }

      for (final chapter in source.chapters) {
        ensureCurrent();
        final body = _loadedIds.contains(chapter.id)
            ? _chapter(chapter.id)
            : await _readChapter(source.id, chapter.id);
        ensureCurrent();
        if (body == null) {
          throw const ValidationFailure('部分章节无法读取，未完成全书试跑。');
        }
        blocks += body.blocks.length;
        for (final block in body.blocks.whereType<TextBlock>()) {
          characters += block.text.length;
        }
        if (blocks > limits.maxBlocks || characters > limits.maxInputUtf16) {
          throw const ValidationFailure('全书试跑超出正文预算。');
        }
        chapters.add(
          chapter.copyWith(blocks: List<Block>.unmodifiable(body.blocks)),
        );
      }
      ensureCurrent();
      return source.copyWith(chapters: List<Chapter>.unmodifiable(chapters));
    } finally {
      _toolRunning = false;
      _aiTextCommandRunning = false;
      _aiTextCancelled = false;
      if (!_closed) notifyListeners();
    }
  });

  Future<Chapter> readAiSelectionChapter(
    String chapterId, {
    bool Function()? isCancelled,
  }) async {
    final source = _requireBook();
    final identity = sessionId;
    final revision = _saveSeq;
    if (_toolRunning || _jobs.isBusy) {
      throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
    }
    final chapters = source.chapters.where(
      (chapter) => chapter.id == chapterId,
    );
    if (identity == null || chapters.length != 1 || chapters.single.isVolume) {
      throw const ValidationFailure('请选择有效的 AI 分析章节。');
    }

    void ensureCurrent() {
      if (isCancelled?.call() ?? false) throw const TaskCancelled();
      if (sessionId != identity ||
          _saveSeq != revision ||
          _book?.id != source.id) {
        throw const ValidationFailure('书稿已变化，请重新确认 AI 分析选区。');
      }
    }

    ensureCurrent();
    await flush();
    ensureCurrent();
    return _runStructure(() async {
      ensureCurrent();
      if (_toolRunning || _jobs.isBusy) {
        throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
      }
      await _ensureLoaded(chapterId);
      ensureCurrent();
      return _chapter(chapterId)!;
    });
  }

  Future<List<AiContextBlock>> readAiContext(
    List<String> chapterIds, {
    bool Function()? isCancelled,
  }) async => (await readAiContextSnapshot(
    chapterIds,
    isCancelled: isCancelled,
  )).blocks;

  Future<AiProofreadingSnapshot> readAiContextSnapshot(
    List<String> chapterIds, {
    bool Function()? isCancelled,
  }) async {
    final selected = List<String>.unmodifiable(chapterIds);
    final source = _requireBook();
    final identity = sessionId;
    final revision = _saveSeq;
    void ensureCurrent() {
      if (isCancelled?.call() ?? false) throw const TaskCancelled();
      if (identity == null ||
          sessionId != identity ||
          _saveSeq != revision ||
          _book?.id != source.id) {
        throw const ValidationFailure('书稿已变化，请重新确认 AI 分析范围。');
      }
    }

    ensureCurrent();
    await flush();
    ensureCurrent();
    return _runStructure(() async {
      ensureCurrent();
      if (_toolRunning || _jobs.isBusy) {
        throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
      }
      if (identity == null ||
          selected.isEmpty ||
          selected.length > 128 ||
          selected.toSet().length != selected.length) {
        throw const ValidationFailure('请选择有效的 AI 分析章节范围。');
      }
      final chapters = <String, Chapter>{
        for (final chapter in source.chapters) chapter.id: chapter,
      };
      if (selected.any(
        (id) => chapters[id] == null || chapters[id]!.isVolume,
      )) {
        throw const ValidationFailure('AI 分析范围包含无效章节或卷。');
      }
      final blocks = <AiContextBlock>[];
      final localChapters = <String, Chapter>{};
      var characters = 0;
      var blockCount = 0;
      _deferredBodyEviction = true;
      for (final id
          in source.chapters
              .map((chapter) => chapter.id)
              .where(selected.contains)) {
        if (isCancelled?.call() ?? false) throw const TaskCancelled();
        await _ensureLoaded(id);
        if (isCancelled?.call() ?? false) throw const TaskCancelled();
        if (sessionId != identity ||
            _saveSeq != revision ||
            _book?.id != source.id) {
          throw const ValidationFailure('书稿已变化，请重新确认 AI 分析范围。');
        }
        final chapter = _chapter(id)!;
        blockCount += chapter.blocks.length;
        if (blockCount > 10000) {
          throw const ValidationFailure('AI 分析范围的内容块超过预算，请减少章节。');
        }
        localChapters[id] = chapter;
        for (final block in chapter.blocks) {
          if (block is! TextBlock) continue;
          characters += block.text.length;
          if (characters > aiMaxContextCharacters || blocks.length >= 10000) {
            throw const ValidationFailure('AI 分析范围超过预算，请减少章节。');
          }
          blocks.add(
            AiContextBlock(
              chapterId: id,
              chapterTitle: chapter.title,
              blockId: block.id,
              text: block.text,
            ),
          );
        }
      }
      if (blocks.isEmpty) throw const ValidationFailure('选定章节没有可分析的正文。');
      ensureCurrent();
      return AiProofreadingSnapshot(blocks: blocks, chapters: localChapters);
    });
  }

  Future<void> applyAiTextProposals(
    List<AiTextProposal> proposals, {
    required Set<String> selectedIds,
    Future<void> Function(void Function() commit)? commitGuard,
  }) {
    final proposalSnapshot = List<AiTextProposal>.unmodifiable(proposals);
    final selectedSnapshot = Set<String>.unmodifiable(selectedIds);
    return _runStructure(() async {
      final source = _requireBook();
      final currentSessionId = sessionId;
      if (currentSessionId == null) {
        throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
      }
      if (_toolRunning || _jobs.isBusy) {
        throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
      }
      _toolRunning = true;
      _aiTextCommandRunning = true;
      _aiTextCancelled = false;
      _toolProgress = null;
      notifyListeners();
      try {
        final seq = _saveSeq;
        final targets = proposalSnapshot
            .where((proposal) => selectedSnapshot.contains(proposal.id))
            .map((proposal) => proposal.target.chapterId)
            .toSet();
        for (final id in targets) {
          await _ensureLoaded(id);
        }
        if (_aiTextCancelled) throw const TaskCancelled();
        if (sessionId != currentSessionId ||
            _book?.id != source.id ||
            _saveSeq != seq) {
          throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
        }
        final selectedBlocks = <String, Set<String>>{};
        for (final proposal in proposalSnapshot) {
          if (!selectedSnapshot.contains(proposal.id)) continue;
          selectedBlocks
              .putIfAbsent(proposal.target.chapterId, () => <String>{})
              .add(proposal.target.blockId);
        }
        var totalCharacters = 0;
        final targetChapters = <Chapter>[];
        for (final chapter in _requireBook().chapters) {
          final ids = selectedBlocks[chapter.id];
          if (ids == null) continue;
          final blocks = <Block>[];
          for (final block in chapter.blocks) {
            if (!ids.contains(block.id)) continue;
            if (block is! TextBlock) {
              throw const ValidationFailure('AI 文本提案目标不是正文段落。');
            }
            totalCharacters += block.text.length;
            if (totalCharacters > aiMaxContextCharacters) {
              throw const ValidationFailure('AI 文本提案正文超出验证预算，请缩小范围。');
            }
            blocks.add(block);
          }
          targetChapters.add(
            Chapter(
              id: chapter.id,
              bookId: chapter.bookId,
              title: '',
              level: chapter.level,
              blocks: List<Block>.unmodifiable(blocks),
            ),
          );
        }
        final work = _jobs.run<_AiTextApplicationInput, ToolPreview>(
          _AiTextApplicationInput(
            source.id,
            currentSessionId,
            seq,
            List<Chapter>.unmodifiable(targetChapters),
            proposalSnapshot,
            selectedSnapshot,
            _history.byteBudget,
          ),
          _compileAiTextJob,
          revision: seq,
          onProgress: (progress) {
            if (_closed ||
                !_aiTextCommandRunning ||
                sessionId != currentSessionId ||
                progress.revision != _saveSeq) {
              return;
            }
            _toolProgress = progress;
            notifyListeners();
          },
        );
        _toolIsolateRunning = true;
        final preview = await work;
        _toolIsolateRunning = false;
        if (_aiTextCancelled) throw const TaskCancelled();
        if (sessionId != currentSessionId ||
            _book?.id != source.id ||
            _saveSeq != seq) {
          throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
        }
        if (preview.patches.isEmpty) return;
        await applyToolPreview(
          preview,
          expectedSessionId: currentSessionId,
          isCancelled: () => _aiTextCancelled,
          commitGuard: commitGuard,
        );
      } finally {
        _toolIsolateRunning = false;
        _toolRunning = false;
        _aiTextCommandRunning = false;
        _aiTextCancelled = false;
        _toolProgress = null;
        if (!_closed) notifyListeners();
      }
    });
  }

  Future<void> applyAiChanges({
    required List<AiTextProposal> textProposals,
    required List<AiChapterSplitProposal> splitProposals,
    required Set<String> selectedIds,
    Future<void> Function(void Function() commit)? commitGuard,
  }) {
    final textSnapshot = List<AiTextProposal>.unmodifiable(textProposals);
    final splitSnapshot = List<AiChapterSplitProposal>.unmodifiable(
      splitProposals,
    );
    final selectedSnapshot = Set<String>.unmodifiable(selectedIds);
    final allIds = <String>{};
    for (final id in [
      ...textSnapshot.map((proposal) => proposal.id),
      ...splitSnapshot.map((proposal) => proposal.id),
    ]) {
      if (id.trim().isEmpty || id.length > 128 || !allIds.add(id)) {
        return Future<void>.error(const ValidationFailure('变更提案标识无效，请重新分析。'));
      }
    }
    if (allIds.length > 100 ||
        selectedSnapshot.length > 100 ||
        !selectedSnapshot.every(allIds.contains)) {
      return Future<void>.error(
        const ValidationFailure('变更提案范围无效，请缩小范围或重新分析。'),
      );
    }
    if (!splitSnapshot.any(
          (proposal) => selectedSnapshot.contains(proposal.id),
        ) &&
        !textSnapshot.any(
          (proposal) =>
              selectedSnapshot.contains(proposal.id) &&
              (proposal.action == AiTextProposalAction.removeBlock ||
                  proposal.action == AiTextProposalAction.renameChapter),
        )) {
      return applyAiTextProposals(
        textSnapshot,
        selectedIds: selectedSnapshot,
        commitGuard: commitGuard,
      );
    }
    return _runStructure(() async {
      final source = _requireBook();
      final currentSessionId = sessionId;
      final seq = _saveSeq;
      if (currentSessionId == null) {
        throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
      }
      if (_toolRunning || _jobs.isBusy) {
        throw const ValidationFailure('另一项任务正在运行，请等待完成或先取消。');
      }
      final targetIds = <String>{
        for (final proposal in textSnapshot)
          if (selectedSnapshot.contains(proposal.id)) proposal.target.chapterId,
        for (final proposal in splitSnapshot)
          if (selectedSnapshot.contains(proposal.id)) proposal.target.chapterId,
      };
      _toolRunning = true;
      _aiTextCommandRunning = true;
      _aiTextCancelled = false;
      _toolProgress = null;
      notifyListeners();
      void ensureCurrent() {
        if (_aiTextCancelled) throw const TaskCancelled();
        if (sessionId != currentSessionId ||
            _book?.id != source.id ||
            _saveSeq != seq) {
          throw const ValidationFailure('提案已失效，请基于当前书稿重新分析。');
        }
      }

      try {
        for (final id in targetIds) {
          ensureCurrent();
          await _ensureLoaded(id);
        }
        ensureCurrent();
        final current = _requireBook();
        var characters = 0;
        var blockCount = 0;
        final inputChapters = <Chapter>[];
        for (final chapter in current.chapters) {
          final selected = targetIds.contains(chapter.id);
          if (selected) {
            for (final block in chapter.blocks) {
              characters += block.plainText.length;
              blockCount++;
              if (characters > aiMaxContextCharacters || blockCount > 10000) {
                throw const ValidationFailure('变更验证超出正文预算，请缩小处理范围。');
              }
            }
          }
          inputChapters.add(
            chapter.copyWith(
              blocks: selected
                  ? List<Block>.unmodifiable(chapter.blocks)
                  : const <Block>[],
            ),
          );
        }
        final identities = <String, AiChapterSplitIdentity>{
          for (final proposal in splitSnapshot)
            if (selectedSnapshot.contains(proposal.id))
              proposal.id: AiChapterSplitIdentity(
                chapterId: _uuid.v4(),
                blockId: _uuid.v4(),
                volumeId: proposal.headingLevel == 1 ? _uuid.v4() : null,
              ),
        };
        final work = _jobs.run<_AiChangeApplicationInput, List<Chapter>>(
          _AiChangeApplicationInput(
            current.copyWith(
              chapters: List<Chapter>.unmodifiable(inputChapters),
            ),
            currentSessionId,
            seq,
            textSnapshot,
            splitSnapshot,
            selectedSnapshot,
            identities,
            _history.byteBudget,
          ),
          _compileAiChangesJob,
          revision: seq,
          onProgress: (progress) {
            if (!_closed &&
                _aiTextCommandRunning &&
                sessionId == currentSessionId &&
                progress.revision == _saveSeq) {
              _toolProgress = progress;
              notifyListeners();
            }
          },
        );
        _toolIsolateRunning = true;
        final compiled = await work;
        _toolIsolateRunning = false;
        ensureCurrent();
        void commit() {
          ensureCurrent();
          final originals = {
            for (final chapter in _requireBook().chapters) chapter.id: chapter,
          };
          final next = <Chapter>[
            for (final chapter in compiled)
              if (originals.containsKey(chapter.id) &&
                  !targetIds.contains(chapter.id))
                chapter.copyWith(blocks: originals[chapter.id]!.blocks)
              else
                chapter,
          ];
          _commitStructure(next, requireUndoBudget: true);
        }

        if (commitGuard == null) {
          commit();
        } else {
          await commitGuard(commit);
        }
      } finally {
        _toolIsolateRunning = false;
        _toolRunning = false;
        _aiTextCommandRunning = false;
        _aiTextCancelled = false;
        _toolProgress = null;
        if (!_closed) notifyListeners();
      }
    });
  }

  /// Replaces the current chapter tree after the caller has shown the parsed
  /// result and obtained explicit destructive confirmation. Session undo is
  /// cleared because it refers to the replaced tree.
  void replaceAllChapters(
    List<Chapter> chapters,
    ParseOptions options, {
    required int expectedSaveSeq,
  }) {
    final book = _requireBook();
    _ensureToolCurrent(expectedSaveSeq);
    final normalized = ChapterEdits.normalize(chapters);
    final ids = normalized.map((chapter) => chapter.id).toSet();
    if (normalized.any((chapter) => chapter.bookId != book.id) ||
        ids.length != normalized.length) {
      throw const ValidationFailure('识别结果的章节不属于当前书籍。');
    }
    final removedIds = book.chapters.map((chapter) => chapter.id).toSet();
    final count = normalized.fold<int>(
      0,
      (total, chapter) => total + WordCount.ofBlocks(chapter.blocks),
    );
    _history.clear();
    _book = book.copyWith(
      chapters: normalized,
      parseOptions: options,
      wordCount: count,
    );
    _loadedIds
      ..clear()
      ..addAll(ids);
    // The parsed tree carries the bodies, so the intro carrier is visible
    // immediately. Book metadata stays untouched here: the description is
    // filled on the next open, exactly like an existing stored book.
    _introChapterId = detectBookIntro(normalized)?.chapterId;
    _activeChapterId = normalized
        .where(
          (chapter) =>
              !chapter.isVolume &&
              (_introChapterId == null || chapter.id != _introChapterId),
        )
        .firstOrNull
        ?.id;
    _markChange(blockDirty: ids, affected: <String>{...removedIds, ...ids});
  }

  Future<void> undo() => _runStructure(() async {
    _requireBook();
    final entry = _history.takeUndo();
    if (entry == null) return;
    try {
      await _applyHistory(entry, redo: false);
    } catch (_) {
      _history.takeRedo();
      rethrow;
    }
  });

  Future<void> redo() => _runStructure(() async {
    _requireBook();
    final entry = _history.takeRedo();
    if (entry == null) return;
    try {
      await _applyHistory(entry, redo: true);
    } catch (_) {
      _history.takeUndo();
      rethrow;
    }
  });

  Future<void> _applyHistory(_EditEntry entry, {required bool redo}) async {
    if (entry is _LayoutEdit) {
      _book = _requireBook().copyWith(
        layout: redo ? entry.after : entry.before,
      );
      _markChange();
      return;
    }
    if (entry is _CoverOptionsEdit) {
      _book = _requireBook().copyWith(
        coverOptions: redo ? entry.after : entry.before,
      );
      _markChange();
      return;
    }
    if (entry is _CoverSourceEdit) {
      final book = _requireBook();
      final mode = redo ? entry.afterMode : entry.beforeMode;
      final assetId = redo ? entry.afterAssetId : entry.beforeAssetId;
      _book = book.copyWith(
        coverMode: mode,
        coverAssetId: assetId,
        clearCoverAssetId: assetId == null,
      );
      _markChange();
      return;
    }
    if (entry is _MetaEdit) {
      _book = _requireBook().copyWith(meta: redo ? entry.after : entry.before);
      _markChange();
      return;
    }
    if (entry is _TextEdit) {
      await _ensureLoaded(entry.chapterId);
      _replaceText(
        entry.chapterId,
        entry.blockId,
        redo ? entry.after : entry.before,
      );
      _markChange(blockDirty: <String>{entry.chapterId});
      await _activate(entry.chapterId);
      return;
    }
    final patch = entry as _StructureEdit;
    final current = _requireBook();
    final slots = redo ? patch.after : patch.before;
    final affected = <String>{...patch.before.keys, ...patch.after.keys};
    final next = current.chapters
        .where((chapter) => !affected.contains(chapter.id))
        .toList();
    final sorted = slots.values.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final blockDirty = redo ? patch.redoBlockDirty : patch.undoBlockDirty;
    for (final slot in sorted) {
      final currentChapter = current.chapters
          .where((chapter) => chapter.id == slot.chapter.id)
          .firstOrNull;
      final restored =
          currentChapter != null &&
              _loadedIds.contains(slot.chapter.id) &&
              !blockDirty.contains(slot.chapter.id)
          ? slot.chapter.copyWith(blocks: currentChapter.blocks)
          : slot.chapter;
      next.insert(slot.index.clamp(0, next.length), restored);
    }
    _book = current.copyWith(
      chapters: next,
      wordCount:
          current.wordCount + (redo ? patch.wordDelta : -patch.wordDelta),
    );
    _markChange(blockDirty: blockDirty, affected: affected);
    final preferred = redo ? patch.afterSelection : patch.beforeSelection;
    _activeChapterId = _selectableChapterId(next, preferred);
    if (_activeChapterId != null && blockDirty.contains(_activeChapterId)) {
      _loadedIds.add(_activeChapterId!);
    }
    _loadedIds.removeWhere((id) => !next.any((chapter) => chapter.id == id));
    final selected = _activeChapterId;
    if (selected != null && !_loadedIds.contains(selected)) {
      await _ensureLoaded(selected);
    }
    notifyListeners();
  }

  /// Explicit lifecycle/return action. Call before disposing the session.
  Future<void> flush() async {
    _requireOpen();
    _saveTimer?.cancel();
    while (dirty) {
      final inFlight = _saving;
      if (inFlight != null) {
        await inFlight;
      } else {
        await _saveOnce();
      }
    }
  }

  Future<void> retrySave() => flush();
  Future<void> onLifecyclePause() => flush();

  /// Flushes on route/window close and then releases the notifier.
  Future<void> close() async {
    _closing = true;
    if (_aiTextCommandRunning) cancelTool();
    try {
      await flush();
      _closed = true;
      _sessionId = null;
      dispose();
    } catch (_) {
      _closing = false;
      rethrow;
    }
  }

  Future<void> _saveOnce() async {
    if (!dirty) return;
    final book = _requireBook();
    final capturedSeq = _saveSeq;
    final dirtyIds = _dirtyChapterSeq.entries
        .where((entry) => entry.value <= capturedSeq)
        .map((entry) => entry.key)
        .toSet();
    final deletedIds = _deletedChapterSeq.entries
        .where((entry) => entry.value <= capturedSeq)
        .map((entry) => entry.key)
        .toSet();
    final completer = Completer<void>();
    _saving = completer.future;
    notifyListeners();
    try {
      final saved = await _store.saveBook(
        book,
        expectedRevision: book.revision,
        dirtyChapterIds: dirtyIds,
        deletedChapterIds: deletedIds,
      );
      final current = _requireBook();
      _book = current.copyWith(
        revision: saved.revision,
        updatedAt: _saveSeq == capturedSeq
            ? saved.updatedAt
            : current.updatedAt,
        wordCount: _saveSeq == capturedSeq
            ? saved.wordCount
            : current.wordCount,
      );
      _savedSeq = capturedSeq;
      _dirtyChapterSeq.removeWhere((_, seq) => seq <= capturedSeq);
      _deletedChapterSeq.removeWhere((_, seq) => seq <= capturedSeq);
      _persistedIds
        ..clear()
        ..addAll(book.chapters.map((chapter) => chapter.id));
      if (_saveSeq > capturedSeq) {
        final currentIds = current.chapters
            .map((chapter) => chapter.id)
            .toSet();
        for (final id in _persistedIds.difference(currentIds)) {
          _deletedChapterSeq[id] = _saveSeq;
        }
      } else if (_structuralCommandRunning) {
        _deferredBodyEviction = true;
      } else {
        _evictCleanBodies();
      }
      _saveError = null;
      completer.complete();
    } catch (error, stackTrace) {
      _saveError = switch (error) {
        BookConflictException() => const ValidationFailure(
          '书稿已在其他位置更新，当前修改仍保留。',
          hint: '先保留当前窗口，再检查另一处的修改。',
        ),
        final AppFailure failure => failure,
        _ => StorageFailure(
          '保存失败，当前修改仍保留。',
          cause: error,
          stackTrace: stackTrace,
        ),
      };
      completer.completeError(_saveError!, stackTrace);
    } finally {
      _saving = null;
      notifyListeners();
    }
    await completer.future;
  }

  Future<T> _runStructure<T>(Future<T> Function() operation) async {
    if (_structuralCommandRunning) {
      throw const ValidationFailure('正在调整目录，请稍后重试。');
    }
    _structuralCommandRunning = true;
    try {
      return await operation();
    } finally {
      _structuralCommandRunning = false;
      if (_deferredBodyEviction) {
        _deferredBodyEviction = false;
        if (!_closed && !dirty && _saving == null) _evictCleanBodies();
      }
    }
  }

  Future<void> _activate(String id) async {
    if (_chapter(id)?.isVolume ?? false) {
      throw const ValidationFailure('卷没有可编辑的正文。');
    }
    await _ensureLoaded(id);
    final previous = _activeChapterId;
    _activeChapterId = id;
    if (previous != null &&
        previous != id &&
        !_dirtyChapterSeq.containsKey(previous)) {
      final chapter = _chapter(previous);
      if (chapter != null) {
        if (_structuralCommandRunning) {
          _deferredBodyEviction = true;
        } else {
          _book = _withChapter(
            _requireBook(),
            chapter.copyWith(blocks: const <Block>[]),
          );
          _loadedIds.remove(previous);
        }
      }
    }
    notifyListeners();
  }

  Future<void> _ensureLoaded(String id) async {
    if (_loadedIds.contains(id)) return;
    final book = _requireBook();
    final generation = _openGeneration;
    if (!book.chapters.any((chapter) => chapter.id == id)) {
      throw const ValidationFailure('章节不存在，请刷新书稿。');
    }
    final loaded = await _readChapter(book.id, id);
    if (_openGeneration != generation) {
      throw const ValidationFailure('当前书籍已切换，请重新操作。');
    }
    if (loaded == null) {
      throw const ValidationFailure('章节内容无法读取，请刷新书稿。');
    }
    // Loading must never replace newer in-memory structure or a dirty body.
    if (_loadedIds.contains(id)) return;
    _book = _withChapter(
      _requireBook(),
      _bodyOnStructure(_requireBook(), loaded),
    );
    _loadedIds.add(id);
    notifyListeners();
  }

  Chapter _bodyOnStructure(Book book, Chapter loaded) {
    final structural = book.chapters.firstWhere(
      (chapter) => chapter.id == loaded.id,
    );
    return structural.copyWith(blocks: loaded.blocks);
  }

  Future<Book?> _readBook(String bookId) async {
    try {
      return await _store.loadBook(bookId);
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw StorageFailure(
        '无法打开书籍，请检查本地存储后重试。',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Chapter?> _readChapter(String bookId, String chapterId) async {
    try {
      return await _store.loadChapter(bookId, chapterId);
    } on AppFailure {
      rethrow;
    } catch (error, stackTrace) {
      throw StorageFailure(
        '无法读取章节，请检查本地存储后重试。',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Loads the preface-shaped chapters near the start of the book and detects
  /// the intro carrier among them. A failed candidate read only leaves that
  /// chapter unrecognized, never fails the open.
  Future<({BookIntro intro})?> _recognizeIntro(Book loaded) async {
    final candidates = <Chapter>[];
    var position = 0;
    for (final chapter in loaded.chapters) {
      if (chapter.isVolume) continue;
      if (position >= maxIntroScanChapters) break;
      position++;
      if (!isIntroChapterCandidate(chapter)) continue;
      final candidate = chapter.blocks.isNotEmpty
          ? chapter
          : await _tryReadCandidate(loaded.id, chapter.id);
      if (candidate == null) continue;
      candidates.add(candidate);
    }
    final intro = detectBookIntro(candidates);
    return intro == null ? null : (intro: intro);
  }

  Future<Chapter?> _tryReadCandidate(String bookId, String chapterId) async {
    try {
      return await _readChapter(bookId, chapterId);
    } on Object {
      return null;
    }
  }

  void _replaceText(String chapterId, String blockId, String text) {
    final book = _requireBook();
    final chapter = _chapter(chapterId);
    if (chapter == null) throw const ValidationFailure('章节不存在，请刷新书稿。');
    final index = chapter.blocks.indexWhere((block) => block.id == blockId);
    if (index < 0 || chapter.blocks[index] is! TextBlock) {
      throw const ValidationFailure('段落不存在，请刷新章节。');
    }
    final before = (chapter.blocks[index] as TextBlock).text;
    final blocks = List<Block>.of(chapter.blocks);
    blocks[index] = TextBlock(id: blockId, text: text);
    _book = _withChapter(book, chapter.copyWith(blocks: blocks)).copyWith(
      wordCount:
          book.wordCount - WordCount.ofText(before) + WordCount.ofText(text),
    );
  }

  void _commitStructure(
    List<Chapter> next, {
    String? preferredChapterId,
    bool requireUndoBudget = false,
  }) {
    final book = _requireBook();
    final before = book.chapters;
    final beforeSlots = <String, _ChapterSlot>{};
    final afterSlots = <String, _ChapterSlot>{};
    final beforeById = {
      for (var i = 0; i < before.length; i++)
        before[i].id: _ChapterSlot(i, before[i]),
    };
    final afterById = {
      for (var i = 0; i < next.length; i++)
        next[i].id: _ChapterSlot(i, next[i]),
    };
    final ids = <String>{...beforeById.keys, ...afterById.keys};
    final redoBlockDirty = <String>{};
    final undoBlockDirty = <String>{};
    var wordDelta = 0;
    for (final id in ids) {
      final old = beforeById[id];
      final fresh = afterById[id];
      if (_sameChapter(old?.chapter, fresh?.chapter)) continue;
      if (old != null) beforeSlots[id] = old;
      if (fresh != null) afterSlots[id] = fresh;
      final blocksChanged = !_sameBlocks(
        old?.chapter.blocks,
        fresh?.chapter.blocks,
      );
      if (blocksChanged) {
        if (fresh != null) redoBlockDirty.add(id);
        if (old != null) undoBlockDirty.add(id);
      }
      wordDelta +=
          WordCount.ofBlocks(fresh?.chapter.blocks ?? const <Block>[]) -
          WordCount.ofBlocks(old?.chapter.blocks ?? const <Block>[]);
    }
    if (beforeSlots.isEmpty && afterSlots.isEmpty) return;
    final nextSelection = preferredChapterId ?? _activeChapterId;
    final edit = _StructureEdit(
      before: beforeSlots,
      after: afterSlots,
      beforeSelection: _activeChapterId,
      afterSelection: nextSelection,
      wordDelta: wordDelta,
      redoBlockDirty: redoBlockDirty,
      undoBlockDirty: undoBlockDirty,
    );
    if (requireUndoBudget && edit.deltaBytes > _history.byteBudget) {
      throw const ValidationFailure('本次修改超过撤销内存预算，请缩小处理范围。');
    }
    _history.recordStructure(edit);
    _book = book.copyWith(
      chapters: next,
      wordCount: book.wordCount + wordDelta,
    );
    _markChange(blockDirty: redoBlockDirty, affected: ids);
    _activeChapterId = _selectableChapterId(next, nextSelection);
    for (final id in redoBlockDirty) {
      _loadedIds.add(id);
    }
    _loadedIds.removeWhere((id) => !next.any((chapter) => chapter.id == id));
    notifyListeners();
  }

  void _markChange({
    Set<String> blockDirty = const <String>{},
    Set<String> affected = const <String>{},
  }) {
    _saveSeq++;
    _book = _requireBook().copyWith(updatedAt: DateTime.now().toUtc());
    final ids = <String>{...affected, ...blockDirty};
    final existing = {
      for (final chapter in _requireBook().chapters) chapter.id,
    };
    for (final id in ids) {
      if (existing.contains(id)) {
        _deletedChapterSeq.remove(id);
        if (blockDirty.contains(id)) _dirtyChapterSeq[id] = _saveSeq;
      } else {
        _dirtyChapterSeq.remove(id);
        if (_persistedIds.contains(id)) {
          _deletedChapterSeq[id] = _saveSeq;
        } else {
          _deletedChapterSeq.remove(id);
        }
      }
    }
    _saveError = null;
    _saveTimer?.cancel();
    _saveTimer = Timer(_debounce, () {
      unawaited(flush().catchError((Object _) {}));
    });
    notifyListeners();
  }

  void _evictCleanBodies() {
    final book = _book;
    if (book == null) return;
    final activeId = _activeChapterId;
    final chapters = <Chapter>[];
    for (final chapter in book.chapters) {
      if (chapter.id != activeId && _loadedIds.contains(chapter.id)) {
        chapters.add(chapter.copyWith(blocks: const <Block>[]));
      } else {
        chapters.add(chapter);
      }
    }
    _book = book.copyWith(chapters: chapters);
    _loadedIds
      ..clear()
      ..addAll(activeId == null ? const <String>[] : <String>[activeId]);
  }

  Book _withChapter(Book book, Chapter chapter) {
    final chapters = List<Chapter>.of(book.chapters);
    final index = chapters.indexWhere((item) => item.id == chapter.id);
    if (index < 0) throw const ValidationFailure('章节不存在，请刷新书稿。');
    chapters[index] = chapter;
    return book.copyWith(chapters: chapters);
  }

  Chapter? _chapter(String id) {
    for (final chapter in _book?.chapters ?? const <Chapter>[]) {
      if (chapter.id == id) return chapter;
    }
    return null;
  }

  String? _selectableChapterId(List<Chapter> chapters, String? preferred) {
    if (preferred != null &&
        chapters.any(
          (chapter) => chapter.id == preferred && !chapter.isVolume,
        )) {
      return preferred;
    }
    return chapters.where((chapter) => !chapter.isVolume).firstOrNull?.id;
  }

  Book _requireBook() {
    _requireOpen();
    final book = _book;
    if (book == null) throw const ValidationFailure('请先打开书籍。');
    return book;
  }

  void _requireOpen() {
    if (_closed) throw StateError('EditorSession is closed');
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (_toolIsolateRunning) _jobs.cancelActive();
    if (_ownsJobs) _jobs.dispose();
    _aiTextCancelled = true;
    _closed = true;
    _closing = true;
    _sessionId = null;
    super.dispose();
  }
}

class _AiChangeApplicationInput {
  const _AiChangeApplicationInput(
    this.book,
    this.sessionId,
    this.saveSeq,
    this.textProposals,
    this.splitProposals,
    this.selectedIds,
    this.identities,
    this.byteBudget,
  );

  final Book book;
  final String sessionId;
  final int saveSeq;
  final List<AiTextProposal> textProposals;
  final List<AiChapterSplitProposal> splitProposals;
  final Set<String> selectedIds;
  final Map<String, AiChapterSplitIdentity> identities;
  final int byteBudget;
}

List<Chapter> _compileAiChangesJob(
  _AiChangeApplicationInput input,
  void Function(double, String) progress,
) {
  progress(0, '验证文本与卷章结构提案');
  final chapters = AiChangeApplication.compile(
    book: input.book,
    sessionId: input.sessionId,
    saveSeq: input.saveSeq,
    textProposals: input.textProposals,
    splitProposals: input.splitProposals,
    selectedIds: input.selectedIds,
    splitIdentities: input.identities,
    byteBudget: input.byteBudget,
  );
  progress(1, '验证完成');
  return chapters;
}

class _AiTextApplicationInput {
  const _AiTextApplicationInput(
    this.bookId,
    this.sessionId,
    this.saveSeq,
    this.targetChapters,
    this.proposals,
    this.selectedIds,
    this.byteBudget,
  );

  final String bookId;
  final String sessionId;
  final int saveSeq;
  final List<Chapter> targetChapters;
  final List<AiTextProposal> proposals;
  final Set<String> selectedIds;
  final int byteBudget;
}

ToolPreview _compileAiTextJob(
  _AiTextApplicationInput input,
  void Function(double, String) progress,
) {
  progress(0, '验证AI文本提案');
  final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  final preview = AiTextApplication.compile(
    book: Book(
      id: input.bookId,
      meta: BookMeta(title: '', author: ''),
      chapters: input.targetChapters,
      createdAt: now,
      updatedAt: now,
    ),
    sessionId: input.sessionId,
    saveSeq: input.saveSeq,
    proposals: input.proposals,
    selectedIds: input.selectedIds,
    byteBudget: input.byteBudget,
  );
  progress(1, '验证完成');
  return preview;
}

class _ProofreadingInput {
  const _ProofreadingInput(
    this.book,
    this.saveSeq,
    this.options,
    this.mode,
    this.dictionaries,
  );
  final Book book;
  final int saveSeq;
  final ReplaceOptions? options;
  final ConvertMode? mode;
  final Map<String, String>? dictionaries;
}

AuditReport _auditJob(
  _ProofreadingInput input,
  void Function(double, String) progress,
) {
  progress(0, '检查书稿');
  final report = Proofreading.audit(input.book);
  progress(1, '检查完成');
  return report;
}

List<MissedChapterCandidate> _missedChapterJob(
  _ProofreadingInput input,
  void Function(double, String) progress,
) {
  progress(0, '查找疑似漏章');
  final candidates = Proofreading.findMissedChapters(input.book);
  progress(1, '查找完成');
  return candidates;
}

ToolPreview _replaceJob(
  _ProofreadingInput input,
  void Function(double, String) progress,
) {
  progress(0, '预览替换');
  final preview = Proofreading.previewReplace(
    input.book,
    baseRevision: input.saveSeq,
    options: input.options!,
  );
  progress(1, '预览完成');
  return preview;
}

ToolPreview _renumberJob(
  _ProofreadingInput input,
  void Function(double, String) progress,
) {
  progress(0, '预览章号');
  final preview = Proofreading.previewRenumber(
    input.book,
    baseRevision: input.saveSeq,
  );
  progress(1, '预览完成');
  return preview;
}

ToolPreview _convertJob(
  _ProofreadingInput input,
  void Function(double, String) progress,
) {
  final mode = input.mode!;
  if (mode == ConvertMode.none) {
    return ToolPreview(
      baseRevision: input.saveSeq,
      hits: 0,
      patches: const <TextPatch>[],
      samples: const <ReplaceSample>[],
    );
  }
  final converter = OpenCcConverter.loadData(input.dictionaries!);
  final patches = <TextPatch>[];
  final chapters = input.book.chapters;
  for (var i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    final newTitle = converter.convertText(chapter.title, mode);
    if (newTitle != chapter.title) {
      patches.add(
        TextPatch(
          chapterId: chapter.id,
          blockId: null,
          before: chapter.title,
          after: newTitle,
        ),
      );
    }
    for (final block in chapter.blocks) {
      if (block is! TextBlock) continue;
      final converted = converter.convertText(block.text, mode);
      if (converted != block.text) {
        patches.add(
          TextPatch(
            chapterId: chapter.id,
            blockId: block.id,
            before: block.text,
            after: converted,
          ),
        );
      }
    }
    progress((i + 1) / chapters.length, '转换当前书稿');
  }
  return ToolPreview(
    baseRevision: input.saveSeq,
    hits: patches.length,
    patches: patches,
    samples: const <ReplaceSample>[],
  );
}

bool _sameBlocks(List<Block>? a, List<Block>? b) {
  if (a == null || b == null) return a == b;
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameChapter(Chapter? a, Chapter? b) => a == null || b == null
    ? a == b
    : a.id == b.id &&
          a.title == b.title &&
          a.parentId == b.parentId &&
          a.level == b.level &&
          a.order == b.order &&
          a.frontMatter == b.frontMatter &&
          _sameBlocks(a.blocks, b.blocks);

sealed class _EditEntry {
  int get deltaBytes;
}

class _TextEdit extends _EditEntry {
  _TextEdit(this.chapterId, this.blockId, this.before, this.after, this.at);
  final String chapterId;
  final String blockId;
  final String before;
  String after;
  DateTime at;

  @override
  int get deltaBytes => utf8.encode(before).length + utf8.encode(after).length;
}

class _MetaEdit extends _EditEntry {
  _MetaEdit(this.before, this.after);
  final BookMeta before;
  final BookMeta after;

  @override
  int get deltaBytes =>
      utf8.encode(jsonEncode(before.toJson())).length +
      utf8.encode(jsonEncode(after.toJson())).length;
}

class _LayoutEdit extends _EditEntry {
  _LayoutEdit(this.before, this.after);
  final LayoutOptions before;
  final LayoutOptions after;

  @override
  int get deltaBytes =>
      utf8.encode(jsonEncode(before.toJson())).length +
      utf8.encode(jsonEncode(after.toJson())).length;
}

class _CoverOptionsEdit extends _EditEntry {
  _CoverOptionsEdit(this.before, this.after);
  final CoverOptions before;
  final CoverOptions after;

  @override
  int get deltaBytes =>
      utf8.encode(jsonEncode(before.toJson())).length +
      utf8.encode(jsonEncode(after.toJson())).length;
}

class _CoverSourceEdit extends _EditEntry {
  _CoverSourceEdit({
    required this.beforeMode,
    required this.beforeAssetId,
    required this.afterMode,
    required this.afterAssetId,
  });
  final CoverMode beforeMode;
  final String? beforeAssetId;
  final CoverMode afterMode;
  final String? afterAssetId;

  @override
  int get deltaBytes =>
      utf8.encode(beforeAssetId ?? '').length +
      utf8.encode(afterAssetId ?? '').length +
      16;
}

class _ChapterSlot {
  const _ChapterSlot(this.index, this.chapter);
  final int index;
  final Chapter chapter;
}

class _StructureEdit extends _EditEntry {
  _StructureEdit({
    required this.before,
    required this.after,
    required this.beforeSelection,
    required this.afterSelection,
    required this.wordDelta,
    required this.redoBlockDirty,
    required this.undoBlockDirty,
  });
  final Map<String, _ChapterSlot> before;
  final Map<String, _ChapterSlot> after;
  final String? beforeSelection;
  final String? afterSelection;
  final int wordDelta;
  final Set<String> redoBlockDirty;
  final Set<String> undoBlockDirty;

  @override
  int get deltaBytes {
    var bytes = 0;
    final oldBlocks = <String, Block>{};
    final newBlocks = <String, Block>{};
    for (final id in <String>{...before.keys, ...after.keys}) {
      final old = before[id]?.chapter;
      final fresh = after[id]?.chapter;
      bytes += utf8.encode(id).length;
      if (old?.title != fresh?.title) {
        bytes += utf8.encode(old?.title ?? '').length;
        bytes += utf8.encode(fresh?.title ?? '').length;
      }
      if (!_sameBlocks(old?.blocks, fresh?.blocks)) {
        // Lists hold references; unchanged blocks moved between chapters do
        // not duplicate their text in the command history.
        bytes += 8 * (old?.blocks.length ?? 0);
        bytes += 8 * (fresh?.blocks.length ?? 0);
        for (final block in old?.blocks ?? const <Block>[]) {
          oldBlocks[block.id] = block;
        }
        for (final block in fresh?.blocks ?? const <Block>[]) {
          newBlocks[block.id] = block;
        }
      }
      bytes += 32; // indices, level, order and parent references
    }
    for (final id in <String>{...oldBlocks.keys, ...newBlocks.keys}) {
      final old = oldBlocks[id];
      final fresh = newBlocks[id];
      if (old == fresh) continue;
      bytes += utf8.encode(id).length;
      bytes += utf8.encode(old?.plainText ?? '').length;
      bytes += utf8.encode(fresh?.plainText ?? '').length;
    }
    return bytes;
  }
}

class _EditHistory {
  _EditHistory(this.byteBudget);
  final int byteBudget;
  final List<_EditEntry> _entries = <_EditEntry>[];
  int _cursor = 0;
  int _bytes = 0;

  bool get canUndo => _cursor > 0;
  bool get canRedo => _cursor < _entries.length;

  void clear() {
    _entries.clear();
    _cursor = 0;
    _bytes = 0;
  }

  void recordText(
    String chapterId,
    String blockId,
    String before,
    String after,
  ) {
    final now = DateTime.now();
    if (_cursor == _entries.length &&
        _entries.isNotEmpty &&
        _entries.last is _TextEdit) {
      final last = _entries.last as _TextEdit;
      if (last.chapterId == chapterId &&
          last.blockId == blockId &&
          now.difference(last.at) <= const Duration(seconds: 2)) {
        _bytes -= last.deltaBytes;
        last.after = after;
        last.at = now;
        _bytes += last.deltaBytes;
        _trim();
        return;
      }
    }
    _record(_TextEdit(chapterId, blockId, before, after, now));
  }

  void recordStructure(_StructureEdit edit) => _record(edit);

  void recordMeta(_MetaEdit edit) => _record(edit);

  void recordOptions(_EditEntry edit) => _record(edit);

  _EditEntry? takeUndo() => canUndo ? _entries[--_cursor] : null;
  _EditEntry? takeRedo() => canRedo ? _entries[_cursor++] : null;

  void _record(_EditEntry entry) {
    if (_cursor < _entries.length) {
      for (var i = _cursor; i < _entries.length; i++) {
        _bytes -= _entries[i].deltaBytes;
      }
      _entries.removeRange(_cursor, _entries.length);
    }
    _entries.add(entry);
    _bytes += entry.deltaBytes;
    _cursor = _entries.length;
    _trim();
  }

  void _trim() {
    while (_entries.isNotEmpty &&
        (_entries.length > 50 || _bytes > byteBudget)) {
      _bytes -= _entries.first.deltaBytes;
      _entries.removeAt(0);
      _cursor = (_cursor - 1).clamp(0, _entries.length);
    }
  }
}
