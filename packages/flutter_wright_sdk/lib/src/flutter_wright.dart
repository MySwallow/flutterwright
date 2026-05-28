import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'handlers/handler.dart';
import 'handlers/health_handler.dart';
import 'handlers/nav_not_configured_handler.dart';
import 'handlers/navigate_handler.dart';
import 'handlers/reset_handler.dart';
import 'handlers/routes_handler.dart';
import 'handlers/screenshot_handler.dart';
import 'handlers/long_press_handler.dart';
import 'handlers/scroll_handler.dart';
import 'handlers/snapshot_handler.dart';
import 'handlers/tap_handler.dart';
import 'handlers/type_handler.dart';
import 'handlers/wait_for_handler.dart';
import 'http_server.dart';
import 'logger.dart';
import 'navigation_adapter.dart';

class FlutterWright {
  FlutterWright._();

  static const String version = '0.7.0';

  /// Convenience [GlobalKey] for the **Navigator 1.0** integration path: pass
  /// it to `MaterialApp(navigatorKey:)`. Stable across the app lifetime.
  ///
  /// Apps on GoRouter / GetX / auto_route don't need this — they pass a
  /// [CallbackNavigationAdapter] to [start] instead and may ignore this key.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'flutter_wright_sdk');

  static FlutterWrightHttpServer? _server;

  /// 常开的语义树句柄。真机/真实 app 默认不生成 Semantics 树(无障碍服务未开
  /// 时),`/snapshot` 就读不到节点;[start] 持有此句柄强制常开,[stop] 释放。
  static SemanticsHandle? _semanticsHandle;

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

    // 强制常开语义树,使 /snapshot 在没有无障碍服务时也能读到节点。
    _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();

    final handlers = <Handler>[
      HealthHandler(version),
      ScreenshotHandler(config.screenshotMode),
      SnapshotHandler(),
      TapHandler(),
      LongPressHandler(),
      TypeHandler(),
      ScrollHandler(),
      WaitForHandler(),
    ];

    // 导航(goto/reset/routes)是可选能力:仅当宿主传了 navigatorKey 或
    // navigationAdapter 才注册;否则占位 handler 回 501「未配置」。
    if (navigationAdapter != null || navigatorKey != null) {
      final NavigationAdapter adapter = navigationAdapter ??
          NavigatorKeyAdapter(navigatorKey!, routes: routes);
      if (navigationAdapter != null && routes.isNotEmpty) {
        vlWarn('start(routes:) ignored because navigationAdapter was provided; '
            'put discoverable routes in the adapter (routesProvider)');
      }
      handlers
        ..add(RoutesHandler(adapter))
        ..add(NavigateHandler(adapter))
        ..add(ResetHandler(adapter));
    } else {
      if (routes.isNotEmpty) {
        vlWarn('start(routes:) ignored: no navigatorKey/adapter — '
            'navigation (goto/reset) not registered');
      }
      handlers
        ..add(NavNotConfiguredHandler('/routes', 'GET'))
        ..add(NavNotConfiguredHandler('/navigate', 'POST'))
        ..add(NavNotConfiguredHandler('/reset', 'POST'));
    }

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
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
  }
}
