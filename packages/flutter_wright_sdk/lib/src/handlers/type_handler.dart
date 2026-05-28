import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

/// POST /type —— 向可编辑文本节点写入文本。
/// 请求体:{"ref": "sN", "text": "输入内容", "element": "(可选标签用于日志)"}
class TypeHandler extends Handler {
  @override
  String get path => '/type';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    final Object? text = ctx.json['text'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    if (text is! String) {
      await ctx.request.writeError(400, 'missing "text"');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.setText(node, text)) {
      await ctx.request.writeError(422, 'node is not an editable text field');
      return;
    }
    vlLog('type ${ctx.json['element'] ?? ref} = "$text"');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
