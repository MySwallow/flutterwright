import 'package:flutter/material.dart';

import 'router/app_router.dart';

/// Shared app factory used by **both** the production entrypoint
/// (`lib/main.dart`) and the debug harness (`dev/main_dev.dart`).
///
/// Keeping app construction in one place means the harness never duplicates
/// bootstrap logic — it just wraps this and injects the SDK's navigatorKey.
/// Note: **no `flutter_wright_sdk` import here**, so `lib/` stays SDK-free.
Widget createApp({GlobalKey<NavigatorState>? navigatorKey}) =>
    FlutterWrightDemoApp(navigatorKey: navigatorKey);

class FlutterWrightDemoApp extends StatelessWidget {
  const FlutterWrightDemoApp({this.navigatorKey, super.key});

  /// Supplied by the debug harness (`FlutterWright.navigatorKey`) so the SDK
  /// can drive Navigator 1.0. Null in production → MaterialApp uses its own.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_wright_sdk demo',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
      ),
      onGenerateRoute: AppRouter.generate,
      initialRoute: '/',
    );
  }
}
