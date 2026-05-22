import 'package:flutter/widgets.dart';

import '../mock_provider.dart';
import 'handler.dart';

class ResetHandler extends Handler {
  ResetHandler({required this.navigatorKey, this.mockProvider});

  final GlobalKey<NavigatorState> navigatorKey;
  final MockDataProvider? mockProvider;

  @override
  String get path => '/reset';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final clearMock = ctx.json['clearMock'] == true;
    final nav = navigatorKey.currentState;
    nav?.popUntil((r) => r.isFirst);
    if (clearMock) mockProvider?.reset();
    await ctx.request.writeOk(<String, Object?>{'clearedMock': clearMock});
  }
}
