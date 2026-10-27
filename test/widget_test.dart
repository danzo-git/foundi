import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/auth/domain/auth_validators.dart';

const completeProfile = AccountProfile(
  fullName: 'Awa Kouassi',
  phone: '+2250700000000',
  profession: 'Étudiante',
  registrationConfirmed: true,
);

FoundiUser account({
  bool verified = true,
  bool password = true,
  bool google = false,
  AccountProfile profile = completeProfile,
}) => FoundiUser(
  id: 'uid',
  email: 'awa@example.com',
  displayName: 'Awa',
  emailVerified: verified,
  hasPassword: password,
  hasGoogle: google,
  profile: profile,
);

FoundiUser copyUser(
  FoundiUser user, {
  bool? verified,
  String? email,
  AccountProfile? profile,
}) => FoundiUser(
  id: user.id,
  email: email ?? user.email,
  displayName: user.displayName,
  emailVerified: verified ?? user.emailVerified,
  hasPassword: user.hasPassword,
  hasGoogle: user.hasGoogle,
  profile: profile ?? user.profile,
);

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user});
  FoundiUser? user;
  final _changes = StreamController<FoundiUser?>.broadcast();
  late final Stream<FoundiUser?> _stream = Stream.multi((controller) {
    final subscription = _changes.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
    controller.add(user);
  }, isBroadcast: true);
  FoundiUser loginResult = account();
  int registrations = 0,
      logins = 0,
      requests = 0,
      googleRequests = 0,
      resets = 0,
      confirmations = 0;
  AccountProfile? savedProfile;
  String? resetEmail;
  bool wrongCode = false, failSending = false, wrongPassword = false;
  bool googleIsNew = true;
  bool? googleRegistering;
  Completer<void>? pendingLogin;

  void emit(FoundiUser? value) {
    user = value;
    _changes.add(value);
  }

  @override
  FoundiUser? get currentUser => user;
  @override
  Stream<FoundiUser?> authStateChanges() => _stream;
  @override
  Future<void> signInWithPassword(String email, String password) async {
    logins++;
    if (pendingLogin != null) await pendingLogin!.future;
    if (wrongPassword) {
      throw const AuthFailure('L’e-mail ou le mot de passe est incorrect.');
    }
    emit(loginResult);
  }

  @override
  Future<void> registerWithPassword({
    required String email,
    required String password,
    required AccountProfile profile,
  }) async {
    registrations++;
    savedProfile = profile;
    emit(account(verified: false, profile: profile));
  }

  @override
  Future<EmailChallenge> requestEmailCode() async {
    requests++;
    if (failSending) throw const AuthFailure('Envoi indisponible.');
    return EmailChallenge(
      id: 'challenge',
      email: user!.email,
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      resendAt: DateTime.now(),
    );
  }

  @override
  Future<void> verifyEmailCode(EmailChallenge challenge, String code) async {
    if (wrongCode) throw const AuthFailure('Ce code est incorrect.');
    emit(copyUser(user!, verified: true));
  }

  @override
  Future<void> changeRegistrationEmail(String email, String password) async {
    emit(copyUser(user!, email: email.trim().toLowerCase()));
  }

  @override
  Future<void> refreshUser() async {
    emit(user);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    resets++;
    resetEmail = email;
  }

  @override
  Future<void> signInWithGoogle({required bool registering}) async {
    googleRequests++;
    googleRegistering = registering;
    emit(
      account(
        password: false,
        google: true,
        profile: googleIsNew
            ? AccountProfile(
                fullName: 'Awa',
                registrationConfirmed: registering,
              )
            : completeProfile,
      ),
    );
  }

  @override
  Future<void> confirmGoogleRegistration() async {
    confirmations++;
    emit(
      copyUser(
        user!,
        profile: AccountProfile(
          fullName: user!.profile.fullName,
          phone: user!.profile.phone,
          profession: user!.profile.profession,
          registrationConfirmed: true,
        ),
      ),
    );
  }

  @override
  Future<void> saveProfile(AccountProfile profile) async {
    savedProfile = profile;
    emit(copyUser(user!, profile: profile));
  }

  @override
  Future<void> signOut() async {
    emit(null);
  }

  Future<void> close() => _changes.close();
}

