import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/core/in_flight_reads.dart';
import 'package:foundi/core/expiring_async_cache.dart';
import 'package:foundi/core/read_queue.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/request_respondents.dart';

class RespondentsSource implements RequestRespondentsRepository {
  RespondentsSource(this.handler);
  final Future<RequestRespondentsPage> Function(String, int) handler;
  final calls = <(String, int)>[];
  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) {
    calls.add((requestId, offset));
    return handler(requestId, offset);
  }
}

RequestRespondentsPage rows(String name, {int? next}) => RequestRespondentsPage(
  total: 2,
  canViewProposals: false,
  nextOffset: next,
  items: [
    RequestRespondent(name, ['Activité'], professionalId: name),
  ],
);
RequestRespondentsPage empty(int? next) => RequestRespondentsPage(
  total: 2,
  canViewProposals: false,
  nextOffset: next,
  items: const [],
);
Widget screen(RespondentsSource repository, {String id = 'request-A'}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RequestRespondents(
            key: const ValueKey('respondents'),
            repository: repository,
            requestId: id,
          ),
        ),
      ),
    );

void main() {
  test(
    'a revoked media cache does not reuse an old transport response',
    () async {
      final cache = ExpiringAsyncCache<String, String>(
        maxEntries: 2,
        maxBytes: 100,
        ttl: const Duration(seconds: 30),
        sizeOf: (value) => value.length,
      );
      final reads = InFlightReads();
      final old = Completer<String>(), fresh = Completer<String>();
      var calls = 0;
      final before = cache.load(
        'photo',
        () => reads.runUnshared(() {
          calls++;
          return old.future;
        }),
      );
      final assertion = expectLater(before, throwsA(isA<CacheInvalidated>()));
      cache.invalidate('photo');
      final after = cache.load(
        'photo',
        () => reads.runUnshared(() {
          calls++;
          return fresh.future;
        }),
      );
      expect(calls, 2);
      old.complete('revoked');
      await assertion;
      fresh.complete('new');
      expect(await after, 'new');
      expect(await cache.load('photo', () async => 'wrong'), 'new');
    },
  );
  testWidgets(
    'waiting and network share one deadline; expired queued media never fetch',
    (t) async {
      final start = t.binding.clock.now();
      final queue = ReadQueue(
        concurrency: 1,
        timeout: const Duration(seconds: 2),
        clock: () => t.binding.clock.now().difference(start),
      );
      final stuck = Completer<String>();
      final first = queue.run((_) => stuck.future);
      final firstError = expectLater(first, throwsA(isA<TimeoutException>()));
      var fetched = false;
      final second = queue.run((_) async {
        fetched = true;
        return 'wrong';
      });
      final secondError = expectLater(second, throwsA(isA<TimeoutException>()));
      await t.pump(const Duration(seconds: 3));
      await Future.wait([firstError, secondError]);
      expect(fetched, false);
      expect(await queue.run((_) async => 'recovered'), 'recovered');
      stuck.complete('late');
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'queued media receives remaining budget and queue length is bounded',
    (t) async {
      final start = t.binding.clock.now();
      final queue = ReadQueue(
        concurrency: 1,
        maxQueued: 1,
        timeout: const Duration(seconds: 2),
        clock: () => t.binding.clock.now().difference(start),
      );
      final pending = Completer<String>();
      final first = queue.run((_) => pending.future);
      Duration? budget;
      final second = queue.run((remaining) async {
        budget = remaining;
        return 'second';
      });
      await expectLater(queue.run((_) async => 'overflow'), throwsStateError);
      await t.pump(const Duration(seconds: 1));
      pending.complete('first');
      await t.pump();
      expect(await Future.wait([first, second]), ['first', 'second']);
      expect(budget, const Duration(seconds: 1));
    },
  );
  testWidgets(
    'temporary pagination errors retain already displayed respondents',
    (t) async {
      final source = RespondentsSource((_, offset) async {
        if (offset > 0) throw const AuthFailure('Connexion interrompue');
        return rows('Initial', next: 20);
      });
      await t.pumpWidget(screen(source));
      await t.pumpAndSettle();
      await t.tap(find.text('Voir plus de répondants'));
      await t.pumpAndSettle();
      expect(find.text('Initial'), findsOneWidget);
      expect(find.text('Connexion interrompue'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'concurrent reads share work but a completed result is never cached',
    () async {
      var calls = 0;
      final pending = Completer<String>();
      final reads = InFlightReads();
      final first = reads.run('profile', () {
        calls++;
        return pending.future;
      });
      final second = reads.run('profile', () async {
        calls++;
        return 'wrong';
      });
      pending.complete('current');
      expect(await Future.wait([first, second]), ['current', 'current']);
      expect(calls, 1);
      expect(
        await reads.run('profile', () async {
          calls++;
          return 'fresh';
        }),
        'fresh',
      );
      expect(calls, 2);
    },
  );
  test(
    'reads never share data across accounts or a new session of the same account',
    () async {
      Object scope = ('account-A', 1);
      final reads = InFlightReads(currentScope: () => scope);
      final old = Completer<String>();
      final previous = reads.run('profile', () => old.future);
      final denied = expectLater(previous, throwsA(isA<ReadScopeChanged>()));
      scope = ('account-B', 1);
      expect(await reads.run('profile', () async => 'B'), 'B');
      scope = ('account-A', 2);
      expect(await reads.run('profile', () async => 'new-A'), 'new-A');
      old.complete('old-A');
      await denied;
    },
  );
  test('a failed read is released so the user can retry immediately', () async {
    final reads = InFlightReads();
    await expectLater(
      reads.run('profile', () async => throw StateError('offline')),
      throwsStateError,
    );
    expect(await reads.run('profile', () async => 'online'), 'online');
  });
  testWidgets('a stuck read expires and late completion cannot erase a retry', (
    t,
  ) async {
    final reads = InFlightReads(timeout: const Duration(seconds: 2));
    final stale = Completer<String>(), fresh = Completer<String>();
    final old = reads.run('profile', () => stale.future);
    final expired = expectLater(old, throwsA(isA<TimeoutException>()));
    await t.pump(const Duration(seconds: 3));
    await expired;
    final retry = reads.run('profile', () => fresh.future);
    stale.complete('obsolete');
    await t.pump();
    final shared = reads.run('profile', () async => 'wrong');
    fresh.complete('fresh');
    expect(await Future.wait([retry, shared]), ['fresh', 'fresh']);
  });
  testWidgets(
    'respondents stop spinning after deadline and ignore an old result after retry',
    (t) async {
      final old = Completer<RequestRespondentsPage>();
      var calls = 0;
      final source = RespondentsSource(
        (_, _) => ++calls == 1 ? old.future : Future.value(rows('Fresh')),
      );
      await t.pumpWidget(screen(source));
      await t.pump(const Duration(seconds: 21));
      await t.pump();
      expect(find.textContaining('trop de temps'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text('Fresh'), findsOneWidget);
      old.complete(rows('Obsolete'));
      await t.pumpAndSettle();
      expect(find.text('Obsolete'), findsNothing);
      expect(find.text('Fresh'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('changing request discards old responses and loading flags', (
    t,
  ) async {
    final old = Completer<RequestRespondentsPage>();
    final source = RespondentsSource(
      (id, _) => id == 'request-A' ? old.future : Future.value(rows('B')),
    );
    await t.pumpWidget(screen(source));
    await t.pumpWidget(screen(source, id: 'request-B'));
    await t.pumpAndSettle();
    old.complete(rows('A'));
    await t.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'empty filtered pages advance automatically with a bounded budget',
    (t) async {
      final source = RespondentsSource(
        (_, offset) async => offset == 0 ? empty(20) : rows('Visible'),
      );
      await t.pumpWidget(screen(source));
      await t.pumpAndSettle();
      expect(source.calls.map((c) => c.$2), [0, 20]);
      expect(find.text('Visible'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      final allEmpty = RespondentsSource(
        (_, offset) async => empty(offset + 20),
      );
      await t.pumpWidget(screen(allEmpty));
      await t.pumpAndSettle();
      expect(allEmpty.calls.map((c) => c.$2), [0, 20, 40]);
      expect(find.text('Voir plus de répondants'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('an access refusal removes previously loaded respondents', (
    t,
  ) async {
    final source = RespondentsSource((_, offset) async {
      if (offset > 0) throw const ReadAccessDenied('Demande indisponible');
      return rows('Initial', next: 20);
    });
    await t.pumpWidget(screen(source));
    await t.pumpAndSettle();
    expect(find.text('Initial'), findsOneWidget);
    await t.tap(find.text('Voir plus de répondants'));
    await t.pumpAndSettle();
    expect(find.text('Initial'), findsNothing);
    expect(find.text('Demande indisponible'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
