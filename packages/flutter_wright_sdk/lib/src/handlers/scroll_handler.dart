import '../logger.dart';
import '../semantics_action.dart';
import '../semantics_snapshot.dart';
import 'handler.dart';

/// POST /scroll —— 触发节点的滚动动作。
/// 请求体:{"ref": "sN", "dir": "up|down|left|right", "element": "(可选标签)"}
class ScrollHandler extends Handler {
  static const Set<String> _dirs = <String>{'up', 'down', 'left', 'right'};

  @override
  String get path => '/scroll';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final Object? ref = ctx.json['ref'];
    final Object? dir = ctx.json['dir'];
    if (ref is! String || ref.isEmpty) {
      await ctx.request.writeError(400, 'missing "ref"');
      return;
    }
    if (dir is! String || !_dirs.contains(dir)) {
      await ctx.request.writeError(400, 'dir must be one of $_dirs');
      return;
    }
    final node = SemanticsSnapshot.resolve(ref);
    if (node == null) {
      await ctx.request
          .writeError(404, 'ref "$ref" not in latest snapshot — re-snapshot');
      return;
    }
    if (!SemanticsActions.scroll(node, dir)) {
      await ctx.request.writeError(422, 'node has no scroll$dir action');
      return;
    }
    vlLog('scroll ${ctx.json['element'] ?? ref} $dir');
    await ctx.request
        .writeOk(<String, Object?>{'snapshot': SemanticsSnapshot.serialize()});
  }
}
