import 'package:flutter/material.dart';

import '../pages/home_page.dart';
import '../pages/login_page.dart';
import '../pages/order_detail_page.dart';
import '../pages/product_detail_page.dart';

class AppRouter {
  /// The named routes this app's [generate] switch handles. Exposed once so
  /// the debug harness can feed `FlutterWright.start(routes:)` without a
  /// duplicated hand-typed list. `onGenerateRoute` apps have no enumerable
  /// route map, so this const is the single source.
  static const List<String> names = <String>[
    '/',
    '/login',
    '/product/detail',
    '/order/detail',
  ];

  static Route<dynamic>? generate(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute<void>(builder: (_) => const HomePage());
      case '/login':
        return MaterialPageRoute<void>(builder: (_) => const LoginPage());
      case '/product/detail':
        return MaterialPageRoute<void>(
          builder: (_) => ProductDetailPage(
            args: settings.arguments as Map<String, Object?>?,
          ),
        );
      case '/order/detail':
        return MaterialPageRoute<void>(
          builder: (_) => OrderDetailPage(
            args: settings.arguments as Map<String, Object?>?,
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
