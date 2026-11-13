import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/professional/domain/professional_directory.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/professional/presentation/professional_profile_widgets.dart';
import 'package:foundi/features/requests/presentation/request_composer.dart';
import 'direct_requests_test.dart' as direct;
import 'public_professional_profile_test.dart' as public;
import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as fixtures;

const captureEnabled = bool.fromEnvironment('DIRECTORY_CAPTURE');
ProfessionalShowcase profileFixture() => captureEnabled
    ? ProfessionalShowcase.fromMap({
        ...jsonDecode(
              File(
                '.dart_tool/unified-account-capture-public-profile.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
        'requestActivity': public.directActivityMap,
      })
    : public.publicProfile();

class DirectoryFake extends direct.DirectRequestsFake
    implements ProfessionalDirectoryRepository {
  DirectoryFake() : super(profile: profileFixture());
  final searches = <({ProfessionalDirectoryFilters filters, String? cursor})>[];
  final invalidated = <String>[];
  bool available = true, failSearch = false, empty = false;
  int mediaReads = 0, directoryReads = 0;
  Future<ProfessionalDirectoryPage> Function(
    ProfessionalDirectoryFilters,
    String?,
  )?
  handler;
  ProfessionalListing get listing => ProfessionalListing(
    professionalId: recipient,
    name: profile.name,
    trade: profile.trade,
    zones: [profile.area.isEmpty ? 'Zone de test' : profile.area],
    categories: ['Catégorie de test'],
    specialties: ['Spécialité de test'],
  );
  @override
  Future<ProfessionalDirectoryPage> searchProfessionals(
    ProfessionalDirectoryFilters filters, {
    String? cursor,
  }) async {
    searches.add((filters: filters, cursor: cursor));
    if (failSearch) throw const AuthFailure('Connexion interrompue. Réessaie.');
    return handler == null
        ? ProfessionalDirectoryPage(empty || !available ? [] : [listing])
        : await handler!(filters, cursor);
  }

  @override
  Future<ProfessionalShowcase> readDirectoryProfessional(String id) async {
    expect(id, recipient);
    directoryReads++;
    if (!available) throw const ProfessionalUnavailable();
    return profile;
  }

  @override
  Future<Set<String>> checkDirectoryProfessionals(List<String> ids) async =>
      available ? ids.toSet() : {};
  @override
  void clearDirectoryMedia(String id) => invalidated.add(id);
  @override
  Future<ProfessionalMediaManifest> directoryMediaManifest(String id) async {
    mediaReads++;
    if (!available) throw const ProfessionalUnavailable();
    return ProfessionalMediaManifest(
      portraitId: profile.portrait == null ? null : 'portrait',
      galleryIds: [
        for (var i = 0; i < profile.gallery.length.clamp(0, 3); i++)
          'gallery$i',
      ],
    );
  }

  @override
  Future<Uint8List> readDirectoryThumbnail(String id, String photoId) async =>
      photoId == 'portrait'
      ? profile.portrait!.bytes
      : profile.gallery[int.parse(photoId.substring(7))].bytes;
}

Future<void> openDirectory(WidgetTester t, {bool guest = false}) async {
  if (!guest) await requests.tapForm(t, find.byKey(const ValueKey('nav-1')));
  await requests.tapForm(t, find.text('Professionnels').first);
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captureEnabled) return;
  final images = t.widgetList<Image>(find.byType(Image)).toList();
  if (images.isNotEmpty) {
    final context = t.element(find.byType(Image).first);
    await t.runAsync(
      () => Future.wait(images.map((i) => precacheImage(i.image, context))),
    );
  }
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('v5Capture')),
  );
  boundary.reassemble();
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('docs/explorer-professionnels-v1-captures')
      ..createSync(recursive: true);
    await File(
      '${folder.path}/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
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
      final b = await File('C:/Windows/Fonts/$font').readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(b)))).load();
    }
  });
  testWidgets(
    'directory reuses public profile and private composer, retaining filters on Back',
    (t) async {
      final repo = DirectoryFake();
      await requests.runFlow(t, repo, (auth, _) async {
        if (captureEnabled) {
          t.view.physicalSize = const Size(430, 932);
          await t.pumpAndSettle();
        }
        await requests.tapForm(t, find.byKey(const ValueKey('nav-1')));
        await capture(t, '00-explorer-demandes');
        await requests.tapForm(t, find.text('Professionnels').first);
        expect(repo.searches.length, 1);
        expect(find.text(repo.profile.name), findsOneWidget);
        expect(find.byKey(const ValueKey('nav-4')), findsNothing);
        await capture(t, '01-explorer-professionnels');
        await t.enterText(
          find.byKey(const ValueKey('professionalSearch')),
          '  ${repo.profile.name}  ',
        );
        await t.pump(const Duration(milliseconds: 401));
        await t.pumpAndSettle();
        expect(repo.searches.last.filters.query, '  ${repo.profile.name}  ');
        await capture(t, '02-recherche');
        await requests.tapForm(t, find.text(repo.profile.name));
        expect(repo.directoryReads, 1);
        public.expectPublicOnly();
        await capture(t, '03-profil-public');
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        expect(repo.directoryReads, 2);
        expect(find.byType(RequestComposer), findsOneWidget);
        expect(find.byKey(const ValueKey('requestAuthorName')), findsNothing);
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('directRequestCategory')),
              )
              .enabled,
          isFalse,
        );
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('directRequestSpecialty')),
              )
              .enabled,
          isFalse,
        );
        expect(repo.publicCalls, 0);
        expect(repo.attempts, isEmpty);
        await capture(t, '04-demande-directe');
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('professionalSearch')),
          findsOneWidget,
        );
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('professionalSearch')),
              )
              .controller!
              .text,
          '  ${repo.profile.name}  ',
        );
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'search debounce and generation discard stale results without resetting newer criteria',
    (t) async {
      final repo = DirectoryFake(),
          old = Completer<ProfessionalDirectoryPage>();
      repo.handler = (filters, cursor) async => filters.query == 'ancien'
          ? old.future
          : ProfessionalDirectoryPage([
              ProfessionalListing(
                professionalId: 'nouveau',
                name: 'Résultat récent',
                trade: 'Menuiserie',
              ),
            ]);
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        await t.enterText(
          find.byKey(const ValueKey('professionalSearch')),
          'ancien',
        );
        await t.pump(const Duration(milliseconds: 401));
        await t.enterText(
          find.byKey(const ValueKey('professionalSearch')),
          'récent',
        );
        await t.pump(const Duration(milliseconds: 401));
        await t.pumpAndSettle();
        old.complete(
          const ProfessionalDirectoryPage([
            ProfessionalListing(
              professionalId: 'ancien',
              name: 'Résultat périmé',
              trade: '',
            ),
          ]),
        );
        await t.pumpAndSettle();
        expect(find.text('Résultat récent'), findsOneWidget);
        expect(find.text('Résultat périmé'), findsNothing);
        expect(repo.searches.last.filters.query, 'récent');
      });
    },
  );
  testWidgets(
    'directory sends an idempotent private request to the selected professional only',
    (t) async {
      final repo = DirectoryFake()..loseResponse = true;
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        await requests.tapForm(t, find.text(repo.profile.name));
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        await requests.fill(
          t,
          'requestDescription',
          'Je souhaite faire réparer mon meuble en bois.',
        );
        await requests.choose(t, 'requestZone', 'Zone de test');
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        await requests.tapForm(t, find.text('Envoyer ma demande privée'));
        expect(find.text('Envoi non confirmé. Réessaie.'), findsOneWidget);
        await requests.tapForm(t, find.text('Envoyer ma demande privée'));
        expect(find.text('C’est envoyé !'), findsOneWidget);
        expect(repo.lastRecipient, repo.recipient);
        expect(repo.publicCalls, 0);
        expect(repo.attempts.toSet().length, 1);
        expect(repo.directDraft!.photosPublic, isFalse);
        expect(repo.directDraft!.categoryId, 'test_sector');
      });
    },
  );
  testWidgets(
    'empty cursor pages continue until an actual result rather than claiming none exist',
    (t) async {
      final repo = DirectoryFake();
      repo.handler = (f, c) async => c == null
          ? const ProfessionalDirectoryPage([], cursor: 'next')
          : ProfessionalDirectoryPage([repo.listing]);
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        expect(repo.searches.length, 2);
        expect(find.text(repo.profile.name), findsOneWidget);
        expect(find.text('Aucun professionnel trouvé'), findsNothing);
      });
    },
  );
  testWidgets(
    'filters combine category specialty and zone; reset clears query and criteria',
    (t) async {
      final repo = DirectoryFake();
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('professionalFilters')),
        );
        await requests.choose(t, 'directory-Catégorie', 'Catégorie de test');
        await requests.choose(t, 'directory-Spécialité', 'Spécialité de test');
        await requests.choose(
          t,
          'directory-Zone d’intervention',
          'Zone de test',
        );
        await requests.tapForm(t, find.text('Voir les résultats'));
        final f = repo.searches.last.filters;
        expect(f.categoryId, 'test_sector');
        expect(f.specialtyId, 'test_specialty');
        expect(f.zoneId, 'test_zone');
        repo.empty = true;
        await requests.tapForm(
          t,
          find.byTooltip('Actualiser les professionnels'),
        );
        await capture(t, '05-vide');
        await requests.tapForm(t, find.text('Réinitialiser la recherche'));
        expect(repo.searches.last.filters.toMap(), {'query': ''});
      });
    },
  );
  testWidgets(
    'retry recovers directory errors and unavailable profile never offers a private request',
    (t) async {
      final repo = DirectoryFake()..failSearch = true;
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        expect(find.text('Connexion interrompue. Réessaie.'), findsOneWidget);
        repo.failSearch = false;
        await requests.tapForm(t, find.text('Réessayer'));
        repo.available = false;
        await requests.tapForm(t, find.text(repo.profile.name));
        expect(
          find.text('Ce professionnel n’est plus disponible.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('requestProfessionalDirectly')),
          findsNothing,
        );
        await capture(t, '06-indisponible');
      });
    },
  );
  testWidgets(
    'revoked approval removes a displayed public profile on lease renewal',
    (t) async {
      final repo = DirectoryFake();
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        await requests.tapForm(t, find.text(repo.profile.name));
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('publicProfileSection-2')),
        );
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
        repo.available = false;
        await t.pump(const Duration(seconds: 30));
        await t.pumpAndSettle();
        expect(
          find.text('Ce professionnel n’est plus disponible.'),
          findsOneWidget,
        );
        expect(find.text('Professionnel vérifié'), findsNothing);
        expect(find.byType(Dialog), findsNothing);
        expect(repo.invalidated, [repo.recipient]);
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'guest browse and login retain the exact chosen private recipient',
    (t) async {
      final repo = DirectoryFake();
      await requests.runFlow(t, repo, (auth, _) async {
        await openDirectory(t, guest: true);
        await requests.tapForm(t, find.text(repo.profile.name));
        await requests.tapForm(
          t,
          find.byKey(const ValueKey('requestProfessionalDirectly')),
        );
        expect(repo.attempts, isEmpty);
        auth.emit(fixtures.account());
        await t.pumpAndSettle();
        expect(find.text('Pour ${repo.profile.name}'), findsOneWidget);
        expect(find.text('Demande directe'), findsOneWidget);
        expect(repo.publicCalls, 0);
      }, guest: true);
    },
  );
  testWidgets(
    'Android Back switches directory to demands before leaving Explorer',
    (t) async {
      final repo = DirectoryFake();
      await requests.runFlow(t, repo, (_, _) async {
        await openDirectory(t);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Explorer les demandes'), findsOneWidget);
        expect(find.byKey(const ValueKey('professionalSearch')), findsNothing);
        await requests.tapForm(t, find.text('Professionnels').first);
        expect(repo.searches.length, 1);
      });
    },
  );
  testWidgets(
    'directory fits a narrow screen with enlarged text and no invented ratings or favorites',
    (t) async {
      final repo = DirectoryFake();
      await requests.runFlow(t, repo, (_, _) async {
        t.view.physicalSize = const Size(320, 740);
        t.platformDispatcher.textScaleFactorTestValue = 1.5;
        await t.pumpAndSettle();
        await openDirectory(t);
        expect(find.byIcon(Icons.favorite_border), findsNothing);
        expect(find.byIcon(Icons.star), findsNothing);
        expect(t.takeException(), isNull);
      });
    },
  );
}
