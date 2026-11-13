import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/notifications/domain/notification_repository.dart';
import 'package:foundi/features/notifications/presentation/notification_views.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/proposals/presentation/proposal_views.dart';
import 'package:foundi/features/requests/domain/request_interaction_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'package:foundi/features/requests/presentation/request_action_bar.dart';
import 'package:foundi/features/requests/presentation/request_views.dart';

import 'notifications_v9_test.dart' as notifications;
import 'proposals_v7_test.dart' as proposals;
import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as fixtures;

const captureEnabled = bool.fromEnvironment('REQUEST_ACTIONS_CAPTURE');
const request = FoundiRequest(
  id: 'RequestInteraction00001',
  title: 'Réparation d’un meuble en bois',
  description:
      'Je cherche un artisan pour réparer la porte d’un meuble en bois. Une intervention en fin de semaine me convient.',
  categoryLabel: 'Services',
  specialtyLabel: 'Menuiserie',
  zoneLabel: 'Cocody',
  categoryId: 'test_sector',
  specialtyId: 'test_specialty',
  zoneId: 'test_zone',
  status: 'published',
  budget: 35000,
  createdAt: null,
);
const closed = FoundiRequest(
  id: 'RequestInteraction00002',
  title: 'Demande de test clôturée',
  description: 'Texte public de test.',
  categoryLabel: 'Services',
  specialtyLabel: '',
  zoneLabel: 'Cocody',
  status: 'closed',
  createdAt: null,
);
const recommended = RecommendationProfessional(
  id: 'atelier',
  name: 'Atelier Ébène',
  categories: ['Services'],
  specialties: ['Menuiserie'],
  zones: ['Cocody'],
);

class ActionRequests extends proposals.Proposals
    implements
        RequestInteractionSource,
        RequestInteractionRepository,
        OpportunityRepository {
  final interactionsChanged = StreamController<void>.broadcast();
  final searches = <String>[],
      recommendations = <String>[],
      profileReads = <String>[];
  final mutations = <bool>[];
  bool mineLiked = false, failLike = false, failRecommendation = false;
  Completer<void>? pendingLike;
  RequestEngagement? counts;

  @override
  RequestInteractionRepository get interactions => this;

  Stream<T> _changes<T>(T Function() value) => Stream.multi((controller) {
    controller.add(value());
    final subscription = interactionsChanged.stream.listen(
      (_) => controller.add(value()),
    );
    controller.onCancel = subscription.cancel;
  });

  @override
  Stream<int> watchRequestLikes(String requestId) =>
      _changes(() => mineLiked ? 1 : 0);
  @override
  Stream<RequestEngagement> watchRequestEngagement(String requestId) =>
      _changes(
        () =>
            counts ??
            RequestEngagement(
              likeCount: mineLiked ? 1 : 0,
              recommendationCount: recommendations.length,
              responseCount: sent
                  .where((proposal) => proposal.requestId == requestId)
                  .length,
            ),
      );
  @override
  Stream<bool> watchMyRequestLike(String requestId, String uid) =>
      _changes(() => mineLiked);
  @override
  Future<void> setRequestLike(String requestId, bool liked) async {
    mutations.add(liked);
    await pendingLike?.future;
    if (failLike) throw const AuthFailure('J’aime non confirmé.');
    mineLiked = liked;
    interactionsChanged.add(null);
  }

  @override
  Future<RecommendationPage> searchRecommendationProfessionals(
    String requestId,
    String query, {
    String? cursor,
  }) async {
    searches.add(query);
    return RecommendationPage(
      query.isEmpty || query == 'Ébène' ? [recommended] : [],
    );
  }

  @override
  Future<bool> recommendRequestProfessional(
    String requestId,
    String professionalId,
  ) async {
    if (failRecommendation) {
      throw const AuthFailure('Recommandation non confirmée.');
    }
    final already = recommendations.contains(professionalId);
    if (!already) recommendations.add(professionalId);
    interactionsChanged.add(null);
    return already;
  }

  @override
  Future<ProfessionalShowcase> readRequestRecommendation(
    String recommendationId,
  ) async {
    profileReads.add(recommendationId);
    return const ProfessionalShowcase(
      name: 'Atelier Ébène',
      trade: 'Menuiserie',
      area: 'Cocody',
    );
  }

  @override
  Future<OpportunityPage> opportunities({
    List<String>? categoryIds,
    List<String>? specialtyIds,
    List<String>? zoneIds,
    Map<String, dynamic>? cursor,
  }) async => OpportunityPage(items, null);
}

class RespondingActionRequests extends ActionRequests
    implements RequestRespondentsRepository {
  @override
  Future<RequestRespondentsPage> listRequestRespondents(
    String requestId, {
    int offset = 0,
  }) async => const RequestRespondentsPage(
    total: 3,
    items: [
      RequestRespondent('Atelier Ébène', ['Menuiserie']),
    ],
    canViewProposals: false,
  );
}

