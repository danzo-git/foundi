import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/presentation/personal_avatar.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/presentation/conversation_card.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/navigation/presentation/space_widgets.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';
import 'conversations_v8_test.dart' as fixtures;
import 'sprint25_test.dart' as capture;

Conversation chat({
  String id = 'CompactConversation00001',
  String name = 'DanzoCorp',
  String client = 'client',
  String professional = 'pro',
  String status = 'active',
  String proposalStatus = 'retained',
  String preview = 'test',
}) => Conversation(
  id: id,
  requestId: 'CompactRequestIdentifier1',
  selectedProposalId: 'a' * 64,
  clientUid: client,
  professionalUid: professional,
  clientName: 'Les délices de l’artisane',
  professionalName: name,
  requestTitle: 'Recherche pâtissière',
  status: status,
  proposalStatus: proposalStatus,
  updatedAt: DateTime(2026, 11, 4, 14, 30).millisecondsSinceEpoch,
  requestSnapshot: capture.request,
  lastMessagePreview: preview,
);

class PhotosRepository extends fixtures.Conversations
    implements ConversationAvatarRepository {
  bool unavailable = false;
  final calls = <List<String>>[];
  Future<Map<String, String>> Function(List<String>)? pendingPhotos;
  @override
  Future<Map<String, String>> resolveConversationAvatars(
    List<String> ids,
  ) async {
    calls.add(ids);
    if (unavailable) throw StateError('Photos unavailable');
    if (pendingPhotos != null) return pendingPhotos!(ids);
    return {
      for (final id in ids)
        id: id == 'CompactConversation00001' ? 'a' * 32 : 'b' * 32,
    };
  }
}

Widget list(
  ConversationRepository repository, {
  String uid = 'client',
  bool clients = false,
  ValueChanged<String>? onOpen,
}) => ConversationListView(
  repository: repository,
  uid: uid,
  canShowClients: true,
  initialProfessional: clients,
  onOpen: onOpen ?? (_) {},
  onExplore: () {},
);

