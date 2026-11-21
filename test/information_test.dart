import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:foundi/features/information/domain/information_repository.dart';
import 'package:foundi/features/information/presentation/information_views.dart';
import 'package:foundi/features/navigation/presentation/foundi_shell.dart';
import 'package:foundi/features/requests/data/firebase_request_repository.dart';
import 'package:foundi/features/professional/presentation/professional_badge.dart';
import 'package:foundi/features/requests/presentation/explorer_view.dart';
import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as auth;
import 'proposals_v7_test.dart' as proposals;
import 'package:foundi/features/navigation/presentation/space_widgets.dart';

FoundiInformation info({
  String id = 'news',
  String version = 'v1',
  Duration duration = const Duration(days: 1),
  bool body = false,
}) => FoundiInformation(
  id: id,
  version: version,
  title: 'Plus de possibilités',
  summary: 'Les particuliers peuvent aussi répondre.',
  body: body ? 'Le texte complet est visible dans cette carte.' : '',
  endsAt: DateTime.now().add(duration),
);

class Information extends requests.FakeRequests
    implements InformationRepository {
  List<FoundiInformation> infos = [info()];
  int lists = 0, reads = 0;
  bool offline = false;
  bool bodyOffline = false, unavailable = false;
  Completer<List<FoundiInformation>>? pendingInformation;
  FoundiInformation? article;
  @override
  Future<List<FoundiInformation>> listInformation({
    bool featuredOnly = false,
  }) async {
    lists++;
    if (offline) throw StateError('offline');
    if (pendingInformation != null) {
      return pendingInformation!.future;
    }
    return featuredOnly ? infos.take(1).toList() : infos;
  }

  @override
  Future<FoundiInformation> readInformation(String id) async {
    reads++;
    if (unavailable) throw const InformationUnavailable();
    if (offline || bodyOffline) throw StateError('offline');
    return article ?? info(id: id, body: true);
  }
}

class _Firestore extends Fake implements FirebaseFirestore {}

class _Functions extends Fake implements FirebaseFunctions {
  final calls = <String>[];
  dynamic input;
  String? readFailure;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    calls.add(name);
    return _Callable(this);
  }
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.functions);
  final _Functions functions;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.input = parameters;
    if (functions.calls.last == 'readFoundiInformation' &&
        functions.readFailure != null) {
      throw FirebaseFunctionsException(
        code: functions.readFailure!,
        message: 'Indisponible',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = {
      'id': 'news',
      'version': 'v1',
      'title': 'Plus de possibilités',
      'summary': 'Résumé',
      'body': 'Article',
      'endsAt': now + 10000,
    };
    return _Result<T>(
      (functions.calls.last == 'listFoundiInformation'
              ? {
                  'items': [item],
                  'serverNow': now,
                }
              : {...item, 'serverNow': now})
          as T,
    );
  }
}

