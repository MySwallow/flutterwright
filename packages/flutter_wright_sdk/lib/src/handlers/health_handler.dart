import 'handler.dart';

class HealthHandler extends Handler {
  HealthHandler(this.version, {this.appName, this.package});

  final String version;
  final String? appName;
  final String? package;

  @override
  String get path => '/health';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeJson(200, <String, Object?>{
      'ok': true,
      'service': 'flutter_wright_sdk',
      'version': version,
      'name': appName,
      'package': package,
    });
  }
}
