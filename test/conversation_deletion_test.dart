import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/data/conversation_visibility.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'conversation_cards_test.dart' as cards;
import 'conversations_v8_test.dart' as fixtures;
import 'sprint25_test.dart' as capture;

class DeletableConversations extends cards.PhotosRepository
    implements ConversationDeletionRepository {
  final removed = <String, Set<String>>{};
  final deletions = <String>[];
  bool failDeletion = false;
  Completer<void>? deleting;
  @override
  Stream<List<Conversation>> watchConversations(
    String uid, {
    required bool asProfessional,
  }) => watch(
    () => chats.values
        .where(
          (c) =>
              (asProfessional
                  ? c.professionalUid == uid
                  : c.clientUid == uid) &&
              !(removed[uid]?.contains(c.id) ?? false),
        )
        .toList(),
  );
  @override
  Future<void> deleteConversation(
    String id, {
    required String viewerUid,
  }) async {
    deletions.add(id);
    if (deleting != null) await deleting!.future;
    if (failDeletion) {
      throw const AuthFailure('Suppression non confirmée. Réessaie.');
    }
    (removed[viewerUid] ??= <String>{}).add(id);
    events.add(null);
  }
}

Widget view(
  ConversationRepository r, {
  String uid = 'client',
  bool clients = false,
}) => ConversationListView(
  repository: r,
  uid: uid,
  canShowClients: true,
  initialProfessional: clients,
  onOpen: (_) {},
  onExplore: () {},
);
Future<void> chooseDeletion(WidgetTester t) async {
  await t.longPress(find.text('DanzoCorp'));
  await t.pumpAndSettle();
  await fixtures.tap(t, find.byKey(const ValueKey('deleteConversationAction')));
}

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
    'pagination fills thirty visible conversations even when more than thirty recent ones were deleted',
    () async {
      final all = List.generate(110, (i) => 'c$i');
      var pages = 0;
      final visible = await loadVisibleConversationRows<String>(
        firstPage: all.take(30).toList(),
        idOf: (id) => id,
        isCurrent: () => true,
        deletedIds: (ids) async =>
            ids.where((id) => int.parse(id.substring(1)) < 70).toSet(),
        nextPage: (last) async {
          pages++;
          return all.skip(all.indexOf(last) + 1).take(30).toList();
        },
      );
      expect(visible, List.generate(30, (i) => 'c${i + 70}'));
      expect(pages, 3);
    },
  );
  test(
    'a stale inbox load stops before returning data for a previous account or role',
    () async {
      var current = true;
      final pending = Completer<Set<String>>();
      final result = loadVisibleConversationRows<String>(
        firstPage: ['private'],
        idOf: (id) => id,
        isCurrent: () => current,
        deletedIds: (_) async => pending.future,
        nextPage: (_) async => [],
      );
      current = false;
      pending.complete({});
      expect(await result, isEmpty);
    },
  );
  testWidgets(
    'long press offers deletion, confirmation explains personal scope and cancellation changes nothing',
    (t) async {
      final r = DeletableConversations();
      r.chats['CompactConversation00001'] = cards.chat();
      await capture.page(t, view(r));
      await t.longPress(find.text('DanzoCorp'));
      await t.pumpAndSettle();
      await capture.capture(t, 'messagerie-menu-suppression');
      await fixtures.tap(t, find.text('Annuler'));
      expect(r.deletions, isEmpty);
      await chooseDeletion(t);
      expect(
        find.textContaining('L’autre personne conserve son historique'),
        findsOneWidget,
      );
      expect(
        find.textContaining('La proposition reste retenue'),
        findsOneWidget,
      );
      await capture.capture(t, 'messagerie-confirmer-suppression');
      await fixtures.tap(t, find.text('Annuler'));
      expect(find.text('DanzoCorp'), findsOneWidget);
      expect(r.deletions, isEmpty);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  for (final professional in [false, true]) {
    testWidgets(
      '${professional ? 'professional' : 'client'} removes own conversation only after server confirmation',
      (t) async {
        final r = DeletableConversations()..deleting = Completer<void>();
        r.chats['CompactConversation00001'] = cards.chat(
          client: professional ? 'other' : 'client',
          professional: professional ? 'client' : 'pro',
          name: professional ? 'Atelier' : 'DanzoCorp',
        );
        await capture.page(t, view(r, clients: professional));
        final name = professional ? 'Les délices de l’artisane' : 'DanzoCorp';
        await t.longPress(find.text(name));
        await t.pumpAndSettle();
        await fixtures.tap(
          t,
          find.byKey(const ValueKey('deleteConversationAction')),
        );
        await t.tap(find.byKey(const ValueKey('confirmDeleteConversation')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text(name), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        r.deleting!.complete();
        await t.pumpAndSettle();
        expect(find.text(name), findsNothing);
        expect(find.text('Aucune conversation'), findsOneWidget);
        expect(r.chats.length, 1);
        expect(r.removed['client'], {'CompactConversation00001'});
        r.events.add(null);
        await t.pumpAndSettle();
        expect(find.text(name), findsNothing);
        await t.pumpWidget(const SizedBox());
        await r.close();
      },
    );
  }
  testWidgets(
    'a failed deletion leaves the card available and can be retried',
    (t) async {
      final r = DeletableConversations()..failDeletion = true;
      r.chats['CompactConversation00001'] = cards.chat();
      await capture.page(t, view(r));
      await chooseDeletion(t);
      await fixtures.tap(
        t,
        find.byKey(const ValueKey('confirmDeleteConversation')),
      );
      expect(find.text('DanzoCorp'), findsOneWidget);
      expect(find.text('Suppression non confirmée. Réessaie.'), findsOneWidget);
      r.failDeletion = false;
      await chooseDeletion(t);
      await fixtures.tap(
        t,
        find.byKey(const ValueKey('confirmDeleteConversation')),
      );
      expect(find.text('DanzoCorp'), findsNothing);
      expect(r.deletions.length, 2);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'switching account while confirmation is open cannot delete for the new viewer',
    (t) async {
      final r = DeletableConversations();
      r.chats['CompactConversation00001'] = cards.chat();
      r.chats['CompactConversation00002'] = cards.chat(
        id: 'CompactConversation00002',
        client: 'second',
        name: 'Second account',
      );
      var uid = 'client';
      late StateSetter update;
      await capture.page(
        t,
        StatefulBuilder(
          builder: (context, set) {
            update = set;
            return view(r, uid: uid);
          },
        ),
      );
      await chooseDeletion(t);
      update(() => uid = 'second');
      await t.pumpAndSettle();
      await fixtures.tap(
        t,
        find.byKey(const ValueKey('confirmDeleteConversation')),
      );
      expect(r.deletions, isEmpty);
      expect(find.text('Second account'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'long press menu and confirmation stay usable with large text on a small phone',
    (t) async {
      final r = DeletableConversations();
      const name =
          'Les délices de l’artisane — pâtisseries et créations artisanales sur commande';
      r.chats['CompactConversation00001'] = cards.chat(name: name);
      await capture.page(t, view(r), width: 320, scale: 1.8);
      t.view.physicalSize = const Size(320, 568);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text(name));
      await t.longPress(find.text(name));
      await t.pumpAndSettle();
      await fixtures.tap(
        t,
        find.byKey(const ValueKey('deleteConversationAction')),
      );
      await t.ensureVisible(
        find.byKey(const ValueKey('confirmDeleteConversation')),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), null);
      await fixtures.tap(t, find.text('Annuler'));
      expect(r.deletions, isEmpty);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
}
