import 'dart:async';

import '../semantics_snapshot.dart';
import 'handler.dart';

/// GET /wait_for —— 轮询条件直到命中或超时。
/// 查询参数:
///   text=<字符串>   语义树中存在此文本即命中
///   ref=<sN>        对应 ref 存在于最近快照即命中
///   gone=<字符串>   语义树中不再含有此文本即命中
///   timeout=<毫秒>  等待上限,默认 5000;超时返回 408
class WaitForHandler extends Handler {
  @override
  String get path => '/wait_for';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Map<String, String> q = ctx.request.uri.queryParameters;
    final String? text = q['text'];
    final String? ref = q['ref'];
    final String? gone = q['gone'];
    final int timeoutMs = int.tryParse(q['timeout'] ?? '') ?? 5000;

    if (text == null && ref == null && gone == null) {
      await ctx.request.writeError(400, 'need one of text= / ref= / gone=');
      return;
    }

    // 条件判断:text 存在 / ref 可解析 / gone 文本消失
    bool met() {
      if (text != null) return SemanticsSnapshot.containsText(text);
      if (ref != null) return SemanticsSnapshot.resolve(ref) != null;
      return !SemanticsSnapshot.containsText(gone!);
    }

    final DateTime deadline =
        DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (met()) {
        await ctx.request.writeOk(
            <String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await ctx.request
        .writeError(408, 'condition not met within ${timeoutMs}ms');
  }
}
