import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_visual_loop/flutter_visual_loop.dart';

void main() {
  group('RouteRegistry', () {
    test('register adds route and contains() finds it', () {
      final r = RouteRegistry();
      r.register('/home');
      expect(r.contains('/home'), isTrue);
      expect(r.names, contains('/home'));
    });

    test('register coerces missing leading slash', () {
      final r = RouteRegistry();
      r.register('settings');
      expect(r.contains('/settings'), isTrue);
    });

    test('unregister removes route', () {
      final r = RouteRegistry();
      r.register('/a');
      r.unregister('/a');
      expect(r.contains('/a'), isFalse);
    });

    test('clear empties registry', () {
      final r = RouteRegistry();
      r.register('/a');
      r.register('/b');
      r.clear();
      expect(r.names, isEmpty);
    });

    test('builderFor returns registered builder', () {
      final r = RouteRegistry();
      r.register('/x', (_) => const SizedBox());
      expect(r.builderFor('/x'), isNotNull);
      expect(r.builderFor('/missing'), isNull);
    });
  });
}
