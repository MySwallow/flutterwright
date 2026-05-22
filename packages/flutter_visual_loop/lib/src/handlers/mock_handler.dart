import '../mock_provider.dart';
import 'handler.dart';

class MockHandler extends Handler {
  MockHandler(this.provider);

  final MockDataProvider? provider;

  @override
  String get path => '/mock';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final p = provider;
    if (p == null) {
      await ctx.request.writeError(501, 'no MockDataProvider configured');
      return;
    }
    final action = ctx.json['action'];
    switch (action) {
      case 'enable':
        final enabled = ctx.json['enabled'];
        if (enabled is! bool) {
          await ctx.request.writeError(400, 'enabled must be bool');
          return;
        }
        p.setEnabled(enabled);
        await ctx.request.writeOk(<String, Object?>{'enabled': enabled});
        return;
      case 'set':
        final key = ctx.json['key'];
        if (key is! String) {
          await ctx.request.writeError(400, 'key must be string');
          return;
        }
        p.set(key, ctx.json['value']);
        await ctx.request.writeOk(<String, Object?>{'key': key});
        return;
      case 'get':
        final key = ctx.json['key'];
        if (key is! String) {
          await ctx.request.writeError(400, 'key must be string');
          return;
        }
        await ctx.request.writeOk(<String, Object?>{
          'key': key,
          'value': p.get(key),
        });
        return;
      case 'reset':
        p.reset();
        await ctx.request.writeOk(<String, Object?>{'reset': true});
        return;
      case 'list':
        await ctx.request.writeOk(<String, Object?>{
          'enabled': p.enabled,
          'keys': p.keys().toList(),
        });
        return;
      default:
        await ctx.request.writeError(400, 'unknown action: $action');
    }
  }
}
