---
name: flutterwright
description: Playwright-style driver for Flutter apps running on Android devices/emulators via the flutter_visual_loop SDK. Use when you need to navigate routes, screenshot, hot-reload, inject mock data, or lock viewport. Skill provides 8 methods (health/goto/screenshot/reload/setViewport/resetViewport/mock/reset).
---

# FlutterWright — Playwright for Flutter on Android

A Layer 2b driver skill: given a host Flutter app that integrates the `flutter_visual_loop` SDK and is running on a connected Android device (real or emulator), this skill exposes a Playwright-style API to drive it from Claude or higher-layer orchestration skills.

Android-only in v1. iOS support, UI interaction (tap/swipe/text), and widget tree introspection are out of scope — see [v1 design spec](../../docs/superpowers/specs/2026-05-22-flutterwright-design.md) §10.

Declare on entry: **"Using flutterwright to <method> <target>."**

## When to use

- Ad-hoc: user has a Flutter app already running via `flutter run` and wants Claude to drive it ("navigate to /order, screenshot it").
- Composition: a higher-layer skill (e.g. flutter-visual-loop UI restoration loop) invokes flutterwright methods as building blocks via `Skill flutterwright "..."`.

Don't use if: the host app hasn't integrated `flutter_visual_loop` SDK (no HTTP control plane → nothing to talk to). Refer the user to [integration-guide.md](../../docs/integration-guide.md).

## Concepts

- **Page** = the Flutter app currently running on a connected Android device.
- **Route** = a named app route (e.g. `/order/detail`).
- **Mock** = data injected via `flutter_visual_loop.MockDataProvider`.
- **Viewport** = `wm size` + `wm density` override locking the device to design resolution.
- **Reload** = Flutter hot reload triggered via SDK `/reload` endpoint (`vm_service.reloadSources`).

## Methods

| Method | Purpose | Script |
|---|---|---|
| `health` | Verify env (adb / device / SDK reachability + auto `adb forward` 9123) | `health.sh` |
| `goto <route> [args=<json>] [popUntilRoot=<bool>]` | Push a named route | `goto.sh` |
| `screenshot <out_path>` | Device screenshot (full frame incl. status bar) to PNG | `screenshot.sh` |
| `reload` | Flutter hot reload via SDK `/reload` | `reload.sh` |
| `setViewport <w> <h> <dpi>` | Lock `wm size` + `wm density` | `set_viewport.sh` |
| `resetViewport` | Restore `wm size` + `wm density` to device defaults | `reset_viewport.sh` |
| `mock <action> [key=<k>] [value=<json>] [enabled=<bool>]` | Mock data control (action ∈ set/get/reset/enable/list) | `mock.sh` |
| `reset [clearMock=<bool>]` | Pop navigator to root, optionally clear mock | `reset.sh` |

## Prerequisites

- macOS / Linux with `adb` and `curl` in `PATH`.
- Host Flutter app integrates `flutter_visual_loop` ≥ 0.2.0 (containing `/reload` endpoint).
- `flutter run -d <device>` is active. **No fifo needed** — v1 dropped the stdin-fifo hot-reload path.

