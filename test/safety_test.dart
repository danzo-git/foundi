import 'dart:io';
import 'dart:async';
import 'package:foundi/app.dart';
import 'widget_test.dart' as auth_fixtures;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/safety/domain/safety_repository.dart';
import 'package:foundi/features/safety/presentation/safety_widgets.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'conversations_v8_test.dart' as chats;
import 'proposals_v7_test.dart' show request;
import 'public_professional_profile_test.dart' as profiles;
import 'package:foundi/features/professional/presentation/professional_showcase_screen.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';

const captures = bool.fromEnvironment('SAFETY_CAPTURE');

class DeniedAccountFake extends auth_fixtures.FakeAuth {
  DeniedAccountFake() : super(user: auth_fixtures.account());
  @override
  Stream<FoundiUser?> authStateChanges() =>
      Stream.error(const AuthFailure('Accès au compte refusé.'));
}

class DeniedProfessionalFake extends auth_fixtures.FakePro {
  @override
  Stream<ProfessionalProfile> watchProfile(String uid) =>
      Stream.error(const AuthFailure('Accès au dossier refusé.'));
}

class SafetyFake implements SafetyRepository {
  bool blockedUser = false, fail = false, own = false, reverse = false;
  final reports = <Map<String, dynamic>>[];
  final unblocked = <String>[];
  final noticeTexts = <String>[];
  final acknowledgedNotices = <String>{};
  bool failAcknowledgement = false;
  final acknowledgements = <String>[];
  @override
  Future<List<SafetyNotice>> notices() async {
    if (fail) throw const AuthFailure('Avis indisponibles. Réessaie.');
    return [
      for (final (i, text) in noticeTexts.indexed)
        SafetyNotice(
          id: 'notice_$i',
          text: text,
          acknowledgedAt: acknowledgedNotices.contains('notice_$i')
              ? DateTime(2026)
              : null,
        ),
    ];
  }

  @override
  Future<void> acknowledgeNotice(String id) async {
    acknowledgements.add(id);
    if (failAcknowledgement) {
      throw const AuthFailure('Fermeture impossible. Réessaie.');
    }
    acknowledgedNotices.add(id);
  }

  @override
  Future<SafetyContext> context(SafetyTarget target) async {
    if (fail) throw const AuthFailure('Connexion interrompue. Réessaie.');
    return SafetyContext(
      own: own,
      blocked: blockedUser,
      contactAllowed: !blockedUser && !reverse,
    );
  }

  @override
  Future<void> report(
    SafetyTarget target,
    String reason,
    String comment,
  ) async {
    if (fail) throw const AuthFailure('Signalement non envoyé. Réessaie.');
    reports.add({...target.toMap(), 'reason': reason, 'comment': comment});
  }

  @override
  Future<void> block(SafetyTarget target) async {
    if (fail) throw const AuthFailure('Blocage non confirmé.');
    blockedUser = true;
  }

  @override
  Future<void> unblockTarget(SafetyTarget target) async {
    blockedUser = false;
  }

  @override
  Future<void> unblock(String uid) async {
    if (fail) throw const AuthFailure('Déblocage non confirmé.');
    unblocked.add(uid);
    blockedUser = false;
  }

