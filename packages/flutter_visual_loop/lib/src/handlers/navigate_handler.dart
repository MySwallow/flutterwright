import 'package:flutter/widgets.dart';

import '../logger.dart';
import 'handler.dart';

class NavigateHandler extends Handler {
  NavigateHandler(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;

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

    final nav = navigatorKey.currentState;
    if (nav == null) {
      await ctx.request.writeError(503, 'navigator not ready');
      return;
    }

    try {
      if (popUntilRoot) {
        nav.popUntil((r) => r.isFirst);
      }
      // ignore: unawaited_futures
      nav.pushNamed(route, arguments: args);
      vlLog('navigated to $route');
      await ctx.request.writeOk(<String, Object?>{'route': route});
    } catch (e, st) {
      vlError('navigate failed', e, st);
      await ctx.request.writeError(500, e.toString());
    }
  }
}