Full setup: see [`README.md` Quickstart](../../README.md#quickstart).

## Method reference

### `health`

```
Skill flutterwright "health"
```

Validates `adb` + at least one connected device + `curl` available, then performs `adb forward tcp:9123 tcp:9123` (idempotent) and probes `GET /health`.

Exit codes: 0 ok / 10 adb missing / 11 no device / 12 SDK unreachable / 13 curl missing.

Output: `ok: device=<id> port=9123`.

### `goto`

```
Skill flutterwright "goto <route> [args=<json>] [popUntilRoot=<bool>]"
```

Push `<route>` via `Navigator.pushNamed`. `args` is an arbitrary JSON value passed as `arguments:`. `popUntilRoot` defaults to `true` (pop to root first, avoiding state pollution across loop iterations).

Example: `Skill flutterwright "goto /order/detail args={\"id\":\"ORD-001\"}"`

Exit codes: 0 ok / 40 missing route or unknown arg / 41 navigator not ready (HTTP 503) / 42 push failed (HTTP 500) / 43 SDK unreachable.

### `screenshot`

```
Skill flutterwright "screenshot <out_path>"
```

`adb exec-out screencap -p > <out>` followed by PNG magic-byte check. Captures **full device frame including status bar**. For Flutter-only render tree, use SDK `GET /screenshot` directly (not exposed as a method in v1).

Example: `Skill flutterwright "screenshot /tmp/order_detail.png"`

Exit codes: 0 ok / 20 empty file / 21 file < 1KB / 22 not a PNG (device locked?).

### `reload`

```
Skill flutterwright "reload"
```

Triggers `vm_service.reloadSources` via SDK `POST /reload`. Assumes source files on the device-side dart isolate have been updated (typically the upper-layer skill or user edited Dart files before invoking).

Example: `Skill flutterwright "reload"`

Exit codes: 0 ok / 30 SDK unreachable / 31 VM service not available (release build? SDK < 0.2.0?) / 32 `/reload` returned non-200.

Implementation detail: sleeps 1s after success to let Flutter apply the reload.

### `setViewport`

```
Skill flutterwright "setViewport <width> <height> <dpi>"
```

Records original `wm size` and `wm density` to `$CLAUDE_JOB_DIR/fw_original.env`, then applies the override and validates via readback (some vendor ROMs silently reject `wm` overrides — readback detects this).

Example: `Skill flutterwright "setViewport 1080 2400 480"`

Exit codes: 0 ok / 60 missing args / 61 override rejected (readback mismatch).

### `resetViewport`

```
Skill flutterwright "resetViewport"
```

Restores `wm size` + `wm density` from `$CLAUDE_JOB_DIR/fw_original.env`. If the file is missing, falls back to `wm size reset` + `wm density reset`. **Always exits 0** — safe to call from a `trap` or any cleanup hook.

Example: `Skill flutterwright "resetViewport"`

Exit codes: 0 always.

### `mock`

```
Skill flutterwright "mock <action> [key=<k>] [value=<json>] [enabled=<bool>]"
```

Dispatches `POST /mock` with the right body for each action:

- `mock set key=<k> value=<json>` — inject a value
- `mock get key=<k>` — read a value
- `mock reset` — clear all
- `mock enable enabled=<true|false>` — toggle global mock mode
- `mock list` — list current state

Examples:
- `Skill flutterwright "mock set key=user value={\"name\":\"Alice\"}"`
- `Skill flutterwright "mock enable enabled=false"`
- `Skill flutterwright "mock list"`

Exit codes: 0 / 50 missing action / 51 invalid action or unknown arg / 52 missing key (set/get) / 53 missing value (set) / 54 missing enabled (enable) / 55 SDK returned 501 (no MockDataProvider configured) / 56 SDK unreachable.

### `reset`

```
Skill flutterwright "reset [clearMock=<bool>]"
```

`POST /reset` with `{"clearMock":<bool>}`. Defaults to `clearMock=true`.

Example: `Skill flutterwright "reset"` or `Skill flutterwright "reset clearMock=false"`

Exit codes: 0 / 70 SDK unreachable or unknown arg / 71 `/reset` returned non-200.

## Dispatch convention

When invoked as `Skill flutterwright "<method> <args...>"`:

1. Parse the first whitespace-separated token as the **method name**.
2. Parse remaining tokens as positional (for `goto`/`screenshot`/`setViewport`) followed by `key=value` pairs.
3. Invoke `bash skills/flutterwright/scripts/<method>.sh <args>`.

JSON values in `key=value` must escape internal `"` as `\"` (so they survive shell + curl). Example:

- Skill call: `goto /order/detail args={\"id\":\"X\"}`
- Bash exec:  `bash scripts/goto.sh /order/detail 'args={"id":"X"}'`

## Exit code map

| Range | Category | Notes |
|---|---|---|
| 0 | success | — |
| 10-13 | env / device | health.sh — see [troubleshooting](../../docs/troubleshooting.md) |
| 20-22 | screenshot | screenshot.sh |
| 30-32 | reload | reload.sh |
| 40-43 | navigate | goto.sh |
| 50-56 | mock | mock.sh |
| 60-61 | viewport | set_viewport.sh / reset_viewport.sh (rare — reset always exits 0) |
| 70-71 | reset | reset.sh |

## See also

- [api-reference.md](../../docs/api-reference.md) — SDK HTTP protocol
- [integration-guide.md](../../docs/integration-guide.md) — integrating the SDK into your Flutter app
- [troubleshooting.md](../../docs/troubleshooting.md) — failure modes by symptom
