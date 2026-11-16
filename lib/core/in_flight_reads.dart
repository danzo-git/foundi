import 'dart:async';

class ReadScopeChanged implements Exception {
  const ReadScopeChanged();
}

/// Shares only concurrent reads. No completed response or permission decision
/// is cached. Identity/session changes fence results from an earlier viewer.
class InFlightReads {
  InFlightReads({
    this.currentScope,
    this.timeout = const Duration(seconds: 20),
    this.maxPending = 32,
  });
  final Object? Function()? currentScope;
  final Duration timeout;
  final int maxPending;
  final _pending = <Object, Future<Object?>>{};

  Future<T> _read<T>(Object? scope, Future<T> Function() read) =>
      Future<T>.sync(read).timeout(timeout).then((value) {
        if (scope != currentScope?.call()) throw const ReadScopeChanged();
        return value;
      });

  // Media caches already share their own misses and fence invalidated results.
  // Their next miss must use a fresh HTTP request after a revocation.
  Future<T> runUnshared<T>(Future<T> Function() read) =>
      _read(currentScope?.call(), read);

  Future<T> run<T>(Object key, Future<T> Function() read) {
    final scope = currentScope?.call();
    final scopedKey = (scope, key);
    final pending = _pending[scopedKey];
    if (pending != null) return pending as Future<T>;
    late final Future<T> future;
    future = _read(scope, read).whenComplete(() {
      if (identical(_pending[scopedKey], future)) {
        _pending.remove(scopedKey);
      }
    });
    // Limit the registry even if a caller opens many different resources. A
    // saturated registry still allows the read, without retaining another key.
    if (_pending.length < maxPending) _pending[scopedKey] = future;
    return future;
  }
}
