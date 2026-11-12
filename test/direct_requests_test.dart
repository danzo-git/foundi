import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/professional/presentation/professional_showcase_screen.dart';
import 'package:foundi/features/requests/presentation/direct_requests.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/domain/request_photo_repository.dart';
import 'package:foundi/features/requests/presentation/request_composer.dart';
import 'package:foundi/features/requests/presentation/request_photos.dart';
import 'request_respondents_test.dart' as respondents;
import 'public_professional_profile_test.dart' as public;
import 'requests_v5_test.dart' as requests;
import 'request_photos_test.dart' as photo_tests;
import 'widget_test.dart' as fixtures;

const directCapture = bool.fromEnvironment('DIRECT_REQUEST_CAPTURE');

class DirectRequestsFake extends public.PublicProfileRequests
    implements DirectRequestRepository, RequestPhotoRepository {
  DirectRequestsFake({ProfessionalShowcase? profile})
    : super(
        profile ??
            const ProfessionalShowcase(
              name: 'Atelier Ébène',
              trade: 'Menuiserie',
              requestActivity: public.directActivity,
            ),
      );
  final privateRequests = <String, FoundiRequest>{};
  final attempts = <String>[];
  final uploads = <String, Uint8List>{};
  String recipient = 'atelier-ebene';
  String? lastRecipient;
  RequestDraft? directDraft;
  int publicCalls = 0;
  @override
  Future<Proposal> sendProposal(String id, ProposalDraft draft) async {
    final value = await super.sendProposal(id, draft);
    final request = privateRequests[id];
    if (request == null) return value;
    final saved = Proposal(
      id: value.id,
      requestId: id,
      requestTitle: request.title,
      professionalUid: request.directProfessionalId!,
      clientUid: request.clientUid!,
      professionalName: request.directProfessionalName!,
      description: draft.description,
      status: 'sent',
      createdAt: 123456,
      amount: draft.amount,
      delay: draft.delay,
    );
    sent[sent.length - 1] = saved;
    return saved;
  }

  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) async => RequestRespondentsPage(
    total: 1,
    canViewProposals: false,
    items: [
      RequestRespondent(profile.name, [
        profile.trade,
      ], professionalId: recipient),
    ],
  );
  @override
  Future<ProfessionalShowcase> readRequestRespondentProfile(
    String requestId,
    String professionalId,
  ) async => profile;
  @override
  Future<FoundiRequest> publish(String id, RequestDraft draft) async {
    publicCalls++;
    throw StateError('Private form called public publication');
  }

  @override
  Future<FoundiRequest> publishDirect(
    String id,
    String professionalId,
    RequestDraft draft,
  ) async {
    attempts.add(id);
    lastRecipient = professionalId;
    directDraft = draft;
    final saved = privateRequests.putIfAbsent(
      id,
      () => FoundiRequest(
        id: id,
        title: draft.title,
        description: draft.description,
        categoryLabel: 'Catégorie de test',
        specialtyLabel: 'Spécialité de test',
        zoneLabel: 'Zone de test',
        categoryId: draft.categoryId,
        specialtyId: draft.specialtyId,
        zoneId: draft.zoneId,
        status: 'published',
        createdAt: DateTime(2026, 11, 12),
        directProfessionalId: professionalId,
        directProfessionalName: profile.name,
        clientUid: 'uid',
        photoIds: draft.photoIds,
        budget: draft.budget,
        requesterName: fixtures.profile.fullName,
      ),
    );
    if (!items.any((r) => r.id == id)) items.add(saved);
    changes.add(null);
    if (loseResponse) {
      loseResponse = false;
      throw const AuthFailure('Envoi non confirmé. Réessaie.');
    }
    return saved;
  }

  @override
  Stream<List<FoundiRequest>> watchPublic() => super.watchPublic().map(
    (items) => items.where((r) => !r.isDirect).toList(),
  );
  @override
  Stream<FoundiRequest?> watchDirectRequest(String id) =>
      Stream.value(privateRequests[id]);
  @override
  Stream<List<FoundiRequest>> watchDirectRequests(String professionalId) =>
      Stream.value(
        privateRequests.values
            .where((r) => r.directProfessionalId == professionalId)
            .toList(),
      );
  @override
  Future<bool> uploadRequestPhoto(String id, LocalRequestPhoto photo) async {
    uploads[photo.id] = photo.bytes;
    return false;
  }

  @override
  Future<void> discardRequestPhotos(String id, List<String> ids) async {
    for (final id in ids) {
      uploads.remove(id);
    }
  }

  @override
  Future<Uint8List> readRequestPhoto(String id, String photoId) async =>
      uploads[photoId]!;
}

