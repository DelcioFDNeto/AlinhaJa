import 'package:flutter/foundation.dart';

class AppLogger {
  static void debug(String Function() messageBuilder) {
    if (kDebugMode) {
      debugPrint(messageBuilder());
    }
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('ERROR: $message\n$error\n$stackTrace');
    }
  }
}