void main() {
  setUpAll(() async {
    if (!capture.captureEnabled) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      final bytes = await File('C:/Windows/Fonts/$name').readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    }
  });
  test(
    'initials handle account names, accents, whitespace and emoji without splitting graphemes',
    () {
      expect(conversationInitials('  Les délices de l’artisane  '), 'LD');
      expect(conversationInitials('autolinkci'), 'A');
      expect(conversationInitials('Élodie Ndiaye'), 'ÉN');
      expect(conversationInitials('👩🏾‍🍳 Atelier'), '👩🏾‍🍳A');
      expect(conversationInitials('   '), '?');
    },
  );
  testWidgets(
    'compact cards show full names, context, preview, date and distinct retained/read-only statuses',
    (t) async {
      final active = chat(),
          closed = chat(
            id: 'CompactConversation00002',
            name: 'autolinkci',
            status: 'read_only',
            preview: 'ok pas de soucis !',
          );
      var opens = 0;
      await capture.page(
        t,
        ListView(
          padding: const EdgeInsets.all(22),
          children: [
            ConversationCard(
              conversation: active,
              viewerUid: 'client',
              onOpen: () => opens++,
            ),
            const SizedBox(height: 12),
            ConversationCard(
              conversation: closed,
              viewerUid: 'client',
              onOpen: () => opens++,
            ),
          ],
        ),
      );
      expect(find.text('Proposition retenue'), findsOneWidget);
      expect(find.text('Lecture seule'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('DanzoCorp')).dy,
        t.getTopLeft(find.text('4 nov.').first).dy,
      );
      final tag = find
          .ancestor(
            of: find.text('Lecture seule'),
            matching: find.byType(Container),
          )
          .first;
      expect(
        (t.widget<Container>(tag).decoration! as BoxDecoration).color,
        const Color(0xFFF0F3F1),
      );
      await t.tap(find.text('ok pas de soucis !'));
      await t.pumpAndSettle();
      expect(opens, 1);
      expect(t.takeException(), null);
    },
  );
  testWidgets(
    'photo resolution stays optional, both list roles open correct conversations',
    (t) async {
      final r = PhotosRepository();
      r.chats['CompactConversation00001'] = chat();
      r.chats['CompactConversation00002'] = chat(
        id: 'CompactConversation00002',
        client: 'other-client',
        professional: 'client',
      );
      String? opened;
      await capture.page(t, list(r, onOpen: (id) => opened = id));
      expect(
        t.widget<ConversationCard>(find.byType(ConversationCard)).avatarKey,
        'a' * 32,
      );
      await fixtures.tap(t, find.text('Mes réponses'));
      expect(
        t.widget<ConversationCard>(find.byType(ConversationCard)).avatarKey,
        'b' * 32,
      );
      expect(find.text('Les délices de l’artisane'), findsOneWidget);
      await fixtures.tap(t, find.text('Les délices de l’artisane'));
      expect(opened, 'CompactConversation00002');
      r.unavailable = true;
      await fixtures.tap(t, find.text('Mes recherches'));
      expect(find.text('DanzoCorp'), findsOneWidget);
      expect(
        t.widget<ConversationCard>(find.byType(ConversationCard)).avatarKey,
        null,
      );
      expect(find.text('D'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'late photo result from previous tab cannot replace the new correspondent',
    (t) async {
      final r = PhotosRepository(), old = Completer<Map<String, String>>();
      r.chats['CompactConversation00001'] = chat();
      r.chats['CompactConversation00002'] = chat(
        id: 'CompactConversation00002',
        client: 'other-client',
        professional: 'client',
      );
      r.pendingPhotos = (ids) async {
        if (ids.single == 'CompactConversation00001') return await old.future;
        return {ids.single: 'b' * 32};
      };
      await capture.page(t, list(r));
      expect(find.text('DanzoCorp'), findsOneWidget);
      await fixtures.tap(t, find.text('Mes réponses'));
      old.complete({'CompactConversation00001': 'a' * 32});
      await t.pumpAndSettle();
      expect(
        t.widget<ConversationCard>(find.byType(ConversationCard)).avatarKey,
        'b' * 32,
      );
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'switching account reloads the conversations instead of retaining another account list',
    (t) async {
      final r = PhotosRepository();
      r.chats['CompactConversation00001'] = chat();
      r.chats['CompactConversation00002'] = chat(
        id: 'CompactConversation00002',
        name: 'Atelier du second compte',
        client: 'second-account',
      );
      var uid = 'client';
      late StateSetter update;
      await capture.page(
        t,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return list(r, uid: uid);
          },
        ),
      );
      update(() => uid = 'second-account');
      await t.pumpAndSettle();
      expect(find.text('DanzoCorp'), findsNothing);
      expect(find.text('Atelier du second compte'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'profile photo replaces initials, and failure or revocation restores avatar',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await capture.bitmap());
      final versions = StreamController<String?>.broadcast();
      Widget card({bool fail = false}) => ConversationCard(
        conversation: chat(),
        viewerUid: 'client',
        onOpen: () {},
        profilePhoto: PersonalAvatar(
          key: ValueKey(fail),
          size: 46,
          versionStream: versions.stream,
          loadImage: (_) async {
            if (fail) throw StateError('offline');
            return bytes;
          },
          fallback: const CircleAvatar(radius: 23, child: Text('D')),
        ),
      );
      await capture.page(t, ListView(children: [card()]));
      versions.add('revision1');
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      await t.runAsync(()=>precacheImage(MemoryImage(bytes),t.element(find.byType(PersonalAvatar))));
      await t.pumpAndSettle();
      expect(t.getSize(find.byType(Image)), const Size(46, 46));
      expect(find.text('D'), findsNothing);
      versions.add(null);
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.text('D'), findsOneWidget);
      await capture.page(t, ListView(children: [card(fail: true)]));
      versions.add('revision2');
      await t.pumpAndSettle();
      expect(find.text('D'), findsOneWidget);
      expect(t.takeException(), null);
      await t.pumpWidget(const SizedBox());
      await versions.close();
    },
  );
  testWidgets('long names and large text stay readable on a 320px phone', (
    t,
  ) async {
    await capture.page(
      t,
      ListView(
        padding: const EdgeInsets.all(22),
        children: [
          ConversationCard(
            conversation: chat(
              name:
                  'Les délices de l’artisane — pâtisseries et créations sur commande',
              preview:
                  'Un long message pour confirmer tous les détails de la prestation sans déborder de la carte.',
            ),
            viewerUid: 'client',
            onOpen: () {},
          ),
        ],
      ),
      width: 320,
      scale: 1.8,
    );
    expect(t.takeException(), null);
    await capture.capture(t, 'messagerie-compacte-petit-ecran');
  });
  testWidgets(
    'capture compact messages with existing photo and initials fallback',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await capture.bitmap());
      await capture.page(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 16, 22, 0),
              child: RequestHeading('Messages', subtitle: 'Vos échanges'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Mes recherches'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      ChoiceChip(
                        label: const Text('Mes réponses'),
                        selected: false,
                        onSelected: (_) {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ConversationCard(
                    conversation: chat(),
                    viewerUid: 'client',
                    onOpen: () {},
                    profilePhoto: PersonalAvatar(
                      size: 46,
                      versionStream: Stream.value('fixture'),
                      loadImage: (_) async => bytes,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConversationCard(
                    conversation: chat(
                      id: 'CompactConversation00002',
                      name: 'autolinkci',
                      status: 'read_only',
                      preview: 'ok pas de soucis !',
                    ),
                    viewerUid: 'client',
                    onOpen: () {},
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Les 30 conversations les plus récentes.',
                    style: TextStyle(fontSize: 12, color: FoundiUi.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      await t.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          t.element(find.byType(PersonalAvatar).first),
        ),
      );
      await t.pumpAndSettle();
      await capture.capture(t, 'messagerie-cartes-compactes');
      expect(t.takeException(), null);
    },
  );
}
