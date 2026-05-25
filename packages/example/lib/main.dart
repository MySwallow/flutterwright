import 'package:flutter/material.dart';

import 'app.dart';

/// Production entrypoint — **no `flutter_wright_sdk` reference**.
///
/// `flutter run` / `flutter build` use this by default, so the debug control
/// server is never compiled in and the SDK stays in `dev_dependencies`. To run
/// with automation enabled: `flutter run -t dev/main_dev.dart`.
void main() => runApp(createApp());
