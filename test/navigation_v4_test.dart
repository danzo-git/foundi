import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'widget_test.dart' as fixtures;

Future<void> captureV4(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('V4_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/v4-preview')..createSync(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('V4_CAPTURE')) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final bold = File('C:/Windows/Fonts/segoeuib.ttf');
    if (bold.existsSync()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(await bold.readAsBytes())),
          ))
          .load();
    }
    final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
    if (emoji.existsSync()) {
      await (FontLoader('Noto Color Emoji')..addFont(
            Future.value(ByteData.sublistView(await emoji.readAsBytes())),
          ))
          .load();
    }
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (font.existsSync()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(await font.readAsBytes())),
          ))
          .load();
    }
  });
  testWidgets(
    'V4 client navigation keeps Publish central and unavailable modules have no side effects',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro();
      await fixtures.flow(t, auth, pro, () async {
        t.view.physicalSize = const Size(390, 844);
        t.view.padding = const FakeViewPadding(top: 24);
        t.view.viewPadding = const FakeViewPadding(top: 24);
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
        final bar = find.byKey(const ValueKey('nav-2'));
        expect(t.getCenter(bar).dx, closeTo(195, 1));
        await captureV4(t, '01-client-home');
        for (final index in [1, 2, 3]) {
          await fixtures.tap(t, find.byKey(ValueKey('nav-$index')));
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.text('Bientôt disponible'),
            ),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
        }
        expect(auth.modeWrites, 0);
        expect(auth.signOuts, 0);
        expect(pro.accessChecks, 0);
        expect(pro.profile.status, ProfessionalStatus.none);
        expect(t.takeException(), isNull);
      });
    },
  );
  testWidgets(
    'V4 approved account, settings and space selector preserve the same session',
    (t) async {
      final auth = fixtures.FakeAuth(
        user: fixtures.account(
          data: fixtures.profile.copyWith(preferredMode: 'professional'),
        ),
      );
      final pro = fixtures.FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: fixtures.activity,
        ),
      );
      await fixtures.flow(t, auth, pro, () async {
        t.view.physicalSize = const Size(390, 844);
        t.view.padding = const FakeViewPadding(top: 24);
        t.view.viewPadding = const FakeViewPadding(top: 24);
        await t.pumpAndSettle();
        await captureV4(t, '02-professional-home');
        await fixtures.tap(t, find.byKey(const ValueKey('nav-4')));
        await captureV4(t, '03-professional-account');
        expect(find.text('Un compte, deux espaces'), findsNothing);
        expect(find.text('CGU et confidentialité'), findsNothing);
        expect(find.text('Se déconnecter'), findsNothing);
        await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
        await captureV4(t, '04-settings');
        expect(find.text('Informations personnelles'), findsOneWidget);
        await fixtures.tap(t, find.byKey(const ValueKey('settingsBack')));
        expect(find.text('Mon compte'), findsOneWidget);
        await fixtures.tap(t, find.text('Changer d’espace  ›'));
        await captureV4(t, '05-space-selector');
        await fixtures.tap(t, find.text('Espace client'));
        await fixtures.tap(t, find.byKey(const ValueKey('confirmSpace')));
        expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
        expect(find.text('Bienvenue côté client'), findsOneWidget);
        await captureV4(t, '06-client-after-switch');
        expect(auth.user!.id, 'uid');
        expect(auth.user!.profile.preferredMode, 'professional');
        expect(auth.modeWrites, 0);
        expect(auth.signOuts, 0);
        expect(pro.accessChecks, 0);
        expect(t.takeException(), isNull);
      });
    },
  );
  for (final status in [
    ProfessionalStatus.draft,
    ProfessionalStatus.pending,
    ProfessionalStatus.needsChanges,
    ProfessionalStatus.rejected,
    ProfessionalStatus.suspended,
  ]) {
    testWidgets(
      'V4 $status retains client space and dossier access despite a forged mode preference',
      (t) async {
        final auth = fixtures.FakeAuth(
          user: fixtures.account(
            data: fixtures.profile.copyWith(preferredMode: 'professional'),
          ),
        );
        final pro = fixtures.FakePro(
          profile: ProfessionalProfile(
            status: status,
            activity: fixtures.activity,
          ),
        );
        await fixtures.flow(t, auth, pro, () async {
          expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
          expect(find.byKey(const ValueKey('professionalHome')), findsNothing);
          await fixtures.tap(t, find.byKey(const ValueKey('nav-4')));
          expect(
            t.widget<Text>(find.byKey(const ValueKey('currentSpace'))).data,
            'Client',
          );
          if (status == ProfessionalStatus.pending) {
            t.view.physicalSize = const Size(390, 844);
            t.view.padding = const FakeViewPadding(top: 24);
            t.view.viewPadding = const FakeViewPadding(top: 24);
            await t.pumpAndSettle();
            await captureV4(t, '09-pending-account');
          }
          await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
          await fixtures.tap(t, find.text('Gérer mes espaces'));
          expect(find.text('Choisir mon espace'), findsNothing);
          expect(find.byKey(const ValueKey('professionalHome')), findsNothing);
          expect(auth.modeWrites, 0);
          expect(pro.accessChecks, 0);
        });
      },
    );
  }
  testWidgets(
    'V4 revocation while the selector is open cannot enter the professional interface',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro(
        profile: const ProfessionalProfile(status: ProfessionalStatus.approved),
      );
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.byKey(const ValueKey('homeSpaceSelector')));
        await fixtures.tap(t, find.text('Espace professionnel'));
        pro.emit(
          const ProfessionalProfile(status: ProfessionalStatus.suspended),
        );
        await t.pumpAndSettle();
        expect(find.text('Choisir mon espace'), findsNothing);
        expect(find.byKey(const ValueKey('professionalHome')), findsNothing);
        expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
        expect(auth.modeWrites, 0);
      });
    },
  );
  testWidgets(
    'V4 settings retain existing personal info, legal route and sign out',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro();
      await fixtures.flow(t, auth, pro, () async {
        await fixtures.tap(t, find.byKey(const ValueKey('nav-4')));
        await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
        await fixtures.tap(t, find.text('Informations personnelles'));
        await fixtures.fill(t, 'fullName', 'Awa Actualisée');
        await fixtures.tap(t, find.text('Enregistrer'));
        expect(auth.saved!.fullName, 'Awa Actualisée');
        await fixtures.tap(t, find.text('Confidentialité et CGU'));
        expect(find.text('Tes conditions d’utilisation'), findsOneWidget);
        await t.pageBack();
        await t.pumpAndSettle();
        await fixtures.tap(t, find.byKey(const ValueKey('settingsSignOut')));
        expect(auth.signOuts, 1);
        expect(find.byKey(const ValueKey('submitAuth')), findsOneWidget);
      });
    },
  );
  testWidgets(
    'V4 small screen and large text keep settings and central Publish accessible',
    (t) async {
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.pending,
          activity: fixtures.activity,
        ),
      );
      await fixtures.flow(t, auth, pro, () async {
        t.view.physicalSize = const Size(320, 568);
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        try {
          await t.pumpAndSettle();
          await fixtures.tap(t, find.byKey(const ValueKey('nav-4')));
          await fixtures.tap(t, find.byKey(const ValueKey('openSettings')));
          await t.ensureVisible(find.byKey(const ValueKey('settingsSignOut')));
          expect(find.byKey(const ValueKey('nav-2')), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          t.platformDispatcher.clearTextScaleFactorTestValue();
        }
      });
    },
  );
}
