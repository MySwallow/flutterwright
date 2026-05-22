import 'package:flutter/material.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

import 'mock/demo_mock_provider.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mock = DemoMockProvider();
  await FlutterWright.start(
    mockProvider: mock,
    testRoutes: const <String>[
      '/',
      '/login',
      '/product/detail',
      '/order/detail',
    ],
  );
  runApp(FlutterWrightRoot(child: FlutterWrightDemoApp(mock: mock)));
}

class FlutterWrightDemoApp extends StatelessWidget {
  const FlutterWrightDemoApp({required this.mock, super.key});

  final DemoMockProvider mock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_wright_sdk demo',
      navigatorKey: FlutterWright.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
      ),
      onGenerateRoute: (settings) => AppRouter.generate(settings, mock),
      initialRoute: '/',
    );
  }
}
