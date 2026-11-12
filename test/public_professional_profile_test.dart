import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/professional/presentation/professional_profile_widgets.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';

import 'request_respondents_test.dart' as respondents;
import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as fixtures;

const captureEnabled = bool.fromEnvironment('PUBLIC_PROFILE_CAPTURE');
const directActivity = ProfessionalRequestActivity(
  categoryId: 'test_sector',
  categoryLabel: 'Catégorie de test',
  specialtyId: 'test_specialty',
  specialtyLabel: 'Spécialité de test',
);
const directActivityMap = {
  'categoryId': 'test_sector',
  'categoryLabel': 'Catégorie de test',
  'specialtyId': 'test_specialty',
  'specialtyLabel': 'Spécialité de test',
};

class PublicProfileRequests extends respondents.RespondentRequests {
  PublicProfileRequests(this.profile);
  final ProfessionalShowcase profile;
  int profileReads = 0, proposalReads = 0;

  @override
  Future<ProfessionalShowcase> readRequestRespondentProfile(
    String requestId,
    String professionalId,
  ) async {
    expect(requestId, respondents.published.id);
    expect(professionalId, 'atelier-ebene');
    profileReads++;
    return profile;
  }

  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) async => RequestRespondentsPage(
    total: 1,
    items: [
      RequestRespondent(profile.name, [
        profile.trade,
      ], professionalId: 'atelier-ebene'),
    ],
    canViewProposals: false,
  );

  @override
  Stream<List<Proposal>> watchReceivedProposals(
    String uid, {
    String? requestId,
  }) {
    proposalReads++;
    return super.watchReceivedProposals(uid, requestId: requestId);
  }
}

