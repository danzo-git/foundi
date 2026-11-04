import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/notifications/domain/notification_repository.dart';
import 'package:foundi/features/notifications/presentation/notification_views.dart';
import 'package:foundi/features/notifications/presentation/conversation_read_tracker.dart';
import 'conversations_v8_test.dart' show Conversations, large, reset;
import 'notifications_v9_test.dart' show InboxFake, n;
import 'proposals_v7_test.dart' show request;
import 'widget_test.dart' as fixtures;
import 'optimistic_messages_v91_test.dart' show ControlledChat;
import 'package:foundi/features/conversations/presentation/conversation_views.dart';

class MessageInboxFake extends InboxFake implements MessageReadRepository {
  int messageCount = 5, subscriptions = 0;
  final counts = StreamController<int>.broadcast();
  final conversationReads = <(String, String)>[];
  Completer<void>? reading;
  @override
  Stream<int> watchUnreadMessages(String uid) {
    subscriptions++;
    return Stream.multi((sink) {
      sink.add(uid == 'other' ? 0 : messageCount);
      final sub = counts.stream.listen(sink.add);
      sink.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> markConversationRead(
    String conversationId,
    String messageId,
  ) async {
    conversationReads.add((conversationId, messageId));
    if (reading != null) await reading!.future;
    messageCount = 2;
    counts.add(messageCount);
  }

  @override
  Future<void> close() async {
    await counts.close();
    await super.close();
  }
}

void main() {
  testWidgets(
    'a pending read acknowledgement never delays the local sending bubble',
    (t) async {
      await large(t);
      final inbox = MessageInboxFake()..reading = Completer<void>();
      final chat = ControlledChat();
      chat.chats[request.id] = chat.makeChat();
      chat.messageRows['incoming'] = const ConversationMessage(
        id: 'incoming',
        senderUid: 'professional',
        createdAt: 1,
        text: 'Reçu',
      );
      final intent = ValueNotifier<NotificationIntent?>(null);
      await t.pumpWidget(
        NotificationScope(
          repository: inbox,
          intent: intent,
          child: MaterialApp(
            home: Scaffold(
              body: ConversationView(
                repository: chat,
                id: request.id,
                uid: chat.me,
                onBack: () {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(inbox.conversationReads.length, 1);
      await t.enterText(
        find.byKey(const ValueKey('messageText')),
        'Réponse immédiate',
      );
      await t.tap(find.byKey(const ValueKey('sendMessage')));
      await t.pump(const Duration(milliseconds: 16));
      expect(find.text('Réponse immédiate'), findsOneWidget);
      expect(find.text('Envoi en cours'), findsOneWidget);
      expect(inbox.reading!.isCompleted, isFalse);
      inbox.reading!.complete();
      chat.calls.single.done.complete();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await inbox.close();
      await chat.close();
      intent.dispose();
      reset(t);
    },
  );
  testWidgets(
    'Messages badge 5 and bell 2; opening Messages alone reads nothing; opening chat reads 3',
    (t) async {
      await large(t);
      final inbox = MessageInboxFake()..items = [n('p1'), n('p2')];
      final auth = fixtures.FakeAuth(user: fixtures.account()),
          pro = fixtures.FakePro();
      final chat = Conversations()..me = auth.currentUser!.id;
      chat.chats[request.id] = chat.makeChat();
      for (var i = 1; i <= 3; i++) {
        chat.messageRows['m$i'] = ConversationMessage(
          id: 'm$i',
          senderUid: 'professional',
          text: 'Entrant $i',
          createdAt: i,
        );
      }
      final intent = ValueNotifier<NotificationIntent?>(null);
      await t.pumpWidget(
        NotificationScope(
          repository: inbox,
          intent: intent,
          child: FoundiApp(
            authRepository: auth,
            professionalRepository: pro,
            requestRepository: chat,
          ),
        ),
      );
      await t.pumpAndSettle();
      Finder badgeText(String text) => find.descendant(
        of: find.byKey(const ValueKey('messageUnreadBadge')),
        matching: find.text(text),
      );
      expect(badgeText('5'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('notificationBell')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('nav-3')));
      await t.pumpAndSettle();
      expect(inbox.conversationReads, isEmpty);
      expect(badgeText('5'), findsOneWidget);
      await t.tap(find.text('Atelier choisi'));
      await t.pumpAndSettle();
      expect(inbox.conversationReads, [(request.id, 'm3')]);
      expect(badgeText('2'), findsOneWidget);
      expect(inbox.items.length, 2);
      expect(inbox.subscriptions, 1);
      inbox.messageCount = 120;
      inbox.counts.add(120);
      await t.pumpAndSettle();
      expect(badgeText('99+'), findsOneWidget);
      final semantics = t.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('120 messages non lus')),
        findsOneWidget,
      );
      semantics.dispose();
      await t.pumpWidget(const SizedBox());
      await inbox.close();
      await chat.close();
      await auth.changes.close();
      await pro.changes.close();
      await pro.docChanges.close();
      intent.dispose();
      reset(t);
    },
  );

  testWidgets('message badge is live and UID scoped, and absent at zero', (
    t,
  ) async {
    final inbox = MessageInboxFake();
    Future<void> show(String uid, bool selected) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageUnreadIcon(
              repository: inbox,
              uid: uid,
              selected: selected,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    await show('a', false);
    expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    await show('a', true);
    expect(inbox.subscriptions, 1);
    await show('other', true);
    expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await t.pumpWidget(const SizedBox());
    await inbox.close();
  });

  testWidgets(
    'general inbox ignores legacy private message types while retaining discussion business events',
    (t) async {
      final inbox = MessageInboxFake()
        ..items = [
          n('private', type: 'message.created', title: 'Texte privé'),
          n('legacy', type: 'chat_message', title: 'Ancien privé'),
          n(
            'business',
            type: 'conversation.opened',
            title: 'Discussion ouverte',
          ),
        ];
      await t.pumpWidget(
        MaterialApp(
          home: NotificationInbox(
            repository: inbox,
            uid: 'a',
            onOpen: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Texte privé'), findsNothing);
      expect(find.text('Ancien privé'), findsNothing);
      expect(find.text('Discussion ouverte'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await inbox.close();
    },
  );

  testWidgets(
    'preview defaults private and remains independent from receiving message pushes',
    (t) async {
      final inbox = MessageInboxFake();
      await t.pumpWidget(
        MaterialApp(
          home: NotificationSettings(repository: inbox, uid: 'a'),
        ),
      );
      await t.pumpAndSettle();
      final setting = find.widgetWithText(
        SwitchListTile,
        'Afficher l’aperçu des messages dans les notifications',
      );
      expect(t.widget<SwitchListTile>(setting).value, isFalse);
      await t.tap(setting);
      await t.pumpAndSettle();
      expect(inbox.preferences['messagePreview'], isTrue);
      expect(inbox.preferences['messages'], isTrue);
      await t.tap(find.widgetWithText(SwitchListTile, 'Messages'));
      await t.pumpAndSettle();
      expect(inbox.preferences['messages'], isFalse);
      expect(inbox.preferences['messagePreview'], isTrue);
      await t.pumpWidget(const SizedBox());
      await inbox.close();
    },
  );

  testWidgets(
    'read tracking requires a visible active resumed conversation at the newest messages',
    (t) async {
      final inbox = MessageInboxFake(), scroll = ScrollController();
      final batch = ValueNotifier(const MessageBatch(<ConversationMessage>[]));
      final navigator = GlobalKey<NavigatorState>(),
          intent = ValueNotifier<NotificationIntent?>(null);
      await t.pumpWidget(
        NotificationScope(
          repository: inbox,
          intent: intent,
          child: MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: ValueListenableBuilder<MessageBatch>(
                valueListenable: batch,
                builder: (context, b, _) => ConversationReadTracker(
                  conversationId: 'chat',
                  uid: 'a',
                  batch: b,
                  scroll: scroll,
                  active: true,
                  child: ListView(
                    controller: scroll,
                    reverse: true,
                    children: List.generate(
                      80,
                      (i) => SizedBox(height: 40, child: Text('Ligne $i')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      batch.value = const MessageBatch([
        ConversationMessage(id: 'm1', senderUid: 'b', createdAt: 1),
      ]);
      await t.pumpAndSettle();
      expect(inbox.conversationReads, isEmpty);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(inbox.conversationReads, [('chat', 'm1')]);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Autre écran')),
        ),
      );
      await t.pumpAndSettle();
      batch.value = const MessageBatch([
        ConversationMessage(id: 'm2', senderUid: 'b', createdAt: 2),
      ]);
      await t.pumpAndSettle();
      expect(inbox.conversationReads.length, 1);
      navigator.currentState!.pop();
      await t.pumpAndSettle();
      expect(inbox.conversationReads.last, ('chat', 'm2'));
      scroll.jumpTo(200);
      await t.pumpAndSettle();
      batch.value = const MessageBatch([
        ConversationMessage(id: 'm3', senderUid: 'b', createdAt: 3),
      ]);
      await t.pumpAndSettle();
      expect(inbox.conversationReads.length, 2);
      scroll.jumpTo(0);
      await t.pumpAndSettle();
      expect(inbox.conversationReads.last, ('chat', 'm3'));
      await t.pumpWidget(const SizedBox());
      scroll.dispose();
      batch.dispose();
      intent.dispose();
      await inbox.close();
    },
  );
}
