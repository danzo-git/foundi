import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/core/initial_event_timeout.dart';
import 'package:foundi/core/latest_async_refresh.dart';
import 'package:foundi/features/conversations/data/conversation_visibility.dart';

// These are stream/timer tests; use an explicit clock without a frame scheduler.
void streamTest(String name, void Function(FakeAsync) body) => test(
  name,
  () => fakeAsync((clock) {
    body(clock);
    clock.flushMicrotasks();
    expect(clock.nonPeriodicTimerCount, 0);
  }),
);

void main() {
  streamTest(
    'a broadcast wrapper can be canceled and relistened with an independent deadline',
    (t) {
      var starts = 0, stops = 0;
      final source = StreamController<String>.broadcast(
        onListen: () => starts++,
        onCancel: () => stops++,
      );
      final stream = withInitialEventTimeout(source.stream);
      expect(stream.isBroadcast, isTrue);
      final values = <String>[], errors = <Object>[];
      final first = stream.listen(values.add, onError: errors.add);
      source.add('first listen');
      t.flushMicrotasks();
      first.cancel();
      t.flushMicrotasks();
      final second = stream.listen(values.add, onError: errors.add);
      t.elapse(const Duration(seconds: 13));
      expect(errors.single, isA<TimeoutException>());
      source.add('second listen');
      t.flushMicrotasks();
      expect(values, ['first listen', 'second listen']);
      expect(starts, 2);
      expect(stops, 1);
      second.cancel();
      t.flushMicrotasks();
      expect(stops, 2);
      source.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'initial deadline fails once, keeps source for reconnect, never times out idle loaded data',
    (t) {
      final source = StreamController<String>();
      final values = <String>[], errors = <Object>[];
      final sub = withInitialEventTimeout(
        source.stream,
      ).listen(values.add, onError: errors.add);
      t.elapse(const Duration(seconds: 11));
      expect(errors, isEmpty);
      t.elapse(const Duration(seconds: 2));
      expect(errors.single, isA<TimeoutException>());
      source.add('reconnected');
      t.flushMicrotasks();
      expect(values, ['reconnected']);
      t.elapse(const Duration(minutes: 1));
      expect(errors, hasLength(1));
      sub.cancel();
      t.flushMicrotasks();
      source.close();
      t.flushMicrotasks();
    },
  );

  streamTest('cancel releases the source and initial timer', (t) {
    var canceled = 0;
    final source = StreamController<String>(onCancel: () => canceled++);
    final errors = <Object>[];
    final sub = withInitialEventTimeout(
      source.stream,
    ).listen((_) {}, onError: errors.add);
    sub.cancel();
    t.flushMicrotasks();
    t.elapse(const Duration(seconds: 20));
    expect(canceled, 1);
    expect(errors, isEmpty);
    source.close();
    t.flushMicrotasks();
  });

  streamTest(
    'an initial error cancels the deadline and a later event can recover',
    (t) {
      final source = StreamController<String>();
      final values = <String>[], errors = <Object>[];
      final sub = withInitialEventTimeout(
        source.stream,
      ).listen(values.add, onError: errors.add);
      source.addError(StateError('permission'));
      t.flushMicrotasks();
      t.elapse(const Duration(seconds: 20));
      expect(errors, hasLength(1));
      source.add('new-authorized-result');
      t.flushMicrotasks();
      expect(values, ['new-authorized-result']);
      sub.cancel();
      t.flushMicrotasks();
      source.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'a stream closing before its first event cannot leave a loading spinner forever',
    (t) {
      final errors = <Object>[];
      final sub = withInitialEventTimeout(
        const Stream<String>.empty(),
      ).listen((_) {}, onError: errors.add);
      t.flushMicrotasks();
      expect(errors.single, isA<StateError>());
      t.elapse(const Duration(seconds: 20));
      expect(errors, hasLength(1));
      sub.cancel();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'cached absent deletion markers never authorize history; server confirmation can unlock it',
    (t) {
      final chat = StreamController<String?>(),
          marker = StreamController<({bool exists, bool fromCache})>();
      final rows = <String?>[];
      final sub = watchVisibleConversation(
        conversation: chat.stream,
        deletion: marker.stream,
        isCurrent: () => true,
      ).listen(rows.add);
      chat.add('private history');
      marker.add((exists: false, fromCache: true));
      t.flushMicrotasks();
      expect(rows, isEmpty);
      marker.add((exists: false, fromCache: false));
      t.flushMicrotasks();
      expect(rows, ['private history']);
      marker.add((exists: true, fromCache: false));
      t.flushMicrotasks();
      expect(rows.last, isNull);
      chat.add('a new message must stay hidden');
      t.flushMicrotasks();
      expect(rows.last, isNull);
      expect(rows, isNot(contains('a new message must stay hidden')));
      sub.cancel();
      t.flushMicrotasks();
      chat.close();
      t.flushMicrotasks();
      marker.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'a retained deletion marker resolves unavailable without waiting for the conversation',
    (t) {
      final chat = StreamController<String?>(),
          marker = StreamController<({bool exists, bool fromCache})>();
      final rows = <String?>[];
      final sub = watchVisibleConversation(
        conversation: chat.stream,
        deletion: marker.stream,
        isCurrent: () => true,
      ).listen(rows.add);
      marker.add((exists: true, fromCache: true));
      t.flushMicrotasks();
      expect(rows, [null]);
      sub.cancel();
      t.flushMicrotasks();
      chat.close();
      t.flushMicrotasks();
      marker.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'an error on history prevents marker updates from restoring the old snapshot',
    (t) {
      final chat = StreamController<String?>(),
          marker = StreamController<({bool exists, bool fromCache})>();
      final rows = <String?>[], errors = <Object>[];
      final sub = watchVisibleConversation(
        conversation: chat.stream,
        deletion: marker.stream,
        isCurrent: () => true,
      ).listen(rows.add, onError: errors.add);
      chat.add('old');
      marker.add((exists: false, fromCache: false));
      t.flushMicrotasks();
      expect(rows, ['old']);
      chat.addError(StateError('permission denied'));
      t.flushMicrotasks();
      marker.add((exists: false, fromCache: false));
      t.flushMicrotasks();
      expect(rows, ['old']);
      expect(errors, hasLength(1));
      chat.add('fresh');
      t.flushMicrotasks();
      expect(rows, ['old', 'fresh']);
      sub.cancel();
      t.flushMicrotasks();
      chat.close();
      t.flushMicrotasks();
      marker.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'an error on deletion visibility fences history until a new server confirmation',
    (t) {
      final chat = StreamController<String?>(),
          marker = StreamController<({bool exists, bool fromCache})>();
      final rows = <String?>[], errors = <Object>[];
      final sub = watchVisibleConversation(
        conversation: chat.stream,
        deletion: marker.stream,
        isCurrent: () => true,
      ).listen(rows.add, onError: errors.add);
      chat.add('old');
      marker.add((exists: false, fromCache: false));
      t.flushMicrotasks();
      marker.addError(StateError('permission denied'));
      t.flushMicrotasks();
      chat.add('new');
      marker.add((exists: false, fromCache: true));
      t.flushMicrotasks();
      expect(rows, ['old']);
      expect(errors, hasLength(1));
      marker.add((exists: false, fromCache: false));
      t.flushMicrotasks();
      expect(rows, ['old', 'new']);
      sub.cancel();
      t.flushMicrotasks();
      chat.close();
      t.flushMicrotasks();
      marker.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'viewer changes fence queued data and cancellation releases both joined sources',
    (t) {
      var current = true, canceled = 0;
      final chat = StreamController<String?>(onCancel: () => canceled++),
          marker = StreamController<({bool exists, bool fromCache})>(
            onCancel: () => canceled++,
          );
      final rows = <String?>[], errors = <Object>[];
      final sub = watchVisibleConversation(
        conversation: chat.stream,
        deletion: marker.stream,
        isCurrent: () => current,
      ).listen(rows.add, onError: errors.add);
      current = false;
      chat.add('previous viewer');
      marker.add((exists: false, fromCache: false));
      t.flushMicrotasks();
      chat.addError(StateError('old subscription'));
      t.flushMicrotasks();
      expect(rows, isEmpty);
      expect(errors, isEmpty);
      sub.cancel();
      t.flushMicrotasks();
      expect(canceled, 2);
      chat.close();
      t.flushMicrotasks();
      marker.close();
      t.flushMicrotasks();
    },
  );

  streamTest(
    'frequent content updates no longer starve an in-flight visibility result',
    (t) {
      final gate = Completer<void>();
      final values = <int>[];
      var runs = 0;
      final refresh = LatestAsyncRefresh((current) async {
        final run = ++runs;
        if (run == 1) await gate.future;
        if (current()) values.add(run);
      });
      refresh.request();
      t.flushMicrotasks();
      for (var i = 0; i < 20; i++) {
        refresh.request(invalidateCurrent: false);
      }
      gate.complete();
      t.flushMicrotasks();
      t.flushMicrotasks();
      expect(values, [1, 2]);
      expect(runs, 2);
      refresh.close();
    },
  );

  streamTest(
    'a visibility change still invalidates work despite content-only updates',
    (t) {
      final gate = Completer<void>();
      final values = <int>[];
      var runs = 0;
      final refresh = LatestAsyncRefresh((current) async {
        final run = ++runs;
        if (run == 1) await gate.future;
        if (current()) values.add(run);
      });
      refresh.request();
      t.flushMicrotasks();
      refresh.request(invalidateCurrent: false);
      refresh.request();
      gate.complete();
      t.flushMicrotasks();
      t.flushMicrotasks();
      expect(values, [2]);
      refresh.close();
    },
  );
}
