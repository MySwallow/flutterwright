import 'package:flutter/widgets.dart';

import 'logger.dart';

/// Tracks routes that have been declared as "visual-loop-discoverable".
///
/// The host app calls `register()` for each named route it wants the skill
/// to know about. The skill calls `GET /routes` to list them.
///
/// This is a separate concept from `MaterialApp.routes` because:
///   1. Many apps use `onGenerateRoute` instead of a static map.
///   2. Some routes (auth, splash) shouldn't be exposed.
class RouteRegistry {
  RouteRegistry();

  final Map<String, WidgetBuilder?> _routes = <String, WidgetBuilder?>{};

  /// Register a route. [builder] is optional — if null, the skill can still
  /// navigate to the route via the host's existing `onGenerateRoute`, this
  /// entry just makes it discoverable.
  void register(String name, [WidgetBuilder? builder]) {
    var n = name;
    if (!n.startsWith('/')) {
      vlWarn('route "$n" does not start with "/"; coercing');
      n = '/$n';
    }
    _routes[n] = builder;
    vlLog('registered route: $n');
  }

  void unregister(String name) {
    _routes.remove(name);
  }

  Iterable<String> get names => _routes.keys;

  WidgetBuilder? builderFor(String name) => _routes[name];

  bool contains(String name) => _routes.containsKey(name);

  void clear() => _routes.clear();
}
