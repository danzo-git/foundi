import 'dart:async';

/// Coalesces bursts and runs at most one refresh at a time. Permission/identity
/// changes invalidate previous work. Content-only updates can request a trailing
/// run without starving the first result during continuous incoming messages.
class LatestAsyncRefresh {
  LatestAsyncRefresh(this.refresh);
  final Future<void> Function(bool Function() isCurrent) refresh;
  bool _running = false, _dirty = false, _closed = false, _scheduled = false;
  int _revision = 0;
  void request({bool invalidateCurrent = true}) {
    if (_closed) return;
    if (invalidateCurrent) _revision++;
    _dirty = true;
    if (_running || _scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_run);
  }

  Future<void> _run() async {
    _scheduled = false;
    if (_closed || _running || !_dirty) return;
    _running = true;
    _dirty = false;
    final revision = _revision;
    try {
      await refresh(() => !_closed && revision == _revision);
    } finally {
      _running = false;
      if (_dirty && !_closed) request();
    }
  }

  void invalidate() {
    _revision++;
    _dirty = false;
  }

  void close() {
    _closed = true;
    invalidate();
  }
}
