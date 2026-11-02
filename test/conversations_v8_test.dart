import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'proposals_v7_test.dart' show Proposals, request;
import 'widget_test.dart' as fixtures;

class Conversations extends Proposals implements ConversationRepository {
  final events = StreamController<void>.broadcast();
  final chats = <String, Conversation>{};
  final messageRows = <String, ConversationMessage>{};
  final sendIds = <String>[];
  final limits = <int>[];
  String me = 'client';
  bool failSelection = false,
      failSend = false,
      commitThenFail = false,
      cached = false;
  int choices = 0, messageIds = 0;
  Completer<void>? selecting, sendingMessage;
  FoundiRequest ownedRequest = request;
  Proposal get offer => Proposal(
    id: 'a' * 64,
    requestId: request.id,
    requestTitle: request.title,
    professionalUid: 'professional',
    clientUid: me,
    professionalName: 'Atelier choisi',
    description: 'Une proposition pour votre demande.',
    status: 'sent',
    createdAt: 1,
    amount: 50000,
  );
  Conversation makeChat({
    String id = 'RequestIdentifier00001',
    String? clientUid,
    String? proUid,
    String status = 'active',
  }) => Conversation(
    id: id,
    requestId: id,
    selectedProposalId: offer.id,
    clientUid: clientUid ?? me,
    professionalUid: proUid ?? 'professional',
    clientName: 'Client Foundi',
    professionalName: 'Atelier choisi',
    requestTitle: request.title,
    status: status,
    updatedAt: 3,
    requestSnapshot: ownedRequest,
  );
  Stream<T> watch<T>(T Function() read) => Stream.multi((sink) {
    sink.add(read());
    final sub = events.stream.listen((_) => sink.add(read()));
    sink.onCancel = sub.cancel;
  });
  @override
  Future<SelectionResult> selectProposal(
    String requestId,
    String proposalId,
  ) async {
    choices++;
    if (selecting != null) await selecting!.future;
    if (failSelection) throw const AuthFailure('Choix non confirmé. Réessaie.');
    ownedRequest = FoundiRequest(
      id: request.id,
      title: request.title,
      description: request.description,
      categoryLabel: request.categoryLabel,
      specialtyLabel: request.specialtyLabel,
      zoneLabel: request.zoneLabel,
      status: 'published',
      createdAt: null,
      conversationId: request.id,
      selectedProposalId: offer.id,
      proposalCount: 1,
    );
    chats[request.id] = makeChat();
    items
      ..clear()
      ..add(ownedRequest);
    events.add(null);
    changes.add(null);
    return SelectionResult(request.id, false);
  }

  @override
  String newDecisionId(String requestId) => 'DecisionIdentifier${++messageIds}';
  @override
  Future<void> decideProposal(
    String requestId,
    String proposalId,
    String action, {
    required String decisionId,
    String? expectedRetainedProposalId,
    String reason = '',
  }) async {}

  @override
  Stream<FoundiRequest?> watchOwnSelection(String uid, String requestId) =>
      watch(() => ownedRequest);
  @override
  Stream<List<Conversation>> watchConversations(
    String uid, {
    required bool asProfessional,
  }) => watch(
    () => chats.values
        .where(
          (c) => asProfessional ? c.professionalUid == uid : c.clientUid == uid,
        )
        .toList(),
  );
  @override
  Stream<Conversation?> watchConversation(String id) => watch(() => chats[id]);
  @override
  Stream<MessageBatch> watchMessages(String id, {int limit = 30}) {
    limits.add(limit);
    return watch(
      () => MessageBatch(
        messageRows.values.toList().reversed.take(limit).toList(),
        fromCache: cached,
      ),
    );
  }

  @override
  String newMessageId(String id) => 'MessageIdentifier${++messageIds}';
  @override
  Future<void> sendConversationMessage(
    String id,
    String messageId,
    String text,
  ) async {
    sendIds.add(messageId);
    if (sendingMessage != null) await sendingMessage!.future;
    if (commitThenFail || !failSend) {
      messageRows.putIfAbsent(
        messageId,
        () => ConversationMessage(
          id: messageId,
          senderUid: me,
          text: text,
          createdAt: messageRows.length + 10,
        ),
      );
      events.add(null);
    }
    if (failSend || commitThenFail) {
      throw const AuthFailure('Envoi non confirmé. Réessaie.');
    }
  }

  Future<void> close() async {
    await events.close();
    await changes.close();
  }
}

