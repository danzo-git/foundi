import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/requests/presentation/explorer_view.dart';
import 'package:foundi/features/professional/presentation/professional_directory_view.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import '../tool/performance/main.dart' as fixture;

class PendingCatalog extends fixture.CatalogFixture {
  final pending = Completer<ProfessionalCatalog>();
  @override
  Future<ProfessionalCatalog> loadCatalog() {
    reads++;
    return pending.future;
  }
}

void main() {
  testWidgets(
    'public requests render before a slow catalog, retain data after catalog error',
    (t) async {
      final repo = fixture.RequestsFixture(), catalog = PendingCatalog();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerView(
              repository: repo,
              catalog: catalog,
              onOpen: (_) {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 90));
      await t.pump();
      expect(find.text('PERFORMANCE_FIXTURE_0'), findsOneWidget);
      expect(catalog.reads, 1);
      catalog.pending.completeError(StateError('offline catalog'));
      await t.pump();
      expect(find.text('PERFORMANCE_FIXTURE_0'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repo.cancellations, 1);
    },
  );

  testWidgets(
    'return to retained Explorer neither reloads nor opens a second subscription',
    (t) async {
      final repo = fixture.RequestsFixture(),
          catalog = fixture.CatalogFixture();
      final key = GlobalKey();
      Widget page(bool active) => MaterialApp(
        home: Scaffold(
          body: Offstage(
            offstage: !active,
            child: ExplorerView(
              key: key,
              active: active,
              repository: repo,
              catalog: catalog,
              onOpen: (_) {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await t.pumpWidget(page(true));
      await t.pump(const Duration(milliseconds: 300));
      await t.pump();
      await t.pumpWidget(page(false));
      await t.pumpWidget(page(true));
      expect(repo.subscriptions, 1);
      expect(catalog.reads, 1);
      expect(find.text('PERFORMANCE_FIXTURE_0'), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repo.cancellations, 1);
    },
  );

  testWidgets(
    'directory rebuilds reuse thumbnails; inactive cards hide media and revalidate',
    (t) async {
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6nGsAAAAASUVORK5CYII=',
      );
      final repo = fixture.DirectoryFixture(bytes, expiringMedia: true),
          catalog = fixture.CatalogFixture();
      final key = GlobalKey();
      Widget page(bool active, int revision) => MaterialApp(
        home: Scaffold(
          body: ProfessionalDirectoryView(
            key: key,
            active: active,
            repository: repo,
            catalog: catalog,
            heading: Text('Annuaire $revision'),
          ),
        ),
      );
      await t.pumpWidget(page(true, 0));
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(repo.thumbnails, 4);
      for (var i = 1; i <= 20; i++) {
        await t.pumpWidget(page(true, i));
        await t.pumpAndSettle();
      }
      expect(repo.thumbnails, 4);
      // A fast availability check must not extend the original media deadline.
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
      expect(repo.thumbnails, 8);
      expect(repo.invalidations, 1);
      await t.pumpWidget(page(false, 21));
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await t.pumpWidget(page(true, 22));
      await t.pumpAndSettle();
      expect(repo.thumbnails, 12);
      expect(repo.invalidations, 1);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
