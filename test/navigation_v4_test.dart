import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/navigation/presentation/space_widgets.dart';
import 'package:foundi/features/notifications/domain/notification_repository.dart';
import 'package:foundi/features/notifications/presentation/notification_views.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'notifications_v9_test.dart' show InboxFake;
import 'opportunities_v6_test.dart' as opportunities;
import 'requests_v5_test.dart' show FakeRequests;
import 'widget_test.dart' as fixtures;

Future<void> captureV4(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('V4_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/v4-preview')..createSync(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void expectTabs(WidgetTester t, List<String> labels) {
  final bar = find.byType(FoundiBottomBar);
  for (final (index, label) in labels.indexed) {
    expect(
      find.descendant(
        of: find.byKey(ValueKey('nav-$index')),
        matching: find.text(label),
      ),
      findsOneWidget,
    );
  }
  expect(
    find.descendant(of: bar, matching: find.byType(InkWell)),
    findsNWidgets(4),
  );
  expect(find.text('Accueil'), findsNothing);
  expect(t.widget<FoundiBottomBar>(bar).selectedIndex, 0);
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
  testWidgets('Client lands on Mes demandes with exactly four tabs', (t) async {
    final auth = fixtures.FakeAuth(user: fixtures.account());
    final pro = fixtures.FakePro();
    final requests = FakeRequests();
    await fixtures.flow(t, auth, pro, () async {
      expectTabs(t, ['Mes demandes', 'Explorer', 'Messages', 'Compte']);
      expect(find.byKey(const ValueKey('openPublication')), findsOneWidget);
      expect(find.text('Aucune demande pour le moment'), findsOneWidget);
      await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
      expect(find.text('Explorer les demandes'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('openPublication')), findsOneWidget);
      expect(auth.modeWrites, 0);
      expect(auth.signOuts, 0);
    }, requests: requests);
    await requests.changes.close();
  });

  testWidgets(
    'Professional Explorer starts on Pour moi and can show all requests',
    (t) async {
      final auth = fixtures.FakeAuth(
        user: fixtures.account(
          data: fixtures.profile.copyWith(preferredMode: 'professional'),
        ),
      );
      final pro = opportunities.Catalog(profile: opportunities.approved);
      final requests = opportunities.ExplorerRequests();
      final inbox = InboxFake();
      final intent = ValueNotifier<NotificationIntent?>(null);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      t.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      t.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        intent.dispose();
        await auth.changes.close();
        await pro.changes.close();
        await pro.docChanges.close();
        await requests.changes.close();
        await inbox.close();
        t.view.reset();
      });

      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture'),
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
      final personalized = find.widgetWithText(ChoiceChip, 'Pour moi');
      expectTabs(t, ['Explorer', 'Mes propositions', 'Messages', 'Compte']);
      expect(t.widget<ChoiceChip>(personalized).selected, isTrue);
      expect(requests.personalizedCalls, 1);
      if (const bool.fromEnvironment('V4_CAPTURE')) {
        await t.runAsync(
          () => precacheImage(
            const AssetImage('assets/branding/foundi-mark.png'),
            t.element(find.byType(FoundiBottomBar)),
          ),
        );
        await t.pumpAndSettle();
      }
      await captureV4(t, '02-explorer-professionnel');
      final emptyState = find.text('Aucune demande trouvée');
      await t.scrollUntilVisible(emptyState, 140);
      expect(emptyState, findsOneWidget);
      final allRequests = find.text('Voir toutes les demandes');
      await t.scrollUntilVisible(allRequests, 140);
      await t.pumpAndSettle();
      await fixtures.tap(t, allRequests);
      expect(t.widget<ChoiceChip>(personalized).selected, isFalse);
      expect(requests.lastFilters, isNotNull);
      await fixtures.tap(t, find.byKey(const ValueKey('spaceSelector')));
      await fixtures.tap(t, find.text('Espace client'));
      await fixtures.tap(t, find.byKey(const ValueKey('confirmSpace')));
      expectTabs(t, ['Mes demandes', 'Explorer', 'Messages', 'Compte']);
      expect(find.byKey(const ValueKey('openPublication')), findsOneWidget);
      await captureV4(t, '01-mes-demandes-client');

      t.view.physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await fixtures.tap(t, find.byKey(const ValueKey('spaceSelector')));
      await fixtures.tap(t, find.text('Espace professionnel'));
      await fixtures.tap(t, find.byKey(const ValueKey('confirmSpace')));
      expect(requests.personalizedCalls, 2);
      expect(t.takeException(), isNull);

      t.view.physicalSize = const Size(390, 844);
      t.platformDispatcher.clearTextScaleFactorTestValue();
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(personalized).selected, isTrue);
      requests.items.add(opportunities.row('linked'));
      inbox.target = const NotificationTarget('opportunity', 'linked');
      intent.value = const NotificationIntent(
        'uid',
        'opportunity-notification',
      );
      await t.pumpAndSettle();
      expect(find.text('Détail de la demande'), findsOneWidget);
      expect(inbox.reads, ['opportunity-notification']);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(t.widget<ChoiceChip>(personalized).selected, isTrue);
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
        await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
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
        expect(find.text('Espace Client'), findsOneWidget);
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
          expect(find.text('Espace Client'), findsOneWidget);
          expect(find.text('Espace Professionnel'), findsNothing);
          await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
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
          expect(find.text('Espace Professionnel'), findsNothing);
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
        await fixtures.tap(t, find.byKey(const ValueKey('spaceSelector')));
        await fixtures.tap(t, find.text('Espace professionnel'));
        pro.emit(
          const ProfessionalProfile(status: ProfessionalStatus.suspended),
        );
        await t.pumpAndSettle();
        expect(find.text('Choisir mon espace'), findsNothing);
        expect(find.text('Espace Professionnel'), findsNothing);
        expect(find.text('Espace Client'), findsOneWidget);
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
        await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
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
    'V4 small screen and large text keep settings and navigation accessible',
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
          await fixtures.tap(t, find.byKey(const ValueKey('nav-3')));
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
