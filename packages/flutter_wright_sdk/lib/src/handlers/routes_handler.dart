import '../navigation_adapter.dart';
import 'handler.dart';

class RoutesHandler extends Handler {
  RoutesHandler(this.adapter);

  final NavigationAdapter adapter;

  @override
  String get path => '/routes';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final routeNames = adapter.discoverableRoutes?.toList() ?? const <String>[];
    await ctx.request.writeJson(200, <String, Object?>{
      'ok': true,
      'routes': routeNames,
    });
  }
}
