import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/moderation_repository.dart';
import 'package:foundi_admin/moderation_page.dart';

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
    return Result<T>({'items': <dynamic>[], 'cursor': null} as T);
  }
}

class Functions extends Fake implements FirebaseFunctions {
  FirebaseFunctionsException? failure;
  final calls = <Map<String, dynamic>>[];
  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    expect(name, 'listSafetyReports');
    return Callable(this);
  }
}

void main() {
  const unavailable =
      'Le service de modération est indisponible. Réessaie plus tard ou vérifie la configuration du serveur.';
  test(
    'Admin sanitizes internal [0], transport failures and raw server exceptions',
    () async {
      final functions = Functions(),
          repo = FirebaseModerationRepository(functions: functions);
      for (final item in [
        ('internal', 'internal [0]'),
        ('internal', 'private index link'),
        ('unavailable', 'UNAVAILABLE'),
        ('unknown', 'UNKNOWN'),
      ]) {
        functions.failure = FunctionsFailure(code: item.$1, message: item.$2);
        await expectLater(
          repo.list({'status': 'new'}),
          throwsA(
            isA<ModerationFailure>().having(
              (e) => e.message,
              'message',
              unavailable,
            ),
          ),
        );
      }
    },
  );
  test(
    'Admin distinguishes missing callable from a missing business resource',
    () async {
      final functions = Functions(),
          repo = FirebaseModerationRepository(functions: functions);
      for (final message in ['', 'NOT_FOUND', 'not-found']) {
        functions.failure = FunctionsFailure(
          code: 'not-found',
          message: message,
        );
        await expectLater(
          repo.list({'status': 'new'}),
          throwsA(
            isA<ModerationFailure>().having(
              (e) => e.message,
              'message',
              'Le service de modération n’est pas accessible. Vérifie son activation sur le serveur.',
            ),
          ),
        );
      }
      functions.failure = FunctionsFailure(
        code: 'not-found',
        message: 'Signalement indisponible.',
      );
      await expectLater(
        repo.list({'status': 'new'}),
        throwsA(
          isA<ModerationFailure>().having(
            (e) => e.message,
            'message',
            'Signalement indisponible.',
          ),
        ),
      );
    },
  );
  test(
    'Admin preserves index readiness, authorization and concurrency decisions from the server',
    () async {
      final functions = Functions(),
          repo = FirebaseModerationRepository(functions: functions);
      for (final item in [
        (
          'failed-precondition',
          'La modération n’est pas prête : les index nécessaires doivent être activés sur le serveur.',
        ),
        ('permission-denied', 'Accès administratif requis.'),
        ('aborted', 'Ce dossier a changé. Actualise avant de décider.'),
      ]) {
        functions.failure = FunctionsFailure(code: item.$1, message: item.$2);
        await expectLater(
          repo.list({'status': 'new'}),
          throwsA(
            isA<ModerationFailure>().having(
              (e) => e.message,
              'message',
              item.$2,
            ),
          ),
        );
      }
    },
  );
  testWidgets(
    'real repository error shows human message and retry without a fake empty queue',
    (t) async {
      final functions = Functions()
        ..failure = FunctionsFailure(code: 'internal', message: 'internal [0]');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModerationPage(
              repository: FirebaseModerationRepository(functions: functions),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text(unavailable), findsOneWidget);
      expect(find.text('internal [0]'), findsNothing);
      expect(find.text('Aucun signalement dans cette file.'), findsNothing);
      functions.failure = null;
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text(unavailable), findsNothing);
      expect(find.text('Aucun signalement dans cette file.'), findsOneWidget);
      expect(functions.calls.length, 2);
    },
  );
}