  @override
  Future<BlockedPage> blocked({String? cursor}) async {
    if (fail) throw const AuthFailure('Liste indisponible. Réessaie.');
    return BlockedPage(
      blockedUser
          ? [const BlockedUser('professional', 'Atelier de plomberie')]
          : [],
    );
  }
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captures) return;
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('safetyCapture')),
  );
  boundary.reassemble();
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('docs/sprint-1-securite-captures')
      ..createSync(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> app(
  WidgetTester t,
  SafetyFake repo,
  Widget body, {
  String? uid = 'client',
  double width = 430,
  double scale = 1,
  VoidCallback? authenticate,
}) async {
  // Use the application's real theme, including button size and input styles.
  final auth = auth_fixtures.FakeAuth();
  await t.pumpWidget(FoundiApp(authRepository: auth));
  await t.pumpAndSettle();
  final productionTheme = t
      .widget<MaterialApp>(find.byType(MaterialApp))
      .theme!;
  await t.pumpWidget(const SizedBox.shrink());
  await auth.changes.close();
  t.view.physicalSize = Size(width, 932);
  t.view.devicePixelRatio = 1;
  final revision = ValueNotifier<int>(0);
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    revision.dispose();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('safetyCapture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: productionTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: SafetyScope(
            repository: repo,
            uid: () => uid,
            onAuthenticate: authenticate ?? () {},
            revision: revision,
            child: child!,
          ),
        ),
        home: Scaffold(body: SafeArea(child: body)),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> chooseReason(WidgetTester t) async {
  await t.tap(find.byKey(const ValueKey('safetyReason')));
  await t.pumpAndSettle();
  await t.tap(find.text('Harcèlement / menaces').last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'SEC profile notices close durably by id, stay in history, and leave later notices visible',
    (t) async {
      final repo = SafetyFake()
        ..noticeTexts.addAll(['Premier avertissement.', 'Avis plus récent.']);
      await app(
        t,
        repo,
        SafetyNoticesPanel(repository: repo, showHistoryLink: true),
      );
      await t.tap(find.byKey(const ValueKey('acknowledge_notice_0')));
      await t.pumpAndSettle();
      expect(find.text('Premier avertissement.'), findsNothing);
      expect(find.text('Avis plus récent.'), findsOneWidget);
      expect(repo.acknowledgements, ['notice_0']);
      await t.pumpWidget(const SizedBox());
      await app(
        t,
        repo,
        SafetyNoticesPanel(repository: repo, showHistoryLink: true),
      );
      expect(find.text('Premier avertissement.'), findsNothing);
      await t.tap(find.text('Historique des avis'));
      await t.pumpAndSettle();
      expect(find.text('Premier avertissement.'), findsOneWidget);
      expect(find.text('Lecture confirmée'), findsOneWidget);
      await capture(t, '17-historique-avis-ferme');
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Premier avertissement.'), findsNothing);
      repo.noticeTexts.add('Nouvelle décision à consulter.');
      await t.pumpWidget(const SizedBox());
      await app(
        t,
        repo,
        SafetyNoticesPanel(repository: repo, showHistoryLink: true),
      );
      expect(find.text('Nouvelle décision à consulter.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'SEC a failed acknowledgement keeps the notice visible and retry closes it only after success',
    (t) async {
      final repo = SafetyFake()
        ..noticeTexts.add('Avertissement à lire.')
        ..failAcknowledgement = true;
      await app(
        t,
        repo,
        SafetyNoticesPanel(repository: repo, showHistoryLink: true),
      );
      await capture(t, '16-avis-fermeture');
      await t.tap(find.text('J’ai compris'));
      await t.pumpAndSettle();
      expect(find.text('Avertissement à lire.'), findsOneWidget);
      expect(find.text('Fermeture impossible. Réessaie.'), findsOneWidget);
      repo.failAcknowledgement = false;
      await t.tap(find.text('J’ai compris'));
      await t.pumpAndSettle();
      expect(find.text('Avertissement à lire.'), findsNothing);
      expect(find.text('Historique des avis'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  setUpAll(() async {
    if (!captures) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final font in ['segoeui.ttf', 'segoeuib.ttf']) {
      final bytes = await File('C:/Windows/Fonts/$font').readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  testWidgets(
    'SEC public request menu opens correct report, validates and confirms',
    (t) async {
      final repo = SafetyFake();
      await app(
        t,
        repo,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [RequestCard(request, showDescription: true)],
        ),
      );
      await t.tap(find.byTooltip('Signaler ou bloquer'));
      await t.pumpAndSettle();
      await capture(t, '01-menu-demande');
      await t.tap(find.text('Signaler la demande'));
      await t.pumpAndSettle();
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();
      expect(find.text('Choisis un motif.'), findsOneWidget);
      await chooseReason(t);
      await t.enterText(
        find.byKey(const ValueKey('safetyComment')),
        'Message menaçant reçu.',
      );
      await capture(t, '02-formulaire-signalement');
      await t.ensureVisible(find.text('Envoyer le signalement'));
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();
      expect(repo.reports.single['targetId'], request.id);
      expect(repo.reports.single['reason'], 'harassment');
      expect(find.textContaining('Signalement envoyé'), findsOneWidget);
    },
  );
  testWidgets(
    'SEC guest is invited to authenticate and own content menu is absent',
    (t) async {
      final repo = SafetyFake();
      var auth = 0;
      await app(
        t,
        repo,
        const SafetyActionMenu(
          target: SafetyTarget('professional', 'pro'),
          allowBlock: true,
        ),
        uid: null,
        authenticate: () => auth++,
      );
      await t.tap(find.byTooltip('Signaler ou bloquer'));
      await t.pumpAndSettle();
      await t.tap(find.text('Signaler le professionnel'));
      await t.pumpAndSettle();
      expect(auth, 1);
      expect(repo.reports, isEmpty);
    },
  );
  testWidgets(
    'SEC self report/block menu disappears after trusted ownership resolution',
    (t) async {
      await app(
        t,
        SafetyFake()..own = true,
        const SafetyActionMenu(
          target: SafetyTarget('professional', 'self'),
          allowBlock: true,
        ),
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    },
  );
  testWidgets('SEC report errors keep draft and retry submits once', (t) async {
    final repo = SafetyFake()..fail = true;
    await app(
      t,
      repo,
      Builder(
        builder: (c) => TextButton(
          onPressed: () => showSafetyReport(
            c,
            const SafetyTarget('message', 'message', conversationId: 'chat'),
          ),
          child: const Text('Signaler'),
        ),
      ),
    );
    await t.tap(find.text('Signaler'));
    await t.pumpAndSettle();
    await chooseReason(t);
    await t.enterText(
      find.byKey(const ValueKey('safetyComment')),
      'Conserver mon complément.',
    );
    await t.tap(find.text('Envoyer le signalement'));
    await t.pumpAndSettle();
    expect(find.text('Signalement non envoyé. Réessaie.'), findsOneWidget);
    expect(repo.reports, isEmpty);
    repo.fail = false;
    await t.tap(find.text('Envoyer le signalement'));
    await t.pumpAndSettle();
    expect(repo.reports.single['conversationId'], 'chat');
    expect(repo.reports.single['comment'], 'Conserver mon complément.');
  });
  testWidgets(
    'SEC blocked users list confirms unblock, updates state and preserves Back',
    (t) async {
      final repo = SafetyFake()..blockedUser = true;
      await app(
        t,
        repo,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.push(
              c,
              MaterialPageRoute<void>(
                builder: (_) => BlockedUsersScreen(repository: repo),
              ),
            ),
            child: const Text('Comptes bloqués'),
          ),
        ),
      );
      await t.tap(find.text('Comptes bloqués'));
      await t.pumpAndSettle();
      await capture(t, '03-comptes-bloques');
      await t.tap(find.text('Débloquer'));
      await t.pumpAndSettle();
      expect(repo.unblocked, isEmpty);
      await t.tap(find.text('Confirmer'));
      await t.pumpAndSettle();
      expect(repo.unblocked, ['professional']);
      expect(find.text('Aucun compte bloqué.'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Comptes bloqués'), findsOneWidget);
    },
  );
  testWidgets(
    'SEC block confirmation makes chat read-only while keeping message history',
    (t) async {
      final repo = SafetyFake(), chat = chats.Conversations();
      final conversation = chat.makeChat();
      chat.chats[conversation.id] = conversation;
      chat.messageRows['history'] = const ConversationMessage(
        id: 'history',
        senderUid: 'professional',
        text: 'Historique conservé',
        createdAt: 2,
      );
      addTearDown(chat.close);
      await app(
        t,
        repo,
        ConversationView(
          repository: chat,
          id: conversation.id,
          uid: 'client',
          onBack: () {},
        ),
      );
      expect(find.byKey(const ValueKey('sendMessage')), findsOneWidget);
      await t.tap(find.byTooltip('Signaler ou bloquer').first);
      await t.pumpAndSettle();
      await capture(t, '04-menu-conversation');
      await t.tap(find.text('Bloquer cet utilisateur'));
      await t.pumpAndSettle();
      expect(repo.blockedUser, false);
      await t.tap(find.text('Bloquer'));
      await t.pumpAndSettle();
      expect(repo.blockedUser, true);
      expect(find.byKey(const ValueKey('sendMessage')), findsNothing);
      expect(find.text('Historique conservé'), findsOneWidget);
      expect(find.textContaining('Utilisateur bloqué'), findsOneWidget);
      await capture(t, '05-conversation-bloquee');
    },
  );
  testWidgets(
    'SEC optimistic message rejected after block keeps the failed draft without a retry action',
    (t) async {
      final repo = SafetyFake(), chat = chats.Conversations();
      final c = chat.makeChat();
      chat.chats[c.id] = c;
      chat.failSend = true;
      chat.sendingMessage = Completer<void>();
      addTearDown(chat.close);
      await app(
        t,
        repo,
        ConversationView(
          repository: chat,
          id: c.id,
          uid: 'client',
          onBack: () {},
        ),
      );
      await t.enterText(
        find.byKey(const ValueKey('messageText')),
        'Brouillon à conserver.',
      );
      await t.tap(find.byKey(const ValueKey('sendMessage')));
      await t.pump();
      await t.tap(find.byTooltip('Signaler ou bloquer').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Bloquer cet utilisateur'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bloquer'));
      await t.pumpAndSettle();
      chat.sendingMessage!.complete();
      await t.pumpAndSettle();
      expect(find.text('Brouillon à conserver.'), findsOneWidget);
      expect(find.text('Échec de l’envoi'), findsOneWidget);
      expect(
        find.byKey(ValueKey('retry-${chat.sendIds.single}')),
        findsNothing,
      );
    },
  );
  testWidgets('SEC blocked public profile offers report and unblock', (
    t,
  ) async {
    final repo = SafetyFake()..blockedUser = true;
    await app(
      t,
      repo,
      ProfessionalShowcaseScreen.recommended(
        professionalId: 'professional',
        loadRecommended: () async => profiles.publicProfile(),
      ),
    );
    await t.tap(find.byTooltip('Signaler ou bloquer'));
    await t.pumpAndSettle();
    expect(find.text('Signaler le professionnel'), findsOneWidget);
    expect(find.text('Débloquer cet utilisateur'), findsOneWidget);
    await capture(t, '06-menu-profil');
  });
  testWidgets('SEC reverse block and offline safety status disable contacts', (
    t,
  ) async {
    final repo = SafetyFake()..reverse = true;
    await app(
      t,
      repo,
      SafetyContactGate(
        target: const SafetyTarget('professional', 'pro'),
        builder: (c, s) => FilledButton(
          onPressed: s?.contactAllowed == true ? () {} : null,
          child: const Text('Contact'),
        ),
      ),
    );
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
  testWidgets(
    'SEC report works at 320px with enlarged text and keyboard scrolling',
    (t) async {
      final repo = SafetyFake();
      await app(
        t,
        repo,
        Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                showSafetyReport(c, const SafetyTarget('request', 'request')),
            child: const Text('Signaler'),
          ),
        ),
        width: 320,
        scale: 1.5,
      );
      await t.tap(find.text('Signaler'));
      await t.pumpAndSettle();
      await chooseReason(t);
      await t.ensureVisible(find.text('Envoyer le signalement'));
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();
      expect(repo.reports.length, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('SEC help displays actual support and conduct rules', (t) async {
    await app(t, SafetyFake(), const SafetyHelpScreen());
    expect(find.text('mailto:kouamedenzel09@gmail.com'), findsOneWidget);
    expect(find.text(foundiConductRules), findsOneWidget);
    await capture(t, '07-aide-regles');
  });
  testWidgets(
    'SEC moderation notices provide appeal access and explicit loading errors',
    (t) async {
      final repo = SafetyFake()
        ..noticeTexts.add(
          'Compte Foundi suspendu. Contacte l’assistance pour une contestation.',
        );
      await app(t, repo, SafetyNoticesScreen(repository: repo));
      expect(find.textContaining('Compte Foundi suspendu'), findsOneWidget);
      await capture(t, '12-notification-moderation');
      await t.tap(find.text('Aide et contestation'));
      await t.pumpAndSettle();
      expect(find.text('mailto:kouamedenzel09@gmail.com'), findsOneWidget);
      final failed = SafetyFake()..fail = true;
      await app(
        t,
        failed,
        SafetyNoticesScreen(
          key: const ValueKey('failed-notices'),
          repository: failed,
        ),
      );
      expect(find.text('Avis indisponibles. Réessaie.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'SEC moderation notices stay accessible after account or professional profile denial',
    (t) async {
      for (final accountDenied in [true, false]) {
        final repo = SafetyFake()
          ..noticeTexts.add(
            'Compte Foundi suspendu. Une contestation est possible.',
          );
        await t.pumpWidget(
          FoundiApp(
            key: ValueKey(accountDenied),
            authRepository: accountDenied
                ? DeniedAccountFake()
                : auth_fixtures.FakeAuth(user: auth_fixtures.account()),
            professionalRepository: accountDenied
                ? auth_fixtures.FakePro()
                : DeniedProfessionalFake(),
            safetyRepository: repo,
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.text(
            accountDenied
                ? 'Le compte est indisponible'
                : 'Dossier indisponible',
          ),
          findsOneWidget,
        );
        await t.tap(find.text('Avis de modération et aide'));
        await t.pumpAndSettle();
        expect(find.textContaining('Compte Foundi suspendu'), findsOneWidget);
        await t.tap(find.text('Aide et contestation'));
        await t.pumpAndSettle();
        expect(find.text('mailto:kouamedenzel09@gmail.com'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'SEC moderation notice identifies the exact publication and keeps its excerpt readable',
    (t) async {
      final repo = SafetyFake()
        ..noticeTexts.add(
          'Contenu masqué par Foundi. Cette demande contient une publicité sans rapport avec le service recherché.\n\nContenu concerné : Demande « Réparer une fuite »\nRéférence : demande-test-2026\nExtrait du contenu examiné :\nUne fuite dans la cuisine à réparer.\n\nAssistance : kouamedenzel09@gmail.com.',
        );
      await app(t, repo, SafetyNoticesScreen(repository: repo), width: 390);
      expect(
        find.textContaining('Demande « Réparer une fuite »'),
        findsOneWidget,
      );
      expect(find.textContaining('demande-test-2026'), findsOneWidget);
      expect(
        find.textContaining('Une fuite dans la cuisine à réparer.'),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsOneWidget);
      await capture(t, '15-avis-contenu-concerne');
      expect(t.takeException(), isNull);
    },
  );
}