ProfessionalShowcase publicProfile() {
  if (captureEnabled) {
    return ProfessionalShowcase.fromMap({
      ...jsonDecode(
            File(
              '.dart_tool/unified-account-capture-public-profile.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
      'requestActivity': directActivityMap,
    });
  }
  final image = {
    'id': 'photo-test',
    'base64': base64Encode(
      File('functions/test/fixtures/photo.png').readAsBytesSync(),
    ),
  };
  // Extra private fields must never become part of the public view model.
  return ProfessionalShowcase.fromMap({
    'revision': 1,
    'requestActivity': directActivityMap,
    'name': 'Atelier Ébène',
    'trade': 'Menuiserie',
    'area': 'Cocody',
    'bio': 'Meubles et rangements sur mesure.',
    'portrait': image,
    'cover': image,
    'gallery': [image, image],
    'email': 'prive@example.test',
    'phone': '+2250700000000',
    'documents': ['Justificatif confidentiel'],
    'proposals': [
      {'message': 'Offre confidentielle', 'amount': 123456},
    ],
  });
}

void expectPublicOnly() {
  for (final text in [
    'Informations personnelles',
    'Vérification professionnelle',
    'Changer d’espace  ›',
    'Modifier le profil',
    'Modifier la couverture',
    'Ajouter',
    'Gérer les réalisations',
    'Voir mes propositions',
    'Propositions reçues',
    'prive@example.test',
    '+2250700000000',
    'Justificatif confidentiel',
    'Offre confidentielle',
    fixtures.account().email,
  ]) {
    expect(find.text(text), findsNothing, reason: text);
  }
  expect(find.byType(TextFormField), findsNothing);
  expect(find.byKey(const ValueKey('openSettings')), findsNothing);
  expect(find.byTooltip('Modifier la photo de profil'), findsNothing);
  expect(find.byTooltip('Retirer la réalisation 1'), findsNothing);
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captureEnabled) return;
  final images = t.widgetList<Image>(find.byType(Image)).toList();
  if (images.isNotEmpty) {
    final context = t.element(find.byType(Image).first);
    await t.runAsync(
      () => Future.wait(
        images.map((image) => precacheImage(image.image, context)),
      ),
    );
  }
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('v5Capture')),
  );
  boundary.reassemble();
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/public-profile-captures')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!captureEnabled) return;
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
    'public respondent profile shares the account design without private data or proposal access',
    (t) async {
      final profile = publicProfile();
      final repo = PublicProfileRequests(profile)
        ..items.add(respondents.published);
      await requests.runFlow(t, repo, (_, _) async {
        if (captureEnabled) {
          t.view.physicalSize = const Size(430, 932);
          await t.pumpAndSettle();
        }
        await requests.tapForm(t, find.text(respondents.published.title));
        await requests.tapForm(t, find.text(profile.name));
        final header = t.widget<ProfessionalShowcaseHeader>(
          find.byType(ProfessionalShowcaseHeader),
        );
        expect(header.profile, same(profile));
        expect(header.showBio, isTrue);
        expect(header.onEdit, isNull);
        expect(header.onCover, isNull);
        expect(header.onPortrait, isNull);
        expect(find.byType(ProfessionalProfileTabs), findsOneWidget);
        expect(find.byType(ProfessionalProfileSection), findsOneWidget);
        expectPublicOnly();
        await capture(t, '01-profil-public-a-propos');

        await requests.tapForm(
          t,
          find.byKey(const ValueKey('publicProfileSection-1')),
        );
        expect(
          find.text('Nom professionnel · ${profile.name}'),
          findsOneWidget,
        );
        expectPublicOnly();
        await capture(t, '02-profil-public-activite');

        await requests.tapForm(
          t,
          find.byKey(const ValueKey('publicProfileSection-2')),
        );
        final gallery = t.widget<ShowcaseGallery>(find.byType(ShowcaseGallery));
        expect(gallery.photos, same(profile.gallery));
        expect(gallery.preview, isFalse);
        expect(gallery.onAdd, isNull);
        expect(gallery.onRemove, isNull);
        expectPublicOnly();
        await capture(t, '03-profil-public-realisations');
        await requests.tapForm(
          t,
          find
              .descendant(
                of: find.byType(ShowcaseGallery),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(find.byType(Dialog), findsOneWidget);
        await requests.tapForm(t, find.text('Fermer'));
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('publicProfileSection-0')),
        );
        await requests.tapForm(
          t,
          find.text('Voir tout (${profile.gallery.length})'),
        );
        expect(
          t.widget<ShowcaseGallery>(find.byType(ShowcaseGallery)).preview,
          isFalse,
        );
        expectPublicOnly();
        expect(repo.profileReads, 1);
        expect(repo.proposalReads, 0);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.text('1 professionnel a répondu'), findsOneWidget);
        expect(find.text(profile.name), findsOneWidget);
        expect(t.takeException(), isNull);
      }, guest: true);
    },
  );

  testWidgets(
    'public respondent profile handles missing images at 320px with large text',
    (t) async {
      final unavailable = ShowcasePhoto(Uint8List.fromList([1, 2, 3]));
      final repo = PublicProfileRequests(
        ProfessionalShowcase(
          name: 'Atelier de création et de menuiserie sur mesure',
          trade: 'Menuiserie et agencement intérieur',
          area: 'Abidjan et les communes environnantes',
          portrait: unavailable,
          cover: unavailable,
          gallery: [unavailable],
        ),
      )..items.add(respondents.published);
      await requests.runFlow(t, repo, (_, _) async {
        t.view.physicalSize = const Size(320, 780);
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text(respondents.published.title),
          140,
          scrollable: respondents.explorerList,
        );
        await requests.tapForm(t, find.text(respondents.published.title));
        await requests.tapForm(t, find.text(repo.profile.name));
        for (var section = 0; section < 3; section++) {
          await requests.tapForm(
            t,
            find.byKey(ValueKey('publicProfileSection-$section')),
          );
          expectPublicOnly();
        }
        await requests.tapForm(
          t,
          find
              .descendant(
                of: find.byType(ShowcaseGallery),
                matching: find.byType(InkWell),
              )
              .first,
        );
        expect(find.text('Image indisponible.'), findsOneWidget);
        await requests.tapForm(t, find.text('Fermer'));
        expect(t.takeException(), isNull);
      }, guest: true);
    },
  );

  testWidgets(
    'public respondent profile shows an empty gallery without edit actions or invented activity',
    (t) async {
      final repo = PublicProfileRequests(
        const ProfessionalShowcase(name: 'Atelier Ébène'),
      )..items.add(respondents.published);
      await requests.runFlow(t, repo, (_, _) async {
        await requests.tapForm(t, find.text(respondents.published.title));
        await requests.tapForm(t, find.text(repo.profile.name));
        expect(find.text('Aucune réalisation ajoutée.'), findsOneWidget);
        expect(find.byType(ProfessionalProfileDetail), findsNothing);
        expectPublicOnly();
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('publicProfileSection-1')),
        );
        expect(find.text('Nom professionnel · Atelier Ébène'), findsOneWidget);
        expect(find.textContaining('Indépendant'), findsNothing);
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('publicProfileSection-2')),
        );
        expect(find.text('Aucune réalisation ajoutée.'), findsOneWidget);
        expect(find.byType(ShowcaseGallery), findsNothing);
        expectPublicOnly();
        expect(t.takeException(), isNull);
      }, guest: true);
    },
  );
}
