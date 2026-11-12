import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';

import 'proposals_v7_test.dart' as proposals;
import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as fixtures;

const published = FoundiRequest(
  id: 'RequestIdentifier00001',
  title: 'Réparer une fuite',
  description: 'Une fuite à réparer dans la cuisine.',
  categoryLabel: 'Services',
  specialtyLabel: 'Plomberie',
  zoneLabel: 'Cocody',
  status: 'published',
  createdAt: null,
  authorPublicName: 'Awa K.',
);
const legacy = FoundiRequest(
  id: 'RequestIdentifier00002',
  title: 'Ancienne demande',
  description: 'Un petit travail à réaliser.',
  categoryLabel: 'Services',
  specialtyLabel: '',
  zoneLabel: 'Cocody',
  status: 'published',
  createdAt: null,
);

class RespondentRequests extends proposals.Proposals
    implements
        RequestRespondentsRepository,
        RequestRespondentProfileRepository {
  RespondentRequests({this.owner = false});

  final bool owner;
  final offsets = <int>[];
  String? receivedRequest;
  final openedProfiles = <String>[];
  bool failProfile = false;

  @override
  Future<ProfessionalShowcase> readRequestRespondentProfile(
    String requestId,
    String professionalId,
  ) async {
    expect(requestId, published.id);
    openedProfiles.add(professionalId);
    if (failProfile) {
      throw const AuthFailure('Ce profil professionnel n’est plus disponible.');
    }
    return ProfessionalShowcase(
      name: professionalId == 'atelier-ebene'
          ? 'Atelier Ébène'
          : 'Atelier Acacia',
      trade: 'Plomberie',
      area: 'Cocody',
      bio: 'Dépannage et installation.',
    );
  }

  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) async {
    expect(requestId, published.id);
    offsets.add(offset);
    return RequestRespondentsPage(
      total: 2,
      items: [
        if (offset == 0)
          const RequestRespondent('Atelier Ébène', [
            'Plomberie',
          ], professionalId: 'atelier-ebene')
        else
          const RequestRespondent('Atelier Acacia', [
            'Entretien',
          ], professionalId: 'atelier-acacia'),
      ],
      canViewProposals: owner,
      nextOffset: offset == 0 ? 20 : null,
    );
  }

  @override
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  }) {
    receivedRequest = requestId;
    return super.watchReceivedProposals(uid, requestId: requestId);
  }
}

Finder get explorerList => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

void main() {
  testWidgets(
    'Explorer shows chosen names and opens only public respondent fields for visitors',
    (t) async {
      final repo = RespondentRequests()..items.addAll([published, legacy]);
      await requests.runFlow(t, repo, (_, _) async {
        t.view.physicalSize = const Size(320, 780);
        t.platformDispatcher.textScaleFactorTestValue = 1.7;
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text('Awa K.'),
          140,
          scrollable: explorerList,
        );
        expect(find.text(published.description), findsOneWidget);
        await t.scrollUntilVisible(
          find.text('Membre Foundi'),
          140,
          scrollable: explorerList,
        );
        await t.scrollUntilVisible(
          find.text(published.title),
          -140,
          scrollable: explorerList,
        );
        await requests.tapForm(t, find.text(published.title));
        expect(find.text('Réponses à la demande'), findsOneWidget);
        expect(find.text('2 professionnels ont répondu'), findsOneWidget);
        expect(find.text('Atelier Ébène'), findsOneWidget);
        expect(find.text('Voir mes propositions'), findsNothing);
        expect(find.text(published.description), findsNothing);
        await requests.tapForm(t, find.text('Voir plus de répondants'));
        expect(find.text('Atelier Acacia'), findsOneWidget);
        expect(repo.offsets, [0, 20]);
        await requests.tapForm(t, find.text('Atelier Acacia'));
        expect(find.text('Profil professionnel'), findsOneWidget);
        await t.scrollUntilVisible(
          find.text('Dépannage et installation.'),
          120,
          scrollable: explorerList,
        );
        expect(find.text('Dépannage et installation.'), findsOneWidget);
        expect(find.text('Modifier le profil'), findsNothing);
        expect(repo.openedProfiles, ['atelier-acacia']);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('2 professionnels ont répondu'), findsOneWidget);
        expect(find.text('Atelier Acacia'), findsOneWidget);
        expect(repo.offsets, [0, 20]);
        await requests.tapForm(t, find.text('Atelier Ébène'));
        expect(find.text('Profil professionnel'), findsOneWidget);
        expect(repo.openedProfiles, ['atelier-acacia', 'atelier-ebene']);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Réponses à la demande'), findsNothing);
        expect(find.text('2 professionnels ont répondu'), findsNothing);
        expect(t.takeException(), isNull);
      }, guest: true);
    },
  );

  testWidgets(
    'The request owner opens the existing received proposals route from respondents',
    (t) async {
      final repo = RespondentRequests(owner: true)
        ..items.add(published)
        ..sent.add(proposals.saved());
      await requests.runFlow(t, repo, (_, _) async {
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        await requests.tapForm(t, find.text(published.title));
        repo.failProfile = true;
        await requests.tapForm(t, find.text('Atelier Ébène'));
        expect(
          find.text('Ce profil professionnel n’est plus disponible.'),
          findsOneWidget,
        );
        repo.failProfile = false;
        await fixtures.tap(t, find.text('Réessayer'));
        expect(find.text('Dépannage et installation.'), findsOneWidget);
        expect(find.text('Modifier le profil'), findsNothing);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await requests.tapForm(t, find.text('Voir mes propositions'));
        expect(find.text('Propositions reçues'), findsOneWidget);
        expect(repo.receivedRequest, published.id);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Réponses à la demande'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'The composer previews the account name and sends no editable author identity',
    (t) async {
      final repo = RespondentRequests();
      await requests.runFlow(t, repo, (_, _) async {
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        await requests.fill(t, 'requestDescription', published.description);
        await requests.chooseReferences(t);
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Auteur affiché · Awa Kouassi'), findsOneWidget);
        expect(find.text('Auteur affiché · Awa K.'), findsNothing);
        await requests.tapForm(t, find.text('Publier ma demande'));
        expect(
          repo.publishedDraft!.toMap(),
          isNot(contains('authorPublicName')),
        );
      });
    },
  );

  testWidgets(
    'The account identity stays read-only when returning from review to change the request',
    (t) async {
      final repo = RespondentRequests();
      await requests.runFlow(t, repo, (_, _) async {
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        await requests.fill(t, 'requestDescription', published.description);
        expect(find.byKey(const ValueKey('requestAuthorName')), findsNothing);
        expect(find.text('Nom d’affichage public'), findsNothing);
        await requests.chooseReferences(t);
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Auteur affiché · Awa Kouassi'), findsOneWidget);
        await requests.tapForm(t, find.text('Modifier'));
        expect(find.byKey(const ValueKey('requestAuthorName')), findsNothing);
        await requests.fill(
          t,
          'requestDescription',
          'Une autre description publique à publier.',
        );
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Auteur affiché · Awa Kouassi'), findsOneWidget);
        await requests.tapForm(t, find.text('Publier ma demande'));
        expect(
          repo.publishedDraft!.toMap(),
          isNot(contains('authorPublicName')),
        );
      });
    },
  );
}
