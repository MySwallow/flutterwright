import 'package:flutter/material.dart';

import '../mock/demo_mock_provider.dart';
import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/order_detail_page.dart';
import '../pages/product_detail_page.dart';

class AppRouter {
  static Route<dynamic>? generate(
    RouteSettings settings,
    DemoMockProvider mock,
  ) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute<void>(builder: (_) => const HomePage());
      case '/login':
        return MaterialPageRoute<void>(builder: (_) => const LoginPage());
      case '/product/detail':
        return MaterialPageRoute<void>(
          builder: (_) => ProductDetailPage(
            args: settings.arguments as Map<String, Object?>?,
            mock: mock,
          ),
        );
      case '/order/detail':
        return MaterialPageRoute<void>(
          builder: (_) => OrderDetailPage(
            args: settings.arguments as Map<String, Object?>?,
            mock: mock,
          ),
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route: ${settings.name}')),
          ),
        );
    }
  }
}