Future<void> capture(WidgetTester t, String name) async {
  if (!captureEnabled) return;
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
    find.byKey(const ValueKey('v5Capture')),
  );
  await t.runAsync(() async {
    final picture = await boundary.toImage(pixelRatio: 2);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('.dart_tool/request-actions-preview')
      ..createSync(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

Finder footerAction(String text) => find.descendant(
  of: find.byType(RequestActionBar),
  matching: find.text(text),
);

void main() {
  setUpAll(() async {
    if (!captureEnabled) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final bytes = await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes();
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  testWidgets(
    'public cards display live totals and the response count opens public respondents',
    (t) async {
      final repo = RespondingActionRequests()
        ..items.add(request)
        ..counts = const RequestEngagement(
          likeCount: 1,
          recommendationCount: 2,
          responseCount: 3,
        );
      addTearDown(repo.interactionsChanged.close);
      await requests.runFlow(t, repo, (_, _) async {
        if (!captureEnabled) {
          t.view.physicalSize = const Size(320, 780);
          t.platformDispatcher.textScaleFactorTestValue = 1.7;
          await t.pumpAndSettle();
        }
        await t.scrollUntilVisible(
          find.text('3 réponses'),
          140,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await requests.tapForm(t, find.text('3 réponses'));
        expect(find.text('3 professionnels ont répondu'), findsOneWidget);
        expect(find.text('Atelier Ébène'), findsOneWidget);
        expect(find.text('Voir mes propositions'), findsNothing);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('2 recommandations'), findsOneWidget);
        await t.ensureVisible(find.text('3 réponses'));
        await capture(t, '07-compteurs-explorer');
        repo.counts = const RequestEngagement(
          likeCount: 1,
          recommendationCount: 1,
          responseCount: 0,
        );
        repo.interactionsChanged.add(null);
        await t.pumpAndSettle();
        expect(find.text('1 recommandation'), findsOneWidget);
        expect(find.text('0 réponses'), findsOneWidget);
        expect(t.takeException(), isNull);
      }, guest: true);
    },
  );

  testWidgets(
    'Client card supports optimistic likes and recommendation without opening the card',
    (t) async {
      final repo = ActionRequests()..items.add(request);
      addTearDown(repo.interactionsChanged.close);
      await requests.runFlow(t, repo, (_, _) async {
        final mineReply = find.ancestor(
          of: footerAction('Répondre'),
          matching: find.byType(TextButton),
        );
        expect(t.widget<TextButton>(mineReply).onPressed, isNull);
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        final like = footerAction('J’aime · 0');
        await t.ensureVisible(like);
        await t.pumpAndSettle();
        await capture(t, '01-explorer-client');
        repo.pendingLike = Completer<void>();
        await t.tap(like);
        await t.pump();
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        expect(find.text('Détail de la demande'), findsNothing);
        repo.pendingLike!.complete();
        await t.pumpAndSettle();
        expect(footerAction('J’aime · 1'), findsOneWidget);
        repo.failLike = true;
        await requests.tapForm(t, footerAction('J’aime · 1'));
        expect(find.byIcon(Icons.favorite), findsOneWidget);
        expect(find.text('J’aime non confirmé.'), findsOneWidget);
        repo.failLike = false;
        await requests.tapForm(t, footerAction('J’aime · 1'));
        expect(repo.mutations, [true, false, false]);

        await requests.tapForm(t, footerAction('Répondre'));
        expect(find.text('Accès professionnel requis'), findsOneWidget);
        expect(repo.accessCalls, 0);
        await fixtures.tap(t, find.text('Fermer'));
        await requests.tapForm(t, footerAction('Recommander'));
        await t.enterText(
          find.widgetWithText(TextField, 'Nom, spécialité ou zone'),
          'Ébène',
        );
        await fixtures.tap(t, find.byTooltip('Rechercher'));
        expect(repo.searches, ['', 'Ébène']);
        await fixtures.tap(t, find.text(recommended.name));
        FocusManager.instance.primaryFocus?.unfocus();
        await capture(t, '04-recommander');
        repo.failRecommendation = true;
        await fixtures.tap(t, find.text('Confirmer la recommandation'));
        expect(find.text('Recommandation non confirmée.'), findsOneWidget);
        repo.failRecommendation = false;
        await fixtures.tap(t, find.text('Confirmer la recommandation'));
        expect(repo.recommendations, ['atelier']);
        expect(
          find.text(
            'Recommandation enregistrée. L’auteur et le professionnel recevront une notification Foundi.',
          ),
          findsOneWidget,
        );
        expect(find.text('Détail de la demande'), findsNothing);

        await requests.tapForm(t, find.text(request.title));
        expect(find.text(request.description), findsOneWidget);
        await t.ensureVisible(footerAction('Répondre'));
        await t.pumpAndSettle();
        if (captureEnabled) {
          await t.pump(const Duration(seconds: 5));
          Scrollable.of(
            t.element(find.text('Détail de la demande')),
          ).position.jumpTo(0);
        }
        await capture(t, '03-detail-demande');
        expect(footerAction('Répondre'), findsOneWidget);
        expect(find.text('Faire une proposition'), findsNothing);
        expect(t.takeException(), isNull);
      });
    },
  );

  testWidgets(
    'Professional replies directly from Pour moi and opens an existing proposal',
    (t) async {
      final repo = ActionRequests()..items.add(request);
      addTearDown(repo.interactionsChanged.close);
      final catalog = fixtures.FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.approved,
          activity: ProfessionalActivity(
            categoryIds: ['test_sector'],
            specialtyIds: ['test_specialty'],
            zoneIds: ['test_zone'],
          ),
        ),
      );
      await requests.runFlow(
        t,
        repo,
        (_, _) async {
          expect(find.text('Pour moi'), findsWidgets);
          // The Explorer section selector can place this lazy card below the viewport.
          await t.scrollUntilVisible(footerAction('Répondre'), 160);
          await t.pumpAndSettle();
          await capture(t, '02-explorer-professionnel');
          expect(repo.accessCalls, 0);
          await requests.tapForm(t, footerAction('Répondre'));
          expect(find.byType(ProposalComposer), findsOneWidget);
          expect(repo.accessCalls, 1);
          await t.binding.handlePopRoute();
          await t.pumpAndSettle();
          expect(footerAction('Répondre'), findsOneWidget);
          repo.sent.add(proposals.saved());
          await requests.tapForm(t, footerAction('Répondre'));
          expect(find.byType(ProposalDetailView), findsOneWidget);
          expect(repo.sendCalls, 0);
        },
        professional: true,
        catalogProvider: catalog,
      );
    },
  );

  testWidgets(
    'Guest sees the real count, actions open sign-in, and 320px with large text does not overflow',
    (t) async {
      final repo = ActionRequests()..items.add(request);
      addTearDown(repo.interactionsChanged.close);
      await requests.runFlow(t, repo, (_, _) async {
        t.view.physicalSize = const Size(320, 780);
        t.platformDispatcher.textScaleFactorTestValue = 1.7;
        await t.pumpAndSettle();
        final like = footerAction('J’aime · 0');
        await t.scrollUntilVisible(
          like,
          160,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await requests.tapForm(t, like);
        expect(find.byKey(const ValueKey('submitAuth')), findsOneWidget);
        expect(repo.mutations, isEmpty);
        expect(t.takeException(), isNull);
      }, guest: true);
    },
  );

  testWidgets(
    'Closed request actions stay disabled and separate from the card hit target',
    (t) async {
      final repo = ActionRequests();
      addTearDown(repo.interactionsChanged.close);
      var opened = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RequestCard(
              closed,
              onTap: () => opened++,
              footer: RequestActionBar(
                request: closed,
                repository: repo,
                uid: 'test',
              ),
            ),
          ),
        ),
      );
      await t.tap(footerAction('Répondre'), warnIfMissed: false);
      await t.tap(footerAction('Recommander'), warnIfMissed: false);
      expect(opened, 0);
      await t.tap(find.text(closed.title));
      expect(opened, 1);
    },
  );

  testWidgets(
    'V9 recommendation opens the read-only public professional showcase',
    (t) async {
      final repo = ActionRequests();
      final inbox = notifications.InboxFake()
        ..target = const NotificationTarget(
          'recommendation',
          'recommendation-id',
        )
        ..items = [
          notifications.n(
            'note',
            type: 'request.recommended',
            category: 'proposals',
            title: 'Professionnel recommandé',
          ),
        ];
      final auth = fixtures.FakeAuth(user: fixtures.account());
      final pro = fixtures.FakePro();
      final intent = ValueNotifier<NotificationIntent?>(null);
      addTearDown(intent.dispose);
      addTearDown(inbox.close);
      addTearDown(repo.interactionsChanged.close);
      addTearDown(repo.changes.close);
      addTearDown(auth.changes.close);
      addTearDown(pro.changes.close);
      addTearDown(pro.docChanges.close);
      await t.pumpWidget(
        NotificationScope(
          repository: inbox,
          intent: intent,
          child: FoundiApp(
            authRepository: auth,
            professionalRepository: pro,
            requestRepository: repo,
          ),
        ),
      );
      await t.pumpAndSettle();
      await fixtures.tap(t, find.byKey(const ValueKey('notificationBell')));
      await fixtures.tap(t, find.text('Professionnel recommandé'));
      expect(repo.profileReads, ['recommendation-id']);
      expect(inbox.reads, ['note']);
      expect(find.text('Atelier Ébène'), findsOneWidget);
      expect(find.text('Modifier le profil'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
}
