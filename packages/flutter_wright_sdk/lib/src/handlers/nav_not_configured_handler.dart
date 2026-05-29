import 'handler.dart';

/// host 未传 navigatorKey/navigationAdapter 时,占位回应导航端点:明确「未配置」。
class NavNotConfiguredHandler extends Handler {
  NavNotConfiguredHandler(this.path, this.method);

  @override
  final String path;

  @override
  final String method;

  @override
  Future<void> handle(HandlerContext ctx) async {
    await ctx.request.writeError(
      501,
      'navigation not configured — pass navigatorKey or navigationAdapter '
      'to FlutterWright.start() to enable goto/reset',
    );
  }
}
