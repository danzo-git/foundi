import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'conversations_v8_test.dart' as fixtures;

class ControlledConversations extends fixtures.Conversations {
  final lists = <String, StreamController<List<Conversation>>>{};
  final details = <StreamController<Conversation?>>[];
  final batches = <StreamController<MessageBatch>>[];
  int canceledLists = 0, canceledDetails = 0, canceledMessages = 0;
  @override
  Stream<List<Conversation>> watchConversations(
    String uid, {
    required bool asProfessional,
  }) => (lists.putIfAbsent(
    '$uid:$asProfessional',
    () => StreamController<List<Conversation>>.broadcast(
      onCancel: () => canceledLists++,
    ),
  )).stream;
  @override
  Stream<Conversation?> watchConversation(String id) {
    final stream = StreamController<Conversation?>.broadcast(
      onCancel: () => canceledDetails++,
    );
    details.add(stream);
    return stream.stream;
  }

  @override
  Stream<MessageBatch> watchMessages(String id, {int limit = 30}) {
    final stream = StreamController<MessageBatch>.broadcast(
      onCancel: () => canceledMessages++,
    );
    batches.add(stream);
    return stream.stream;
  }

  @override
  Future<void> close() async {
    for (final stream in [...lists.values, ...details, ...batches]) {
      await stream.close();
    }
    await super.close();
  }
}

Widget list(
  ControlledConversations repository, {
  String uid = 'client',
  bool clients = false,
}) => ConversationListView(
  repository: repository,
  uid: uid,
  canShowClients: true,
  initialProfessional: clients,
  onOpen: (_) {},
  onExplore: () {},
);

Widget detail(ControlledConversations repository) => ConversationView(
  repository: repository,
  id: 'RequestIdentifier00001',
  uid: 'client',
  onBack: () {},
);

Future<void> page(WidgetTester t, Widget child) =>
    t.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets(
    'loaded history can recover after conversation error and re-listen its memoized messages stream',
    (t) async {
      final repository = ControlledConversations();
      await page(t, detail(repository));
      await t.pump();
      repository.details.single.add(repository.makeChat());
      await t.pump();
      await t.pump();
      final messages = repository.batches.single;
      messages.add(
        const MessageBatch([
          ConversationMessage(
            id: 'one',
            senderUid: 'professional',
            text: 'First load',
            createdAt: 1,
          ),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.text('First load'), findsOneWidget);
      repository.details.single.addError(StateError('visibility unavailable'));
      await t.pumpAndSettle();
      expect(find.text('First load'), findsNothing);
      expect(repository.canceledMessages, 1);
      repository.details.single.add(repository.makeChat());
      await t.pump();
      await t.pump();
      expect(repository.batches, hasLength(1));
      messages.add(
        const MessageBatch([
          ConversationMessage(
            id: 'two',
            senderUid: 'professional',
            text: 'Recovered load',
            createdAt: 2,
          ),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.text('Recovered load'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repository.canceledMessages, 2);
      await repository.close();
    },
  );

  testWidgets(
    'a silent conversation list offers retry after its deadline and recovers on reconnect',
    (t) async {
      final repository = ControlledConversations();
      await page(t, list(repository));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pump(const Duration(seconds: 13));
      await t.pump();
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      repository.lists['client:false']!.add([repository.makeChat()]);
      await t.pumpAndSettle();
      expect(find.text('Atelier choisi'), findsOneWidget);
      expect(find.text('Réessayer'), findsNothing);
      expect(repository.canceledLists, 0);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repository.canceledLists, 1);
      await repository.close();
    },
  );

  testWidgets(
    'silent detail has a retry path; an explicit unavailable result resolves without a spinner',
    (t) async {
      final repository = ControlledConversations();
      await page(t, detail(repository));
      await t.pump();
      await t.pump(const Duration(seconds: 13));
      await t.pump();
      expect(find.text('Réessayer'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.text('Réessayer'));
      await t.pump();
      expect(repository.details, hasLength(2));
      expect(repository.canceledDetails, 1);
      repository.details.last.add(null);
      await t.pumpAndSettle();
      expect(
        find.text('Cette discussion est privée ou indisponible.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repository.canceledDetails, 2);
      await repository.close();
    },
  );

  testWidgets(
    'silent messages offer a fresh subscription and ignore late results from the old attempt',
    (t) async {
      final repository = ControlledConversations();
      await page(t, detail(repository));
      await t.pump();
      repository.details.single.add(repository.makeChat());
      await t.pump();
      await t.pump();
      expect(repository.batches, hasLength(1));
      await t.pump(const Duration(seconds: 13));
      await t.pump();
      expect(find.text('Réessayer les messages'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.text('Réessayer les messages'));
      await t.pump();
      expect(repository.batches, hasLength(2));
      expect(repository.canceledMessages, 1);
      repository.batches.first.add(
        const MessageBatch([
          ConversationMessage(
            id: 'obsolete',
            senderUid: 'professional',
            text: 'Old attempt',
            createdAt: 1,
          ),
        ]),
      );
      repository.batches.last.add(
        const MessageBatch([
          ConversationMessage(
            id: 'current',
            senderUid: 'professional',
            text: 'Current attempt',
            createdAt: 2,
          ),
        ]),
      );
      await t.pumpAndSettle();
      expect(find.text('Old attempt'), findsNothing);
      expect(find.text('Current attempt'), findsOneWidget);
      expect(find.text('Réessayer les messages'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repository.canceledMessages, 2);
      expect(repository.canceledDetails, 1);
      await repository.close();
    },
  );

  testWidgets(
    'account changes cancel the old wait and cannot show previous user rows or timeout',
    (t) async {
      final repository = ControlledConversations();
      var uid = 'client';
      late StateSetter update;
      await page(
        t,
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return list(repository, uid: uid);
          },
        ),
      );
      await t.pump();
      update(() => uid = 'new-client');
      await t.pump();
      repository.lists['client:false']!.add([repository.makeChat()]);
      repository.lists['new-client:false']!.add([]);
      await t.pumpAndSettle();
      expect(find.text('Atelier choisi'), findsNothing);
      expect(repository.canceledLists, 1);
      await t.pump(const Duration(seconds: 13));
      await t.pump();
      expect(find.text('Réessayer'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      expect(repository.canceledLists, 2);
      await repository.close();
    },
  );
}
