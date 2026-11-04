import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/conversations/presentation/text_message_outbox.dart';
import 'conversations_v8_test.dart' show Conversations, large, reset;
import 'proposals_v7_test.dart' show request;

class HeldSend {
  HeldSend(this.id, this.text);
  final String id, text;
  final done = Completer<void>();
}

class ControlledChat extends Conversations {
  final calls = <HeldSend>[];
  bool initialSnapshot = true;
  final snapshots = StreamController<MessageBatch>.broadcast();
  @override
  Future<void> sendConversationMessage(
    String id,
    String messageId,
    String text,
  ) {
    final call = HeldSend(messageId, text);
    calls.add(call);
    return call.done.future;
  }

  @override
  Stream<MessageBatch> watchMessages(String id, {int limit = 30}) {
    limits.add(limit);
    return Stream.multi((sink) {
      if (initialSnapshot) sink.add(MessageBatch(messageRows.values.toList()));
      final sub = snapshots.stream.listen(sink.add, onError: sink.addError);
      sink.onCancel = sub.cancel;
    });
  }

  void commit(int index, {bool cache = false, bool pendingWrites = false}) {
    final call = calls[index];
    messageRows[call.id] = ConversationMessage(
      id: call.id,
      senderUid: me,
      text: call.text,
      createdAt: 100 + index,
    );
    snapshots.add(
      MessageBatch(
        messageRows.values.toList(),
        fromCache: cache,
        hasPendingWrites: pendingWrites,
      ),
    );
  }

  @override
  Future<void> close() async {
    await snapshots.close();
    await super.close();
  }
}

