import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import '../core/errors/app_failure.dart';

final Logger _logger = Logger('app');

/// Installs global error handlers and a friendly in-place error widget.
///
/// Errors are logged with technical detail; the UI only shows an actionable
/// sentence (docs/01-architecture.md §8).
void installErrorHandlers() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logger.severe(
      'flutter error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _logger.severe('uncaught error: $error', error, stack);
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) =>
      const _ErrorPlaceholder();
}

/// Replacement widget when a subtree fails to build. Must not depend on
/// inherited themes or localizations, since either may be the thing that broke.
class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFFF6F2EA),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '出了点问题 / Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF5B554B)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Runs [body] and reports a typed failure instead of leaking raw exceptions.
AppFailure asAppFailure(Object error, StackTrace stack) {
  if (error is AppFailure) return error;
  _logger.severe('unexpected: $error', error, stack);
  return UnexpectedFailure(cause: error, stackTrace: stack);
}
