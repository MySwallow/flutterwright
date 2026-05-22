import 'dart:async';
import 'dart:developer' as developer;

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../logger.dart';
import 'handler.dart';

class ReloadHandler extends Handler {
  ReloadHandler();

  @override
  String get path => '/reload';

  @override
  String get method => 'POST';

  @override
  Future<void> handle(HandlerContext ctx) async {
    final info = await developer.Service.getInfo();
    final serverUri = info.serverUri;
    if (serverUri == null) {
      await ctx.request.writeError(503, 'VM service is not enabled in this process');
      return;
    }

    final wsUri = _toWsUri(serverUri);
    VmService? vm;
    try {
      vm = await vmServiceConnectUri(wsUri.toString());
      final vmInfo = await vm.getVM();
      final isolates = vmInfo.isolates ?? const <IsolateRef>[];
      if (isolates.isEmpty) {
        await ctx.request.writeError(500, 'no isolates found');
        return;
      }
      final mainIso = isolates.firstWhere(
        (i) => i.name == 'main',
        orElse: () => isolates.first,
      );
      final result = await vm.reloadSources(mainIso.id!);
      final success = result.success ?? false;
      vlLog('reload success=$success');
      if (success) {
        await ctx.request.writeOk();
      } else {
        await ctx.request.writeError(500, 'reloadSources returned success=false');
      }
    } catch (e, st) {
      vlError('reload failed', e, st);
      await ctx.request.writeError(500, e.toString());
    } finally {
      await vm?.dispose();
    }
  }

  Uri _toWsUri(Uri http) {
    final path = http.path.endsWith('/') ? '${http.path}ws' : '${http.path}/ws';
    final scheme = http.scheme == 'https' ? 'wss' : 'ws';
    return http.replace(scheme: scheme, path: path);
  }
}
