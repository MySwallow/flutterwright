# FlutterWright

Playwright-style Flutter device automation via Claude Code skill, on Android.

A monorepo containing:

- a **Claude Code skill** (`skills/flutterwright/`) exposing 8 methods (goto / screenshot / reload / mock / setViewport / …),
- a **Dart SDK** (`packages/flutter_visual_loop/`) that runs a debug-only HTTP control plane inside any Flutter app,
- a **demo Flutter app** (`packages/example/`) showing SDK integration,
- **reference documentation** (`docs/`).

```
flutterwright/
├── skills/flutterwright/   <- Claude Code skill (SKILL.md + scripts)
├── packages/
│   ├── flutter_visual_loop/  <- Dart SDK
│   └── example/              <- demo Flutter app
├── docs/                   <- API ref / architecture / integration / troubleshooting
└── ...
```

## Quickstart (5 minutes)

### Prerequisites

- Flutter 3.24+ (`flutter doctor` clean)
- Android real device (USB debugging on) or Android emulator
- `adb` in PATH (Android platform-tools)
- `curl`

### 1. Clone and bootstrap the demo app

```bash
git clone https://github.com/MySwallow/flutterwright.git
cd flutterwright/packages/example
flutter create . --platforms=android --org com.example.flutterwright
flutter pub get
```

`flutter create .` only fills in `android/` scaffolding; existing files are not touched.

### 2. Run the demo app (no fifo, plain `flutter run`)

```bash
flutter run -d $(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
```

Wait for:

```
[flutter_visual_loop] listening on http://127.0.0.1:9123
```

### 3. Forward the port + verify

```bash
adb forward tcp:9123 tcp:9123
curl http://localhost:9123/health
# → {"ok":true,"version":"0.2.0","service":"flutter_visual_loop"}
```

### 4. Drive the app from Claude Code

In a Claude Code session (cwd anywhere; the skill is repo-local at `skills/flutterwright/`):

```
Skill flutterwright "health"
Skill flutterwright "goto /order/detail args={\"id\":\"ORD-001\"}"
Skill flutterwright "screenshot $CLAUDE_JOB_DIR/cur.png"
```

See [`skills/flutterwright/SKILL.md`](skills/flutterwright/SKILL.md) for the full method reference.

### 5. Integrate the SDK into your own Flutter app

```dart
import 'package:flutter_visual_loop/flutter_visual_loop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterVisualLoop.start(
    testRoutes: const ['/home', '/order/detail', '/login'],
  );
  runApp(VisualLoopRoot(child: const MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: FlutterVisualLoop.navigatorKey,
      onGenerateRoute: yourRouter,
    );
  }
}
```

Full integration patterns (GoRouter, auth tokens, mock layering, multi-flavor): [`docs/integration-guide.md`](docs/integration-guide.md).

**Letting an AI assistant do the integration?** Point it at the AI-targeted version: [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md) — same content, restructured as a decision tree with pre-checks, exact code blocks, and verification steps so the assistant can't drift.

## Documentation

| Doc | What's in it |
|---|---|
| [`skills/flutterwright/SKILL.md`](skills/flutterwright/SKILL.md) | The 8 methods (signature, exit codes, examples) |
| [`docs/api-reference.md`](docs/api-reference.md) | SDK HTTP protocol — for direct curl / SDK contributors |
| [`docs/architecture.md`](docs/architecture.md) | Layering, components, security constraints |
| [`docs/integration-guide.md`](docs/integration-guide.md) | Dart integration patterns (10 scenarios) — for humans |
| [`docs/integration-guide-for-ai.md`](docs/integration-guide-for-ai.md) | **AI-targeted** integration guide: pre-checks, decision tree, verification steps |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Failure modes by symptom + E2E checklist |
| [`docs/superpowers/specs/`](docs/superpowers/specs/) | Design specs (v1 + future) |

## License

MIT — see [`LICENSE`](LICENSE).
