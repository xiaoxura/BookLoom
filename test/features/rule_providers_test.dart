import 'package:bookloom/app/ai_rule_providers.dart';
import 'package:bookloom/app/providers.dart';
import 'package:bookloom/app/rule_providers.dart';
import 'package:bookloom/core/model/book.dart';
import 'package:bookloom/core/model/chapter.dart';
import 'package:bookloom/core/model/metadata.dart';
import 'package:bookloom/features/editor/application/ai_rule_creation_task.dart';
import 'package:bookloom/features/editor/application/editor_session.dart';
import 'package:bookloom/features/editor/application/rule_workbench_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('constructing optional AI rule task does not open storage', () async {
    final session = EditorSession.withStore(store: _BookStore());
    await session.open('book');
    var databaseReads = 0;
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) {
          databaseReads++;
          throw StateError('Optional database has not been configured.');
        }),
      ],
    );
    final subscription = container.listen(
      aiRuleCreationTaskProvider(session),
      (previous, next) {},
    );
    expect(subscription.read().phase, AiRuleCreationPhase.idle);
    expect(subscription.read().consent, isNull);
    expect(subscription.read().proposals, isEmpty);
    expect(databaseReads, 0);
    subscription.close();
    container.dispose();
    session.dispose();
  });

  test(
    'keeping the optional rules task alive does not open its database',
    () async {
      final session = EditorSession.withStore(store: _BookStore());
      await session.open('book');
      var databaseReads = 0;
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWith((ref) {
            databaseReads++;
            throw StateError('Optional database has not been configured.');
          }),
        ],
      );
      final subscription = container.listen(
        ruleWorkbenchTaskProvider(session),
        (previous, next) {},
      );
      final task = subscription.read();
      expect(task.phase, RuleWorkbenchPhase.idle);
      expect(task.isLoaded, isFalse);
      expect(databaseReads, 0);

      await task.load();
      expect(databaseReads, 1);
      expect(task.phase, RuleWorkbenchPhase.failed);
      expect(task.rules, isEmpty);
      expect(task.isLoaded, isFalse);

      subscription.close();
      container.dispose();
      session.dispose();
    },
  );
}

class _BookStore implements EditorBookStore {
  final Book _book = Book(
    id: 'book',
    meta: BookMeta(title: '合成书'),
    chapters: const [Chapter(id: 'chapter', bookId: 'book', title: '第一章')],
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<Book?> loadBook(String bookId) async => _book;

  @override
  Future<Chapter?> loadChapter(String bookId, String chapterId) async =>
      _book.chapters.single;

  @override
  Future<Book> saveBook(
    Book book, {
    required int expectedRevision,
    required Set<String> dirtyChapterIds,
    Set<String> deletedChapterIds = const {},
  }) async => book;
}
