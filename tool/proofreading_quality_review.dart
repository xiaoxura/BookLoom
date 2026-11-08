import 'dart:io';

import 'src/proofreading_quality.dart';
import 'src/proofreading_quality_review.dart';

Future<void> main(List<String> arguments) async {
  try {
    String? corpusPath;
    String? templatePath;
    String? reviewsPath;
    String? outputPath;
    var allowExternal = false;
    var statusOnly = false;
    for (final argument in arguments) {
      if (argument.startsWith('--corpus=') && corpusPath == null) {
        corpusPath = argument.substring('--corpus='.length);
      } else if (argument.startsWith('--export-template=') &&
          templatePath == null) {
        templatePath = argument.substring('--export-template='.length);
      } else if (argument.startsWith('--reviews=') && reviewsPath == null) {
        reviewsPath = argument.substring('--reviews='.length);
      } else if (argument.startsWith('--output=') && outputPath == null) {
        outputPath = argument.substring('--output='.length);
      } else if (argument == '--allow-external' && !allowExternal) {
        allowExternal = true;
      } else if (argument == '--status' && !statusOnly) {
        statusOnly = true;
      } else {
        throw const FormatException(
          'usage: dart run tool/proofreading_quality_review.dart '
          '--corpus=FILE --export-template=FILE [--allow-external] '
          'or --corpus=FILE --reviews=FILE --output=FILE [--allow-external] '
          'or --corpus=FILE --reviews=FILE --status [--allow-external]',
        );
      }
    }
    if (corpusPath == null ||
        corpusPath.isEmpty ||
        templatePath == '' ||
        reviewsPath == '' ||
        outputPath == '') {
      throw const FormatException('file paths cannot be empty');
    }
    final exporting = templatePath != null;
    if (statusOnly &&
        (exporting || outputPath != null || reviewsPath == null)) {
      throw const FormatException('--status needs --corpus and --reviews');
    }
    if (exporting == (reviewsPath != null || outputPath != null) ||
        (!exporting &&
            !statusOnly &&
            (reviewsPath == null || outputPath == null))) {
      throw const FormatException(
        'choose either --export-template, --reviews with --output, or --status',
      );
    }
    final corpusRaw = await File(corpusPath).readAsString();
    if (statusOnly) {
      final reviewRaw = await File(reviewsPath!).readAsString();
      final progress = inspectReviewProgress(
        corpusRaw,
        reviewRaw,
        allowExternal: allowExternal,
      );
      stderr.writeln(
        'review status: ${progress.approved}/${progress.total} approved, '
        '${progress.pending} pending, ${progress.challenged} challenged.',
      );
      for (final id in progress.challengedIds.take(10)) {
        stderr.writeln('challenged: $id');
      }
      for (final id in progress.pendingIds.take(10)) {
        stderr.writeln('pending: $id');
      }
      exitCode = progress.complete ? 0 : 1;
    } else if (exporting) {
      final template = exportReviewTemplate(
        corpusRaw,
        allowExternal: allowExternal,
      );
      await File(templatePath).writeAsString('$template\n');
      final corpus = QualityCorpus.decode(
        corpusRaw,
        allowExternal: allowExternal,
      );
      final labels = corpus.cases
          .expand((qualityCase) => qualityCase.labels)
          .length;
      stderr.writeln(
        'review template: ${corpus.cases.length} cases, $labels labels, '
        'corpus sha256 ${qualityCorpusDigest(corpusRaw)}; '
        'mark every label approved before finalizing.',
      );
    } else {
      final reviewRaw = await File(reviewsPath!).readAsString();
      final reviewed = finalizeReviewedCorpus(
        corpusRaw,
        reviewRaw,
        allowExternal: allowExternal,
      );
      await File(outputPath!).writeAsString(reviewed);
      final corpus = QualityCorpus.decode(
        reviewed,
        allowExternal: allowExternal,
      );
      final labels = corpus.cases
          .expand((qualityCase) => qualityCase.labels)
          .length;
      final review = corpus.provenance['review'] as Map<String, Object?>;
      stderr.writeln(
        'reviewed corpus: ${corpus.cases.length} cases, $labels approved '
        'labels, reviewer ${review['reviewer']}; '
        'written to $outputPath.',
      );
    }
  } on Object catch (error) {
    stderr.writeln('review configuration error: $error');
    exitCode = 2;
  }
}
