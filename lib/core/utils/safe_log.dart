import 'package:flutter/foundation.dart';

/// Central logging guard.
///
/// - Never prints message plaintext or private keys (only counts/hashes).
/// - Every catch site is expected to log through [SafeLog.error] — no silent
///   error swallowing anywhere in the app.
abstract final class SafeLog {
  static void info(String tag, String message) {
    debugPrint('[صب الجاي:$tag] $message');
  }

  static void error(String tag, String message, [Object? exception]) {
    final String dump = exception == null
        ? message
        : '$message | ${exception.runtimeType}: $exception';
    debugPrint('[صب الجاي:$tag][ERR] $dump');
  }
}
