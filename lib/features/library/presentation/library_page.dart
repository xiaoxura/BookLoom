import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/app_page.dart';
import '../../../design/components/book_plate.dart';
import '../../../design/components/empty_state.dart';
import '../../../l10n/app_localizations.dart';

/// Shelf of books. Empty until the import milestone lands;
/// the layout is final so the rest of M1 can fill it in.
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return AppPage(
      eyebrow: l10n.appTagline,
      title: l10n.libraryTitle,
      subtitle: l10n.librarySubtitle,
      scrollable: false,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: EmptyState(
                  illustration: const BookPlate(),
                  title: l10n.libraryEmptyTitle,
                  message: l10n.libraryEmptyMessage,
                  hint: l10n.libraryEmptyHint,
                  actions: <Widget>[
                    FilledButton.icon(
                      onPressed: () => context.go('/import'),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.libraryEmptyAction),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
