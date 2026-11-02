import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/conversations/presentation/proposal_negotiation.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/proposals/presentation/proposal_views.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'conversations_v8_test.dart' show Conversations, large, tap, reset;
import 'proposals_v7_test.dart' show request;

class Negotiation extends Conversations {
  Negotiation() {
    sent.addAll([offer, second]);
  }
  final states = <String, String>{};
  final links = <String, String>{};
  final decisions = <Map<String, dynamic>>[];
  bool failDecision = false;
  Completer<void>? deciding;
  Proposal get second => Proposal(
    id: 'b' * 64,
    requestId: request.id,
    requestTitle: request.title,
    professionalUid: 'other-pro',
    clientUid: me,
    professionalName: 'Garage Horizon',
    description: 'Une autre solution professionnelle.',
    status: 'sent',
    createdAt: 2,
  );
  Proposal current(Proposal p) => Proposal(
    id: p.id,
    requestId: p.requestId,
    requestTitle: p.requestTitle,
    professionalUid: p.professionalUid,
    clientUid: p.clientUid,
    professionalName: p.professionalName,
    description: p.description,
    status: states[p.id] ?? p.status,
    createdAt: p.createdAt,
    amount: p.amount,
    conversationId: links[p.id],
  );
  @override
  Stream<Proposal?> watchProposal(String id) =>
      watch(() => current(sent.firstWhere((p) => p.id == id)));
  @override
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  }) => watch(() => sent.map(current).toList());
  void refreshChat(String id) {
    final p = current(sent.firstWhere((p) => p.id == id));
    chats[id] = Conversation(
      id: id,
      requestId: request.id,
      selectedProposalId: id,
      clientUid: me,
      professionalUid: p.professionalUid,
      clientName: 'Client Foundi',
      professionalName: p.professionalName,
      requestTitle: request.title,
      status: p.status == 'rejected' ? 'read_only' : 'active',
      proposalStatus: p.status,
      archivedReason: p.status == 'rejected' ? 'proposal_rejected' : null,
      updatedAt: 3,
      requestSnapshot: ownedRequest,
    );
  }

  @override
  Future<SelectionResult> selectProposal(
    String requestId,
    String proposalId,
  ) async {
    final existed = links.containsKey(proposalId);
    links[proposalId] = proposalId;
    states.putIfAbsent(proposalId, () => 'discussing');
    refreshChat(proposalId);
    events.add(null);
    return SelectionResult(proposalId, existed);
  }

  @override
  Future<void> decideProposal(
    String requestId,
    String proposalId,
    String action, {
    required String decisionId,
    String? expectedRetainedProposalId,
    String reason = '',
  }) async {
    decisions.add({
      'id': decisionId,
      'action': action,
      'proposalId': proposalId,
      'expected': expectedRetainedProposalId,
      'reason': reason,
    });
    if (deciding != null) await deciding!.future;
    if (failDecision) {
      throw const AuthFailure('Décision non confirmée. Réessaie.');
    }
    if (action == 'retain' &&
        ownedRequest.retainedProposalId != null &&
        ownedRequest.retainedProposalId != proposalId) {
      final old = ownedRequest.retainedProposalId!;
      states[old] = links.containsKey(old) ? 'discussing' : 'sent';
      if (links.containsKey(old)) {
        refreshChat(old);
      }
    }
    states[proposalId] = action == 'retain' ? 'retained' : 'rejected';
    final retained = action == 'retain'
        ? proposalId
        : ownedRequest.retainedProposalId == proposalId
        ? null
        : ownedRequest.retainedProposalId;
    ownedRequest = FoundiRequest(
      id: request.id,
      title: request.title,
      description: request.description,
      categoryLabel: request.categoryLabel,
      specialtyLabel: request.specialtyLabel,
      zoneLabel: request.zoneLabel,
      status: 'published',
      createdAt: null,
      retainedProposalId: retained,
      retainedProfessionalName: retained == null
          ? null
          : sent.firstWhere((p) => p.id == retained).professionalName,
    );
    if (links.containsKey(proposalId)) refreshChat(proposalId);
    events.add(null);
  }
}

