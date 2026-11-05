import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/workbench_providers.dart';
import '../../../core/storage/book_repository.dart';
import '../../../design/components/app_page.dart';
import '../../../design/components/book_plate.dart';
import '../../../design/components/empty_state.dart';
import '../../../design/theme/app_tokens.dart';
import '../../../design/tokens/app_metrics.dart';
import '../../../l10n/app_localizations.dart';
import '../../preview/book_thumbnail.dart';

enum _Sort { recent, title, opened }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  _Sort _sort = _Sort.recent;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final books = ref.watch(libraryBooksProvider);
    return AppPage(
      scrollable: false,
      child: books.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: EmptyState(
            title: l10n.libraryLoadFailed,
            actions: [
              OutlinedButton(
                onPressed: () => ref.invalidate(libraryBooksProvider),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
        ),
        data: (List<BookSummary> all) {
          if (all.isEmpty) return _empty(l10n);
          final query = _search.text.trim().toLowerCase();
          final shown = all
              .where(
                (book) =>
                    query.isEmpty ||
                    book.title.toLowerCase().contains(query) ||
                    book.author.toLowerCase().contains(query),
              )
              .toList();
          switch (_sort) {
            case _Sort.recent:
              shown.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            case _Sort.title:
              shown.sort((a, b) => a.title.compareTo(b.title));
            case _Sort.opened:
              shown.sort(
                (a, b) => (b.lastOpenedAt ?? b.updatedAt).compareTo(
                  a.lastOpenedAt ?? a.updatedAt,
                ),
              );
          }
          return Column(
            children: [
              _toolbar(l10n),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: EmptyState(title: l10n.libraryNoMatch))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
                        itemCount: shown.length,
                        itemBuilder: (_, index) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _tile(shown[index], l10n),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _empty(AppLocalizations l10n) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: EmptyState(
            illustration: const BookPlate(),
            title: l10n.libraryEmptyTitle,
            message: l10n.libraryEmptyMessage,
            actions: [
              FilledButton.icon(
                onPressed: () => context.go('/import'),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.libraryEmptyAction),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _toolbar(AppLocalizations l10n) => LayoutBuilder(
    builder: (_, constraints) => Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: constraints.maxWidth < 520 ? constraints.maxWidth : 280,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.librarySearch,
              prefixIcon: const Icon(Icons.search_outlined),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.libraryClearSearch,
                      onPressed: () => setState(_search.clear),
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
        ),
        DropdownButton<_Sort>(
          value: _sort,
          items: [
            DropdownMenuItem(
              value: _Sort.recent,
              child: Text(l10n.librarySortRecent),
            ),
            DropdownMenuItem(
              value: _Sort.title,
              child: Text(l10n.librarySortTitle),
            ),
            DropdownMenuItem(
              value: _Sort.opened,
              child: Text(l10n.librarySortOpened),
            ),
          ],
          onChanged: (value) => setState(() => _sort = value ?? _sort),
        ),
        FilledButton.icon(
          onPressed: () => context.go('/import'),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.libraryEmptyAction),
        ),
      ],
    ),
  );

  Widget _tile(BookSummary book, AppLocalizations l10n) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: _busy ? null : () => context.push('/books/${book.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              BookThumbnail(
                key: ValueKey(
                  '${book.id}:${book.revision}:${book.updatedAt.microsecondsSinceEpoch}',
                ),
                summary: book,
                repository: ref.read(bookRepositoryProvider),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${book.author.isEmpty ? l10n.libraryUnknownAuthor : book.author} · ${l10n.libraryBookStats(book.chapterCount, book.wordCount)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.inkSecondary),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l10n.libraryBookActions,
                enabled: !_busy,
                onSelected: (value) {
                  if (value == 'rename') _rename(book);
                  if (value == 'delete') _delete(book);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l10n.libraryRename),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.libraryDelete),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BookSummary book) async {
    final l10n = AppLocalizations.of(context);
    var draft = book.title;
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.libraryRename),
        content: TextFormField(
          initialValue: book.title,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: l10n.libraryBookTitle),
          onChanged: (value) => draft = value,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialog, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.pop(dialog, value);
            },
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (!mounted || title == null || title == book.title) return;
    await _perform(
      () => ref
          .read(bookRepositoryProvider)
          .renameBook(book.id, title, expectedRevision: book.revision),
    );
  }

  Future<void> _delete(BookSummary book) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.libraryDelete),
        content: Text(l10n.libraryDeleteConfirm(book.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(l10n.libraryDelete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _perform(() => ref.read(bookRepositoryProvider).deleteBook(book.id));
  }

  Future<void> _perform(Future<Object?> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(libraryBooksProvider);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).libraryOperationFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
