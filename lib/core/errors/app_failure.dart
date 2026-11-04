/// User-facing failures with an actionable message and a technical cause.
///
/// UI never shows a raw exception: repositories throw these, the app layer
/// logs [cause]/[stackTrace] and surfaces [message].
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause, this.stackTrace});

  /// Short, actionable Chinese message.
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  /// Optional next step shown under the message ("换一种编码再试" etc.).
  String? get hint => null;

  @override
  String toString() => '$runtimeType($message)';
}

final class ImportFailure extends AppFailure {
  const ImportFailure(
    super.message, {
    super.cause,
    super.stackTrace,
    this.hint,
  });

  @override
  final String? hint;
}

final class ExportFailure extends AppFailure {
  const ExportFailure(
    super.message, {
    super.cause,
    super.stackTrace,
    this.hint,
  });

  @override
  final String? hint;
}

final class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.cause, super.stackTrace});

  @override
  String? get hint => '检查磁盘空间，或稍后重试。';
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(
    super.message, {
    super.cause,
    super.stackTrace,
    this.hint,
  });

  @override
  final String? hint;
}

/// Anything we did not anticipate. Still shown as a friendly message.
final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure({super.cause, super.stackTrace})
    : super('出现了未预期的问题。');

  @override
  String? get hint => '已记录日志。如果反复出现，请附上日志反馈。';
}
