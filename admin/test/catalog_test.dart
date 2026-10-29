import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/catalog_page.dart';
import 'package:foundi_admin/catalog_repository.dart';

class FakeCatalog implements CatalogRepository {
  final data = <String, dynamic>{
    'enabled': false,
    'version': 'v1',
    'categories': [
      {
        'id': 'craft',
        'label': 'Artisans',
        'active': true,
        'specialties': <dynamic>[],
        'requirements': {'independent': <String>[], 'company': <String>[]},
      },
    ],
    'zones': <dynamic>[],
    'documentTypes': <dynamic>[],
  };
  final updates = <Map<String, dynamic>>[];
  bool offline = false;
  @override
  Stream<Map<String, dynamic>> watch() => Stream.value(data);
  @override
  Future<void> update(Map<String, dynamic> operation) async {
    if (offline) throw StateError('offline');
    updates.add(operation);
  }
}

void main() {
  testWidgets(
    'category editor keeps ID and sends guarded mutation, not direct Firestore write',
    (t) async {
      final repo = FakeCatalog();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogPage(section: 'categories', repository: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Modifier').first);
      await t.pumpAndSettle();
      await t.enterText(
        find.byType(TextFormField).first,
        'Artisans et services',
      );
      await t.ensureVisible(find.text('Enregistrer'));
      await t.tap(find.text('Enregistrer'));
      await t.pumpAndSettle();
      expect(repo.updates.single['id'], 'craft');
      expect(repo.updates.single['expectedVersion'], 'v1');
      expect(repo.updates.single['value']['label'], 'Artisans et services');
    },
  );
  testWidgets(
    'network error reports unsaved mutation and catalog fits a narrow viewport',
    (t) async {
      t.view.physicalSize = const Size(390, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeCatalog()..offline = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogPage(section: 'categories', repository: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byTooltip('Désactiver').first);
      await t.tap(find.byTooltip('Désactiver').first);
      await t.pumpAndSettle();
      expect(find.textContaining('Enregistrement impossible'), findsOneWidget);
      expect(repo.updates, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'geographic editor offers parent and level without destructive delete',
    (t) async {
      final repo = FakeCatalog();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogPage(section: 'zones', repository: repo),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Ajouter une zone'));
      await t.pumpAndSettle();
      expect(find.text('Type de zone'), findsOneWidget);
      expect(find.text('Zone parente'), findsOneWidget);
      expect(find.text('Supprimer'), findsNothing);
    },
  );
}
