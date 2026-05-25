import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'handlers/handler.dart';
import 'handlers/health_handler.dart';
import 'handlers/navigate_handler.dart';
import 'handlers/reset_handler.dart';
import 'handlers/routes_handler.dart';
import 'handlers/screenshot_handler.dart';
import 'http_server.dart';
import 'logger.dart';
import 'navigation_adapter.dart';

class FlutterWright {
  FlutterWright._();

  static const String version = '0.6.0';

  /// Convenience [GlobalKey] for the **Navigator 1.0** integration path: pass
  /// it to `MaterialApp(navigatorKey:)`. Stable across the app lifetime.
  ///
  /// Apps on GoRouter / GetX / auto_route don't need this — they pass a
  /// [CallbackNavigationAdapter] to [start] instead and may ignore this key.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'flutter_wright_sdk');

  static FlutterWrightHttpServer? _server;

  static bool get isRunning => _server?.isRunning ?? false;

  /// Bind the control server. Idempotent — calling twice is a no-op.
  ///
  /// In release builds (or when `config.enableInDebugOnly == true` and
  /// `kDebugMode` is false), returns without binding.
  static Future<void> start({
    FlutterWrightConfig config = const FlutterWrightConfig(),
    NavigationAdapter? navigationAdapter,
    GlobalKey<NavigatorState>? navigatorKey,
    Iterable<String> routes = const <String>[],
  }) async {
    if (config.enableInDebugOnly && !kDebugMode) {
      vlLog('release build: SDK disabled');
      return;
    }
    if (_server != null) {
      vlWarn('start() called twice; ignoring');
      return;
    }

    // Default to the Navigator 1.0 path (shared navigatorKey). Apps on
    // GoRouter / GetX / FlutterBoost pass their own adapter instead.
    final NavigationAdapter adapter = navigationAdapter ??
        NavigatorKeyAdapter(
          navigatorKey ?? FlutterWright.navigatorKey,
          routes: routes,
        );

    if (navigationAdapter != null && routes.isNotEmpty) {
      vlWarn('start(routes:) ignored because navigationAdapter was provided; '
          'put discoverable routes in the adapter (routesProvider)');
    }

    final handlers = <Handler>[
      HealthHandler(version),
      RoutesHandler(adapter),
      NavigateHandler(adapter),
      ResetHandler(adapter),
      ScreenshotHandler(config.screenshotMode),
    ];

    _server = FlutterWrightHttpServer(config: config, handlers: handlers);
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
