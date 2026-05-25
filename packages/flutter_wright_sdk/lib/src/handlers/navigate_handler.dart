import '../logger.dart';
import '../navigation_adapter.dart';
import 'handler.dart';

class NavigateHandler extends Handler {
  NavigateHandler(this.adapter);

  final NavigationAdapter adapter;

  @override
  String get path => '/navigate';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final route = ctx.json['route'];
    if (route is! String || route.isEmpty) {
      await ctx.request.writeError(400, 'missing "route"');
      return;
    }
    final args = ctx.json['args'];
    final popUntilRoot = ctx.json['popUntilRoot'] != false;

    if (!adapter.isReady) {
      await ctx.request.writeError(503, 'navigator not ready');
      return;
    }

    try {
      await adapter.navigate(route, args: args, popUntilRoot: popUntilRoot);
      vlLog('navigated to $route');
      await ctx.request.writeOk(<String, Object?>{'route': route});
    } catch (e, st) {
      vlError('navigate failed', e, st);
      await ctx.request.writeError(500, e.toString());
    }
  }
}
