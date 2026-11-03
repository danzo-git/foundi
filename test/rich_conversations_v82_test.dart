import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/conversations/domain/rich_conversation_repository.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/conversations/presentation/media_actions.dart';
import 'package:foundi/features/conversations/presentation/rich_message_widgets.dart';
import 'conversations_v8_test.dart' show Conversations, large, reset;
import 'proposals_v7_test.dart' show request;
import 'widget_test.dart' as fixtures;

final photo = File('functions/test/fixtures/photo.png').readAsBytesSync();
final pdf = File('functions/test/fixtures/document.pdf').readAsBytesSync();
Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

class Enriched extends Conversations implements RichConversationRepository {
  final uploads = <String>[],
      shares = <String>[],
      reads = <String>[],
      cancels = <String>[];
  final bytes = <String, Uint8List>{};
  bool failUpload = false,
      failCancel = false,
      denyRead = false,
      awaitingScan = false,
      contactFail = false,
      cancelReady = false,
      denyConversation = false;
  Completer<void>? transferring;
  @override
  Stream<Conversation?> watchConversation(String id) => denyConversation
      ? Stream.error(StateError('permission-denied'))
      : super.watchConversation(id);
  @override
  Future<String> sendAttachment(
    String conversationId,
    String messageId,
    AttachmentDraft draft, {
    required AttachmentCancellation cancellation,
    required void Function(double) onProgress,
  }) async {
    uploads.add(messageId);
    onProgress(.4);
    if (transferring != null) await transferring!.future;
    if (cancellation.requested) {
      return cancelAttachment(conversationId, messageId);
    }
    if (failUpload) throw const AuthFailure('Envoi non confirmé. Réessaie.');
    onProgress(1);
    if (awaitingScan) return 'awaiting_scan';
    bytes[messageId] = draft.bytes;
    messageRows.putIfAbsent(
      messageId,
      () => ConversationMessage(
        id: messageId,
        senderUid: me,
        createdAt: uploads.length + 10,
        type: draft.type,
        originalName: draft.originalName,
        sizeBytes: draft.bytes.length,
        contentType: draft.contentType,
        storagePath: 'private/$messageId',
      ),
    );
    events.add(null);
    return 'ready';
  }

  @override
  Future<String> cancelAttachment(
    String conversationId,
    String messageId,
  ) async {
    cancels.add(messageId);
    if (failCancel) throw const AuthFailure('Réseau indisponible');
    return cancelReady ? 'ready' : 'cancelled';
  }

  @override
  Future<Uint8List> readAttachment(
    String conversationId,
    String messageId,
  ) async {
    reads.add(messageId);
    if (denyRead) {
      throw const AuthFailure(
        'Fichier indisponible, hors ligne ou accès refusé.',
      );
    }
    return bytes[messageId]!;
  }

  @override
  Future<void> shareContact(
    String conversationId,
    String messageId,
    String phoneNumber,
  ) async {
    shares.add(phoneNumber);
    if (contactFail) throw const AuthFailure('Partage non confirmé. Réessaie.');
    messageRows[messageId] = ConversationMessage(
      id: messageId,
      senderUid: me,
      type: 'contact',
      phoneNumber: phoneNumber,
      createdAt: 10,
    );
    events.add(null);
  }
}

class Actions implements ConversationMediaActions {
  bool camera = true, failCall = false, failOpen = false;
  int pdfOpens = 0, picks = 0;
  final called = <String>[];
  AttachmentDraft? image = AttachmentDraft(
    bytes: photo,
    originalName: 'photo.png',
    type: 'image',
  );
  AttachmentDraft? document = AttachmentDraft(
    bytes: pdf,
    originalName: 'fiche.pdf',
    type: 'pdf',
  );
  @override
  bool get supportsCamera => camera;
  @override
  Future<AttachmentDraft?> pickImage({bool camera = false}) async {
    picks++;
    return image;
  }

  @override
  Future<AttachmentDraft?> pickPdf() async => document;
  @override
  Future<void> openPdf(String uid, Uint8List bytes, String name) async {
    if (failOpen) throw const AuthFailure('Ouverture PDF refusée.');
    pdfOpens++;
  }

