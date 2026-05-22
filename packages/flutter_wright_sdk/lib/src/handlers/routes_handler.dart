import '../route_registry.dart';
import 'handler.dart';

class RoutesHandler extends Handler {
  RoutesHandler(this.registry);

  final RouteRegistry registry;

  @override
  String get path => '/routes';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeJson(200, <String, Object?>{
      'ok': true,
      'routes': registry.names.toList(),
    });
  }
}
