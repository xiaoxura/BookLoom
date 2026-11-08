import 'dart:convert';
import 'dart:io';

import 'package:bookloom/features/settings/data/ai_http_client.dart';

import 'src/proofreading_quality.dart';
import 'src/proofreading_quality_live.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = QualityCliOptions.parse(arguments, Platform.environment);
    final corpus = QualityCorpus.decode(
      await File(
        options.corpusPath ?? 'test/fixtures/proofreading/quality-corpus.json',
      ).readAsString(),
      allowExternal: options.allowExternal,
    );
    if (options.corpusPath == null) validateReferenceCorpusCoverage(corpus);
    QualityReport report;
    String? origin;
    Map<String, Object?>? live;
    if (options.live case final liveOptions?) {
      validateLiveCorpusConsent(corpus, sendExternal: options.sendExternal);
      stderr.writeln(
        'live quality run: ${corpus.cases.length} cases '
        '(${corpus.provenance['kind']}, '
        'userManuscripts=${corpus.containsUserManuscripts}, '
        'humanReviewed=${corpus.humanReviewed}), '
        'format=${liveOptions.formatName}, '
        'host=${liveOptions.endpoint.requestUri.host}, '
        'model=${liveOptions.model}, '
        'key-env=${liveOptions.keyEnvironment}, '
        'max-cases=${liveOptions.maxCases}; responses are untrusted.',
      );
      final client = AiHttpClient(timeout: liveOptions.timeout);
      var cancelled = false;
      final interrupt = ProcessSignal.sigint.watch().listen(
        (_) => cancelled = true,
      );
      try {
        final collection = await collectLiveResponses(
          corpus,
          options: liveOptions,
          client: client,
          isCancelled: () => cancelled,
        );
        report = QualityEvaluator.evaluateResponses(
          corpus,
          collection.responsesByCase,
        );
        origin = 'external_unverified';
        live = liveProviderMetadata(liveOptions, collection);
      } finally {
        await interrupt.cancel();
        client.dispose();
      }
    } else if (options.responsesPath == null) {
      report = QualityEvaluator.evaluateRules(corpus);
    } else {
      final batch = QualityResponseBatch.decode(
        await File(options.responsesPath!).readAsString(),
      );
      origin = batch.origin;
      report = QualityEvaluator.evaluateResponses(
        corpus,
        batch.responsesByCase,
      );
    }
    final output = report.toJson();
    if (origin != null) output['response_origin'] = origin;
    if (live != null) output['live_provider'] = live;
    final encoded = const JsonEncoder.withIndent('  ').convert(output);
    if (options.outputPath == null) {
      stdout.writeln(encoded);
    } else {
      await File(options.outputPath!).writeAsString('$encoded\n');
    }
    if (options.markdownPath case final path?) {
      await File(path).writeAsString(qualityMarkdownReport(report));
    }
    if (options.strict && report.hasStrictFailure) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('quality configuration error: $error');
    exitCode = 2;
  }
}

void validateReferenceCorpusCoverage(QualityCorpus corpus) {
  const expectedLabelCounts = <String, int>{
    'site-banner': 1,
    'mixed-paragraph': 1,
    'author-note': 1,
    'story-quote': 1,
    'ordinary-reading': 1,
    'ambiguous-note': 1,
    'unseen-promotion': 1,
    'emoji-crlf': 1,
    'two-deletions': 2,
    'same-text-different-role': 2,
    'standard-heading': 1,
    'punctuation-heading': 1,
    'combined-range-heading': 1,
    'decorated-heading': 1,
    'split-emoji-crlf': 1,
    'inline-title-not-heading': 1,
    'heading-shaped-story': 1,
    'number-gap-diagnostic': 1,
    'numbering-diagnostic': 1,
    'merged-without-heading': 1,
    'volume-resources': 1,
    'chunk-boundary': 1,
    'block-remove-site-ad': 1,
    'block-remove-between-resources': 1,
    'block-mixed-ad-stays-text': 1,
    'rename-wrong-directory-title': 1,
    'rename-empty-directory-title': 1,
    'rename-emoji-heading': 1,
  };
  if (corpus.cases.length != expectedLabelCounts.length ||
      corpus.cases.any(
        (qualityCase) =>
            expectedLabelCounts[qualityCase.id] != qualityCase.labels.length,
      )) {
    throw const FormatException(
      'reference corpus coverage changed: expected all 28 cases and 30 labels',
    );
  }
}
