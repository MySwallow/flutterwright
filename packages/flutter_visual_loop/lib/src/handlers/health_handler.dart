import 'handler.dart';

class HealthHandler extends Handler {
  HealthHandler(this.version);

  final String version;

  @override
  String get path => '/health';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeJson(200, <String, Object?>{
      'ok': true,
      'version': version,
      'service': 'flutter_visual_loop',
    });
  }
}