Future<void> openProfile(WidgetTester t, DirectRequestsFake repo) async {
  await requests.tapForm(t, find.byKey(const ValueKey('nav-1')));
  await requests.tapForm(t, find.text(respondents.published.title));
  await requests.tapForm(t, find.text(repo.profile.name));
}

void main() {
  setUpAll(() async {
    if (!directCapture) return;
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
    'recommended profiles route a private demand to their public identity without saving it in the showcase',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final navigation = ValueNotifier<DirectRequestIntent?>(null);
      DirectProfessionalTarget? selected;
      const profile = ProfessionalShowcase(
        name: 'Atelier recommandé',
        professionalId: 'recommended-pro',
        requestActivity: public.directActivity,
      );
      try {
        await t.pumpWidget(
          MaterialApp(
            home: DirectRequestsScope(
              auth: auth,
              navigation: navigation,
              onRequest: (target) => selected = target,
              child: ProfessionalShowcaseScreen.recommended(
                loadRecommended: () async => profile,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        expect(selected!.id, 'recommended-pro');
        expect(selected!.name, profile.name);
        final buttonSize = t.getSize(
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        expect(buttonSize.width, lessThan(350));
        expect(buttonSize.height, greaterThanOrEqualTo(48));
        expect(selected!.activity!.specialtyId, 'test_specialty');
        expect(profile.toSaveMap().containsKey('professionalId'), isFalse);
        expect(profile.toSaveMap().containsKey('requestActivity'), isFalse);
      } finally {
        await t.pumpWidget(const SizedBox());
        navigation.dispose();
        await auth.changes.close();
      }
    },
  );
  testWidgets(
    'direct demand from the public profile reuses the form and retries privately with one ID',
    (t) async {
      final repo =
          DirectRequestsFake(
              profile: directCapture ? public.publicProfile() : null,
            )
            ..items.add(respondents.published)
            ..loseResponse = true;
      await requests.runFlow(t, repo, (_, _) async {
        if (directCapture) {
          t.view.physicalSize = const Size(430, 932);
          await t.pumpAndSettle();
        }
        await openProfile(t, repo);
        if (directCapture) await public.capture(t, 'direct-01-profil');
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        expect(find.text('Demande directe'), findsOneWidget);
        expect(find.text('Pour ${repo.profile.name}'), findsOneWidget);
        if (directCapture) await public.capture(t, 'direct-02-formulaire');
        expect(find.byKey(const ValueKey('requestAuthorName')), findsNothing);
        expect(find.text('Nom affiché au professionnel'), findsNothing);
        expect(find.text('Nom d’affichage public'), findsNothing);
        for (final field in [
          'directRequestCategory',
          'directRequestSpecialty',
        ]) {
          expect(
            t.widget<TextFormField>(find.byKey(ValueKey(field))).enabled,
            isFalse,
          );
        }
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        await requests.fill(
          t,
          'requestDescription',
          'Je souhaite faire réparer mon meuble en bois.',
        );
        await requests.choose(t, 'requestZone', 'Zone de test');
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        if (directCapture) await public.capture(t, 'direct-03-verification');
        expect(find.text('Vérifie avant envoi'), findsOneWidget);
        expect(
          find.textContaining('Voici ce qui sera visible, même sans compte'),
          findsNothing,
        );
        await requests.tapForm(t, find.text('Envoyer ma demande privée'));
        expect(find.text('Envoi non confirmé. Réessaie.'), findsOneWidget);
        await requests.tapForm(t, find.text('Envoyer ma demande privée'));
        expect(find.text('C’est envoyé !'), findsOneWidget);
        if (directCapture) await public.capture(t, 'direct-04-confirmation');
        expect(repo.publicCalls, 0);
        expect(repo.attempts.toSet().length, 1);
        expect(repo.privateRequests.length, 1);
        expect(repo.lastRecipient, repo.recipient);
        expect(repo.directDraft!.photosPublic, isFalse);
        expect(repo.directDraft!.categoryId, 'test_sector');
        expect(repo.directDraft!.specialtyId, 'test_specialty');
        expect(
          repo.directDraft!.toMap().containsKey('authorPublicName'),
          isFalse,
        );
        await requests.tapForm(t, find.text('Voir ma demande'));
        expect(find.text('Demande privée'), findsOneWidget);
        expect(find.text('Voir mes propositions'), findsOneWidget);
        expect(find.text('Recommander'), findsNothing);
        expect(t.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'guest login retains the chosen professional without publishing anything',
    (t) async {
      final repo = DirectRequestsFake()..items.add(respondents.published);
      await requests.runFlow(t, repo, (auth, _) async {
        await requests.tapForm(t, find.text(respondents.published.title));
        await requests.tapForm(t, find.text(repo.profile.name));
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        expect(find.text('Demande directe'), findsNothing);
        expect(repo.attempts, isEmpty);
        auth.emit(fixtures.account());
        await t.pumpAndSettle();
        expect(find.text('Demande directe'), findsOneWidget);
        expect(find.text('Pour ${repo.profile.name}'), findsOneWidget);
        expect(repo.publicCalls, 0);
        expect(repo.attempts, isEmpty);
      }, guest: true);
    },
  );

  testWidgets(
    'the approved recipient receives direct requests inside the existing account navigation',
    (t) async {
      final repo = DirectRequestsFake();
      const id = 'DirectRequestIdentifier0001';
      repo.privateRequests[id] = FoundiRequest(
        id: id,
        title: 'Réparer mon meuble privé',
        description: 'Une réparation réservée à ce professionnel.',
        categoryLabel: 'Services',
        specialtyLabel: 'Menuiserie',
        zoneLabel: 'Cocody',
        status: 'published',
        createdAt: null,
        directProfessionalId: 'uid',
        directProfessionalName: 'Atelier Ébène',
        clientUid: 'client',
        requesterName: 'Koffi Yao',
      );
      await requests.runFlow(t, repo, (_, _) async {
        if (directCapture) {
          t.view.physicalSize = const Size(430, 932);
          await t.pumpAndSettle();
        }
        await requests.tapForm(t, find.byKey(const ValueKey('nav-3')));
        await requests.tapForm(t, find.text('Demandes directes reçues'));
        expect(find.text('Koffi Yao'), findsOneWidget);
        if (directCapture) await public.capture(t, 'direct-v2-05-reception');
        await requests.tapForm(t, find.text('Réparer mon meuble privé'));
        expect(find.text('Demande de Koffi Yao'), findsOneWidget);
        if (directCapture) await public.capture(t, 'direct-v2-06-detail');
        expect(find.text('Demande privée'), findsOneWidget);
        expect(find.text('Recommander'), findsNothing);
        expect(find.text('Voir mes propositions'), findsNothing);
        expect(repo.accessCalls, 1);
        await requests.tapForm(t, find.text('Faire une proposition'));
        await requests.fill(
          t,
          'proposalDescription',
          'Je peux réparer ce meuble en bois cette semaine.',
        );
        await t.scrollUntilVisible(
          find.text('Prévisualiser ma proposition'),
          160,
          scrollable: respondents.explorerList,
        );
        await requests.tapForm(t, find.text('Prévisualiser ma proposition'));
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('sendProposal')),
          160,
          scrollable: respondents.explorerList,
        );
        await requests.tapForm(t, find.byKey(const ValueKey('sendProposal')));
        await requests.tapForm(t, find.text('Voir mes propositions'));
        expect(repo.sendCalls, 1);
        expect(repo.sent.single.requestId, id);
        expect(find.text('Mes propositions'), findsWidgets);
        expect(t.takeException(), isNull);
      }, professional: true);
    },
  );

  testWidgets(
    'a professional cannot send a direct request to their own public profile',
    (t) async {
      final repo = DirectRequestsFake()
        ..recipient = 'uid'
        ..items.add(respondents.published);
      await requests.runFlow(t, repo, (_, _) async {
        await openProfile(t, repo);
        expect(
          find.byKey(const ValueKey('requestProfessionalDirectly')),
          findsNothing,
        );
      });
    },
  );

  testWidgets(
    'photos on a direct demand stay private through preview and send',
    (t) async {
      final repo = DirectRequestsFake();
      final catalog = fixtures.FakePro();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      try {
        final bytes = File(
          'functions/test/fixtures/photo.png',
        ).readAsBytesSync();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestComposer(
                repository: repo,
                catalog: catalog,
                directTarget: const DirectProfessionalTarget(
                  'atelier-ebene',
                  'Atelier Ébène',
                  activity: public.directActivity,
                ),
                accountName: fixtures.profile.fullName,
                onExit: () {},
                onMine: () {},
                onOpen: (_) {},
                photoPicker: () async => [
                  RequestPhotoSelection(bytes.length, () async => bytes),
                ],
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await requests.fill(
          t,
          'requestDescription',
          'Une réparation avec une photographie privée.',
        );
        await requests.choose(t, 'requestZone', 'Zone de test');
        await photo_tests.selectPhotos(t);
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        await requests.tapForm(t, find.text('Envoyer ma demande privée'));
        expect(repo.directDraft!.photoIds.length, 1);
        expect(repo.directDraft!.photosPublic, isFalse);
        expect(repo.uploads.length, 1);
        expect(repo.publicCalls, 0);
      } finally {
        await t.pumpWidget(const SizedBox());
        await repo.changes.close();
        await catalog.changes.close();
        await catalog.docChanges.close();
        t.view.reset();
      }
    },
  );

  testWidgets(
    'missing professional activity blocks sending instead of allowing a client choice',
    (t) async {
      final repo = DirectRequestsFake(), catalog = fixtures.FakePro();
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestComposer(
                repository: repo,
                catalog: catalog,
                directTarget: const DirectProfessionalTarget(
                  'atelier-ebene',
                  'Atelier Ébène',
                ),
                accountName: fixtures.profile.fullName,
                onExit: () {},
                onMine: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await requests.fill(
          t,
          'requestDescription',
          'Je souhaite réparer mon meuble en bois.',
        );
        await requests.choose(t, 'requestZone', 'Zone de test');
        final verify = find.byKey(const ValueKey('verifyRequest'));
        await Scrollable.ensureVisible(t.element(verify));
        expect(t.widget<FilledButton>(verify).onPressed, isNull);
        expect(find.byKey(const ValueKey('requestAuthorName')), findsNothing);
        expect(
          find.textContaining('L’activité est indisponible.'),
          findsOneWidget,
        );
        expect(repo.attempts, isEmpty);
      } finally {
        await t.pumpWidget(const SizedBox());
        await repo.changes.close();
        await catalog.changes.close();
        await catalog.docChanges.close();
      }
    },
  );

  testWidgets(
    'editing a private request keeps its original professional activity locked',
    (t) async {
      final repo = DirectRequestsFake(), catalog = fixtures.FakePro();
      final existing = FoundiRequest(
        id: 'DirectRequestEdit00001',
        title: 'Réparer une table',
        description: 'Je souhaite réparer une table en bois.',
        categoryLabel: 'Catégorie de test',
        specialtyLabel: 'Spécialité de test',
        categoryId: 'test_sector',
        specialtyId: 'test_specialty',
        zoneId: 'test_zone',
        zoneLabel: 'Zone de test',
        status: 'published',
        createdAt: DateTime(2026, 11, 12),
        directProfessionalId: 'atelier-ebene',
        directProfessionalName: 'Atelier Ébène',
        requesterName: fixtures.profile.fullName,
      );
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RequestComposer(
                repository: repo,
                catalog: catalog,
                initial: existing,
                accountName: fixtures.profile.fullName,
                onExit: () {},
                onMine: () {},
                onOpen: (_) {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        for (final key in ['directRequestCategory', 'directRequestSpecialty']) {
          expect(
            t.widget<TextFormField>(find.byKey(ValueKey(key))).enabled,
            isFalse,
          );
        }
        await requests.tapForm(t, find.byKey(const ValueKey('verifyRequest')));
        expect(find.text('Auteur affiché · Awa Kouassi'), findsOneWidget);
        expect(
          find.text('Catégorie de test · Spécialité de test'),
          findsOneWidget,
        );
        expect(find.text('Nom affiché au professionnel'), findsNothing);
      } finally {
        await t.pumpWidget(const SizedBox());
        await repo.changes.close();
        await catalog.changes.close();
        await catalog.docChanges.close();
      }
    },
  );
}
