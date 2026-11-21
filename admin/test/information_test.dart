import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/information_page.dart';
import 'package:foundi_admin/information_repository.dart';

class Repository implements InformationRepository {
  final saves = <Map<String, dynamic>>[];
  bool fail = false;
  @override
  Future<Map<String, dynamic>> list({Map<String, dynamic>? cursor}) async => {
    'items': [
      {
        'id': 'draft',
        'version': 'v1',
        'title': 'À publier',
        'summary': 'Résumé',
        'body': 'Article',
        'status': 'draft',
        'endsAt': DateTime.now()
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      },
      {
        'id': 'archive',
        'version': 'v2',
        'title': 'Ancienne annonce',
        'summary': 'Résumé ancien',
        'body': 'Texte conservé',
        'status': 'expired',
        'endsAt': DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      },
    ],
    'cursor': null,
  };
  @override
  Future<void> save(Map<String, dynamic> input) async {
    if (fail) {
      throw const InformationFailure('Cette annonce a changé. Actualise.');
    }
    saves.add(input);
  }
}

void main() {
  testWidgets(
    'admin publishes with end date and guarded revision; archives retain content',
    (t) async {
      final repo = Repository();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InformationPage(repository: repo)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Ancienne annonce'), findsNothing);
      await t.tap(find.text('Ouvrir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Publier'));
      await t.pumpAndSettle();
      expect(repo.saves.single['id'], 'draft');
      expect(repo.saves.single['expectedVersion'], 'v1');
      expect(repo.saves.single['status'], 'published');
      expect(
        repo.saves.single['endsAt'],
        greaterThan(DateTime.now().millisecondsSinceEpoch),
      );
      await t.tap(find.text('Archives'));
      await t.pumpAndSettle();
      expect(find.text('À publier'), findsNothing);
      expect(find.text('Ancienne annonce'), findsOneWidget);
      await t.tap(find.text('Ouvrir'));
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Texte conservé'),
        findsOneWidget,
      );
      await t.tap(find.text('Publier'));
      await t.pumpAndSettle();
      expect(
        find.text('Choisis une date de fin future pour publier.'),
        findsOneWidget,
      );
      expect(repo.saves.length, 1);
    },
  );
  testWidgets(
    'new announcement validates content and keeps draft open on conflict',
    (t) async {
      final repo = Repository()..fail = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InformationPage(repository: repo)),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Créer une annonce'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer en brouillon'));
      await t.pumpAndSettle();
      expect(find.text('Ce champ est requis.'), findsNWidgets(3));
      expect(repo.saves, isEmpty);
      final fields = find.byType(TextFormField);
      await t.enterText(fields.at(0), 'Titre');
      await t.enterText(fields.at(1), 'Résumé');
      await t.enterText(fields.at(2), 'Article');
      await t.tap(find.text('Enregistrer en brouillon'));
      await t.pumpAndSettle();
      expect(find.text('Cette annonce a changé. Actualise.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );
}
