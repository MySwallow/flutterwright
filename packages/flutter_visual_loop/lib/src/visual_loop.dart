import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'handlers/handler.dart';
import 'handlers/health_handler.dart';
import 'handlers/mock_handler.dart';
import 'handlers/navigate_handler.dart';
import 'handlers/reset_handler.dart';
import 'handlers/routes_handler.dart';
import 'handlers/screenshot_handler.dart';
import 'handlers/reload_handler.dart';
import 'http_server.dart';
import 'logger.dart';
import 'mock_provider.dart';
import 'route_registry.dart';

class FlutterVisualLoop {
  FlutterVisualLoop._();

  static const String version = '0.2.0';

  /// Single GlobalKey the host should pass to `MaterialApp(navigatorKey:)`.
  /// Stable across the app lifetime.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'flutter_visual_loop');

  static final RouteRegistry routes = RouteRegistry();

  static VisualLoopHttpServer? _server;
  static MockDataProvider? _mockProvider;

  static bool get isRunning => _server?.isRunning ?? false;
  static MockDataProvider? get mockProvider => _mockProvider;

  /// Bind the control server. Idempotent — calling twice is a no-op.
  ///
  /// In release builds (or when `config.enableInDebugOnly == true` and
  /// `kDebugMode` is false), returns without binding.
  static Future<void> start({
    VisualLoopConfig config = const VisualLoopConfig(),
    MockDataProvider? mockProvider,
    Iterable<String> testRoutes = const <String>[],
  }) async {
    if (config.enableInDebugOnly && !kDebugMode) {
      vlLog('release build: SDK disabled');
      return;
    }
    if (_server != null) {
      vlWarn('start() called twice; ignoring');
      return;
    }
    _mockProvider = mockProvider;
    for (final r in testRoutes) {
      routes.register(r);
    }

    final handlers = <Handler>[
      HealthHandler(version),
      RoutesHandler(routes),
      NavigateHandler(navigatorKey),
      ResetHandler(
        navigatorKey: navigatorKey,
        mockProvider: mockProvider,
      ),
      MockHandler(mockProvider),
      ScreenshotHandler(config.screenshotMode),
      ReloadHandler(),
    ];

    _server = VisualLoopHttpServer(config: config, handlers: handlers);
    if (config.autoStart) {
      await _server!.start();
    }
  }

  /// Bind a deferred server (when `autoStart: false` was used).
  static Future<void> bind() async {
    if (_server == null) {
      throw StateError('call start() first');
    }
    await _server!.start();
  }

  static Future<void> stop() async {
    await _server?.stop();
    _server = null;
  }
}
