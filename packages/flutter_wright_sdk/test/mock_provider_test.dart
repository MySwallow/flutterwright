import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_wright_sdk/flutter_wright_sdk.dart';

void main() {
  group('InMemoryMockDataProvider', () {
    test('default enabled = true', () {
      final p = InMemoryMockDataProvider();
      expect(p.enabled, isTrue);
    });

    test('initialEnabled=false respected', () {
      final p = InMemoryMockDataProvider(initialEnabled: false);
      expect(p.enabled, isFalse);
    });

    test('set/get round-trips', () {
      final p = InMemoryMockDataProvider();
      p.set('k', 42);
      expect(p.get('k'), 42);
    });

    test('setEnabled toggles flag', () {
      final p = InMemoryMockDataProvider();
      p.setEnabled(false);
      expect(p.enabled, isFalse);
      p.setEnabled(true);
      expect(p.enabled, isTrue);
    });

    test('reset restores initial enabled state and clears store', () {
      final p = InMemoryMockDataProvider(initialEnabled: false);
      p.setEnabled(true);
      p.set('k', 'v');
      p.reset();
      expect(p.enabled, isFalse);
      expect(p.get('k'), isNull);
    });

    test('keys() lists current keys', () {
      final p = InMemoryMockDataProvider();
      p.set('a', 1);
      p.set('b', 2);
      expect(p.keys().toSet(), <String>{'a', 'b'});
    });
  });
}
