import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'logger.dart';

/// Key on the [FlutterWrightRoot] `RepaintBoundary` so `/screenshot` can find
/// and capture the app's render tree.
///
/// This is necessary because the binding's *root* render object is the
/// `RenderView` (which is never a `RenderRepaintBoundary`), and the boundary
/// installed by [FlutterWrightRoot] sits *below* that view. Locating it by key
/// is the only reliable way to reach it.
final GlobalKey fwRepaintBoundaryKey =
    GlobalKey(debugLabel: 'flutter_wright_sdk.repaintBoundary');

/// Capture the current screen via the [FlutterWrightRoot] `RepaintBoundary`.
///
/// Returns null when no `RepaintBoundary` is reachable — i.e. the host did not
/// wrap its app with [FlutterWrightRoot]. In that case the skill should fall
/// back to `adb exec-out screencap`.
///
/// The captured image excludes OS chrome (status/nav bars). Pair with
/// `adb exec-out screencap` when you need the full device frame.
Future<Uint8List?> captureFlutterScreen({double? pixelRatio}) async {
  try {
    final binding = WidgetsBinding.instance;
    // Prefer the FlutterWrightRoot boundary (located by key); fall back to the
    // binding root for hosts that already expose a RepaintBoundary there.
    final RenderObject? boundary =
        fwRepaintBoundaryKey.currentContext?.findRenderObject() ??
            // ignore: deprecated_member_use
            binding.rootElement?.renderObject;

    if (boundary is! RenderRepaintBoundary) {
      vlWarn('no RepaintBoundary found; '
          'wrap your app with FlutterWrightRoot to enable /screenshot');
      return null;
    }

    final ratio = pixelRatio ??
        binding.platformDispatcher.views.first.devicePixelRatio;
    final image = await boundary.toImage(pixelRatio: ratio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (e, st) {
    vlError('captureFlutterScreen failed', e, st);
    return null;
  }
}

/// Widget wrapper to make `/screenshot` reliable.
///
/// Usage: `runApp(FlutterWrightRoot(child: MyApp()))`. Installs a keyed
/// `RepaintBoundary` ([fwRepaintBoundaryKey]) that [captureFlutterScreen] uses.
class FlutterWrightRoot extends StatelessWidget {
  const FlutterWrightRoot({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: fwRepaintBoundaryKey, child: child);
  }
}
