import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/safety/data/firebase_safety_repository.dart';
import 'package:foundi/features/safety/domain/safety_repository.dart';
import 'package:foundi/features/safety/presentation/safety_widgets.dart';

class FunctionsFailure extends FirebaseFunctionsException {
  FunctionsFailure({required super.code, super.message = ''});
}

class Result<T> extends Fake implements HttpsCallableResult<T> {
  Result(this.data);
  @override
  final T data;
}

class Callable extends Fake implements HttpsCallable {
  Callable(this.functions);
  final Functions functions;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    functions.calls.add(Map<String, dynamic>.from(parameters as Map));
    if (functions.failure case final failure?) {
      throw failure;
    }
    return Result<T>(functions.response as T);
  }
}

class Functions extends Fake implements FirebaseFunctions {
  FirebaseFunctionsException? failure;
  String expectedName = 'submitSafetyReport';
  Map<String, dynamic> response = {
    'reportId': 'test-report',
    'duplicate': false,
  };
  final calls = <Map<String, dynamic>>[];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    expect(name, expectedName);
    return Callable(this);
  }
}

void main() {
  const target = SafetyTarget('request', 'request-test');
  const unavailable =
      'Le service de sécurité est indisponible sur le serveur. Réessaie plus tard.';
  const temporary =
      'Le service de sécurité est temporairement indisponible. Réessaie plus tard.';
  test(
    'notice transport preserves stable identities and reading state and acknowledges only a notice id',
    () async {
      final id = 'a' * 64;
      final functions = Functions()
        ..expectedName = 'listSafetyNotices'
        ..response = {
          'items': ['Ancien format'],
          'notices': [
            {'id': id, 'text': 'Avertissement ciblé', 'acknowledgedAt': null},
            {'id': 'b' * 64, 'text': 'Avis consulté', 'acknowledgedAt': 1000},
          ],
        };
      final repo = FirebaseSafetyRepository(functions: functions);
      final notices = await repo.notices();
      expect(notices.first.id, id);
      expect(notices.first.acknowledged, false);
      expect(notices.last.acknowledged, true);
      functions.expectedName = 'acknowledgeSafetyNotice';
      functions.response = {'acknowledged': true};
      await repo.acknowledgeNotice(id);
      expect(functions.calls.last, {'noticeId': id});
      functions.failure = FunctionsFailure(code: 'unavailable');
      await expectLater(
        repo.acknowledgeNotice(id),
        throwsA(isA<AuthFailure>()),
      );
    },
  );
  test(
    'missing callable does not display raw NOT_FOUND or claim the request disappeared',
    () async {
      final functions = Functions(),
          repo = FirebaseSafetyRepository(functions: functions);
      for (final message in ['', 'NOT_FOUND', 'not-found', 'NOT FOUND']) {
        functions.failure = FunctionsFailure(
          code: 'not-found',
          message: message,
        );
        await expectLater(
          repo.report(target, 'other', ''),
          throwsA(
            isA<AuthFailure>().having((e) => e.message, 'message', unavailable),
          ),
        );
      }
    },
  );
  test(
    'internal SDK and server errors never expose raw infrastructure messages',
    () async {
      final functions = Functions(),
          repo = FirebaseSafetyRepository(functions: functions);
      for (final message in [
        'internal [0]',
        'INTERNAL',
        'Authentication is temporarily unavailable.',
        'private index URL',
      ]) {
        functions.failure = FunctionsFailure(
          code: 'internal',
          message: message,
        );
        await expectLater(
          repo.report(target, 'other', ''),
          throwsA(
            isA<AuthFailure>().having((e) => e.message, 'message', temporary),
          ),
        );
      }
    },
  );
  test(
    'business errors for removed content, authorization and quotas stay meaningful',
    () async {
      final functions = Functions(),
          repo = FirebaseSafetyRepository(functions: functions);
      for (final item in [
        ('not-found', 'Cette demande n’est plus disponible.'),
        ('permission-denied', 'Ce compte est suspendu.'),
        ('resource-exhausted', 'Limite quotidienne atteinte.'),
        ('invalid-argument', 'Choisis un motif.'),
      ]) {
        functions.failure = FunctionsFailure(code: item.$1, message: item.$2);
        await expectLater(
          repo.report(target, 'other', ''),
          throwsA(
            isA<AuthFailure>().having((e) => e.message, 'message', item.$2),
          ),
        );
      }
    },
  );
  test('authentication and timeout errors give an action to take', () async {
    final functions = Functions(),
        repo = FirebaseSafetyRepository(functions: functions);
    for (final item in [
      ('unauthenticated', 'Reconnecte-toi pour continuer.'),
      (
        'deadline-exceeded',
        'Le serveur ne répond pas. Vérifie ta connexion et réessaie.',
      ),
    ]) {
      functions.failure = FunctionsFailure(code: item.$1);
      await expectLater(
        repo.report(target, 'other', ''),
        throwsA(
          isA<AuthFailure>().having((e) => e.message, 'message', item.$2),
        ),
      );
    }
  });
  testWidgets(
    'missing endpoint preserves report draft and never confirms a failed submission',
    (t) async {
      final functions = Functions()
        ..failure = FunctionsFailure(code: 'not-found', message: 'NOT_FOUND');
      final repo = FirebaseSafetyRepository(functions: functions);
      var submitted = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  submitted =
                      await showDialog<bool>(
                        context: context,
                        builder: (_) =>
                            ReportDialog(repository: repo, target: target),
                      ) ==
                      true;
                },
                child: const Text('Signaler'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Signaler'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('safetyReason')));
      await t.pumpAndSettle();
      await t.tap(find.text('Contenu inapproprié').last);
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('safetyComment')),
        'demande pas cohérente',
      );
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);
      expect(find.text('NOT_FOUND'), findsNothing);
      expect(find.text('demande pas cohérente'), findsOneWidget);
      expect(submitted, false);
      expect(functions.calls.length, 1);
      functions.failure = null;
      await t.tap(find.text('Envoyer le signalement'));
      await t.pumpAndSettle();
      expect(submitted, true);
      expect(functions.calls.last['comment'], 'demande pas cohérente');
      expect(functions.calls.last['reason'], 'inappropriate');
    },
  );
}
