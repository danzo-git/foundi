import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/navigation/presentation/space_widgets.dart';
import 'package:foundi/features/requests/domain/request_photo_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/request_composer.dart';
import 'package:foundi/features/requests/presentation/request_photos.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';

import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as fixtures;

const captureEnabled = bool.fromEnvironment('REQUEST_PHOTOS_CAPTURE');
const captureKey = ValueKey('requestPhotoCapture');
const fixtureDirectory = String.fromEnvironment(
  'REQUEST_PHOTOS_FIXTURE_DIR',
  defaultValue: 'functions/test/fixtures',
);

Uint8List fixture(String extension) =>
    File('$fixtureDirectory/photo.$extension').readAsBytesSync();

RequestPhotoSelection photoSelection(String extension) {
  final bytes = fixture(extension);
  return RequestPhotoSelection(bytes.length, () async => bytes);
}

class PhotoRequests extends requests.FakeRequests
    implements RequestPhotoRepository {
  final uploaded = <String, Uint8List>{};
  final discarded = <String>[];
  int attempts = 0;
  int reads = 0;
  int? failUploadAt;
  Completer<Uint8List>? pendingRead;

  @override
  Future<bool> uploadRequestPhoto(
    String requestId,
    LocalRequestPhoto photo,
  ) async {
    if (items.any((request) => request.id == requestId)) return true;
    if (++attempts == failUploadAt) {
      throw const AuthFailure('Envoi interrompu.');
    }
    uploaded[photo.id] = photo.bytes;
    return false;
  }

  @override
  Future<void> discardRequestPhotos(String requestId, List<String> ids) async {
    for (final id in ids) {
      discarded.add(id);
      uploaded.remove(id);
    }
  }

  @override
  Future<Uint8List> readRequestPhoto(String requestId, String photoId) async {
    reads++;
    if (pendingRead case final pending?) return pending.future;
    return uploaded[photoId]!;
  }
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captureEnabled) return;
  FocusManager.instance.primaryFocus?.unfocus();
  final formHeader = find.text('Nouvelle demande');
  if (formHeader.evaluate().isNotEmpty) {
    Scrollable.of(t.element(formHeader)).position.jumpTo(0);
  }
  await t.pumpAndSettle();
  final images = find.byType(Image);
  if (images.evaluate().isNotEmpty) {
    final context = t.element(images.first);
    final providers = t.widgetList<Image>(images).map((image) => image.image);
    await t.runAsync(() async {
      await Future.wait(
        providers.map((provider) => precacheImage(provider, context)),
      ).timeout(const Duration(seconds: 10));
    });
    await t.pumpAndSettle();
  }
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/request-photos-preview')
      ..createSync(recursive: true);
    await File('${dir.path}/$name.png').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> selectPhotos(WidgetTester t) async {
  final finder = find.ancestor(
    of: find.text('Ajouter des photos (facultatif)'),
    matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
  );
  final button = t.widget<OutlinedButton>(finder);
  await t.runAsync(button.onPressed! as Future<void> Function());
  await t.pumpAndSettle();
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
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  testWidgets(
    'zero photos uses the original publication payload and skips media calls',
    (t) async {
      final repo = PhotoRequests();
      await requests.runFlow(t, repo, (auth, pro) async {
        await requests.preview(t);
        await requests.tapForm(t, find.text('Publier ma demande'));
        expect(find.text('C’est publié !'), findsOneWidget);
        expect(repo.attempts, 0);
        expect(repo.discarded, isEmpty);
        expect(repo.publishIds, ['request-1']);
        expect(repo.publishedDraft!.toMap(), isNot(contains('photoIds')));
      });
    },
  );

  testWidgets(
    'validates JPEG PNG WebP and rejects HEIC, PDF, corrupt and oversized files',
    (t) async {
      await t.runAsync(() async {
        for (final (extension, mime) in [
          ('jpeg', 'image/jpeg'),
          ('png', 'image/png'),
          ('webp', 'image/webp'),
        ]) {
          expect(
            (await validateRequestPhoto(photoSelection(extension))).contentType,
            mime,
          );
        }
        final invalid = [
          Uint8List.fromList([
            0,
            0,
            0,
            20,
            102,
            116,
            121,
            112,
            104,
            101,
            105,
            99,
          ]),
          File('functions/test/fixtures/document.pdf').readAsBytesSync(),
          fixture('png').sublist(0, 16),
        ];
        for (final bytes in invalid) {
          await expectLater(
            validateRequestPhoto(
              RequestPhotoSelection(bytes.length, () async => bytes),
            ),
            throwsA(isA<AuthFailure>()),
          );
        }
        await expectLater(
          validateRequestPhoto(
            RequestPhotoSelection(maxRequestPhotoBytes + 1, () async {
              throw StateError(
                'Le fichier trop lourd ne doit pas être chargé.',
              );
            }),
          ),
          throwsA(isA<AuthFailure>()),
        );
      });
    },
  );

  testWidgets(
    'selects one to three photos, removes, previews, retries and opens the published gallery',
    (t) async {
      final repo = PhotoRequests();
      final pro = fixtures.FakePro();
      var selection = <RequestPhotoSelection>[];
      FoundiRequest? published;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = captureEnabled
          ? const Size(390, 844)
          : const Size(320, 640);
      if (!captureEnabled) t.platformDispatcher.textScaleFactorTestValue = 1.7;
      try {
        await t.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                scaffoldBackgroundColor: FoundiUi.background,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: FoundiUi.green,
                  primary: FoundiUi.green,
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              home: StatefulBuilder(
                builder: (context, update) => Scaffold(
                  body: SafeArea(
                    child: published == null
                        ? RequestComposer(
                            repository: repo,
                            catalog: pro,
                            onExit: () {},
                            onMine: () {},
                            onOpen: (request) => update(() {
                              published = request;
                            }),
                            photoPicker: () async => selection,
                          )
                        : RequestDetailView(
                            repository: repo,
                            id: published!.id,
                            onBack: () {},
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Jusqu’à 3 photos · 0/3'), findsOneWidget);
        await capture(t, '01-zero-photo');
        const description = 'Réparer un meuble en bois dans le salon.';
        await requests.fill(t, 'requestDescription', description);
        selection = [photoSelection('jpeg')];
        await selectPhotos(t);
        expect(find.text('Jusqu’à 3 photos · 1/3'), findsOneWidget);
        await capture(t, '02-une-photo');
        selection = [photoSelection('png')];
        await selectPhotos(t);
        expect(find.text('Jusqu’à 3 photos · 2/3'), findsOneWidget);
        await capture(t, '03-deux-photos');
        selection = [photoSelection('png'), photoSelection('webp')];
        await selectPhotos(t);
        expect(find.textContaining('réduis ta sélection'), findsOneWidget);
        expect(find.text('Jusqu’à 3 photos · 2/3'), findsOneWidget);
        selection = [photoSelection('webp')];
        await selectPhotos(t);
        expect(find.text('Jusqu’à 3 photos · 3/3'), findsOneWidget);
        await capture(t, '04-trois-photos');
        await requests.tapForm(t, find.byTooltip('Retirer la photo 2'));
        expect(find.text('Jusqu’à 3 photos · 2/3'), findsOneWidget);
        await capture(t, '05-photo-retiree');
        expect(repo.attempts, 0);
        await requests.chooseReferences(t);
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        expect(find.text('Photos de la demande'), findsOneWidget);
        expect(repo.attempts, 0);
        await capture(t, '06-verification');
        repo.failUploadAt = 2;
        await requests.tapForm(t, find.text('Publier ma demande'));
        expect(find.textContaining('Envoi interrompu'), findsOneWidget);
        expect(repo.publishIds, isEmpty);
        await requests.tapForm(t, find.text('Modifier'));
        expect(find.text(description), findsOneWidget);
        await requests.tapForm(t, find.byTooltip('Retirer la photo 2'));
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        await requests.tapForm(t, find.text('Publier ma demande'));
        expect(repo.publishIds, ['request-1']);
        expect(repo.items.single.photoIds, hasLength(1));
        expect(repo.discarded, hasLength(1));
        expect(repo.uploaded, hasLength(1));
        await requests.tapForm(t, find.text('Voir ma demande'));
        expect(find.text('Photos de la demande'), findsOneWidget);
        await capture(t, '07-detail-publie');
        final zoom = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Agrandir la photo 1',
        );
        await requests.tapForm(t, zoom);
        expect(find.text('Photo 1'), findsOneWidget);
        await fixtures.tap(t, find.text('Fermer'));
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        await repo.changes.close();
        await pro.changes.close();
        await pro.docChanges.close();
        t.view.reset();
        t.platformDispatcher.clearTextScaleFactorTestValue();
      }
    },
  );

  testWidgets(
    'guest sees text without a photo request and signed-in detail can retry a refusal',
    (t) async {
      final repo = PhotoRequests();
      final photo = 'a' * 32;
      repo.uploaded[photo] = fixture('png');
      final request = await repo.publish(
        'test-request',
        RequestDraft(
          categoryId: 'c',
          specialtyId: '',
          zoneId: 'z',
          title: 'Réparer un meuble',
          description: 'Réparer un meuble dans la chambre.',
          photoIds: [photo],
        ),
      );
      Widget view({required bool allowed}) => MaterialApp(
        home: Scaffold(
          body: RequestDetailView(
            key: ValueKey(allowed),
            repository: repo,
            id: request.id,
            onBack: () {},
            canReadPhotos: allowed,
          ),
        ),
      );
      try {
        await t.pumpWidget(view(allowed: false));
        await t.pumpAndSettle();
        expect(find.text(request.description), findsOneWidget);
        expect(find.textContaining('Photos réservées'), findsOneWidget);
        expect(repo.reads, 0);
        final pending = Completer<Uint8List>();
        repo.pendingRead = pending;
        await t.pumpWidget(view(allowed: true));
        await t.pump();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is CircularProgressIndicator &&
                widget.semanticsLabel == 'Chargement de la photo 1',
          ),
          findsOneWidget,
        );
        pending.completeError(const AuthFailure('Accès aux photos refusé.'));
        repo.pendingRead = null;
        await t.pumpAndSettle();
        expect(find.text('Accès aux photos refusé.'), findsOneWidget);
        await requests.tapForm(t, find.text('Réessayer la photo 1'));
        expect(find.text('Accès aux photos refusé.'), findsNothing);
        expect(repo.reads, 2);
      } finally {
        await t.pumpWidget(const SizedBox());
        await repo.changes.close();
      }
    },
  );
}
