import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'handlers/handler.dart';
import 'logger.dart';

class FlutterWrightHttpServer {
  FlutterWrightHttpServer({required this.config, required this.handlers});

  final FlutterWrightConfig config;
  final List<Handler> handlers;

  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) {
      vlWarn('already running on ${config.host}:${config.port}');
      return;
    }
    _server = await HttpServer.bind(config.host, config.port, shared: false);
    vlLog('listening on http://${config.host}:${config.port}');
    _server!.listen(_dispatch, onError: (Object e, StackTrace st) {
      vlError('server error', e, st);
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    vlLog('stopped');
  }

  Future<void> _dispatch(HttpRequest req) async {
    try {
      final method = req.method.toUpperCase();
      final path = req.uri.path;
      final handler = handlers.firstWhere(
        (h) => h.path == path && h.method == method,
        orElse: () => _NotFound(),
      );
      final body = await _readBody(req);
      final json = _safeJson(body);
      await handler.handle(HandlerContext(
        request: req,
        body: body,
        json: json,
      ));
    } catch (e, st) {
      vlError('dispatch failed', e, st);
      try {
        req.response.statusCode = 500;
        req.response.write(jsonEncode(<String, Object?>{
          'ok': false,
          'error': e.toString(),
        }));
        await req.response.close();
      } catch (_) {
        // socket already closed; ignore
      }
    }
  }

  Future<String> _readBody(HttpRequest req) async {
    final contentLength = req.contentLength;
    if (contentLength == 0) return '';
    if (contentLength > config.maxBodyBytes) {
      req.response.statusCode = 413;
      await req.response.close();
      return '';
    }
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > config.maxBodyBytes) {
        req.response.statusCode = 413;
        await req.response.close();
        return '';
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  Map<String, Object?> _safeJson(String body) {
    if (body.isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) return decoded;
      return const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }
}

class _NotFound extends Handler {
  @override
  String get path => '*';

  @override
  String get method => '*';

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeError(
      404,
      'no handler for ${ctx.request.method} ${ctx.request.uri.path}',
    );
  }
}
