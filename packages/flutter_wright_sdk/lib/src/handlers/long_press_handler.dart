import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

/// POST /long_press —— 触发节点的长按动作。
/// 请求体:{"ref": "sN", "element": "(可选标签用于日志)"}
class LongPressHandler extends Handler {
  @override
  String get path => '/long_press';

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
    if (!SemanticsActions.longPress(node)) {
      await ctx.request.writeError(422, 'node has no longPress action');
      return;
    }
    vlLog('longPress ${ctx.json['element'] ?? ref}');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
