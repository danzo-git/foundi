import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:foundi/features/professional/presentation/professional_badge.dart';
import 'package:foundi/features/proposals/domain/proposal_repository.dart';
import 'package:foundi/features/proposals/presentation/proposal_views.dart';
import 'package:foundi/features/conversations/domain/conversation_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/request_respondents.dart';
import 'package:foundi/features/requests/data/firebase_request_repository.dart';
import 'proposals_v7_test.dart' as fixtures;

class Certifications extends fixtures.Proposals
    implements ProposalCertificationRepository {
  int batches = 0;
  Map<String, bool> certifications = {};
  @override
  Future<Map<String, bool>> resolveCertifications(List<String> ids) async {
    batches++;
    return {for (final id in ids) id: certifications[id] == true};
  }
}

class MixedRespondents extends fixtures.Proposals
    implements RequestRespondentsRepository {
  bool certified = true;
  int reads = 0;
  Completer<RequestRespondentsPage>? pendingPage;
  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) async {
    reads++;
    if (pendingPage != null) return pendingPage!.future;
    return RequestRespondentsPage(
      total: 2,
      canViewProposals: false,
      items: [
        RequestRespondent(
          'Atelier',
          const [],
          responderId: 'pro',
          certified: certified,
        ),
        const RequestRespondent('Awa', [], responderId: 'ordinary'),
      ],
    );
  }
}

class _Firestore extends Fake implements FirebaseFirestore {}

class _Functions extends Fake implements FirebaseFunctions {
  String? endpoint;
  dynamic payload;
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    endpoint = name;
    return _Callable(this);
  }
}

