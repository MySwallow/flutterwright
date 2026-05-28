import 'package:flutter/material.dart';
import 'package:flutter_wright_example/app.dart';
import 'package:flutter_wright_example/router/app_router.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

/// Debug entrypoint — the **only** place that imports `flutter_wright_sdk`.
///
/// Run with: `flutter run -t dev/main_dev.dart`
///
/// It reuses the shared [createApp] factory (so there's no duplicated app
/// bootstrap to maintain) and only adds the SDK wiring around it. Because
/// production `lib/main.dart` never references the SDK, default `flutter build`
/// excludes it entirely and the SDK stays a `dev_dependency`.
///
/// This demo uses Navigator 1.0 → default [NavigatorKeyAdapter]: inject
/// `FlutterWright.navigatorKey`. Apps on GoRouter / GetX pass
/// `navigationAdapter: CallbackNavigationAdapter(...)` instead (see
/// docs/integration-guide.md).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterWright.start(
    navigatorKey: FlutterWright.navigatorKey,
    routes: AppRouter.names,
  );
  runApp(
    FlutterWrightRoot(
      child: createApp(navigatorKey: FlutterWright.navigatorKey),
    ),
  );
}
