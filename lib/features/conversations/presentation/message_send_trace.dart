import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Opt-in in profile/release with --dart-define=V91_TRACE=true.
/// Only random message IDs and timing metadata; never message content or UID.
class MessageSendTrace {
  MessageSendTrace._(this.id, this.clock);
  static final _traces = <String, MessageSendTrace>{};
  static final _received = <String>{};
  static const enabled = kDebugMode || bool.fromEnvironment('V91_TRACE');
  final String id;
  final Stopwatch clock;
  final _once = <String>{};
  int attempt = 0;

  static MessageSendTrace start(String id, Stopwatch clock) {
    if (_traces.length >= 100) _traces.remove(_traces.keys.first);
    final trace = MessageSendTrace._(id, clock);
    _traces[id] = trace;
    trace.mark('T0_tap');
    trace.mark('T1_handler');
    return trace;
  }

  static MessageSendTrace? find(String id) => _traces[id];

  static void snapshot(
    String id, {
    required bool fromCache,
    required bool pendingWrites,
  }) {
    final trace = find(id);
    if (trace != null) {
      trace.mark(
        'T5_snapshot',
        once: true,
        fromCache: fromCache,
        pendingWrites: pendingWrites,
      );
    } else {
      _receive(
        id,
        'R0_snapshot',
        fromCache: fromCache,
        pendingWrites: pendingWrites,
      );
    }
  }

  static void bubbleFrame(String id) {
    final trace = find(id);
    if (trace != null) {
      trace.mark('T6_bubble_frame', once: true);
    } else {
      _receive(id, 'R1_bubble_built_frame');
    }
  }

  static void _receive(
    String id,
    String stage, {
    bool? fromCache,
    bool? pendingWrites,
  }) {
    if (!enabled) return;
    if (_received.length >= 1000) _received.remove(_received.first);
    if (!_received.add('$id:$stage:$fromCache:$pendingWrites')) return;
    debugPrintSynchronously(
      jsonEncode({
        'event': 'message_receive_timing',
        'messageId': id,
        'stage': stage,
        'atUtc': DateTime.now().toUtc().toIso8601String(),
        'fromCache': ?fromCache,
        'pendingWrites': ?pendingWrites,
      }),
    );
  }

  void mark(
    String stage, {
    bool once = false,
    bool? fromCache,
    bool? pendingWrites,
  }) {
    if (once && !_once.add('$stage:$fromCache:$pendingWrites')) return;
    if (!enabled) return;
    debugPrintSynchronously(
      jsonEncode({
        'event': 'message_send_timing',
        'messageId': id,
        'attempt': attempt,
        'stage': stage,
        'elapsedUs': clock.elapsedMicroseconds,
        'atUtc': DateTime.now().toUtc().toIso8601String(),
        'fromCache': ?fromCache,
        'pendingWrites': ?pendingWrites,
      }),
    );
  }
}
