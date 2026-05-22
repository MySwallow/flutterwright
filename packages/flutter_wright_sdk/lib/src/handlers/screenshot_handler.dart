import 'dart:io';

import '../config.dart';
import '../screenshot.dart';
import 'handler.dart';

class ScreenshotHandler extends Handler {
  ScreenshotHandler(this.mode);

  final ScreenshotMode mode;

  @override
  String get path => '/screenshot';

  @override
  String get method => 'GET';

  @override
  Future<void> handle(HandlerContext ctx) async {
    if (mode == ScreenshotMode.external) {
      await ctx.request.writeError(
        501,
        'screenshotMode=external; use adb exec-out screencap',
      );
      return;
    }
    final bytes = await captureFlutterScreen();
    if (bytes == null) {
      await ctx.request.writeError(
        500,
        'failed to capture; wrap your app with FlutterWrightRoot',
      );
      return;
    }
    ctx.request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('image', 'png');
    ctx.request.response.add(bytes);
    await ctx.request.response.close();
  }
}