Future<void> large(WidgetTester t) async {
  t.view.physicalSize = const Size(430, 1150);
  t.view.devicePixelRatio = 1;
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void reset(WidgetTester t) {
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
}

void main() {
  testWidgets('small phone keyboard leaves the text composer usable', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(() {
      t.view.resetViewInsets();
      reset(t);
    });
    final r = Conversations();
    r.chats[request.id] = r.makeChat();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationView(
            repository: r,
            id: request.id,
            uid: r.me,
            onBack: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('messageText')),
      'Bonjour sur téléphone',
    );
    await tap(t, find.byKey(const ValueKey('sendMessage')));
    expect(t.takeException(), isNull);
    expect(r.messageRows.length, 1);
    await t.pumpWidget(const SizedBox());
    await r.close();
  });

  testWidgets(
    'author confirms selection then opens discussion and Messages without losing history',
    (t) async {
      await large(t);
      final r = Conversations(),
          auth = fixtures.FakeAuth(user: fixtures.account()),
          pro = fixtures.FakePro();
      r.me = auth.currentUser!.id;
      r.items.add(request);
      r.sent.add(r.offer);
      await t.pumpWidget(
        FoundiApp(
          authRepository: auth,
          professionalRepository: pro,
          requestRepository: r,
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('nav-4')));
      await tap(t, find.text('Mes demandes'));
      await tap(t, find.text('Voir les propositions reçues (1)'));
      await tap(t, find.text(request.title));
      r.failSelection = true;
      await tap(
        t,
        find.widgetWithText(FilledButton, 'Discuter avec ce professionnel'),
      );
      expect(find.text('Choix non confirmé. Réessaie.'), findsOneWidget);
      r.failSelection = false;
      await tap(
        t,
        find.widgetWithText(FilledButton, 'Discuter avec ce professionnel'),
      );
      expect(r.ownedRequest.status, 'published');
      await t.enterText(
        find.byKey(const ValueKey('messageText')),
        'Bonjour depuis le client',
      );
      await tap(t, find.byKey(const ValueKey('sendMessage')));
      expect(find.text('Bonjour depuis le client'), findsOneWidget);
      r.messageRows['reply'] = const ConversationMessage(
        id: 'reply',
        senderUid: 'professional',
        text: 'Bonjour depuis le professionnel',
        createdAt: 50,
      );
      r.events.add(null);
      await t.pumpAndSettle();
      expect(find.text('Bonjour depuis le professionnel'), findsOneWidget);
      await tap(t, find.byKey(const ValueKey('nav-3')));
      expect(find.text('Vos échanges'), findsOneWidget);
      expect(find.text('Mes clients'), findsNothing);
      await tap(t, find.text('Atelier choisi'));
      expect(find.text('Bonjour depuis le client'), findsOneWidget);
      await tap(t, find.text('Voir la demande liée'));
      expect(find.text(request.description), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
      await auth.changes.close();
      await pro.changes.close();
      await pro.docChanges.close();
      reset(t);
    },
  );
  testWidgets(
    'empty context and dual role list use Mes recherches and Mes clients',
    (t) async {
      await large(t);
      final r = Conversations();
      String? opened;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationListView(
              repository: r,
              uid: r.me,
              canShowClients: true,
              onOpen: (id) => opened = id,
              onExplore: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Aucune conversation'), findsOneWidget);
      r.chats['RequestIdentifier00001'] = r.makeChat();
      r.chats['RequestIdentifier00002'] = r.makeChat(
        id: 'RequestIdentifier00002',
        clientUid: 'another-client',
        proUid: r.me,
      );
      r.events.add(null);
      await t.pumpAndSettle();
      expect(find.text('Atelier choisi'), findsOneWidget);
      await tap(t, find.text('Mes clients'));
      expect(find.text('Client Foundi'), findsOneWidget);
      await tap(t, find.text('Client Foundi'));
      expect(opened, 'RequestIdentifier00002');
      await t.pumpWidget(const SizedBox());
      await r.close();
      reset(t);
    },
  );
  testWidgets(
    'lost response retries same message ID, no fake local success, repeated tap and read-only state',
    (t) async {
      await large(t);
      final r = Conversations();
      r.chats[request.id] = r.makeChat();
      r.cached = true;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationView(
              repository: r,
              id: request.id,
              uid: r.me,
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Historique local — connexion en cours…'),
        findsOneWidget,
      );
      await tap(t, find.byKey(const ValueKey('sendMessage')));
      expect(
        find.text('Écris un message de 1 à 2000 caractères.'),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const ValueKey('messageText')),
        'Message fiable',
      );
      r.failSend = true;
      await tap(t, find.byKey(const ValueKey('sendMessage')));
      expect(find.text('Envoi non confirmé. Réessaie.'), findsOneWidget);
      expect(r.messageRows, isEmpty);
      r.failSend = false;
      r.commitThenFail = true;
      await tap(t, find.byKey(const ValueKey('sendMessage')));
      expect(r.messageRows.length, 1);
      expect(find.text('Envoi non confirmé. Réessaie.'), findsOneWidget);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('messageText')))
            .controller!
            .text,
        'Message fiable',
      );
      r.commitThenFail = false;
      r.sendingMessage = Completer<void>();
      await t.tap(find.byKey(const ValueKey('sendMessage')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('sendMessage')));
      await t.pump();
      expect(r.sendIds.length, 3);
      expect(r.sendIds.toSet().length, 1);
      expect(r.sendIds.first, r.sendIds.last);
      r.sendingMessage!.complete();
      await t.pumpAndSettle();
      expect(r.messageRows.length, 1);
      r.chats[request.id] = r.makeChat(status: 'read_only');
      r.events.add(null);
      await t.pumpAndSettle();
      expect(find.text('Discussion en lecture seule'), findsOneWidget);
      expect(find.byKey(const ValueKey('messageText')), findsNothing);
      expect(find.text('Message fiable'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
      reset(t);
    },
  );
  testWidgets(
    'message history grows with a bounded query and a selected proposal reopens its conversation',
    (t) async {
      await large(t);
      final r = Conversations();
      r.chats[request.id] = r.makeChat();
      for (var i = 0; i < 100; i++) {
        r.messageRows['$i'] = ConversationMessage(
          id: '$i',
          senderUid: r.me,
          text: 'Texte $i',
          createdAt: i,
        );
      }
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationView(
              repository: r,
              id: request.id,
              uid: r.me,
              onBack: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        final old = find.text('Charger les anciens messages');
        await t.scrollUntilVisible(
          old,
          400,
          scrollable: find
              .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tap(t, old);
      }
      expect(r.limits, [30, 60, 90, 100]);
      expect(find.text('Charger les anciens messages'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await r.close();
      reset(t);
    },
  );
}
