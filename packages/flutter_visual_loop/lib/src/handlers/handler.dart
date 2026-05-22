import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logger.dart';

class HandlerContext {
  HandlerContext({
    required this.request,
    required this.body,
    required this.json,
  });

  final HttpRequest request;
  final String body;
  final Map<String, Object?> json;
}

abstract class Handler {
  /// Path this handler answers, e.g. `/health`. Match is exact.
  String get path;

  /// Allowed HTTP method (uppercase), e.g. `GET` or `POST`.
  String get method;

  Future<void> handle(HandlerContext ctx);
}

extension HandlerResponse on HttpRequest {
  Future<void> writeJson(int status, Map<String, Object?> body) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> writeOk([Map<String, Object?>? extra]) {
    final body = <String, Object?>{'ok': true, ...?extra};
    return writeJson(HttpStatus.ok, body);
  }

  Future<void> writeError(int status, String message) {
    vlWarn('$method ${uri.path} -> $status: $message');
    return writeJson(
      status,
      <String, Object?>{'ok': false, 'error': message},
    );
  }
}
