import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// SQLite database. Schema changes require a `schemaVersion` bump plus a
/// migration (and a migration test) — see docs/03-data-model.md §10.
@DriftDatabase(tables: [Books, Sources, Chapters, Blocks, Assets, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the database on a background isolate so large queries never block
  /// the UI thread.
  static AppDatabase openAt(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));

  /// In-memory database for tests.
  static AppDatabase memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async => m.createAll(),
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
