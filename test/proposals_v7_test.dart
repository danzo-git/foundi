import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/proposals/presentation/proposal_views.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'requests_v5_test.dart' show FakeRequests;
import 'widget_test.dart' as fixtures;

const request = FoundiRequest(
  id: 'RequestIdentifier00001',
  title: 'Besoin de prestation',
  description: 'Une prestation de service.',
  categoryLabel: 'Services',
  specialtyLabel: 'Réparation',
  zoneLabel: 'Cocody',
  status: 'published',
  createdAt: null,
  proposalCount: 1,
);
Proposal saved({
  String description = 'Une solution professionnelle détaillée',
  int? amount = 25000,
  String delay = '2 jours',
}) => Proposal(
  id: 'a' * 64,
  requestId: request.id,
  requestTitle: request.title,
  professionalUid: 'pro',
  clientUid: 'client',
  professionalName: 'Atelier test',
  description: description,
  status: 'sent',
  createdAt: 123456,
  amount: amount,
  delay: delay,
);

class Proposals extends FakeRequests implements ProposalRepository {
  final sent = <Proposal>[];
  int accessCalls = 0, sendCalls = 0;
  ProposalDraft? lastDraft;
  bool fail = false, own = false, approved = true;
  Completer<void>? sending;
  @override
  Future<ProposalAccess> proposalAccess(String requestId) async {
    accessCalls++;
    if (own) {
      throw const AuthFailure('Tu ne peux pas répondre à ta propre demande.');
    }
    return ProposalAccess(sent.isEmpty, sent.isEmpty ? null : sent.first.id);
  }

  @override
  Future<Proposal> sendProposal(String requestId, ProposalDraft draft) async {
    sendCalls++;
    lastDraft = draft;
    if (sending != null) await sending!.future;
    if (fail) throw const AuthFailure('Envoi non confirmé. Réessaie.');
    final p = saved(
      description: draft.description,
      amount: draft.amount,
      delay: draft.delay,
    );
    sent.add(p);
    return p;
  }

  @override
  Stream<List<Proposal>> watchSentProposals(String uid) =>
      fail ? Stream.error(StateError('offline')) : Stream.value(sent);
  @override
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  }) => watchSentProposals(uid);
  @override
  Stream<Proposal?> watchProposal(String id) =>
      Stream.value(sent.where((p) => p.id == id).firstOrNull);
  @override
  Future<bool> proposalApproval(String id) async => approved;
}

Future<void> size(WidgetTester t) async {
  t.view.physicalSize = const Size(430, 1100);
  t.view.devicePixelRatio = 1;
}

Future<void> tap(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).first);
  await t.tap(find.text(text).first);
  await t.pumpAndSettle();
}

