import '../logger.dart';
import '../navigation_adapter.dart';
import 'handler.dart';

class ResetHandler extends Handler {
  ResetHandler(this.adapter);

  final NavigationAdapter adapter;

  @override
  String get path => '/reset';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    try {
      if (adapter.isReady) {
        await adapter.reset();
      }
      await ctx.request.writeOk();
    } catch (e, st) {
      vlError('reset failed', e, st);
      await ctx.request.writeError(500, e.toString());
    }
  }
}