Future<void> flow(
  WidgetTester tester,
  FakeAuthRepository repo,
  Future<void> Function() body,
) async {
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  try {
    await tester.pumpWidget(FoundiApp(authRepository: repo));
    await tester.pumpAndSettle();
    await body();
  } finally {
    await tester.pumpWidget(const SizedBox());
    await repo.close();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> text(WidgetTester tester, String key, String value) =>
    tester.enterText(find.byKey(ValueKey(key)), value);
Future<void> fillProfile(WidgetTester tester) async {
  await text(tester, 'fullName', 'Awa Kouassi');
  await text(tester, 'phone', '+225 07 00 00 00 00');
  await text(tester, 'profession', 'Étudiante');
}

Future<void> login(WidgetTester tester) async {
  await text(tester, 'email', 'awa@example.com');
  await text(tester, 'password', 'un-mot-de-passe-solide');
  await tap(tester, find.byKey(const ValueKey('submitAuth')));
}

Future<void> signupToCredentials(WidgetTester tester) async {
  await tap(tester, find.byKey(const ValueKey('switchAuthMode')));
  await fillProfile(tester);
  await tap(tester, find.byKey(const ValueKey('submitAuth')));
}

void main() {
  test('phone normalization preserves the international number', () {
    expect(
      AuthValidators.normalizePhone('+225 (07) 00-00.00 00'),
      '+2250700000000',
    );
    expect(AuthValidators.phone('0700000000'), isNotNull);
    expect(AuthValidators.phone('+2250700000000'), isNull);
    expect(AuthValidators.password('court'), isNotNull);
  });

  testWidgets('login validates email and password before calling Firebase', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await text(tester, 'email', 'bad');
      await tap(tester, find.byKey(const ValueKey('submitAuth')));
      expect(find.text('Saisis une adresse e-mail valide.'), findsOneWidget);
      expect(find.text('Saisis ton mot de passe.'), findsOneWidget);
      expect(repo.logins, 0);
    });
  });

  testWidgets('verified password login opens the account and can sign out', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await login(tester);
      expect(find.text('Mon compte'), findsOneWidget);
      expect(repo.requests, 0);
      await tap(tester, find.text('Se déconnecter'));
      expect(find.byKey(const ValueKey('email')), findsOneWidget);
    });
  });

  testWidgets('invalid credentials stay on login', (tester) async {
    final repo = FakeAuthRepository()..wrongPassword = true;
    await flow(tester, repo, () async {
      await login(tester);
      expect(
        find.text('L’e-mail ou le mot de passe est incorrect.'),
        findsOneWidget,
      );
      expect(find.text('Mon compte'), findsNothing);
    });
  });

  testWidgets('signup requires name phone and profession', (tester) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await tap(tester, find.byKey(const ValueKey('switchAuthMode')));
      await tap(tester, find.byKey(const ValueKey('submitAuth')));
      expect(
        find.text('Saisis ton nom complet (2 à 100 caractères).'),
        findsOneWidget,
      );
      expect(
        find.text('Renseigne ta profession ou ton activité.'),
        findsOneWidget,
      );
      expect(repo.registrations, 0);
    });
  });

  testWidgets('signup validates password length and confirmation', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await signupToCredentials(tester);
      await text(tester, 'email', 'awa@example.com');
      await text(tester, 'password', 'court');
      await text(tester, 'passwordConfirmation', 'autre');
      await tap(tester, find.byKey(const ValueKey('submitAuth')));
      expect(find.text('Utilise au moins 12 caractères.'), findsOneWidget);
      expect(
        find.text('Les mots de passe ne correspondent pas.'),
        findsOneWidget,
      );
      expect(repo.registrations, 0);
    });
  });

  testWidgets('classic signup saves the profile then requires the email code', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await signupToCredentials(tester);
      await text(tester, 'email', 'awa@example.com');
      await text(tester, 'password', 'un-mot-de-passe-solide');
      await text(tester, 'passwordConfirmation', 'un-mot-de-passe-solide');
      await tap(tester, find.byKey(const ValueKey('submitAuth')));
      expect(repo.registrations, 1);
      expect(repo.savedProfile!.phone, '+2250700000000');
      expect(repo.savedProfile!.profession, 'Étudiante');
      expect(find.text('Mon compte'), findsNothing);
      expect(find.byKey(const ValueKey('code')), findsOneWidget);
      await text(tester, 'code', '012345');
      await tap(tester, find.text('Valider mon e-mail'));
      expect(find.text('Mon compte'), findsOneWidget);
      expect(repo.user!.id, 'uid');
    });
  });

  testWidgets(
    'unverified login resumes verification instead of granting access',
    (tester) async {
      final repo = FakeAuthRepository()..loginResult = account(verified: false);
      await flow(tester, repo, () async {
        await login(tester);
        expect(find.text('Vérifier mon e-mail'), findsOneWidget);
        expect(find.text('Mon compte'), findsNothing);
        expect(repo.requests, 1);
      });
    },
  );

  testWidgets('unfinished classic profile is resumed before sending the code', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..loginResult = account(verified: false, profile: const AccountProfile());
    await flow(tester, repo, () async {
      await login(tester);
      expect(find.text('Compléter mon inscription'), findsOneWidget);
      expect(repo.requests, 0);
      await fillProfile(tester);
      await tap(tester, find.text('Continuer'));
      expect(find.byKey(const ValueKey('code')), findsOneWidget);
      expect(repo.requests, 1);
    });
  });

  testWidgets('incorrect verification code never opens the account', (
    tester,
  ) async {
    final repo = FakeAuthRepository(user: account(verified: false))
      ..wrongCode = true;
    await flow(tester, repo, () async {
      await text(tester, 'code', '999999');
      await tap(tester, find.text('Valider mon e-mail'));
      expect(find.text('Ce code est incorrect.'), findsOneWidget);
      expect(find.text('Mon compte'), findsNothing);
    });
  });

  testWidgets('resends without requiring a code', (tester) async {
    final repo = FakeAuthRepository(user: account(verified: false));
    await flow(tester, repo, () async {
      await tap(tester, find.text('Renvoyer un code'));
      expect(repo.requests, 2);
    });
  });

  testWidgets(
    'SMTP failure permits retry and retains the pending registration',
    (tester) async {
      final repo = FakeAuthRepository(user: account(verified: false))
        ..failSending = true;
      await flow(tester, repo, () async {
        expect(find.text('Envoi indisponible.'), findsOneWidget);
        repo.failSending = false;
        await tap(tester, find.text('Recevoir mon code'));
        expect(find.byKey(const ValueKey('code')), findsOneWidget);
      });
    },
  );

  testWidgets('email correction requests a new code for the same UID', (
    tester,
  ) async {
    final repo = FakeAuthRepository(user: account(verified: false));
    await flow(tester, repo, () async {
      await tap(tester, find.text('Corriger mon adresse e-mail'));
      await text(tester, 'newEmail', 'new@example.com');
      await text(tester, 'currentPassword', 'un-mot-de-passe-solide');
      await tap(tester, find.text('Modifier mon adresse'));
      expect(repo.user!.email, 'new@example.com');
      expect(repo.user!.id, 'uid');
      expect(repo.requests, 2);
    });
  });

  testWidgets('forgot password sends a link and shows a generic confirmation', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await tap(tester, find.text('Mot de passe oublié ?'));
      await text(tester, 'resetEmail', 'awa@example.com');
      await tap(tester, find.text('Envoyer le lien'));
      expect(repo.resets, 1);
      expect(repo.resetEmail, 'awa@example.com');
      expect(
        find.textContaining('Si cette adresse correspond à un compte'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'legacy users can define a password without creating another account',
    (tester) async {
      final repo = FakeAuthRepository(user: account(password: false));
      await flow(tester, repo, () async {
        expect(find.text('Sécuriser mon compte'), findsOneWidget);
        await tap(tester, find.text('Définir mon mot de passe'));
        await tap(tester, find.text('Envoyer le lien'));
        expect(repo.resetEmail, 'awa@example.com');
        expect(repo.registrations, 0);
        expect(repo.user!.id, 'uid');
      });
    },
  );

  testWidgets('a new Google account from login requires confirmation', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await tap(tester, find.byKey(const ValueKey('googleAuth')));
      expect(repo.googleRegistering, false);
      expect(find.text('C’est ta première visite'), findsOneWidget);
      expect(find.text('Mon compte'), findsNothing);
      await tap(tester, find.text('Créer mon compte'));
      expect(repo.confirmations, 1);
      expect(find.text('Mon compte'), findsOneWidget);
      expect(find.text('Compléter mon profil'), findsOneWidget);
    });
  });

  testWidgets('Google signup does not require the classic profile form', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await tap(tester, find.byKey(const ValueKey('switchAuthMode')));
      await tap(tester, find.byKey(const ValueKey('googleAuth')));
      expect(repo.googleRegistering, true);
      expect(find.text('Mon compte'), findsOneWidget);
      expect(repo.registrations, 0);
      expect(repo.requests, 0);
    });
  });

  testWidgets('existing Google account logs in directly', (tester) async {
    final repo = FakeAuthRepository()..googleIsNew = false;
    await flow(tester, repo, () async {
      await tap(tester, find.byKey(const ValueKey('googleAuth')));
      expect(find.text('Mon compte'), findsOneWidget);
      expect(find.text('C’est ta première visite'), findsNothing);
    });
  });

  testWidgets('new Google registration can be cancelled', (tester) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      await tap(tester, find.byKey(const ValueKey('googleAuth')));
      await tap(tester, find.text('Revenir à la connexion'));
      expect(repo.user, isNull);
      expect(find.byKey(const ValueKey('email')), findsOneWidget);
    });
  });

  testWidgets('Google users can save partial profile updates later', (
    tester,
  ) async {
    final repo = FakeAuthRepository(
      user: account(
        password: false,
        google: true,
        profile: const AccountProfile(
          fullName: 'Awa',
          registrationConfirmed: true,
        ),
      ),
    );
    await flow(tester, repo, () async {
      await tap(tester, find.text('Informations personnelles'));
      await text(tester, 'phone', '+33 6 00 00 00 00');
      await tap(tester, find.text('Enregistrer'));
      expect(repo.savedProfile!.phone, '+33600000000');
      expect(repo.savedProfile!.profession, '');
      expect(find.text('Mon compte'), findsOneWidget);
    });
  });

  testWidgets('duplicate requests are disabled while logging in', (
    tester,
  ) async {
    final repo = FakeAuthRepository()..pendingLogin = Completer<void>();
    await flow(tester, repo, () async {
      await text(tester, 'email', 'awa@example.com');
      await text(tester, 'password', 'un-mot-de-passe-solide');
      await tester.ensureVisible(find.byKey(const ValueKey('submitAuth')));
      await tester.tap(find.byKey(const ValueKey('submitAuth')));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(repo.logins, 1);
      repo.pendingLogin!.complete();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('restores a verified session without sending another code', (
    tester,
  ) async {
    final repo = FakeAuthRepository(user: account());
    await flow(tester, repo, () async {
      expect(find.text('Mon compte'), findsOneWidget);
      expect(repo.requests, 0);
    });
  });

  testWidgets('small screen with large text remains scrollable', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    await flow(tester, repo, () async {
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      try {
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('setupPassword')));
        expect(tester.takeException(), isNull);
        await tap(tester, find.byKey(const ValueKey('switchAuthMode')));
        await tester.ensureVisible(find.byKey(const ValueKey('googleAuth')));
        expect(tester.takeException(), isNull);
      } finally {
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      }
    });
  });
}
