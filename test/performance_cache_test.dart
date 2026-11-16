import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/core/expiring_async_cache.dart';
import 'package:foundi/core/public_reference_store.dart';
import 'package:foundi/core/latest_async_refresh.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'cache coalesces concurrent loads, expires and retries failed loads',
    () async {
      var now = DateTime(2026), calls = 0;
      final cache = ExpiringAsyncCache<String, String>(
        maxEntries: 2,
        maxBytes: 20,
        ttl: const Duration(seconds: 30),
        sizeOf: (s) => s.length,
        clock: () => now,
      );
      final waiting = Completer<String>();
      final a = cache.load('a', () {
        calls++;
        return waiting.future;
      });
      final b = cache.load('a', () async {
        calls++;
        return 'wrong';
      });
      waiting.complete('first');
      expect(await Future.wait([a, b]), ['first', 'first']);
      expect(calls, 1);
      expect(await cache.load('a', () async => 'wrong'), 'first');
      now = now.add(const Duration(seconds: 30));
      await expectLater(
        cache.load('a', () async => throw StateError('offline')),
        throwsStateError,
      );
      expect(await cache.load('a', () async => 'fresh'), 'fresh');
    },
  );

  test(
    'invalidation fences pending media and cannot erase its replacement',
    () async {
      final cache = ExpiringAsyncCache<String, String>(
        maxEntries: 2,
        maxBytes: 20,
        ttl: const Duration(seconds: 30),
        sizeOf: (s) => s.length,
      );
      final old = Completer<String>(), fresh = Completer<String>();
      final a = cache.load('professional/photo', () => old.future);
      final rejected = expectLater(a, throwsA(isA<CacheInvalidated>()));
      cache.invalidateWhere((key) => key.startsWith('professional/'));
      final b = cache.load('professional/photo', () => fresh.future);
      old.complete('revoked');
      await rejected;
      final c = cache.load('professional/photo', () async => 'wrong');
      fresh.complete('new');
      expect(await Future.wait([b, c]), ['new', 'new']);
    },
  );

  test(
    'cache enforces LRU entries and bytes, excludes oversized images',
    () async {
      final cache = ExpiringAsyncCache<String, Uint8List>(
        maxEntries: 2,
        maxBytes: 6,
        ttl: const Duration(seconds: 30),
        sizeOf: (b) => b.length,
      );
      var reads = 0;
      Future<Uint8List> get(String key, int size) => cache.load(key, () async {
        reads++;
        return Uint8List(size);
      });
      await get('a', 3);
      await get('b', 3);
      await get('a', 3);
      await get('c', 3);
      await get('b', 3);
      expect(reads, 4);
      await get('huge', 7);
      await get('huge', 7);
      expect(reads, 6);
      cache.clear();
      await get('b', 3);
      expect(reads, 7);
    },
  );

  test(
    'reference load is shared, expires and does not return stale offline data',
    () async {
      var now = DateTime(2026), reads = 0, offline = false;
      final store = PublicReferenceStore<String>(
        fetch: () async {
          reads++;
          if (offline) throw StateError('offline');
          return 'catalog';
        },
        source: () => const Stream.empty(),
        clock: () => now,
      );
      expect(
        await Future.wait(List.generate(20, (_) => store.load())),
        everyElement('catalog'),
      );
      expect(reads, 1);
      now = now.add(const Duration(seconds: 31));
      offline = true;
      await expectLater(store.load(), throwsStateError);
      offline = false;
      expect(await store.load(), 'catalog');
      expect(reads, 3);
    },
  );

  test(
    'reference watchers share one source and detach the last subscription',
    () async {
      var subscriptions = 0, cancellations = 0;
      final source = StreamController<String>.broadcast(
        onListen: () => subscriptions++,
        onCancel: () => cancellations++,
      );
      final store = PublicReferenceStore<String>(
        fetch: () async => 'fetch',
        source: () => source.stream,
      );
      final left = <String>[], right = <String>[];
      final a = store.watch().listen(left.add),
          b = store.watch().listen(right.add);
      source.add('first');
      await flush();
      expect(subscriptions, 1);
      expect(left, ['first']);
      expect(right, ['first']);
      expect(await store.load(), 'first');
      await a.cancel();
      expect(cancellations, 0);
      await b.cancel();
      expect(cancellations, 1);
      final c = store.watch().listen(right.add);
      await flush();
      expect(subscriptions, 2);
      source.add('second');
      await flush();
      expect(await store.load(), 'second');
      await c.cancel();
      await source.close();
    },
  );

  test(
    'reference revocation errors fence pending responses and clear warm value',
    () async {
      final pending = Completer<String>();
      final source = StreamController<String>();
      final store = PublicReferenceStore<String>(
        fetch: () => pending.future,
        source: () => source.stream,
      );
      final errors = <Object>[];
      final subscription = store.watch().listen((_) {}, onError: errors.add);
      final load = store.load();
      final assertion = expectLater(load, throwsA(isA<CacheInvalidated>()));
      source.addError(StateError('permission denied'));
      await flush();
      pending.complete('obsolete');
      await assertion;
      expect(errors, hasLength(1));
      await subscription.cancel();
      await source.close();
    },
  );

  test(
    'refresh coalesces bursts, discards old work and releases after cancellation',
    () async {
      var runs = 0;
      final gate = Completer<void>();
      final values = <int>[];
      final refresh = LatestAsyncRefresh((current) async {
        final run = ++runs;
        if (run == 1) await gate.future;
        if (current()) values.add(run);
      });
      for (var i = 0; i < 20; i++) {
        refresh.request();
      }
      await flush();
      expect(runs, 1);
      for (var i = 0; i < 20; i++) {
        refresh.request();
      }
      gate.complete();
      await flush();
      await flush();
      expect(runs, 2);
      expect(values, [2]);
      refresh.request();
      refresh.close();
      await flush();
      expect(runs, 2);
    },
  );
}
