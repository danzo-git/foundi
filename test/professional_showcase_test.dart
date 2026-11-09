import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';

import 'proposals_v7_test.dart' as proposals;
import 'widget_test.dart' as fixtures;

class ShowcasePro extends fixtures.FakePro
    implements ProfessionalShowcaseRepository {
  ShowcasePro({super.profile, this.showcase});

  ProfessionalShowcase? showcase;
  final reads = <String?>[];
  bool failShowcaseSave = false;

  @override
  Future<ProfessionalShowcase?> readShowcase({String? proposalId}) async {
    reads.add(proposalId);
    return showcase;
  }

  @override
  Future<ProfessionalShowcase> saveShowcase(
    ProfessionalShowcase profile,
  ) async {
    if (failShowcaseSave) {
      throw const AuthFailure('Enregistrement à réessayer.');
    }
    return showcase = profile;
  }
}

void main() {
  testWidgets(
    'approved professional edits the showcase and opens private account settings',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final photo = ShowcasePhoto(
        File('functions/test/fixtures/photo.png').readAsBytesSync(),
      );
      final pro = ShowcasePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
        showcase: ProfessionalShowcase(
          name: 'Atelier Test',
          trade: 'Menuiserie',
          portrait: photo,
          cover: photo,
          gallery: [photo],
        ),
      );
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
        await fixtures.tap(t, find.text('Mon profil professionnel'));
        expect(find.text('Atelier Test'), findsOneWidget);
        expect(find.text(auth.user!.email), findsNothing);
        expect(find.byType(Image), findsAtLeastNWidgets(3));
        await fixtures.tap(t, find.text('Modifier le profil'));
        final name = find.widgetWithText(TextFormField, 'Nom affiché');
        await t.enterText(name, 'Atelier Actualisé');
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        final private = find.text('Informations personnelles');
        final scrollable = find.byType(Scrollable).first;
        await t.scrollUntilVisible(private, 220, scrollable: scrollable);
        await t.pumpAndSettle();
        await fixtures.tap(t, private);
        expect(find.text('Tes informations'), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        final remove = find.byTooltip('Retirer la réalisation 1');
        await t.scrollUntilVisible(remove, -140, scrollable: scrollable);
        await t.pumpAndSettle();
        await fixtures.tap(t, remove);
        expect(find.byTooltip('Retirer la réalisation 1'), findsNothing);

        final save = find.text('Enregistrer');
        await t.scrollUntilVisible(save, 180, scrollable: scrollable);
        await t.pumpAndSettle();
        pro.failShowcaseSave = true;
        await fixtures.tap(t, save);
        expect(find.text('Enregistrement à réessayer.'), findsOneWidget);
        expect(pro.showcase!.name, 'Atelier Test');
        pro.failShowcaseSave = false;
        await fixtures.tap(t, save);
        expect(find.text('Atelier Actualisé'), findsOneWidget);
        expect(find.text('Aucune réalisation ajoutée.'), findsOneWidget);
        expect(pro.showcase!.portrait, same(photo));
        expect(pro.showcase!.cover, same(photo));
        expect(pro.showcase!.gallery, isEmpty);
      });
    },
  );

  testWidgets('client opens the read-only showcase from a received proposal', (
    t,
  ) async {
    final auth = fixtures.FakeAuth(
      user: const FoundiUser(
        id: 'client',
        email: 'client@example.test',
        emailVerified: true,
        hasPassword: true,
        hasGoogle: false,
        profile: fixtures.profile,
      ),
    );
    final pro = ShowcasePro(
      showcase: const ProfessionalShowcase(
        name: 'Atelier visible',
        trade: 'Menuiserie',
      ),
    );
    final requests = proposals.Proposals()
      ..items.add(proposals.request)
      ..sent.add(proposals.saved());
    try {
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.text('Voir les propositions reçues (1)'));
        await fixtures.tap(t, find.text(proposals.request.title));
        await fixtures.tap(t, find.text('Voir le profil professionnel'));
        expect(find.text('Atelier visible'), findsOneWidget);
        expect(find.text('Modifier le profil'), findsNothing);
        expect(find.text('Informations personnelles'), findsNothing);
        expect(pro.reads, [proposals.saved().id]);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('Détail de la proposition'), findsOneWidget);
      }, requests: requests);
    } finally {
      await requests.changes.close();
    }
  });
}
