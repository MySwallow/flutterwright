import 'package:flutter/foundation.dart';

/// Lightweight log prefix so users can grep `flutter run` output for
/// SDK-originated lines.
void vlLog(String msg) {
  if (kDebugMode) {
    debugPrint('[flutter_visual_loop] $msg');
  }
}

void vlWarn(String msg) {
  if (kDebugMode) {
    debugPrint('[flutter_visual_loop][WARN] $msg');
  }
}

void vlError(String msg, [Object? error, StackTrace? stack]) {
  if (kDebugMode) {
    debugPrint('[flutter_visual_loop][ERROR] $msg');
    if (error != null) debugPrint('  cause: $error');
    if (stack != null) debugPrint(stack.toString());
  }
}
