import 'dart:io';

import 'package:uuid/uuid.dart';

/// Atomically commits a validated file within a caller-owned private directory.
/// The caller must clean the directory if a worker isolate is killed.
void writeStagedFile(
  String outputPath,
  void Function(String candidatePath) writeAndValidate,
) {
  if (FileSystemEntity.typeSync(outputPath, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw FileSystemException('Export destination already exists', outputPath);
  }
  final candidate = File('$outputPath.bookloom-${const Uuid().v4()}.tmp');
  try {
    candidate.createSync(exclusive: true);
    writeAndValidate(candidate.path);
    if (FileSystemEntity.typeSync(outputPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Export destination already exists',
        outputPath,
      );
    }
    candidate.renameSync(outputPath);
  } finally {
    if (candidate.existsSync()) candidate.deleteSync();
  }
}
