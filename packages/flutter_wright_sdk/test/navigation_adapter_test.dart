import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';
import 'package:flutter_wright_sdk/src/handlers/navigate_handler.dart';
import 'package:flutter_wright_sdk/src/handlers/reset_handler.dart';

void main() {
  // GlobalKey.currentState reads WidgetsBinding.instance.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavigatorKeyAdapter (Navigator 1.0)', () {
    test('isReady is false until a NavigatorState is mounted', () {
      final key = GlobalKey<NavigatorState>();
      final adapter = NavigatorKeyAdapter(key);
      expect(adapter.isReady, isFalse);
    });
  });

  group('CallbackNavigationAdapter (GoRouter / GetX / any)', () {
    test('forwards route + args + popUntilRoot to onNavigate', () async {
      String? gotRoute;
      Object? gotArgs;
      bool? gotPop;
      final adapter = CallbackNavigationAdapter(
        onNavigate: (route, args, popUntilRoot) {
          gotRoute = route;
          gotArgs = args;
          gotPop = popUntilRoot;
        },
        onReset: () {},
      );

      await adapter.navigate('/order/detail',
          args: <String, Object?>{'id': 'ORD-1'}, popUntilRoot: false);

      expect(gotRoute, '/order/detail');
      expect(gotArgs, <String, Object?>{'id': 'ORD-1'});
      expect(gotPop, isFalse);
    });

    test('forwards reset to onReset', () async {
      var reset = false;
      final adapter = CallbackNavigationAdapter(
        onNavigate: (_, __, ___) {},
        onReset: () => reset = true,
      );
      await adapter.reset();
      expect(reset, isTrue);
    });

    test('isReady defaults to true and honors readiness closure', () {
      expect(
        CallbackNavigationAdapter(onNavigate: (_, __, ___) {}, onReset: () {})
            .isReady,
        isTrue,
      );
      var ready = false;
      final gated = CallbackNavigationAdapter(
        onNavigate: (_, __, ___) {},
        onReset: () {},
        readiness: () => ready,
      );
      expect(gated.isReady, isFalse);
      ready = true;
      expect(gated.isReady, isTrue);
    });
  });

  group('handlers accept any NavigationAdapter', () {
    test('NavigateHandler is POST /navigate', () {
      final h = NavigateHandler(
        CallbackNavigationAdapter(onNavigate: (_, __, ___) {}, onReset: () {}),
      );
      expect(h.method, 'POST');
      expect(h.path, '/navigate');
    });

    test('ResetHandler is POST /reset', () {
      final h = ResetHandler(
        CallbackNavigationAdapter(onNavigate: (_, __, ___) {}, onReset: () {}),
      );
      expect(h.method, 'POST');
      expect(h.path, '/reset');
    });
  });
}
