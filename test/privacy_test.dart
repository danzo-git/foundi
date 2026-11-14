import 'package:flutter/services.dart';
import 'package:foundi/app.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/privacy/privacy_repository.dart';
import 'package:foundi/features/privacy/privacy_views.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/auth/presentation/legal_acceptance_screen.dart';
import 'widget_test.dart' as fixtures;

class PrivacyFake extends PrivacyRepository {
  bool requested = false, closed = false, fail = false;
  String state = 'queued';
  int calls = 0, retries = 0;
  @override
  bool get pending => requested && !closed;
  @override
  bool get hasPassword => true;
  @override
  bool get hasGoogle => true;
  @override
  Future<void> request({String? password, bool google = false}) async {
    calls++;
    if (fail) throw const AuthFailure('Identité non confirmée');
    requested = true;
    notifyListeners();
  }

  @override
  Future<DeletionStatus> status() async {
    if (fail) throw const AuthFailure('Suivi indisponible');
    return DeletionStatus(state, canRetry: state == 'retry');
  }

  @override
  Future<void> retry() async {
    retries++;
    state = 'queued';
  }

  @override
  Future<void> closeCompletedReceipt() async {
    if (state != 'completed') throw const AuthFailure('En cours');
    closed = true;
    notifyListeners();
  }

  @override
  Future<void> forgetLocalReceipt() async {
    closed = true;
    notifyListeners();
  }
}

class LegalFake extends fixtures.FakeAuth {
  int acceptances = 0;
  @override
  Future<LegalDocuments> loadLegalDocuments() async => const LegalDocuments(
    version: 'old',
    terms: 'Texte des CGU publiées',
    privacy: 'Texte de confidentialité publié',
  );
  @override
  Future<void> acceptLegal(String version) async {
    acceptances++;
  }
}

final boundary = GlobalKey();
Future<void> screen(WidgetTester t, Widget page) async {
  t.view.physicalSize = const Size(430, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final auth = fixtures.FakeAuth();
  await t.pumpWidget(FoundiApp(authRepository: auth));
  await t.pumpAndSettle();
  final theme = t.widget<MaterialApp>(find.byType(MaterialApp)).theme;
  await t.pumpWidget(const SizedBox.shrink());
  await auth.changes.close();
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: RepaintBoundary(key: boundary, child: page),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('PRIVACY_CAPTURE')) return;
  await t.runAsync(() async {
    final image =
        await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/sprint-2-captures/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'an unavailable receipt can be closed locally without cancelling or completing the server request',
    (t) async {
      final repo = PrivacyFake()
        ..requested = true
        ..fail = true;
      await screen(
        t,
        PrivacySessionGate(
          repository: repo,
          child: const Scaffold(body: Text('Accueil')),
        ),
      );
      await capture(t, 'app-suivi-indisponible');
      await t.tap(find.text('Quitter le suivi sur cet appareil'));
      await t.pumpAndSettle();
      await t.tap(find.text('Quitter ce suivi'));
      await t.pumpAndSettle();
      expect(find.text('Accueil'), findsOneWidget);
      expect(repo.state, 'queued');
      expect(repo.retries, 0);
    },
  );
  setUpAll(() async {
    if (!const bool.fromEnvironment('PRIVACY_CAPTURE')) return;
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
    'delete requires explicit confirmation and retains cancellation',
    (t) async {
      final repo = PrivacyFake();
      await screen(t, DeleteAccountScreen(repository: repo));
      await capture(t, 'app-suppression-confirmation');
      final button = find.widgetWithText(
        FilledButton,
        'Confirmer la suppression',
      );
      await t.scrollUntilVisible(
        button,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(button);
      await t.pump();
      expect(repo.calls, 0);
      expect(find.text('Annuler'), findsOneWidget);
      await t.scrollUntilVisible(
        find.byType(CheckboxListTile),
        -350,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      await t.scrollUntilVisible(
        button,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(button);
      await t.pumpAndSettle();
      expect(repo.calls, 1);
      expect(repo.pending, true);
    },
  );
  testWidgets('cancelled or failed identity never requests deletion', (
    t,
  ) async {
    final repo = PrivacyFake()..fail = true;
    await screen(t, DeleteAccountScreen(repository: repo));
    await t.scrollUntilVisible(
      find.byType(CheckboxListTile),
      -350,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.ensureVisible(find.text('Vérifier avec Google et supprimer'));
    await t.tap(find.text('Vérifier avec Google et supprimer'));
    await t.pumpAndSettle();
    expect(repo.pending, false);
    expect(find.text('Identité non confirmée'), findsOneWidget);
    await capture(t, 'app-verification-refusee');
  });
  testWidgets(
    'pending, retry and complete states are distinct and never inferred from failure',
    (t) async {
      final repo = PrivacyFake()..requested = true;
      await screen(t, DeletionStatusScreen(repository: repo));
      expect(find.text('Suppression en cours'), findsOneWidget);
      expect(find.text('Fermer le suivi sur cet appareil'), findsNothing);
      await capture(t, 'app-suppression-en-cours');
      repo.state = 'retry';
      await t.tap(find.text('Actualiser le suivi'));
      await t.pumpAndSettle();
      expect(find.text('Demander une reprise'), findsOneWidget);
      await capture(t, 'app-suppression-reprise');
      await t.tap(find.text('Demander une reprise'));
      await t.pumpAndSettle();
      expect(repo.retries, 1);
      repo.fail = true;
      await t.tap(find.text('Actualiser le suivi'));
      await t.pumpAndSettle();
      expect(find.text('Suivi indisponible'), findsOneWidget);
      expect(find.text('Suppression terminée'), findsNothing);
      repo.fail = false;
      repo.state = 'completed';
      await t.tap(find.text('Actualiser le suivi'));
      await t.pumpAndSettle();
      expect(find.text('Suppression terminée'), findsOneWidget);
      await capture(t, 'app-suppression-terminee');
    },
  );
  testWidgets('tracking remains accessible independently of auth session', (
    t,
  ) async {
    final repo = PrivacyFake()..requested = true;
    await screen(
      t,
      PrivacySessionGate(
        repository: repo,
        child: const Scaffold(body: Text('Accueil')),
      ),
    );
    expect(find.text('Suivi de suppression'), findsOneWidget);
    repo.state = 'completed';
    await t.tap(find.text('Actualiser le suivi'));
    await t.pumpAndSettle();
    await t.tap(find.text('Fermer le suivi sur cet appareil'));
    await t.pumpAndSettle();
    expect(find.text('Accueil'), findsOneWidget);
  });
  testWidgets(
    'reading each legal document offers no acceptance and preserves history',
    (t) async {
      final repo = LegalFake();
      await screen(
        t,
        LegalAcceptanceScreen(
          repository: repo,
          readOnly: true,
          document: 'privacy',
        ),
      );
      expect(find.text('Texte de confidentialité publié'), findsOneWidget);
      expect(find.text('Texte des CGU publiées'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Accepter et continuer'), findsNothing);
      expect(repo.acceptances, 0);
      await capture(t, 'app-confidentialite-lecture');
    },
  );
}
