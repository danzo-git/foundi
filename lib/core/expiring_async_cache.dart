/// Bounded, memory-only cache for explicitly public, short-lived data.
/// Invalidating also fences pending responses: an old request cannot restore
/// revoked media, nor erase a newer request for the same key.
class CacheInvalidated implements Exception {
  const CacheInvalidated();
}

class ExpiringAsyncCache<K, V extends Object> {
  ExpiringAsyncCache({
    required this.maxEntries,
    required this.maxBytes,
    required this.ttl,
    required this.sizeOf,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEntries, maxBytes;
  final Duration ttl;
  final int Function(V) sizeOf;
  final DateTime Function() _clock;
  final _values = <K, ({V value, DateTime until, int bytes})>{};
  final _pending = <K, ({Object token, Future<V> future})>{};
  int _bytes = 0;

  Future<V> load(K key, Future<V> Function() fetch) {
    final cached = _values.remove(key);
    if (cached != null) {
      _bytes -= cached.bytes;
      if (cached.until.isAfter(_clock())) {
        _values[key] = cached;
        _bytes += cached.bytes;
        return Future.value(cached.value);
      }
    }
    final pending = _pending[key];
    if (pending != null) return pending.future;
    final token = Object();
    // Schedule the fetch after recording its identity, including sync failures.
    final future = Future<V>.sync(fetch)
        .then((value) {
          if (_pending[key]?.token != token) throw const CacheInvalidated();
          final bytes = sizeOf(value);
          if (bytes <= maxBytes) {
            _values[key] = (
              value: value,
              until: _clock().add(ttl),
              bytes: bytes,
            );
            _bytes += bytes;
            while (_values.length > maxEntries || _bytes > maxBytes) {
              _bytes -= _values.remove(_values.keys.first)!.bytes;
            }
          }
          return value;
        })
        .whenComplete(() {
          if (_pending[key]?.token == token) _pending.remove(key);
        });
    _pending[key] = (token: token, future: future);
    return future;
  }

  void invalidate(K key) {
    final entry = _values.remove(key);
    if (entry != null) _bytes -= entry.bytes;
    _pending.remove(key);
  }

  void invalidateWhere(bool Function(K) matches) {
    for (final key in {
      ..._values.keys,
      ..._pending.keys,
    }.where(matches).toList()) {
      invalidate(key);
    }
  }

  void clear() {
    _values.clear();
    _pending.clear();
    _bytes = 0;
  }
}
