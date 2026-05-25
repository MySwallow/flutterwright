/// Debug-only in-app HTTP server for Flutter apps. Designed to be driven by
/// the matching `flutter-wright` Claude Code skill, but the HTTP API
/// is plain JSON over `127.0.0.1` so any client works.
library flutter_wright_sdk;

export 'src/config.dart' show FlutterWrightConfig, ScreenshotMode;
export 'src/navigation_adapter.dart'
    show NavigationAdapter, NavigatorKeyAdapter, CallbackNavigationAdapter;
export 'src/route_registry.dart' show RouteRegistry;
export 'src/screenshot.dart' show FlutterWrightRoot;
export 'src/flutter_wright.dart' show FlutterWright;
