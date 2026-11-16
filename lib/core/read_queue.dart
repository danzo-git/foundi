import 'dart:async';
import 'dart:collection';

/// A bounded read queue. The deadline includes waiting for a slot, so queued
/// images cannot accumulate successive full network timeouts.
class ReadQueue {
  ReadQueue({
    this.concurrency = 4,
    this.maxQueued = 96,
    this.timeout = const Duration(seconds: 20),
    Duration Function()? clock,
  }) : _clock = clock ?? _monotonicClock();
  final int concurrency, maxQueued;
  final Duration timeout;
  final Duration Function() _clock;
  final _waiters = Queue<Completer<void>>();
  int _running = 0;

  static Duration Function() _monotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _running--;
    }
  }

  Future<T> run<T>(Future<T> Function(Duration remaining) read) async {
    final started = _clock();
    var acquired = false;
    try {
      if (_running < concurrency) {
        _running++;
      } else {
        if (_waiters.length >= maxQueued) {
          throw StateError('La file de photos est occupée. Réessaie.');
        }
        final waiter = Completer<void>();
        _waiters.add(waiter);
        await waiter.future.timeout(
          timeout,
          onTimeout: () {
            if (!_waiters.remove(waiter)) _release();
            throw TimeoutException(
              'Le chargement des photos a expiré.',
              timeout,
            );
          },
        );
      }
      acquired = true;
      final remaining = timeout - (_clock() - started);
      if (remaining <= Duration.zero) {
        throw TimeoutException('Le chargement des photos a expiré.', timeout);
      }
      return await Future<T>.sync(() => read(remaining)).timeout(remaining);
    } finally {
      if (acquired) _release();
    }
  }
}