class _Callable extends Fake implements HttpsCallable {
  _Callable(this.functions);
  final _Functions functions;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.payload = parameters;
    return _Result<T>(
      {
            'certifications': {'a': true, 'b': false},
          }
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
  test(
    'shell-facing Firebase facade exposes and delegates grouped certification',
    () async {
      final functions = _Functions();
      final repository = FirebaseRequestRepository(
        firestore: _Firestore(),
        functions: functions,
      );
      expect(repository, isA<ProposalCertificationRepository>());
      final values = await repository.resolveCertifications(['a', 'b']);
      expect(values, {'a': true, 'b': false});
      expect(functions.endpoint, 'resolveProposalCertifications');
      expect(functions.payload, {
        'proposalIds': ['a', 'b'],
      });
    },
  );
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_RESPONDER_CARD')) return;
    final bytesFont = File(
      '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/segoeui.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytesFont)))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'neutral and legacy models tolerate absent optional professional fields',
    () {
      final fields = <String, dynamic>{
        'requestId': 'request',
        'clientUid': 'client',
        'requestTitle': 'Besoin',
        'description': 'Solution',
        'status': 'sent',
        'createdAt': 1,
      };
      final legacy = Proposal.fromMap('legacy', {
        ...fields,
        'professionalUid': 'pro',
        'professionalName': 'Atelier',
      });
      final ordinary = Proposal.fromMap('ordinary', {
        ...fields,
        'responderUid': 'user',
        'responderName': 'Awa',
      });
      expect(legacy.responderUid, 'pro');
      expect(ordinary.responderUid, 'user');
      expect(ordinary.professionalUid, isEmpty);
      expect(
        Proposal.fromMap('partial', fields).responderName,
        'Utilisateur Foundi',
      );
      final chat = Conversation.fromMap('chat', {
        'requestId': 'request',
        'proposalId': 'ordinary',
        'clientUid': 'client',
        'clientName': 'Auteur',
        'responderUid': 'user',
        'responderName': 'Awa',
        'requestTitle': 'Besoin',
        'status': 'active',
        'updatedAt': 1,
        'requestSnapshot': {
          'title': 'Besoin',
          'description': 'Description',
          'categoryLabel': 'Services',
          'zoneLabel': 'Zone',
          'status': 'published',
          'createdAt': 1,
        },
      });
      expect(chat.otherName('client'), 'Awa');
      expect(chat.professionalUid, isEmpty);
    },
  );

  testWidgets(
    'mixed proposals use one batch; revocation removes badge and explanation stays available',
    (tester) async {
      final repo = Certifications();
      final pro = fixtures.saved();
      final ordinary = Proposal(
        id: 'b' * 64,
        requestId: pro.requestId,
        requestTitle: pro.requestTitle,
        responderUid: 'ordinary',
        responderName: 'Awa',
        clientUid: 'client',
        description: 'Une solution',
        status: 'sent',
        createdAt: 2,
      );
      repo.sent.addAll([pro, ordinary]);
      repo.certifications = {pro.id: true};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalListView(
              repository: repo,
              uid: 'client',
              received: true,
              onOpen: (_) {},
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.batches, 1);
      expect(find.byType(ProfessionalBadge), findsOneWidget);
      await tester.tap(find.byType(ProfessionalBadge));
      await tester.pumpAndSettle();
      expect(find.text(badgeExplanation), findsOneWidget);
      expect(find.text(badgeDisclaimer), findsOneWidget);
      Navigator.of(tester.element(find.text(badgeDisclaimer))).pop();
      await tester.pumpAndSettle();
      repo.certifications = {};
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(repo.batches, 2);
      expect(find.byType(ProfessionalBadge), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );

  testWidgets(
    'mixed respondents refresh certification and stop late pagination after timeout',
    (tester) async {
      final repo = MixedRespondents();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RequestRespondents(
                repository: repo,
                requestId: fixtures.request.id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProfessionalBadge), findsOneWidget);
      expect(find.text('Awa'), findsOneWidget);
      repo.certified = false;
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(find.byType(ProfessionalBadge), findsNothing);
      repo.pendingPage = Completer<RequestRespondentsPage>();
      await tester.pump(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 21));
      expect(repo.reads, 3);
      repo.pendingPage!.complete(
        const RequestRespondentsPage(
          total: 100,
          items: [],
          nextOffset: 20,
          canViewProposals: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.reads, 3);
      expect(find.text('Awa'), findsOneWidget);
      expect(find.byType(ProfessionalBadge), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );

  testWidgets(
    'professional profile action follows live certification, including later approval',
    (tester) async {
      final repo = Certifications();
      final p = Proposal(
        id: 'c' * 64,
        requestId: fixtures.request.id,
        requestTitle: 'Besoin',
        responderUid: 'ordinary',
        responderName: 'Awa',
        clientUid: 'client',
        description: 'Une solution',
        status: 'sent',
        createdAt: 1,
      );
      repo.sent.add(p);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalDetailView(
              repository: repo,
              id: p.id,
              onBack: () {},
              professionalProfileAction: (_) => () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Voir le profil professionnel'), findsNothing);
      repo.certifications = {p.id: true};
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(find.byType(ProfessionalBadge), findsOneWidget);
      expect(find.text('Voir le profil professionnel'), findsOneWidget);
      repo.certifications = {};
      await tester.pump(const Duration(seconds: 46));
      await tester.pumpAndSettle();
      expect(find.byType(ProfessionalBadge), findsNothing);
      expect(find.text('Voir le profil professionnel'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repo.changes.close();
    },
  );

  for (final width in [320.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('badge card fits $width dp at text scale $scale and closes', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1500),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: CertificationInfoCard(
                      onDismiss: () => dismissed = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Professionnel vérifié'), findsOneWidget);
        expect(find.text('Particulier'), findsOneWidget);
        await tester.tap(find.byTooltip('Fermer l’explication'));
        expect(dismissed, isTrue);
      });
    }
  }

  testWidgets('capture the actual Flutter information card', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_RESPONDER_CARD')) return;
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: CertificationInfoCard(onDismiss: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File('.dart_tool/responders-card.png');
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
