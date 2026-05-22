/// Contract a host app implements so the visual-loop skill can flip mock
/// data on/off and swap individual values without restarting the app.
///
/// The host wires the provider into its repositories/services — the SDK
/// itself never reads mock data, it only routes control commands here.
abstract class MockDataProvider {
  /// Whether mock mode is currently active.
  bool get enabled;

  /// Turn mock mode on/off globally.
  void setEnabled(bool value);

  /// Read a value by key. Hosts decide the key schema.
  Object? get(String key);

  /// Write a value by key.
  void set(String key, Object? value);

  /// Drop all mock values and reset `enabled` to its initial state.
  void reset();

  /// Optional: list known keys (for `/mock` action=list introspection).
  Iterable<String> keys() => const <String>[];
}

/// Drop-in mock provider that stores key/value pairs in memory.
/// Good enough for the demo app and for many real apps.
class InMemoryMockDataProvider implements MockDataProvider {
  InMemoryMockDataProvider({bool initialEnabled = true})
      : _initialEnabled = initialEnabled,
        _enabled = initialEnabled;

  final bool _initialEnabled;
  bool _enabled;
  final Map<String, Object?> _store = <String, Object?>{};

  @override
  bool get enabled => _enabled;

  @override
  void setEnabled(bool value) {
    _enabled = value;
  }

  @override
  Object? get(String key) => _store[key];

  @override
  void set(String key, Object? value) {
    _store[key] = value;
  }

  @override
  void reset() {
    _store.clear();
    _enabled = _initialEnabled;
  }

  @override
  Iterable<String> keys() => _store.keys;
}
