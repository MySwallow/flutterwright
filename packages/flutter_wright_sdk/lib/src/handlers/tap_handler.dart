import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

/// POST /tap —— 触发节点的 tap(点击)动作。
/// 请求体:{"ref": "sN", "element": "(可选标签用于日志)"}
class TapHandler extends Handler {
  @override
  String get path => '/tap';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.tap(node)) {
      await ctx.request.writeError(422, 'node has no tap action');
      return;
    }
    vlLog('tap ${ctx.json['element'] ?? ref}');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
