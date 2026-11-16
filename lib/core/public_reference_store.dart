import 'dart:async';
import 'expiring_async_cache.dart';

/// One public reference document, shared only within this repository instance.
/// No profiles, identifiers, messages, photos or permission decisions belong here.
class PublicReferenceStore<T extends Object> {
  PublicReferenceStore({
    required this.fetch,
    required this.source,
    this.ttl = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final Future<T> Function() fetch;
  final Stream<T> Function() source;
  final Duration ttl;
  final DateTime Function() _clock;
  T? _value;
  DateTime? _until;
  Future<T>? _pending;
  int _revision = 0;
  final _listeners = <MultiStreamController<T>>{};
  StreamSubscription<T>? _subscription;

  bool get _fresh => _value != null && (_until?.isAfter(_clock()) ?? false);
  void _save(T value) {
    _value = value;
    _until = _clock().add(ttl);
  }

  Future<T> load() {
    if (_fresh) return Future.value(_value);
    if (_pending case final pending?) return pending;
    final revision = _revision;
    late final Future<T> pending;
    pending = Future<T>.sync(fetch)
        .then((value) {
          if (revision != _revision) {
            if (_fresh) return _value!;
            throw const CacheInvalidated();
          }
          _save(value);
          return value;
        })
        .whenComplete(() {
          if (identical(_pending, pending)) _pending = null;
        });
    _pending = pending;
    return pending;
  }

  void invalidate() {
    _revision++;
    _value = null;
    _until = null;
    _pending = null;
  }

  Stream<T> watch() => Stream<T>.multi((listener) {
    _listeners.add(listener);
    if (_fresh) listener.add(_value!);
    if (_subscription == null) {
      final session = Object();
      _session = session;
      _subscription = source().listen(
        (value) {
          if (_session != session) return;
          _revision++;
          _save(value);
          for (final target in _listeners.toList()) {
            target.add(value);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (_session != session) return;
          invalidate();
          for (final target in _listeners.toList()) {
            target.addError(error, stack);
          }
        },
        onDone: () {
          if (_session != session) return;
          _subscription = null;
          _session = null;
          for (final target in _listeners.toList()) {
            target.close();
          }
          _listeners.clear();
        },
      );
    }
    listener.onCancel = () async {
      _listeners.remove(listener);
      if (_listeners.isEmpty) {
        final subscription = _subscription;
        _subscription = null;
        _session = null;
        await subscription?.cancel();
      }
    };
  });
  Object? _session;
}