class _Result<T> extends Fake implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_INFORMATION')) return;
    final font = await File(
      '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/segoeui.ttf',
    ).readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('warm card fits a narrow screen and large text', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repo = Information()..items.add(proposals.request);
    final key = GlobalKey();
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: FoundiUi.green),
          fontFamily: 'Roboto',
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            backgroundColor: FoundiUi.background,
            body: Column(
              children: [
                const FoundiBrand(),
                Expanded(
                  child: ExplorerView(
                    repository: repo,
                    onOpen: (_) {},
                    onPublish: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.textContaining('Jusqu’au'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    if (const bool.fromEnvironment('CAPTURE_INFORMATION')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '.dart_tool/foundi-information-explorer.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: WarmInformationCard(
                title: 'Plus de possibilités pour vos demandes.',
                summary: 'Les particuliers peuvent aussi proposer leur aide.',
                body:
                    'Tout le message reste visible dans la carte, sans ouvrir une autre page.',
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await repo.changes.close();
  });
  test(
    'real request facade delegates summary and article endpoints and handles server time',
    () async {
      final functions = _Functions();
      final repository = FirebaseRequestRepository(
        firestore: _Firestore(),
        functions: functions,
      );
      final summaries = await repository.listInformation(featuredOnly: true);
      expect(functions.input, {'featuredOnly': true});
      expect(summaries.single.id, 'news');
      expect((await repository.readInformation('news')).body, 'Article');
      expect(functions.calls, [
        'listFoundiInformation',
        'readFoundiInformation',
      ]);
      expect(functions.input, {'id': 'news'});
      functions.readFailure = 'not-found';
      await expectLater(
        repository.readInformation('news'),
        throwsA(isA<InformationUnavailable>()),
      );
      final skewed = FoundiInformation.fromMap({
        'id': 'a',
        'version': 'v',
        'title': 'T',
        'summary': 'S',
        'endsAt': 2000,
        'serverNow': 1000,
      });
      expect(
        skewed.validUntil.difference(DateTime.now()).inMilliseconds,
        closeTo(1000, 100),
      );
    },
  );
  testWidgets(
    'complete text stays in the card and dismissal survives remount without hiding hub content',
    (t) async {
      final repo = Information();
      Widget card(String user) => MaterialApp(
        home: Scaffold(
          body: ExplorerInformation(repository: repo, accountId: user),
        ),
      );
      await t.pumpWidget(card('awa'));
      await t.pumpAndSettle();
      expect(find.text('Plus de possibilités'), findsOneWidget);
      expect(repo.reads, 1);
      expect(
        find.text('Le texte complet est visible dans cette carte.'),
        findsOneWidget,
      );
      expect(find.text('Découvrir'), findsNothing);
      expect(
        Navigator.of(t.element(find.byType(ExplorerInformation))).canPop(),
        isFalse,
      );
      await t.tap(find.byTooltip('Fermer l’annonce'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(card('awa'));
      await t.pumpAndSettle();
      expect(find.text('Plus de possibilités'), findsNothing);
      expect(repo.reads, 1);
      await t.pumpWidget(
        MaterialApp(home: InformationScreen(repository: repo)),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Plus de possibilités'), 200);
      await t.pumpAndSettle();
      expect(
        find.text('Le texte complet est visible dans cette carte.'),
        findsOneWidget,
      );
      expect(repo.reads, 2);
      expect(find.text('Découvrir'), findsNothing);
      expect(
        Navigator.of(t.element(find.byType(InformationScreen))).canPop(),
        isFalse,
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(card('other'));
      await t.pumpAndSettle();
      expect(find.text('Plus de possibilités'), findsOneWidget);
      repo.infos = [info(version: 'v2')];
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(card('awa'));
      await t.pumpAndSettle();
      expect(find.text('Plus de possibilités'), findsOneWidget);
      await t.tap(find.byTooltip('Fermer l’annonce'));
      await t.pumpAndSettle();
      repo.infos = [info(version: 'v1')];
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(card('awa'));
      await t.pumpAndSettle();
      expect(find.text('Plus de possibilités'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );
  testWidgets(
    'account shows the complete permanent badge card even when announcements fail',
    (t) async {
      final repo = Information()..offline = true;
      final user = auth.account(),
          authentication = auth.FakeAuth(user: auth.account());
      await t.pumpWidget(
        MaterialApp(
          home: FoundiShell(
            user: user,
            auth: authentication,
            requestRepository: repo,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('nav-3')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Informations Foundi'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Informations Foundi'));
      await t.pumpAndSettle();
      expect(find.textContaining(badgeExplanation), findsOneWidget);
      expect(find.textContaining(badgeDisclaimer), findsOneWidget);
      expect(find.text('Comprendre le badge'), findsNothing);
      expect(find.byType(WarmInformationCard), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Les annonces sont momentanément indisponibles.'),
        250,
      );
      expect(
        find.text('Les annonces sont momentanément indisponibles.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
      await authentication.changes.close();
    },
  );
  testWidgets(
    'expiry removes the complete card, and a slow announcement does not block Explorer',
    (t) async {
      final repo = Information()
        ..article = info(body: true, duration: const Duration(seconds: 2));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnnouncementInformationCard(
              repository: repo,
              announcement: info(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Le texte complet est visible dans cette carte.'),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 3));
      expect(
        find.text('Le texte complet est visible dans cette carte.'),
        findsNothing,
      );
      expect(find.byType(WarmInformationCard), findsNothing);
      repo.pendingInformation = Completer();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExplorerView(
              repository: repo,
              onOpen: (_) {},
              onPublish: () {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Aucune demande publiée pour le moment'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.pumpWidget(const SizedBox());
      repo.pendingInformation!.complete([info()]);
      await t.pump();
      expect(t.takeException(), isNull);
      await repo.changes.close();
    },
  );
  testWidgets(
    'full text retries inline and an unavailable announcement disappears',
    (t) async {
      final repo = Information()..bodyOffline = true;
      Widget card() => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnnouncementInformationCard(
              repository: repo,
              announcement: info(),
            ),
          ),
        ),
      );
      await t.pumpWidget(card());
      await t.pumpAndSettle();
      expect(
        find.text('Le texte complet est momentanément indisponible.'),
        findsOneWidget,
      );
      expect(find.text('Découvrir'), findsNothing);
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(
        find.text('Le texte complet est momentanément indisponible.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      repo.bodyOffline = false;
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(
        find.text('Le texte complet est visible dans cette carte.'),
        findsOneWidget,
      );
      expect(
        Navigator.of(
          t.element(find.byType(AnnouncementInformationCard)),
        ).canPop(),
        isFalse,
      );
      repo.unavailable = true;
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(card());
      await t.pumpAndSettle();
      expect(find.byType(WarmInformationCard), findsNothing);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );
  testWidgets(
    'hub fetches full text for nearby cards rather than the entire history',
    (t) async {
      final repo = Information()
        ..infos = List.generate(20, (i) => info(id: 'news$i'));
      await t.pumpWidget(
        MaterialApp(home: InformationScreen(repository: repo)),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const ValueKey('news0:v1')), 250);
      await t.pumpAndSettle();
      expect(repo.reads, greaterThan(0));
      expect(repo.reads, lessThan(20));
      expect(find.text('Découvrir'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );
}
