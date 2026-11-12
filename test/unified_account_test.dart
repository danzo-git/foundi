import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/notifications/presentation/notification_views.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/professional/presentation/professional_profile_widgets.dart';

import 'notifications_v9_test.dart' show InboxFake;
import 'professional_showcase_test.dart' show ShowcasePro;
import 'proposals_v7_test.dart' as proposals;
import 'widget_test.dart' as fixtures;

const captureEnabled = bool.fromEnvironment('UNIFIED_ACCOUNT_CAPTURE');
const captureKey = ValueKey('unifiedAccountCapture');

ProfessionalShowcase fixtureShowcase() {
  final photo = ShowcasePhoto(
    File('functions/test/fixtures/photo.png').readAsBytesSync(),
  );
  return ProfessionalShowcase(
    name: 'Atelier Test',
    trade: 'Menuiserie',
    area: 'Zone de test',
    bio: 'Meubles et rangements sur mesure.',
    portrait: photo,
    cover: photo,
    gallery: [photo, photo],
  );
}

class AccountPro extends ShowcasePro {
  AccountPro({super.profile, super.showcase});
  bool failRead = false;

  @override
  Future<ProfessionalShowcase?> readShowcase({String? proposalId}) async {
    if (failRead) throw const AuthFailure('Profil indisponible.');
    return super.readShowcase(proposalId: proposalId);
  }
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
    find.byKey(captureKey),
  );
  // Repaint retained layers so each export includes the header and navigation.
  boundary.reassemble();
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/unified-account-captures')
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
    'the approved account keeps its saved profile and selected section in both spaces',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = AccountPro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
        showcase: fixtureShowcase(),
      );
      final requests = proposals.Proposals();
      try {
        await fixtures.flow(t, auth, pro, () async {
          await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
          expect(find.text('Atelier Test'), findsOneWidget);
          expect(find.text('Mon profil professionnel'), findsNothing);
          expect(find.text('Vue d’ensemble'), findsNothing);
          expect(find.byType(ProfessionalShowcaseHeader), findsOneWidget);
          expect(pro.reads, [null]);
          await fixtures.tap(t, find.byKey(const ValueKey('accountSection-2')));
          expect(find.byType(ShowcaseGallery), findsOneWidget);
          await fixtures.tap(t, find.text('Changer d’espace  ›'));
          await fixtures.tap(t, find.text('Espace professionnel'));
          await fixtures.tap(t, find.byKey(const ValueKey('confirmSpace')));
          expect(find.text('Mon compte'), findsOneWidget);
          expect(find.text('Atelier Test'), findsOneWidget);
          expect(pro.reads, [null]);
          expect(find.text('Gérer les réalisations'), findsOneWidget);
          await fixtures.tap(t, find.byTooltip('Modifier la photo de profil'));
          expect(find.text('Modifier mon profil'), findsOneWidget);
          expect(find.text('Photo de profil'), findsOneWidget);
          await t.pageBack();
          await t.pumpAndSettle();
          await fixtures.tap(t, find.text('Gérer les réalisations'));
          expect(find.text('Ajouter une réalisation'), findsOneWidget);
          await t.pageBack();
          await t.pumpAndSettle();
          expect(auth.signOuts, 0);
          expect(auth.modeWrites, 0);
          await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
          await fixtures.tap(t, find.text('Informations professionnelles'));
          expect(find.text('Mon compte'), findsOneWidget);
          expect(find.text('Nom commercial · Awa Services'), findsOneWidget);
        }, requests: requests);
      } finally {
        await requests.changes.close();
      }
    },
  );

  testWidgets(
    'profile loading errors keep editing disabled until a successful retry',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = AccountPro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
        showcase: fixtureShowcase(),
      )..failRead = true;
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
        expect(
          find.text('Le profil professionnel est indisponible.'),
          findsOneWidget,
        );
        expect(find.text('Modifier le profil'), findsNothing);
        expect(find.byTooltip('Modifier la photo de profil'), findsNothing);
        pro.failRead = false;
        await fixtures.tap(t, find.text('Réessayer le profil'));
        expect(find.text('Atelier Test'), findsOneWidget);
        expect(find.text('Modifier le profil'), findsOneWidget);
        expect(pro.showcase!.gallery.length, 2);
      });
    },
  );

  testWidgets(
    'personal email stays private and settings reuse the existing password reset',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro();
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
        expect(find.text(auth.user!.email), findsNothing);
        await fixtures.tap(t, find.text('Informations personnelles'));
        final email = t.widget<TextFormField>(
          find.byKey(const ValueKey('accountEmail')),
        );
        expect(
          t
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const ValueKey('accountEmail')),
                  matching: find.byType(TextField),
                ),
              )
              .readOnly,
          isTrue,
        );
        expect(email.initialValue, auth.user!.email);
        await t.pageBack();
        await t.pumpAndSettle();
        await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
        await fixtures.tap(t, find.text('Sécurité'));
        await fixtures.tap(t, find.text('Réinitialiser mon mot de passe'));
        expect(find.text(auth.user!.email), findsOneWidget);
        await fixtures.tap(t, find.text('Envoyer le lien'));
        expect(auth.resets, 1);
      });
    },
  );

  testWidgets(
    'approval revocation removes the showcase and edit actions immediately',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = AccountPro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
        showcase: fixtureShowcase(),
      );
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
        expect(
          find.descendant(
            of: find.byType(ProfessionalShowcaseHeader),
            matching: find.text('Professionnel vérifié'),
          ),
          findsOneWidget,
        );
        pro.emit(
          const ProfessionalProfile(
            status: ProfessionalStatus.suspended,
            activity: fixtures.activity,
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Professionnel vérifié'), findsNothing);
        expect(find.byType(ProfessionalShowcaseHeader), findsNothing);
        expect(find.text('Modifier le profil'), findsNothing);
        expect(find.text('Suivre mon dossier'), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const ValueKey('currentSpace'))).data,
          'Client',
        );
      });
    },
  );

  testWidgets(
    'approved account stays usable at 320px with large text and unavailable images',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final unavailable = ShowcasePhoto(Uint8List.fromList([1, 2, 3]));
      final pro = AccountPro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
        showcase: ProfessionalShowcase(
          name: 'Atelier de menuiserie et de création',
          trade: 'Menuiserie',
          portrait: unavailable,
          cover: unavailable,
          gallery: [unavailable],
        ),
      );
      await fixtures.flow(t, auth, pro, () async {
        t.view.physicalSize = const Size(320, 780);
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        try {
          await t.pumpAndSettle();
          await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
          await fixtures.tap(t, find.byKey(const ValueKey('accountSection-1')));
          await fixtures.tap(t, find.byKey(const ValueKey('accountSection-2')));
          await fixtures.tap(t, find.text('Informations personnelles'));
          expect(find.text('Tes informations'), findsOneWidget);
          await t.pageBack();
          await t.pumpAndSettle();
          await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
          expect(find.text('Compte et préférences'), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          t.platformDispatcher.clearTextScaleFactorTestValue();
        }
      });
    },
  );

  for (final (status, name) in [
    (ProfessionalStatus.approved, '01-professionnel-approuve'),
    (ProfessionalStatus.none, '02-compte-client'),
    (ProfessionalStatus.pending, '03-professionnel-en-attente'),
  ]) {
    testWidgets(
      'unified account state $status renders its real fields and permitted actions',
      (t) async {
        final auth = fixtures.FakeAuth(user: fixtures.account());
        final showcase = status == ProfessionalStatus.approved && captureEnabled
            ? ProfessionalShowcase.fromMap(
                jsonDecode(
                      File(
                        '.dart_tool/unified-account-capture-public-profile.json',
                      ).readAsStringSync(),
                    )
                    as Map<String, dynamic>,
              )
            : fixtureShowcase();
        final activity = status == ProfessionalStatus.approved && captureEnabled
            ? ProfessionalActivity(
                businessName: showcase.name,
                description: showcase.bio,
              )
            : status == ProfessionalStatus.none
            ? const ProfessionalActivity()
            : fixtures.activity;
        final pro = AccountPro(
          profile: ProfessionalProfile(status: status, activity: activity),
          showcase: showcase,
        );
        final requests = proposals.Proposals();
        final inbox = InboxFake();
        final intent = ValueNotifier<NotificationIntent?>(null);
        t.view.physicalSize = const Size(430, 932);
        t.view.devicePixelRatio = 1;
        try {
          await t.pumpWidget(
            RepaintBoundary(
              key: captureKey,
              child: NotificationScope(
                repository: inbox,
                intent: intent,
                child: FoundiApp(
                  authRepository: auth,
                  professionalRepository: pro,
                  requestRepository: requests,
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
          expect(find.text('Mon compte'), findsOneWidget);
          if (status == ProfessionalStatus.approved) {
            expect(find.byType(ProfessionalShowcaseHeader), findsOneWidget);
            expect(find.text(showcase.name), findsOneWidget);
            expect(pro.reads, [null]);
          } else {
            expect(find.byType(ProfessionalShowcaseHeader), findsNothing);
            expect(find.text('Professionnel vérifié'), findsNothing);
            expect(
              find.byKey(const ValueKey('accountSection-0')),
              findsNothing,
            );
            expect(pro.reads, isEmpty);
          }
          await capture(t, name);
          if (status == ProfessionalStatus.none) {
            await fixtures.tap(t, find.text('Devenir professionnel'));
            expect(pro.profile.status, ProfessionalStatus.draft);
          } else if (status == ProfessionalStatus.pending) {
            await fixtures.tap(t, find.text('Suivre mon dossier'));
            expect(
              find.text('Nous examinons ton profil professionnel.'),
              findsOneWidget,
            );
            await fixtures.tap(t, find.text('Retour à mon espace'));
            expect(find.text('Mon compte'), findsOneWidget);
          } else if (captureEnabled) {
            await t.ensureVisible(find.byKey(const ValueKey('currentSpace')));
            await capture(t, '04-professionnel-gestion');
          }
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          await auth.changes.close();
          await pro.changes.close();
          await pro.docChanges.close();
          await requests.changes.close();
          await inbox.close();
          intent.dispose();
          t.view.reset();
        }
      },
    );
  }
}