  @override
  Future<void> callPhone(String number) async {
    if (failCall) {
      throw const AuthFailure(
        'Action Appeler indisponible. Tu peux copier le numéro.',
      );
    }
    called.add(number);
  }
}

const captureKey = ValueKey('capture-v82');
Future<void> screen(
  WidgetTester t,
  Enriched r,
  Actions actions, {
  bool linked = false,
  String phone = '',
}) async {
  r.chats.putIfAbsent(request.id, () => r.makeChat());
  await t.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF6F9F7),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF107865)),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF107865),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          fontFamily: Platform.environment['CAPTURE_V82_UI'] == '1'
              ? 'FoundiCapture'
              : null,
        ),
        home: Scaffold(
          body: ConversationView(
            key: ValueKey(r),
            repository: r,
            proposals: linked ? r : null,
            id: request.id,
            uid: r.me,
            ownPhone: phone,
            mediaActions: actions,
            onBack: () {},
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  if (Platform.environment['CAPTURE_V82_UI'] != '1') return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5),
        data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('docs/v82-captures').create(recursive: true);
    await File(
      'docs/v82-captures/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> close(WidgetTester t, Enriched r) async {
  await t.pumpWidget(const SizedBox());
  await r.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['CAPTURE_V82_UI'] == '1') {
      await ui.loadFontFromList(
        await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
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
  test(
    'legacy and discriminated messages, file bounds and formats remain compatible',
    () {
      expect(
        ConversationMessage.fromMap('old', {
          'senderUid': 'a',
          'text': 'Historique',
          'createdAt': 1,
        }).type,
        'text',
      );
      expect(
        ConversationMessage.fromMap('phone', {
          'senderUid': 'a',
          'type': 'contact',
          'phoneNumber': '+2250700000000',
          'createdAt': 1,
        }).phoneNumber,
        '+2250700000000',
      );
      for (final data in [
        () => AttachmentDraft(
          bytes: Uint8List(0),
          originalName: 'x.png',
          type: 'image',
        ),
        () =>
            AttachmentDraft(bytes: photo, originalName: 'a.zip', type: 'image'),
        () => AttachmentDraft(
          bytes: Uint8List(10 * 1048576 + 1),
          originalName: 'a.png',
          type: 'image',
        ),
        () => AttachmentDraft(
          bytes: Uint8List(15 * 1048576 + 1),
          originalName: 'a.pdf',
          type: 'pdf',
        ),
      ]) {
        expect(data, throwsA(isA<AuthFailure>()));
      }
    },
  );
  testWidgets(
    'contact is never automatic: exact own number, cancel, validation, confirmation, call and copy',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Enriched(), a = Actions();
      await screen(t, r, a, phone: '+2250100000000');
      await tap(t, find.byKey(const ValueKey('chatExtras')));
      await tap(t, find.text('Partager mon numéro'));
      expect(r.shares, isEmpty);
      expect(find.text('Numéro à partager : +2250100000000'), findsOneWidget);
      await tap(t, find.text('Annuler'));
      expect(r.shares, isEmpty);
      await tap(t, find.byKey(const ValueKey('chatExtras')));
      await tap(t, find.text('Partager mon numéro'));
      await t.enterText(find.byKey(const ValueKey('contactNumber')), '0700');
      await tap(t, find.text('Je confirme le partage'));
      expect(r.shares, isEmpty);
      await t.enterText(
        find.byKey(const ValueKey('contactNumber')),
        '+225 07 00 00 00 00',
      );
      await tap(t, find.text('Je confirme le partage'));
      expect(r.shares, ['+2250700000000']);
      expect(find.text('Contact partagé'), findsOneWidget);
      await tap(t, find.text('Appeler'));
      expect(a.called, ['+2250700000000']);
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tap(t, find.text('Copier'));
      expect(copied, '+2250700000000');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await capture(t, '01-contact');
      await close(t, r);
    },
  );
  testWidgets(
    'image preview sends only on confirmation; error and retry reuse ID, then private full screen',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Enriched(), a = Actions();
      await screen(t, r, a);
      await t.enterText(
        find.byKey(const ValueKey('messageText')),
        'Brouillon conservé',
      );
      await tap(t, find.byKey(const ValueKey('chatExtras')));
      await tap(t, find.text('Photo'));
      expect(r.uploads, isEmpty);
      expect(find.text('Prévisualiser la photo'), findsOneWidget);
      r.failUpload = true;
      await tap(t, find.text('Envoyer la photo'));
      expect(find.text('Envoi non confirmé. Réessaie.'), findsOneWidget);
      expect(r.messageRows, isEmpty);
      r.failUpload = false;
      await tap(t, find.text('Réessayer l’envoi'));
      expect(r.uploads.length, 2);
      expect(r.uploads[0], r.uploads[1]);
      expect(r.messageRows.length, 1);
      await t.runAsync(() async {
        await precacheImage(
          MemoryImage(photo),
          t.element(find.byType(Image).first),
        );
      });
      await t.pumpAndSettle();
      expect(t.widget<RawImage>(find.byType(RawImage).first).image, isNotNull);
      await t.tap(find.byType(Image).first);
      await t.pumpAndSettle();
      expect(find.byType(PrivateImageViewer), findsOneWidget);
      await tap(t, find.byTooltip('Fermer la photo'));
      await t.runAsync(() async {
        await precacheImage(
          MemoryImage(photo),
          t.element(find.byType(Image).first),
        );
      });
      await t.pumpAndSettle();
      expect(t.widget<RawImage>(find.byType(RawImage).first).image, isNotNull);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('messageText')))
            .controller!
            .text,
        'Brouillon conservé',
      );
      await capture(t, '02-photo');
      await close(t, r);
    },
  );
  testWidgets(
    'PDF name/size do not preload bytes; missing/denied file and external opening errors can retry',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Enriched(), a = Actions();
      r.messageRows['pdf'] = ConversationMessage(
        id: 'pdf',
        senderUid: 'pro',
        createdAt: 1,
        type: 'pdf',
        originalName: 'fiche.pdf',
        sizeBytes: pdf.length,
      );
      r.bytes['pdf'] = pdf;
      await screen(t, r, a);
      expect(r.reads, isEmpty);
      expect(find.text('fiche.pdf'), findsOneWidget);
      r.denyRead = true;
      await tap(t, find.text('Ouvrir le PDF'));
      expect(a.pdfOpens, 0);
      expect(find.textContaining('accès refusé'), findsOneWidget);
      r.denyRead = false;
      a.failOpen = true;
      await tap(t, find.text('Ouvrir le PDF'));
      expect(find.text('Ouverture PDF refusée.'), findsOneWidget);
      a.failOpen = false;
      await tap(t, find.text('Ouvrir le PDF'));
      expect(a.pdfOpens, 1);
      await capture(t, '03-pdf');
      await close(t, r);
    },
  );
  testWidgets(
    'quarantine is not sent, cancellation confirms server state and can exit without false success offline',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Enriched(), a = Actions();
      r.awaitingScan = true;
      await screen(t, r, a);
      await tap(t, find.byKey(const ValueKey('chatExtras')));
      await tap(t, find.text('Document PDF'));
      await tap(t, find.text('Envoyer le PDF'));
      expect(
        find.textContaining('aucun message n’a été envoyé'),
        findsOneWidget,
      );
      expect(r.messageRows, isEmpty);
      await capture(t, '04-quarantaine');
      r.failCancel = true;
      await tap(t, find.text('Annuler'));
      expect(find.textContaining('Annulation non confirmée'), findsOneWidget);
      await tap(t, find.text('Fermer sans confirmation'));
      await tap(t, find.text('Fermer cet envoi'));
      expect(find.byKey(const ValueKey('messageText')), findsOneWidget);
      expect(r.messageRows, isEmpty);
      await close(t, r);
    },
  );
  testWidgets(
    'upload progress disables duplicate sends and cancellation acknowledges a publication race',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      for (final alreadyReady in [false, true]) {
        final r = Enriched()..cancelReady = alreadyReady, a = Actions();
        final pending = Completer<void>();
        r.transferring = pending;
        await screen(t, r, a);
        await tap(t, find.byKey(const ValueKey('chatExtras')));
        await tap(t, find.text('Document PDF'));
        await tap(t, find.text('Envoyer le PDF'));
        expect(find.text('Envoi 40 %'), findsOneWidget);
        expect(
          t
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          .4,
        );
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Réessayer l’envoi'),
              )
              .onPressed,
          isNull,
        );
        expect(r.uploads, hasLength(1));
        expect(r.messageRows, isEmpty);
        await tap(t, find.text('Annuler'));
        expect(find.byType(AttachmentUploadSheet), findsNothing);
        expect(r.cancels, isNotEmpty);
        expect(
          find.text('Le fichier a déjà été envoyé.'),
          alreadyReady ? findsOneWidget : findsNothing,
        );
        pending.complete();
        await t.pumpAndSettle();
        await close(t, r);
      }
    },
  );
  testWidgets(
    'small phone keyboard, linked proposal detail and return preserve composer and history',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(() {
        t.view.resetViewInsets();
        reset(t);
      });
      final r = Enriched(), a = Actions();
      r.sent.add(r.offer);
      await screen(t, r, a, linked: true);
      await t.enterText(find.byKey(const ValueKey('messageText')), 'Brouillon');
      await tap(t, find.byTooltip('Voir la proposition'));
      expect(find.text(r.offer.description), findsOneWidget);
      await tap(t, find.text('Retour à la conversation'));
      expect(find.text('Détail de la proposition'), findsNothing);
      expect(t.takeException(), isNull);
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('messageText')))
            .controller!
            .text,
        'Brouillon',
      );
      expect(find.byKey(const ValueKey('chatExtras')), findsOneWidget);
      await close(t, r);
    },
  );
  testWidgets(
    'media loads lazily, read-only removes extras and unauthorized conversation never exposes controls',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Enriched(), a = Actions();
      for (var i = 0; i < 40; i++) {
        r.messageRows['image$i'] = ConversationMessage(
          id: 'image$i',
          senderUid: 'pro',
          createdAt: i,
          type: 'image',
        );
        r.bytes['image$i'] = photo;
      }
      await screen(t, r, a);
      expect(r.reads.length, lessThan(15));
      r.chats[request.id] = r.makeChat(status: 'read_only');
      r.events.add(null);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('chatExtras')), findsNothing);
      await close(t, r);
      final denied = Enriched()..denyConversation = true;
      await screen(t, denied, a);
      expect(
        find.text('Cette discussion est privée ou indisponible.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chatExtras')), findsNothing);
      await close(t, denied);
    },
  );
  testWidgets(
    'sign out closes private image routes and removes previous account media',
    (t) async {
      await large(t);
      addTearDown(() => reset(t));
      final r = Enriched(),
          auth = fixtures.FakeAuth(user: fixtures.account()),
          pro = fixtures.FakePro();
      r.me = auth.currentUser!.id;
      r.chats[request.id] = r.makeChat();
      r.messageRows['image'] = ConversationMessage(
        id: 'image',
        senderUid: r.me,
        createdAt: 1,
        type: 'image',
      );
      r.bytes['image'] = photo;
      await t.pumpWidget(
        FoundiApp(
          authRepository: auth,
          professionalRepository: pro,
          requestRepository: r,
        ),
      );
      await t.pumpAndSettle();
      await tap(t, find.byKey(const ValueKey('nav-3')));
      await tap(t, find.text('Atelier choisi'));
      await t.tap(find.byType(Image).first);
      await t.pumpAndSettle();
      expect(find.byType(PrivateImageViewer), findsOneWidget);
      await auth.signOut();
      await t.pumpAndSettle();
      expect(find.byType(PrivateImageViewer), findsNothing);
      expect(find.byType(Image), findsNothing);
      await close(t, r);
      await auth.changes.close();
      await pro.changes.close();
      await pro.docChanges.close();
    },
  );
}
