import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/moderation_page.dart';
import 'package:foundi_admin/moderation_repository.dart';
import 'package:foundi_admin/main.dart' show AdminApp;

const captures = bool.fromEnvironment('SAFETY_CAPTURE');

class ModerationFake implements ModerationRepository {
  @override
  Future<ModerationAttachment> readAttachment(String id) async =>
      throw const ModerationFailure('Preuve indisponible.');
  final filters = <Map<String, dynamic>>[],
      decisions = <Map<String, dynamic>>[];
  bool fail = false;
  Map<String, dynamic> report = {
    'id': 'a' * 64,
    'targetType': 'professional',
    'targetId': 'professional-test',
    'reportedUid': 'professional-test',
    'reporterUid': 'client-test',
    'label': 'Atelier de plomberie',
    'reason': 'harassment',
    'comment': 'Des messages menaçants ont été reçus.',
    'status': 'new',
    'priority': 'high',
    'revision': 1,
    'createdAt': 1794567600000,
    'evidence': {
      'name': 'Atelier de plomberie',
      'bio': 'Plomberie et réparation.',
      'photoIds': [],
    },
    'audit': <dynamic>[],
  };
  @override
  Future<Map<String, dynamic>> list(Map<String, dynamic> input) async {
    filters.add(input);
    if (fail) throw const ModerationFailure('Service indisponible. Réessaie.');
    return {
      'items': input['status'] == report['status'] ? [report] : [],
      'cursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> detail(String id) async => Map.of(report);
  @override
  Future<void> decide(Map<String, dynamic> input) async {
    if (fail) {
      throw const ModerationFailure(
        'Ce dossier a changé. Actualise avant de décider.',
      );
    }
    decisions.add(input);
    report = {
      ...report,
      'status': ['take', 'reopen'].contains(input['action'])
          ? 'in_progress'
          : input['action'] == 'dismiss'
          ? 'dismissed'
          : 'resolved',
      'assignedAdminUid': 'admin-test',
      'revision': (report['revision'] as int) + 1,
      if (input['action'] == 'hide') 'contentHidden': true,
      'audit': [
        ...report['audit'] as List,
        {
          'adminUid': 'admin-test',
          'action': input['action'],
          'reason': input['reason'],
          if (input['publicMessage'] != null)
            'publicMessage': input['publicMessage'],
          'createdAt': 1794567900000,
        },
      ],
    };
  }
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captures) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('adminCapture')),
  );
  boundary.reassemble();
  await t.pumpAndSettle();
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('../docs/sprint-1-securite-captures')
      ..createSync(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> app(WidgetTester t, Widget body, {double width = 1200}) async {
  late ThemeData productionTheme;
  await t.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          productionTheme =
              (const AdminApp().build(context) as MaterialApp).theme!;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  t.view.physicalSize = Size(width, 950);
  t.view.devicePixelRatio = 1;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('adminCapture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: productionTheme,
        home: Scaffold(body: body),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    if (!captures) return;
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
    'SEC examination status explains tracking and applies no sanction',
    (t) async {
      final repo = ModerationFake();
      await app(t, ModerationDetailPage(repository: repo, id: 'a' * 64));
      await t.ensureVisible(find.text('Commencer l’examen'));
      await t.tap(find.text('Commencer l’examen'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Cette étape n’applique aucune sanction'),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const ValueKey('moderationPrivateReason')),
        'Examen des éléments en cours.',
      );
      await t.tap(find.text('Confirmer la décision'));
      await t.pumpAndSettle();
      expect(repo.decisions.single['action'], 'take');
      expect(
        find.textContaining('une décision reste à prendre'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Commencer l’examen'),
        findsNothing,
      );
      expect(find.widgetWithText(OutlinedButton, 'Avertir'), findsOneWidget);
      await capture(t, '11-admin-examen-en-cours');
    },
  );
  testWidgets(
    'SEC admin file filters and private detail show evidence and audit',
    (t) async {
      final repo = ModerationFake();
      await app(t, ModerationPage(repository: repo));
      await capture(t, '08-admin-file');
      await t.tap(find.text('Atelier de plomberie'));
      await t.pumpAndSettle();
      expect(find.textContaining('Signalant : client-test'), findsOneWidget);
      await capture(t, '09-admin-detail');
      await t.tap(find.text('Avertir'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirmer la décision'));
      await t.pumpAndSettle();
      expect(find.text('Justifie cette décision.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('moderationPrivateReason')),
        'Menaces établies après examen.',
      );
      await t.enterText(
        find.byKey(const ValueKey('moderationPublicMessage')),
        'Le profil contient des propos menaçants. Merci de les retirer.',
      );
      await t.tap(find.text('Confirmer la décision'));
      await t.pumpAndSettle();
      expect(repo.decisions.single['expectedRevision'], 1);
      expect(find.textContaining('Menaces établies'), findsOneWidget);
      await capture(t, '10-admin-audit');
    },
  );
  testWidgets('SEC admin stale decision error does not claim success', (
    t,
  ) async {
    final repo = ModerationFake();
    await app(
      t,
      ModerationDetailPage(repository: repo, id: 'a' * 64),
      width: 390,
    );
    repo.fail = true;
    await t.ensureVisible(find.text('Suspendre le compte'));
    await t.pumpAndSettle();
    await t.tap(find.text('Suspendre le compte'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('moderationPrivateReason')),
      'Décision de modération.',
    );
    await t.enterText(
      find.byKey(const ValueKey('moderationPublicMessage')),
      'Ton compte est suspendu pour non-respect des règles.',
    );
    await t.tap(find.text('Confirmer la décision'));
    await t.pumpAndSettle();
    expect(
      find.text('Ce dossier a changé. Actualise avant de décider.'),
      findsOneWidget,
    );
    expect(repo.decisions, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'SEC admin can review a warning and add a distinct decision without erasing history',
    (t) async {
      final repo = ModerationFake()
        ..report = {
          ...ModerationFake().report,
          'status': 'resolved',
          'revision': 2,
          'audit': [
            {
              'adminUid': 'admin-first',
              'action': 'warn',
              'reason': 'Première décision conservée.',
              'createdAt': 1794567600000,
            },
          ],
        };
      await app(t, ModerationDetailPage(repository: repo, id: 'a' * 64));
      expect(
        find.widgetWithText(OutlinedButton, 'Masquer le contenu public'),
        findsNothing,
      );
      await t.ensureVisible(find.text('Réexaminer le dossier'));
      await t.tap(find.text('Réexaminer le dossier'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('les mesures actives restent appliquées'),
        findsOneWidget,
      );
      await t.enterText(
        find.byKey(const ValueKey('moderationPrivateReason')),
        'Nouveaux éléments à examiner.',
      );
      await t.tap(find.text('Confirmer la décision'));
      await t.pumpAndSettle();
      expect(repo.decisions.single['expectedRevision'], 2);
      expect(repo.decisions.single.containsKey('publicMessage'), false);
      expect(
        find.widgetWithText(OutlinedButton, 'Masquer le contenu public'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Suspendre le compte'),
        findsOneWidget,
      );
      await capture(t, '13-admin-reexamen');
      await t.ensureVisible(find.text('Masquer le contenu public'));
      await t.tap(find.text('Masquer le contenu public'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('moderationPrivateReason')),
        'Répétition constatée en interne.',
      );
      await t.enterText(
        find.byKey(const ValueKey('moderationPublicMessage')),
        'Le profil reste masqué jusqu’à la correction de son contenu.',
      );
      await t.tap(find.text('Confirmer la décision'));
      await t.pumpAndSettle();
      expect(repo.decisions.last['expectedRevision'], 3);
      expect(
        repo.decisions.last['publicMessage'],
        'Le profil reste masqué jusqu’à la correction de son contenu.',
      );
      expect((repo.report['audit'] as List).map((a) => a['action']), [
        'warn',
        'reopen',
        'hide',
      ]);
      expect(
        find.textContaining('Première décision conservée'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'SEC admin follows server actions and requires the separate user message',
    (t) async {
      final repo = ModerationFake()
        ..report = {
          ...ModerationFake().report,
          'availableActions': ['warn'],
        };
      await app(t, ModerationDetailPage(repository: repo, id: 'a' * 64));
      expect(
        find.widgetWithText(OutlinedButton, 'Suspendre le compte'),
        findsNothing,
      );
      await t.ensureVisible(find.text('Avertir'));
      await t.tap(find.text('Avertir'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('moderationPrivateReason')),
        'Raison privée seulement.',
      );
      await t.tap(find.text('Confirmer la décision'));
      await t.pumpAndSettle();
      expect(
        find.text('Explique la décision à l’utilisateur.'),
        findsOneWidget,
      );
      expect(repo.decisions, isEmpty);
      await capture(t, '14-admin-message-utilisateur');
    },
  );
  testWidgets(
    'SEC admin filters refresh query and network failure is explicit',
    (t) async {
      final repo = ModerationFake();
      await app(t, ModerationPage(repository: repo), width: 320);
      await t.tap(find.text('Traités'));
      await t.pumpAndSettle();
      expect(repo.filters.last['status'], 'resolved');
      expect(find.text('Aucun signalement dans cette file.'), findsOneWidget);
      repo.fail = true;
      await t.tap(find.byTooltip('Actualiser'));
      await t.pumpAndSettle();
      expect(find.text('Service indisponible. Réessaie.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
