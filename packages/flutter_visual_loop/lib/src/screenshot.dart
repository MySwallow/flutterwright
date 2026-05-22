import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'logger.dart';

/// Capture the current screen via the root `RenderRepaintBoundary`.
///
/// Returns null when the root render object is not a `RepaintBoundary`.
/// In that case, the host should wrap its app with [VisualLoopRoot], or
/// the skill should fall back to `adb exec-out screencap`.
///
/// The captured image excludes OS chrome (status/nav bars). Pair with
/// `adb exec-out screencap` when you need the full device frame.
Future<Uint8List?> captureFlutterScreen({double? pixelRatio}) async {
  try {
    final binding = WidgetsBinding.instance;
    // ignore: deprecated_member_use
    final RenderObject? root = binding.rootElement?.renderObject;

    if (root is! RenderRepaintBoundary) {
      vlWarn('root render object is not a RepaintBoundary; '
          'wrap your app with VisualLoopRoot to enable /screenshot');
      return null;
    }

    final ratio = pixelRatio ??
        binding.platformDispatcher.views.first.devicePixelRatio;
    final image = await root.toImage(pixelRatio: ratio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (e, st) {
    vlError('captureFlutterScreen failed', e, st);
    return null;
  }
}

/// Widget wrapper to make `/screenshot` reliable.
///
/// Usage: `runApp(VisualLoopRoot(child: MyApp()))`.
class VisualLoopRoot extends StatelessWidget {
  const VisualLoopRoot({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: child);
  }
}
