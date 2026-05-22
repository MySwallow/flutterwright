import 'package:flutter/material.dart';
import 'package:flutter_visual_loop/flutter_visual_loop.dart';

import 'mock/demo_mock_provider.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mock = DemoMockProvider();
  await FlutterVisualLoop.start(
    mockProvider: mock,
    testRoutes: const <String>[
      '/',
      '/login',
      '/product/detail',
      '/order/detail',
    ],
  );
  runApp(VisualLoopRoot(child: VisualLoopDemoApp(mock: mock)));
}

class VisualLoopDemoApp extends StatelessWidget {
  const VisualLoopDemoApp({required this.mock, super.key});

  final DemoMockProvider mock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_visual_loop demo',
      navigatorKey: FlutterVisualLoop.navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
      ),
      onGenerateRoute: (settings) => AppRouter.generate(settings, mock),
      initialRoute: '/',
    );
  }
}
