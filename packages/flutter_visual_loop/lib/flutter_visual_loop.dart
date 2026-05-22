/// Debug-only HTTP control plane for Flutter apps. Designed to be driven by
/// the matching `flutter-visual-loop` Claude Code skill, but the HTTP API
/// is plain JSON over `127.0.0.1` so any client works.
library flutter_visual_loop;

export 'src/config.dart' show VisualLoopConfig, ScreenshotMode;
export 'src/mock_provider.dart'
    show MockDataProvider, InMemoryMockDataProvider;
export 'src/route_registry.dart' show RouteRegistry;
export 'src/screenshot.dart' show VisualLoopRoot;
export 'src/visual_loop.dart' show FlutterVisualLoop;
