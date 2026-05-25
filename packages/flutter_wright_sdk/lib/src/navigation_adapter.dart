import 'dart:async';

import 'package:flutter/widgets.dart';

/// Decouples the SDK's `/navigate` and `/reset` control commands from any
/// particular routing stack.
///
/// Different apps route completely differently — Navigator 1.0 named routes,
/// GoRouter (URL/declarative), GetX (`Get.toNamed`), auto_route, etc. The host
/// picks a built-in adapter or supplies its own so the **same** skill works
/// regardless of the routing architecture. The SDK never assumes a routing API.
abstract class NavigationAdapter {
  /// Whether navigation can currently be performed (e.g. the navigator/router
  /// is mounted). When false, `/navigate` answers `503 navigator not ready`.
  bool get isReady;

  /// Navigate to [route]. [args] is an opaque payload the host interprets
  /// (route arguments / `extra` / GetX `arguments`). When [popUntilRoot] is
  /// true the adapter should first return to the root so navigation is
  /// deterministic regardless of the current stack depth.
  FutureOr<void> navigate(
    String route, {
    Object? args,
    bool popUntilRoot = true,
  });

  /// Return to the app's root/home (used by `/reset`).
  FutureOr<void> reset();

  /// Routes this adapter can enumerate for `GET /routes`. Null = not
  /// enumerable (e.g. `onGenerateRoute` / FlutterBoost `routeFactory`); the
  /// handler then returns an empty list. Concrete default benefits subclasses
  /// that `extends` this type; adapters that `implements` NavigationAdapter
  /// (incl. the built-ins below) must declare it themselves.
  Iterable<String>? get discoverableRoutes => null;
}

/// Default adapter for **Navigator 1.0 named routes**.
///
/// Drives a shared [GlobalKey] that the host also passes to
/// `MaterialApp(navigatorKey:)` / `CupertinoApp` / `WidgetsApp`. Used
/// automatically when [FlutterWright.start] is called without an explicit
/// `navigationAdapter`.
class NavigatorKeyAdapter implements NavigationAdapter {
  NavigatorKeyAdapter(
    this.navigatorKey, {
    Iterable<String> routes = const <String>[],
  }) : _routes = List<String>.unmodifiable(routes);

  final GlobalKey<NavigatorState> navigatorKey;
  // Eagerly materialized so a one-shot `Iterable` (e.g. a `sync*` generator)
  // isn't consumed by the `isEmpty` check before `discoverableRoutes` reads it.
  final List<String> _routes;

  @override
  Iterable<String>? get discoverableRoutes =>
      _routes.isEmpty ? null : _routes;

  @override
  bool get isReady => navigatorKey.currentState != null;

  @override
  FutureOr<void> navigate(
    String route, {
    Object? args,
    bool popUntilRoot = true,
  }) {
    // Handler already gated on isReady; if the navigator unmounted in between
    // (rare race), throw so the handler answers 500 rather than a silent 200.
    final nav = navigatorKey.currentState;
    if (nav == null) {
      throw StateError('navigator unmounted between isReady and navigate');
    }
    if (popUntilRoot) nav.popUntil((r) => r.isFirst);
    // ignore: unawaited_futures
    nav.pushNamed(route, arguments: args);
    return null;
  }

  @override
  FutureOr<void> reset() {
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
  }
}

/// Escape-hatch adapter for **any** routing stack — supply two closures.
///
/// This is how GoRouter / GetX / auto_route / Beamer integrate: the host owns
/// the routing API, the SDK just calls back.
///
/// GoRouter (`go()` already replaces history, so `popUntilRoot` needs no
/// special handling — it's effectively always true):
/// ```dart
/// CallbackNavigationAdapter(
///   onNavigate: (route, args, _) => router.go(route, extra: args),
///   onReset: () => router.go('/'),
/// )
/// ```
///
/// GetX:
/// ```dart
/// CallbackNavigationAdapter(
///   onNavigate: (route, args, _) => Get.toNamed(route, arguments: args),
///   onReset: () => Get.until((r) => r.isFirst),
/// )
/// ```
class CallbackNavigationAdapter implements NavigationAdapter {
  CallbackNavigationAdapter({
    required this.onNavigate,
    required this.onReset,
    bool Function()? readiness,
    Iterable<String> Function()? routesProvider,
  })  : _readiness = readiness,
        _routesProvider = routesProvider;

  /// Called for `/navigate`. Receives the route, opaque args, and the
  /// `popUntilRoot` flag (honor it if your stack supports it).
  final FutureOr<void> Function(String route, Object? args, bool popUntilRoot)
      onNavigate;

  /// Called for `/reset` to return to the root/home.
  final FutureOr<void> Function() onReset;

  final bool Function()? _readiness;

  // Called for `GET /routes`. Returns the routes this stack can enumerate
  // (e.g. GetX `getPages.map((p) => p.name)`), or null for non-enumerable
  // stacks. Invoked per request so dynamic route tables stay fresh.
  final Iterable<String> Function()? _routesProvider;

  @override
  Iterable<String>? get discoverableRoutes => _routesProvider?.call();

  @override
  bool get isReady => _readiness?.call() ?? true;

  @override
  FutureOr<void> navigate(
    String route, {
    Object? args,
    bool popUntilRoot = true,
  }) =>
      onNavigate(route, args, popUntilRoot);

  @override
  FutureOr<void> reset() => onReset();
}