Future<void> open(
  WidgetTester t,
  ControlledChat r, {
  String? uid,
  String? id,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConversationView(
          repository: r,
          id: id ?? request.id,
          uid: uid ?? r.me,
          onBack: () {},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> send(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const ValueKey('messageText')), text);
  await t.tap(find.byKey(const ValueKey('sendMessage')));
  await t.pump(const Duration(milliseconds: 16));
}

void main() {
  Future<ControlledChat> setup(WidgetTester t) async {
    await large(t);
    final r = ControlledChat();
    r.chats[request.id] = r.makeChat();
    addTearDown(() async {
      await t.pumpWidget(const SizedBox());
      await r.close();
      reset(t);
    });
    return r;
  }

  testWidgets(
    'first frame before initial listener; rapid sends and double tap; ACK before snapshot',
    (t) async {
      final r = await setup(t);
      r.initialSnapshot = false;
      // A loading stream has an animated spinner, so do not pumpAndSettle yet.
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
      await t.pump();
      await send(t, 'Premier');
      expect(find.text('Premier'), findsOneWidget);
      expect(find.text('Envoi en cours'), findsOneWidget);
      expect(find.text('Envoyé'), findsNothing);
      await t.tap(find.byKey(const ValueKey('sendMessage')));
      await t.pump();
      expect(r.calls.length, 1);
      await send(t, 'Deuxième');
      expect(r.calls.length, 2);
      expect(find.text('Envoi en cours'), findsNWidgets(2));
      // Reply out of order: each completion updates only its own bubble.
      r.calls[1].done.complete();
      await t.pumpAndSettle();
      expect(find.text('Envoi en cours'), findsOneWidget);
      expect(find.text('Envoyé'), findsOneWidget);
      r.calls[0].done.complete();
      await t.pumpAndSettle();
      expect(find.text('Envoyé'), findsNWidgets(2));
      r.commit(0);
      r.commit(1);
      await t.pumpAndSettle();
      expect(find.text('Premier'), findsOneWidget);
      expect(find.text('Deuxième'), findsOneWidget);
      expect(r.limits, [30]); // No resubscription on each local state change.
      expect(
        TextMessageOutbox.forConversation(r, r.me, request.id).items,
        isEmpty,
      );
    },
  );

  testWidgets(
    'authoritative snapshot confirms commit even when callable response is lost',
    (t) async {
      final r = await setup(t);
      await open(t, r);
      await send(t, 'Accusé perdu');
      r.commit(0);
      await t.pumpAndSettle();
      expect(find.text('Envoyé'), findsOneWidget);
      r.calls[0].done.completeError(const AuthFailure('Réponse perdue'));
      await t.pumpAndSettle();
      expect(find.text('Accusé perdu'), findsOneWidget);
      expect(find.text('Échec de l’envoi'), findsNothing);
      expect(find.text('Envoyé'), findsOneWidget);
    },
  );

  testWidgets(
    'offline failure retains bubble; cached snapshot is not ACK; retry is idempotent',
    (t) async {
      final r = await setup(t);
      await open(t, r);
      await send(t, 'Réseau indisponible');
      r.commit(0, cache: true);
      await t.pumpAndSettle();
      expect(find.text('Envoi en cours'), findsOneWidget);
      expect(find.text('Envoyé'), findsNothing);
      r.calls[0].done.completeError(const AuthFailure('Hors ligne'));
      await t.pumpAndSettle();
      expect(find.text('Échec de l’envoi'), findsOneWidget);
      expect(find.text('Réseau indisponible'), findsOneWidget);
      final retry = t
          .widget<TextButton>(find.byKey(ValueKey('retry-${r.calls.first.id}')))
          .onPressed!;
      retry();
      retry();
      await t.pumpAndSettle();
      expect(r.calls.length, 2);
      expect(r.calls[0].id, r.calls[1].id);
      expect(r.calls[0].text, r.calls[1].text);
      expect(find.text('Envoi en cours'), findsOneWidget);
      r.calls[1].done.complete();
      r.commit(1);
      await t.pumpAndSettle();
      expect(r.messageRows.length, 1);
      expect(find.text('Réseau indisponible'), findsOneWidget);
      expect(find.text('Envoyé'), findsOneWidget);
    },
  );

  testWidgets(
    'pending Firestore metadata cannot confirm; later server event heals failed send',
    (t) async {
      final r = await setup(t);
      await open(t, r);
      await send(t, 'Confirmation tardive');
      r.commit(0, pendingWrites: true);
      await t.pumpAndSettle();
      expect(find.text('Envoi en cours'), findsOneWidget);
      r.calls[0].done.completeError(const AuthFailure('Délai dépassé'));
      await t.pumpAndSettle();
      expect(find.text('Échec de l’envoi'), findsOneWidget);
      r.commit(0);
      await t.pumpAndSettle();
      expect(find.text('Envoyé'), findsOneWidget);
      expect(find.text('Confirmation tardive'), findsOneWidget);
    },
  );

  testWidgets(
    'leaving and reopening retains pending operation and failed retry ID',
    (t) async {
      final r = await setup(t);
      await open(t, r);
      await send(t, 'Retour au chat');
      await t.pumpWidget(const SizedBox());
      r.calls[0].done.completeError(const AuthFailure('Hors ligne'));
      await t.pump();
      await open(t, r);
      expect(find.text('Retour au chat'), findsOneWidget);
      expect(find.text('Échec de l’envoi'), findsOneWidget);
      await t.tap(find.byKey(ValueKey('retry-${r.calls.first.id}')));
      await t.pump();
      expect(r.calls[0].id, r.calls[1].id);
      r.calls[1].done.complete();
      await t.pumpAndSettle();
      expect(find.text('Envoyé'), findsOneWidget);
    },
  );

  testWidgets(
    'listener failure leaves local bubble; listener retry does not resend',
    (t) async {
      final r = await setup(t);
      await open(t, r);
      await send(t, 'Toujours visible');
      r.snapshots.addError(StateError('Network unavailable'));
      await t.pumpAndSettle();
      expect(find.text('Toujours visible'), findsOneWidget);
      expect(find.text('Envoi en cours'), findsOneWidget);
      await t.tap(find.text('Réessayer les messages'));
      await t.pumpAndSettle();
      expect(r.calls.length, 1);
      r.calls[0].done.complete();
      r.commit(0);
      await t.pumpAndSettle();
      expect(find.text('Toujours visible'), findsOneWidget);
    },
  );

  testWidgets(
    'server refusal never shows sent; read-only removes retry and preserves failed draft',
    (t) async {
      final r = await setup(t);
      await open(t, r);
      await send(t, 'Refus serveur');
      r.calls[0].done.completeError(const AuthFailure('Accès refusé'));
      await t.pumpAndSettle();
      expect(find.text('Échec de l’envoi'), findsOneWidget);
      expect(find.text('Envoyé'), findsNothing);
      r.chats[request.id] = r.makeChat(status: 'read_only');
      r.events.add(null);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('messageText')), findsNothing);
      expect(find.byKey(ValueKey('retry-${r.calls.first.id}')), findsNothing);
      expect(find.text('Refus serveur'), findsOneWidget);
    },
  );

  testWidgets('changing account and chat cannot expose another local outbox', (
    t,
  ) async {
    final r = await setup(t);
    await open(t, r);
    await send(t, 'Brouillon privé');
    const other = 'RequestIdentifier00002';
    r.chats[other] = r.makeChat(id: other, clientUid: 'another-client');
    await open(t, r, id: other, uid: 'another-client');
    expect(find.text('Brouillon privé'), findsNothing);
    r.calls[0].done.completeError(const AuthFailure('Échec'));
    await t.pumpAndSettle();
    expect(find.text('Brouillon privé'), findsNothing);
    await open(t, r);
    expect(find.text('Brouillon privé'), findsOneWidget);
    expect(find.text('Échec de l’envoi'), findsOneWidget);
  });
}