void reset(WidgetTester t) {
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

void main() {
  testWidgets(
    'compose validates amount, previews, confirms once and never succeeds after failed send',
    (t) async {
      await size(t);
      final repo = Proposals();
      var history = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalComposer(
              repository: repo,
              request: request,
              onBack: () {},
              onSent: () => history = true,
            ),
          ),
        ),
      );
      await tap(t, 'Prévisualiser ma proposition');
      expect(find.textContaining('10 caractères minimum'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('proposalDescription')),
        'Une proposition concrète et détaillée',
      );
      await t.enterText(find.byKey(const ValueKey('proposalAmount')), '0');
      await tap(t, 'Prévisualiser ma proposition');
      expect(find.textContaining('strictement positif'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('proposalAmount')), '25 000');
      await t.enterText(find.byKey(const ValueKey('proposalDelay')), '2 jours');
      await tap(t, 'Prévisualiser ma proposition');
      expect(repo.sendCalls, 0);
      expect(find.text('25 000 FCFA'), findsOneWidget);
      repo.fail = true;
      await tap(t, 'Confirmer et envoyer');
      expect(find.text('C’est envoyé !'), findsNothing);
      expect(find.text('Envoi non confirmé. Réessaie.'), findsOneWidget);
      repo.fail = false;
      repo.sending = Completer<void>();
      await t.tap(find.byKey(const ValueKey('sendProposal')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('sendProposal')));
      await t.pump();
      expect(repo.sendCalls, 2);
      repo.sending!.complete();
      await t.pumpAndSettle();
      expect(find.text('C’est envoyé !'), findsOneWidget);
      expect(repo.sent.length, 1);
      expect(repo.lastDraft?.amount, 25000);
      await tap(t, 'Voir mes propositions');
      expect(history, true);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
      reset(t);
    },
  );
  testWidgets(
    'approved professional in client space can send from Tout Explorer and reach own history',
    (t) async {
      await size(t);
      final repo = Proposals()..items.add(request);
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
      );
      await t.pumpWidget(
        FoundiApp(
          authRepository: auth,
          professionalRepository: pro,
          requestRepository: repo,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('nav-1')));
      await t.pumpAndSettle();
      await tap(t, request.title);
      await tap(t, 'Faire une proposition');
      await t.enterText(
        find.byKey(const ValueKey('proposalDescription')),
        'Une solution professionnelle sans coordonnées',
      );
      await tap(t, 'Prévisualiser ma proposition');
      await tap(t, 'Confirmer et envoyer');
      await tap(t, 'Voir mes propositions');
      expect(find.text('Mes propositions'), findsOneWidget);
      await tap(t, request.title);
      expect(find.text('Détail de la proposition'), findsOneWidget);
      expect(find.text('Professionnel actuellement approuvé'), findsOneWidget);
      expect(find.text('Accepter'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
      await auth.changes.close();
      await pro.changes.close();
      await pro.docChanges.close();
      reset(t);
    },
  );
  testWidgets(
    'author sees actual received count and reads private received detail without accepting',
    (t) async {
      await size(t);
      final repo = Proposals()
        ..items.add(request)
        ..sent.add(saved());
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro();
      await t.pumpWidget(
        FoundiApp(
          authRepository: auth,
          professionalRepository: pro,
          requestRepository: repo,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('nav-4')));
      await t.pumpAndSettle();
      await tap(t, 'Mes demandes');
      await tap(t, 'Voir les propositions reçues (1)');
      expect(find.text('Propositions reçues'), findsOneWidget);
      await tap(t, request.title);
      expect(find.text('Atelier test'), findsOneWidget);
      expect(
        find.text('Une solution professionnelle détaillée'),
        findsOneWidget,
      );
      expect(find.text('Accepter'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
      await auth.changes.close();
      await pro.changes.close();
      await pro.docChanges.close();
      reset(t);
    },
  );
  testWidgets('unapproved action and own request never expose sending CTA', (
    t,
  ) async {
    final repo = Proposals();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalAction(
            repository: repo,
            request: request,
            approved: false,
            onCompose: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.accessCalls, 0);
    expect(find.text('Accès professionnel requis'), findsOneWidget);
    expect(find.text('Faire une proposition'), findsNothing);
    repo.own = true;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalAction(
            repository: repo,
            request: request,
            approved: true,
            onCompose: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('propre demande'), findsOneWidget);
    expect(find.text('Faire une proposition'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await repo.changes.close();
  });
  testWidgets(
    'sent and received lists have empty and retry states and inactive approval is not a verified badge',
    (t) async {
      final repo = Proposals();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalListView(
              repository: repo,
              uid: 'pro',
              received: false,
              onOpen: (_) {},
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Aucune proposition envoyée'), findsOneWidget);
      repo.fail = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalListView(
              key: const ValueKey('received'),
              repository: repo,
              uid: 'client',
              received: true,
              onOpen: (_) {},
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Réessayer'), findsOneWidget);
      repo.fail = false;
      await tap(t, 'Réessayer');
      expect(find.text('Aucune proposition reçue'), findsOneWidget);
      repo.sent.add(saved());
      repo.approved = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalDetailView(
              repository: repo,
              id: repo.sent.first.id,
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Vérification professionnelle non active'),
        findsOneWidget,
      );
      expect(find.text('Professionnel actuellement approuvé'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );
}
