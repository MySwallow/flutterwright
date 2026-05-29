import 'dart:io';

import '../semantics_snapshot.dart';
import 'handler.dart';

/// 返回当前 Flutter Semantics 树的 YAML 快照(Playwright 风格)。
/// 每行可操作节点带有 `[ref=sN]`,后续交互端点凭此 ref 定位。
class SnapshotHandler extends Handler {
  @override
  String get path => '/snapshot';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final String yaml = SemanticsSnapshot.serialize();
    ctx.request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'plain', charset: 'utf-8')
      ..write(yaml);
    await ctx.request.response.close();
  }
}
