import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/personal_avatar_repository.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/auth/presentation/account_view.dart';
import 'package:foundi/features/auth/presentation/personal_avatar.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/domain/request_location_repository.dart';
import 'package:foundi/features/requests/presentation/request_composer.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';
import 'package:foundi/features/requests/presentation/request_zone_picker.dart';
import 'widget_test.dart' as fixtures;
import 'professional_showcase_test.dart' as showcase;
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/professional/presentation/professional_profile_widgets.dart';
import 'requests_v5_test.dart' as requests;

const captureEnabled = bool.fromEnvironment('SPRINT25_CAPTURE');
final boundary = GlobalKey();
const catalog = ProfessionalCatalog(
  enabled: true,
  categories: [
    ProfessionalCategory('services', 'Services à domicile', [
      ReferenceChoice('plomberie', 'Plomberie'),
    ], {}),
  ],
  unclassifiedCategory: ProfessionalCategory(
    'foundi_other',
    'Autre / Je ne sais pas quelle catégorie choisir',
    [],
    {},
  ),
  zones: [
    ReferenceChoice('cocody', 'Cocody'),
    ReferenceChoice('plateau', 'Plateau'),
    ReferenceChoice('yop', 'Yopougon'),
    ReferenceChoice('bingerville', 'Bingerville'),
  ],
);
const request = FoundiRequest(
  id: 'Sprint25FixtureRequest01',
  title: 'Installer une étagère dans mon salon',
  description:
      'Je cherche une personne pour fixer une étagère au mur et vérifier les supports.',
  categoryLabel: 'Services à domicile',
  specialtyLabel: '',
  zoneLabel: 'Cocody · Plateau',
  status: 'published',
  createdAt: null,
  authorPublicName: 'Awa Kouassi',
  zoneIds: ['cocody', 'plateau'],
);

Future<void> page(
  WidgetTester t,
  Widget child, {
  double width = 430,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 980);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final auth = fixtures.FakeAuth();
  await t.pumpWidget(FoundiApp(authRepository: auth));
  await t.pumpAndSettle();
  final theme = t.widget<MaterialApp>(find.byType(MaterialApp)).theme;
  await t.pumpWidget(const SizedBox());
  await auth.changes.close();
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => RepaintBoundary(
        key: boundary,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Foundi')),
        body: child,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captureEnabled) return;
  await t.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/sprint-2-5-captures/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

// A synthetic bitmap fixture selected by the test. No real person's photo,
// Google photo or professional portrait is used by these screen captures.
Future<Uint8List> bitmap() async {
  final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 96, 96),
    Paint()..color = const Color(0xffd7ebe3),
  );
  canvas.drawOval(
    const Rect.fromLTWH(10, 60, 76, 72),
    Paint()..color = const Color(0xff176b59),
  );
  canvas.drawOval(
    const Rect.fromLTWH(25, 13, 46, 65),
    Paint()..color = const Color(0xff68462e),
  );
  canvas.drawOval(
    const Rect.fromLTWH(30, 24, 36, 44),
    Paint()..color = const Color(0xffb87c55),
  );
  final image = await recorder.endRecording().toImage(96, 96);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class UnavailableLocationFake implements RequestLocationRepository {
  @override
  Future<List<ReferenceChoice>> suggest(List<ReferenceChoice> choices) async =>
      throw const RequestLocationFailure(
        'Localisation non autorisée. Choisis tes zones manuellement.',
      );
  @override
  Future<void> openSettings() async {}
}

class AvatarFake implements PersonalAvatarRepository {
  PersonalAvatarState value = const PersonalAvatarState(
    hasPhoto: true,
    published: true,
  );
  int revoked = 0, removed = 0, uploads = 0, saves = 0;
  @override
  Future<PersonalAvatarState> personalAvatarState() async => value;
  @override
  Future<void> removePersonalAvatar() async {
    removed++;
    value = const PersonalAvatarState();
  }

