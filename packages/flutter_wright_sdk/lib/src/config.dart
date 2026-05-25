/// How the SDK captures screenshots when `/screenshot` is hit.
enum ScreenshotMode {
  /// Use a `RepaintBoundary` of the root widget. Excludes OS chrome
  /// (status bar, navigation bar). Works on all platforms incl. web/desktop.
  flutter,

  /// Tell the caller to use `adb exec-out screencap`. SDK returns 501
  /// when this endpoint is hit. Useful on Android when you want the
  /// full device frame.
  external,
}

class FlutterWrightConfig {
  const FlutterWrightConfig({
    this.host = '127.0.0.1',
    this.port = 9123,
    this.enableInDebugOnly = true,
    this.autoStart = true,
    this.screenshotMode = ScreenshotMode.flutter,
    this.maxBodyBytes = 1024 * 1024,
  });

  /// Bind address. Keep `127.0.0.1` unless you know what you're doing —
  /// `0.0.0.0` exposes the control plane to the whole LAN.
  final String host;

  /// TCP port.
  final int port;

  /// If true (default), `start()` returns without binding when not in debug.
  final bool enableInDebugOnly;

  /// If true (default), `start()` binds immediately. Set false to defer
  /// to a later `FlutterWright.bind()` call.
  final bool autoStart;

  /// See [ScreenshotMode].
  final ScreenshotMode screenshotMode;

  /// Reject request bodies larger than this with a 413. Default 1 MiB.
  final int maxBodyBytes;
}
