import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/requests/data/firebase_request_repository.dart';
import 'package:foundi/features/requests/domain/request_repository.dart';
import 'requests_v5_test.dart' as requests;
import 'widget_test.dart' as fixtures;

class Database extends Fake implements FirebaseFirestore {}

class FunctionsFailure extends FirebaseFunctionsException {
  FunctionsFailure({required super.code, super.message = ''});
}

class Result<T> extends Fake implements HttpsCallableResult<T> {
  Result(this.data);
  @override
  final T data;
}

class PublicationCallable extends Fake implements HttpsCallable {
  PublicationCallable(this.functions);
  final Functions functions;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final input = Map<String, dynamic>.from(parameters as Map);
    functions.calls.add(input);
    if (functions.failure != null) throw functions.failure!;
    return Result<T>(
      {
            ...Map<String, dynamic>.from(input['request'] as Map),
            'id': input['requestId'],
            'categoryLabel': 'Catégorie de test',
            'specialtyLabel': 'Spécialité de test',
            'zoneLabel': 'Zone de test',
            'status': 'published',
            'createdAt': 123456,
          }
          as T,
    );
  }
}

class Functions extends Fake implements FirebaseFunctions {
  FirebaseFunctionsException? failure;
  final calls = <Map<String, dynamic>>[];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    expect(name, 'publishRequest');
    return PublicationCallable(this);
  }
}

class PublicationRequests extends requests.FakeRequests {
  PublicationRequests(this.firebase);
  final FirebaseRequestRepository firebase;
  @override
  Future<FoundiRequest> publish(String id, RequestDraft draft) async {
    publishIds.add(id);
    final saved = await firebase.publish(id, draft);
    items.add(saved);
    changes.add(null);
    return saved;
  }
}

void main() {
  const draft = RequestDraft(
    categoryId: 'c',
    specialtyId: 's',
    zoneId: 'z',
    title: 'Un besoin de test',
    description: 'Une demande de test complète.',
  );
  const emailMessage =
      'Vérifie ton adresse e-mail avant de publier une demande.';
  const quotaMessage =
      'Tu as atteint la limite de publication. Réessaie plus tard.';

  test(
    'real repository maps quota and verification errors while preserving other preconditions',
    () async {
      final functions = Functions();
      final repository = FirebaseRequestRepository(
        firestore: Database(),
        functions: functions,
      );
      for (final message in ['', 'Internal quota reason']) {
        functions.failure = FunctionsFailure(
          code: 'resource-exhausted',
          message: message,
        );
        await expectLater(
          repository.publish('request-id', draft),
          throwsA(
            isA<AuthFailure>().having(
              (e) => e.message,
              'message',
              quotaMessage,
            ),
          ),
        );
      }
      functions.failure = FunctionsFailure(
        code: 'failed-precondition',
        message: emailMessage,
      );
      await expectLater(
        repository.publish('request-id', draft),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains(emailMessage), contains('code reçu par e-mail')),
          ),
        ),
      );
      const catalog =
          'Les catégories et zones sont temporairement indisponibles.';
      functions.failure = FunctionsFailure(
        code: 'failed-precondition',
        message: catalog,
      );
      await expectLater(
        repository.publish('request-id', draft),
        throwsA(
          isA<AuthFailure>().having((e) => e.message, 'message', catalog),
        ),
      );
      functions.failure = FunctionsFailure(code: 'unavailable');
      await expectLater(
        repository.publish('request-id', draft),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.message,
            'message',
            contains('une même demande'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'verification and quota rejection keep every draft field and the same ID through navigation and retry',
    (t) async {
      final functions = Functions()
        ..failure = FunctionsFailure(
          code: 'failed-precondition',
          message: emailMessage,
        );
      final repository = PublicationRequests(
        FirebaseRequestRepository(firestore: Database(), functions: functions),
      );
      await requests.runFlow(t, repository, (auth, pro) async {
        await requests.preview(t);
        await requests.tapForm(t, find.byKey(const ValueKey('publishRequest')));
        expect(find.textContaining(emailMessage), findsOneWidget);
        expect(find.textContaining('code reçu par e-mail'), findsOneWidget);
        expect(repository.items, isEmpty);
        await requests.tapForm(t, find.text('Modifier'));
        expect(
          t
              .widget<TextFormField>(find.byKey(const ValueKey('requestTitle')))
              .controller!
              .text,
          'Mon besoin de test',
        );
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('requestDescription')),
              )
              .controller!
              .text,
          'Une description publique de mon besoin de test.',
        );
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('requestBudget')),
              )
              .controller!
              .text,
          '100 000',
        );
        await requests.tapForm(t, find.text('Vérifier ma demande'));
        functions.failure = FunctionsFailure(code: 'resource-exhausted');
        await requests.tapForm(t, find.byKey(const ValueKey('publishRequest')));
        expect(find.text(quotaMessage), findsOneWidget);
        await fixtures.tap(t, find.byKey(const ValueKey('nav-1')));
        await fixtures.tap(t, find.byKey(const ValueKey('nav-0')));
        await fixtures.tap(t, find.byKey(const ValueKey('openPublication')));
        expect(find.text(quotaMessage), findsOneWidget);
        expect(repository.ids, 1);
        functions.failure = null;
        await requests.tapForm(t, find.byKey(const ValueKey('publishRequest')));
        expect(find.text('C’est publié !'), findsOneWidget);
        expect(repository.items.length, 1);
        expect(repository.publishIds, ['request-1', 'request-1', 'request-1']);
        expect(functions.calls.length, 3);
        expect(functions.calls[1], functions.calls[0]);
        expect(functions.calls[2], functions.calls[0]);
        expect((functions.calls.first['request'] as Map)['budget'], 100000);
        expect(
          (functions.calls.first['request'] as Map)['categoryId'],
          'test_sector',
        );
        expect(
          (functions.calls.first['request'] as Map)['specialtyId'],
          'test_specialty',
        );
        expect(
          (functions.calls.first['request'] as Map)['zoneId'],
          'test_zone',
        );
      });
    },
  );
}