  @override
  Future<PersonalAvatarState> savePersonalAvatar({
    Uint8List? bytes,
    String? contentType,
    required bool publish,
  }) async {
    if (!publish) revoked++;
    saves++;
    if (bytes != null) uploads++;
    return value = PersonalAvatarState(
      hasPhoto: true,
      published: publish,
      preview: bytes ?? value.preview,
    );
  }
}

void main() {
  setUpAll(() async {
    if (!captureEnabled) return;
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
  testWidgets(
    'avatar image, absent, revoked and network error fall back without Google or private data',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await bitmap());
      final versions = StreamController<String?>.broadcast();
      int reads = 0;
      await page(
        t,
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const RequestHeading('Explorer', subtitle: 'Demandes publiées'),
            RequestCard(
              request,
              showDescription: true,
              authorAvatar: PersonalAvatar(
                publicId: 'fixture',
                versionStream: versions.stream,
                loadImage: (_) async {
                  reads++;
                  return bytes;
                },
              ),
            ),
          ],
        ),
      );
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      versions.add('v1');
      await t.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(reads, 1);
      await t.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          t.element(find.byType(PersonalAvatar)),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, 'explorer-avatar-autorise');
      versions.add(null);
      await t.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      await capture(t, 'explorer-avatar-absent-ou-revoque');
      await page(t, const Center(child: PersonalAvatar()));
      expect(find.byType(Image), findsNothing);
      await page(
        t,
        Center(
          child: PersonalAvatar(
            versionStream: Stream.value('bad'),
            loadImage: (_) async => throw StateError('network'),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
      expect(t.takeException(), isNull);
      await versions.close();
    },
  );
  testWidgets(
    'manual searchable zones cap at three, allow removal, location fallback preserves selection at 320px',
    (t) async {
      var selected = <String>[];
      await page(
        t,
        StatefulBuilder(
          builder: (context, update) => ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const RequestHeading('Nouvelle demande'),
              RequestZonePicker(
                locationRepository: UnavailableLocationFake(),
                choices: catalog.zones,
                selected: selected,
                onChanged: (v) => update(() => selected = v),
              ),
            ],
          ),
        ),
        width: 320,
        scale: 1.7,
      );
      await requests.tapForm(
        t,
        find.byKey(const ValueKey('chooseRequestZones')),
      );
      final first = t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Cocody'),
      );
      first.onChanged!(true);
      first.onChanged!(true);
      await t.pumpAndSettle();
      expect(find.text('1/3 zones sélectionnées'), findsOneWidget);
      for (final label in ['Plateau', 'Yopougon']) {
        await fixtures.tap(t, find.text(label).last);
      }
      final fourth = t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Bingerville'),
      );
      expect(fourth.onChanged, isNull);
      await capture(t, 'zones-320px-grandes-polices');
      await fixtures.tap(t, find.text('Confirmer'));
      expect(selected, ['cocody', 'plateau', 'yop']);
      await requests.tapForm(t, find.text('Utiliser ma position actuelle'));
      expect(find.text('Choisis ta zone manuellement'), findsOneWidget);
      await fixtures.tap(t, find.text('Continuer'));
      expect(selected, hasLength(3));
      final chip = find.widgetWithText(InputChip, 'Plateau');
      t.widget<InputChip>(chip).onDeleted!();
      await t.pumpAndSettle();
      expect(selected, ['cocody', 'yop']);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown category requires a detail, previews all zones and publishes on existing workflow',
    (t) async {
      final pro = fixtures.FakePro()..references = catalog;
      final repository = requests.FakeRequests();
      await page(
        t,
        RequestComposer(
          repository: repository,
          catalog: pro,
          accountName: 'Awa Kouassi',
          onExit: () {},
          onMine: () {},
          onOpen: (_) {},
        ),
      );
      await requests.fill(
        t,
        'requestDescription',
        'Je souhaite un entretien complet de mon aquarium.',
      );
      await requests.choose(
        t,
        'requestCategory',
        'Autre / Je ne sais pas quelle catégorie choisir',
      );
      await requests.fill(t, 'requestServiceDetail', 'Entretien d’un aquarium');
      await requests.tapForm(
        t,
        find.byKey(const ValueKey('chooseRequestZones')),
      );
      await fixtures.tap(t, find.text('Cocody').last);
      await fixtures.tap(t, find.text('Plateau').last);
      await capture(t, 'selection-zones');
      await fixtures.tap(t, find.text('Confirmer'));
      await Scrollable.ensureVisible(
        t.element(find.byKey(const ValueKey('requestServiceDetail'))),
        alignment: .4,
      );
      await t.pumpAndSettle();
      await capture(t, 'besoin-non-classe');
      await requests.tapForm(t, find.text('Vérifier ma demande'));
      expect(find.text('Vérifie avant publication'), findsOneWidget);
      expect(find.text('Cocody · Plateau'), findsOneWidget);
      expect(find.text('Entretien d’un aquarium'), findsOneWidget);
      await capture(t, 'apercu-multi-zone');
      await requests.tapForm(t, find.text('Publier ma demande'));
      expect(repository.publishedDraft?.zoneIds, ['cocody', 'plateau']);
      expect(repository.publishedDraft?.specialtyId, '');
      expect(
        repository.publishedDraft?.serviceDetail,
        'Entretien d’un aquarium',
      );
      await t.pumpWidget(const SizedBox());
      await pro.changes.close();
      await pro.docChanges.close();
      await repository.changes.close();
    },
  );
  testWidgets(
    'account avatar uploads without a professional account and reuses existing photo',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await bitmap());
      final repository = AvatarFake()..value = const PersonalAvatarState();
      await page(
        t,
        Center(
          child: AccountIdentityAvatar(
            repository: repository,
            initials: 'AK',
            picker: () async => AccountPhotoSelection(bytes, 'image/png'),
          ),
        ),
      );
      await fixtures.tap(
        t,
        find.byKey(const ValueKey('accountIdentityAvatar')),
      );
      expect(find.text('Ma photo de compte'), findsOneWidget);
      await fixtures.tap(t, find.text('Choisir une photo'));
      await t.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          t.element(find.byType(PersonalAvatarEditor)),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, 'compte-photo-selection-directe');
      await fixtures.tap(t, find.text('Utiliser cette photo'));
      expect(repository.uploads, 1);
      expect(repository.value.published, isTrue);
      expect(find.byType(PersonalAvatarEditor), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      await fixtures.tap(
        t,
        find.byKey(const ValueKey('accountIdentityAvatar')),
      );
      expect(find.text('Changer ma photo'), findsOneWidget);
      expect(find.text('Utiliser cette photo'), findsNothing);
      expect(repository.uploads, 1);
      await capture(t, 'compte-photo-existante-reutilisee');
      await fixtures.tap(t, find.text('Supprimer ma photo'));
      expect(repository.removed, 1);
      expect(find.byType(Image), findsNothing);
      expect(find.text('AK'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'existing unpublished photo is reused without selecting or uploading a file',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await bitmap());
      final repository = AvatarFake()
        ..value = PersonalAvatarState(
          hasPhoto: true,
          published: false,
          preview: bytes,
        );
      await page(
        t,
        ListView(
          children: [
            PersonalAvatarEditor(
              repository: repository,
              picker: () async => throw StateError('Picker must not open'),
            ),
          ],
        ),
      );
      await fixtures.tap(t, find.text('Utiliser cette photo'));
      expect(repository.uploads, 0);
      expect(repository.saves, 1);
      expect(repository.value.published, isTrue);
      expect(repository.value.preview, bytes);
    },
  );
  testWidgets(
    'account identity is editable for clients and unfinished professional dossiers',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await bitmap());
      final repository = AvatarFake();
      for (final status in [
        ProfessionalStatus.none,
        ProfessionalStatus.draft,
      ]) {
        repository.value = status == ProfessionalStatus.none
            ? PersonalAvatarState(
                hasPhoto: true,
                published: true,
                preview: bytes,
              )
            : const PersonalAvatarState();
        await page(
          t,
          AccountScreen(
            user: const FoundiUser(
              id: 'fixture',
              displayName: 'Les délices',
              email: 'fixture@example.test',
              emailVerified: true,
              hasPassword: true,
              hasGoogle: false,
              profile: AccountProfile(fullName: 'Les délices'),
            ),
            professional: ProfessionalProfile(
              status: status,
              activity: const ProfessionalActivity(
                businessName: "les délices de l’artisane",
                description:
                    'Je confectionne des mignardises (crêpes, gâteaux etc…)',
              ),
            ),
            avatarRepository: repository,
            professionalSpace: false,
            onSpaces: () {},
            onDossier: () {},
            onActivity: () {},
            onPersonal: () {},
          ),
        );
        expect(
          find.byKey(const ValueKey('accountIdentityAvatar')),
          findsOneWidget,
        );
        if (status == ProfessionalStatus.none) {
          await t.runAsync(
            () => precacheImage(
              MemoryImage(bytes),
              t.element(find.byType(AccountIdentityAvatar)),
            ),
          );
          await t.pumpAndSettle();
        }
        await capture(
          t,
          status == ProfessionalStatus.none
              ? 'compte-client-photo-identite'
              : 'compte-dossier-avatar-cliquable',
        );
        await fixtures.tap(
          t,
          find.byKey(const ValueKey('accountIdentityAvatar')),
        );
        expect(find.text('Ma photo de compte'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'approved professional portrait opens the shared account photo editor',
    (t) async {
      late Uint8List bytes;
      await t.runAsync(() async => bytes = await bitmap());
      final repository = AvatarFake()
        ..value = PersonalAvatarState(
          hasPhoto: true,
          published: true,
          preview: bytes,
        );
      final profile = ProfessionalShowcase(
        name: 'Les délices de l’artisane',
        trade: 'Pâtisserie',
        portrait: ShowcasePhoto(bytes),
      );
      final pro = showcase.ShowcasePro(showcase: profile);
      await page(
        t,
        AccountScreen(
          user: fixtures.account(),
          professional: const ProfessionalProfile(
            status: ProfessionalStatus.approved,
          ),
          avatarRepository: repository,
          showcaseRepository: pro,
          professionalSpace: true,
          onSpaces: () {},
          onDossier: () {},
          onActivity: () {},
          onPersonal: () {},
        ),
      );
      await t.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          t.element(find.byType(ProfessionalShowcaseHeader)),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, 'compte-pro-photo-commune');
      final portrait = find
          .descendant(
            of: find.byType(ProfessionalShowcaseHeader),
            matching: find.byType(Image),
          )
          .first;
      await fixtures.tap(t, portrait);
      expect(find.text('Ma photo de compte'), findsOneWidget);
      expect(find.text('Changer ma photo'), findsOneWidget);
      expect(repository.uploads, 0);
      await t.pumpWidget(const SizedBox());
      await pro.changes.close();
      await pro.docChanges.close();
    },
  );
  test(
    'legacy zones and positive unknown catalogue reference remain compatible',
    () {
      final old = FoundiRequest.fromMap('old', {
        'title': 'Besoin',
        'description': 'Description',
        'categoryLabel': 'Services',
        'zoneId': 'cocody',
        'zoneLabel': 'Cocody',
        'status': 'published',
      });
      expect(old.searchZoneIds, ['cocody']);
      expect(const ExplorerFilters(zoneId: 'cocody').matches(old), isTrue);
      final multi = FoundiRequest.fromMap('new', {
        'title': 'Besoin',
        'description': 'Description',
        'categoryLabel': 'Services',
        'zoneId': 'cocody',
        'zoneIds': ['cocody', 'plateau'],
        'zoneLabel': 'Cocody',
        'zoneLabels': ['Cocody', 'Plateau'],
        'status': 'published',
      });
      expect(const ExplorerFilters(zoneId: 'plateau').matches(multi), isTrue);
      expect(multi.zoneLabel, 'Cocody · Plateau');
    },
  );
}