const captureKey = ValueKey('capture-v81');
Future<void> screen(WidgetTester t, Widget child) async {
  await t.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: Platform.environment['CAPTURE_V81_UI'] == '1'
              ? 'FoundiCapture'
              : null,
          scaffoldBackgroundColor: const Color(0xFFF6F9F7),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f6d)),
          useMaterial3: true,
        ),
        home: Scaffold(body: SafeArea(child: child)),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  if (Platform.environment['CAPTURE_V81_UI'] != '1') return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('docs/v81-captures');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['CAPTURE_V81_UI'] == '1') {
      await ui.loadFontFromList(
        await File(
          Platform.environment['CAPTURE_V81_FONT'] ??
              'C:/Windows/Fonts/segoeui.ttf',
        ).readAsBytes(),
        fontFamily: 'FoundiCapture',
      );
      await ui.loadFontFromList(
        await File(
          'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
        ).readAsBytes(),
        fontFamily: 'MaterialIcons',
      );
    }
  });
  testWidgets(
    'V8.1 multiple discussions, retained replacement names previous pro and cancellation preserves choice',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Negotiation();
      var selected = r.offer.id;
      Widget panel() => StreamBuilder<Proposal?>(
        stream: r.watchProposal(selected),
        builder: (_, s) => !s.hasData
            ? const SizedBox()
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(s.data!.professionalName),
                  Text(s.data!.statusLabel),
                  SelectionPanel(
                    key: ValueKey(selected),
                    repository: r,
                    proposals: r,
                    proposal: s.data!,
                    uid: r.me,
                    onOpen: (_) {},
                    onMine: () {},
                  ),
                ],
              ),
      );
      await screen(t, panel());
      await tap(t, find.text('Discuter avec ce professionnel'));
      expect(find.text('Ouvrir la discussion'), findsOneWidget);
      expect(r.ownedRequest.status, 'published');
      await tap(t, find.text('Retenir cette proposition'));
      await tap(t, find.text('Confirmer la retenue'));
      expect(r.states[r.offer.id], 'retained');
      expect(r.chats[r.offer.id]!.active, isTrue);
      selected = r.second.id;
      await screen(t, panel());
      await tap(t, find.text('Discuter avec ce professionnel'));
      expect(r.chats.length, 2);
      await tap(t, find.text('Retenir cette proposition'));
      expect(
        find.textContaining('Atelier choisi ne sera plus retenue'),
        findsOneWidget,
      );
      await tap(t, find.text('Annuler'));
      expect(r.ownedRequest.retainedProposalId, r.offer.id);
      await tap(t, find.text('Retenir cette proposition'));
      await tap(t, find.text('Confirmer le remplacement'));
      expect(r.states[r.offer.id], 'discussing');
      expect(r.states[r.second.id], 'retained');
      expect(r.decisions.last['expected'], r.offer.id);
      await screen(
        t,
        ProposalListView(
          repository: r,
          uid: r.me,
          received: true,
          onOpen: (_) {},
          onBack: () {},
        ),
      );
      expect(find.text('En discussion'), findsOneWidget);
      expect(find.text('Retenue'), findsOneWidget);
      await capture(t, '01-propositions');
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'V8.1 client decides from chat, refusal with optional reason archives only that conversation',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Negotiation();
      await r.selectProposal(request.id, r.offer.id);
      await r.selectProposal(request.id, r.second.id);
      await screen(
        t,
        ConversationView(
          repository: r,
          proposals: r,
          id: r.offer.id,
          uid: r.me,
          onBack: () {},
        ),
      );
      await capture(t, '02-discussion');
      await tap(t, find.text('Retenir ou refuser'));
      await tap(t, find.text('Refuser cette proposition'));
      await t.enterText(
        find.byKey(const ValueKey('rejectionReason')),
        'Autre solution adaptée',
      );
      await tap(t, find.text('Confirmer le refus'));
      expect(r.decisions.last['reason'], 'Autre solution adaptée');
      expect(r.chats[r.offer.id]!.active, isFalse);
      expect(r.chats[r.second.id]!.active, isTrue);
      Navigator.of(t.element(find.byType(ProposalDecisionPanel).last)).pop();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('messageText')), findsNothing);
      expect(find.text('Proposition refusée · Lecture seule'), findsOneWidget);
      await capture(t, '03-refus-archive');
      await screen(
        t,
        ConversationView(
          repository: r,
          proposals: r,
          key: ValueKey(r.second.id),
          id: r.second.id,
          uid: 'other-pro',
          onBack: () {},
        ),
      );
      expect(find.text('Retenir ou refuser'), findsNothing);
      expect(find.byKey(const ValueKey('messageText')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'V8.1 failed decisions retain retry ID, cancellation and repeated confirmation do not send twice',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Negotiation();
      await screen(
        t,
        ListView(
          children: [
            ProposalDecisionPanel(repository: r, proposal: r.offer, uid: r.me),
          ],
        ),
      );
      await tap(t, find.text('Retenir cette proposition'));
      await tap(t, find.text('Annuler'));
      expect(r.decisions, isEmpty);
      r.failDecision = true;
      await tap(t, find.text('Retenir cette proposition'));
      await tap(t, find.text('Confirmer la retenue'));
      expect(find.text('Décision non confirmée. Réessaie.'), findsOneWidget);
      expect(r.ownedRequest.retainedProposalId, isNull);
      r.failDecision = false;
      r.deciding = Completer<void>();
      await tap(t, find.text('Retenir cette proposition'));
      await t.tap(find.text('Confirmer la retenue'));
      await t.pump(const Duration(seconds: 1));
      await t.pump();
      expect(r.decisions.length, 2);
      expect(r.decisions[0]['id'], r.decisions[1]['id']);
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Retenir cette proposition'),
            )
            .onPressed,
        isNull,
      );
      r.deciding!.complete();
      await t.pumpAndSettle();
      expect(r.ownedRequest.retainedProposalId, r.offer.id);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
}
