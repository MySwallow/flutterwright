import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_visual_loop/src/handlers/reload_handler.dart';

void main() {
  group('ReloadHandler', () {
    test('is registered on POST /reload', () {
      final h = ReloadHandler();
      expect(h.method, 'POST');
      expect(h.path, '/reload');
    });
  });
}
