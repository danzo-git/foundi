import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/auth/domain/auth_repository.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';

const profile = AccountProfile(
  fullName: 'Awa Kouassi',
  registrationConfirmed: true,
);
const activity = ProfessionalActivity(
  businessName: 'Awa Services',
  categoryIds: ['test_sector'],
  specialtyIds: ['test_specialty'],
  zoneIds: ['test_zone'],
  description: 'Mes prestations de service pour les clients de Foundi.',
);
const catalog = ProfessionalCatalog(
  enabled: true,
  categories: [
    ProfessionalCategory(
      'test_sector',
      'Catégorie de test',
      [ReferenceChoice('test_specialty', 'Spécialité de test')],
      {
        'independent': ['qualification'],
        'company': ['qualification'],
      },
    ),
  ],
  zones: [ReferenceChoice('test_zone', 'Zone de test')],
  documents: [
    ReferenceChoice('identity', 'Pièce d’identité'),
    ReferenceChoice('qualification', 'Justificatif professionnel'),
  ],
);
FoundiUser account({
  bool verified = true,
  bool google = false,
  bool password = true,
  AccountProfile data = profile,
}) => FoundiUser(
  id: 'uid',
  email: 'awa@example.com',
  displayName: 'Awa',
  emailVerified: verified,
  hasPassword: password,
  hasGoogle: google,
  profile: data,
);
FoundiUser copy(
  FoundiUser u, {
  bool? verified,
  AccountProfile? data,
  String? email,
}) => FoundiUser(
  id: u.id,
  email: email ?? u.email,
  displayName: u.displayName,
  emailVerified: verified ?? u.emailVerified,
  hasPassword: u.hasPassword,
  hasGoogle: u.hasGoogle,
  profile: data ?? u.profile,
);

class FakeAuth implements AuthRepository {
  FakeAuth({this.user});
  FoundiUser? user;
  final changes = StreamController<FoundiUser?>.broadcast();
  late final Stream<FoundiUser?> stream = Stream.multi((c) {
    final s = changes.stream.listen(c.add);
    c.onCancel = s.cancel;
    c.add(user);
  }, isBroadcast: true);
  int requests = 0, registrations = 0, resets = 0, modeWrites = 0, signOuts = 0;
  bool wrongCode = false,
      wrongPassword = false,
      failSending = false,
      googleNew = true;
  String? googlePath;
  AccountProfile? saved;
  LegalDocuments legal = const LegalDocuments();
  void emit(FoundiUser? u) {
    user = u;
    changes.add(u);
  }

  @override
  FoundiUser? get currentUser => user;
  @override
  Stream<FoundiUser?> authStateChanges() => stream;
  @override
  Future<void> signInWithPassword(String email, String password) async {
    if (wrongPassword) {
      throw const AuthFailure('L’e-mail ou le mot de passe est incorrect.');
    }
    emit(user ?? account());
  }

  @override
  Future<void> registerWithPassword({
    required String email,
    required String password,
    required AccountProfile profile,
  }) async {
    saved = profile;
    registrations++;
    emit(account(verified: false, data: profile));
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
  Future<void> verifyEmailCode(EmailChallenge c, String code) async {
    if (wrongCode) throw const AuthFailure('Ce code est incorrect.');
    emit(copy(user!, verified: true));
  }

  @override
  Future<void> changeRegistrationEmail(String email, String password) async =>
      emit(copy(user!, email: email));
  @override
  Future<void> refreshUser() async => emit(user);
  @override
  Future<void> sendPasswordReset(String email) async {
    resets++;
  }

  @override
  Future<void> signInWithGoogle({
    required bool registering,
    String registrationPath = 'client',
    String termsVersion = '',
  }) async {
    googlePath = registrationPath;
    emit(
      account(
        google: true,
        password: false,
        data: googleNew
            ? profile.copyWith(
                registrationConfirmed: registering,
                registrationPath: registrationPath,
                termsVersion: termsVersion,
              )
            : profile,
      ),
    );
  }

  @override
  Future<void> confirmGoogleRegistration({
    String registrationPath = 'client',
    String termsVersion = '',
  }) async => emit(
    copy(
      user!,
      data: user!.profile.copyWith(
        registrationConfirmed: true,
        registrationPath: registrationPath,
        termsVersion: termsVersion,
      ),
    ),
  );
  @override
  Future<void> saveProfile(AccountProfile profile) async {
    saved = profile;
    emit(copy(user!, data: profile));
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    emit(null);
  }

  @override
  Future<LegalDocuments> loadLegalDocuments() async => legal;
  @override
  Future<void> acceptLegal(String version) async =>
      emit(copy(user!, data: user!.profile.copyWith(termsVersion: version)));
  @override
  Future<void> setPreferredMode(String mode) async {
    modeWrites++;
    emit(copy(user!, data: user!.profile.copyWith(preferredMode: mode)));
  }
}

class FakePro implements ProfessionalRepository {
  FakePro({this.profile = const ProfessionalProfile()});
  ProfessionalProfile profile;
  ProfessionalCatalog references = catalog;
  List<ProfessionalDocument> documents = [];
  final changes = StreamController<ProfessionalProfile>.broadcast();
  final docChanges = StreamController<List<ProfessionalDocument>>.broadcast();
  bool failSave = false;
  int accessChecks = 0;
  void emit(ProfessionalProfile p) {
    profile = p;
    changes.add(p);
  }

  @override
  Stream<ProfessionalProfile> watchProfile(String uid) => Stream.multi((c) {
    final s = changes.stream.listen(c.add);
    c.onCancel = s.cancel;
    c.add(profile);
  });
  @override
  Stream<List<ProfessionalDocument>> watchDocuments(String uid) =>
      Stream.multi((c) {
        final s = docChanges.stream.listen(c.add);
        c.onCancel = s.cancel;
        c.add(documents);
      });
  @override
  Future<ProfessionalCatalog> loadCatalog() async => references;
  @override
  Stream<ProfessionalCatalog> watchCatalog() => loadCatalog().asStream();
  @override
  Future<void> start() async {
    if (profile.status == ProfessionalStatus.none) {
      emit(const ProfessionalProfile(status: ProfessionalStatus.draft));
    }
  }

  @override
  Future<void> saveActivity(
    ProfessionalActivity value, {
    required bool complete,
  }) async {
    if (failSave) throw const AuthFailure('Réseau indisponible.');
    emit(
      ProfessionalProfile(
        status: ProfessionalStatus.draft,
        step: complete ? 3 : 2,
        activity: value,
      ),
    );
  }

  @override
  Future<void> uploadDocument(String kind, String name, Uint8List bytes) async {
    documents.removeWhere((d) => d.kind == kind);
    documents.add(ProfessionalDocument(kind, name, true));
    docChanges.add(documents);
  }

  @override
  Future<void> submit({required bool certified}) async {
    if (!certified ||
        ![
          'identity',
          'qualification',
        ].every((id) => documents.any((d) => d.kind == id && d.ready))) {
      throw const AuthFailure('Justificatifs manquants.');
    }
    emit(
      ProfessionalProfile(
        status: ProfessionalStatus.pending,
        step: 3,
        activity: profile.activity,
      ),
    );
  }

  @override
  Future<void> checkAccess() async {
    accessChecks++;
    if (!profile.approved) throw const AuthFailure('Accès refusé.');
  }
}

Future<void> flow(
  WidgetTester t,
  FakeAuth a,
  FakePro p,
  Future<void> Function() body,
) async {
  t.view.physicalSize = const Size(430, 932);
  t.view.devicePixelRatio = 1;
  try {
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: FoundiApp(authRepository: a, professionalRepository: p),
      ),
    );
    await t.pumpAndSettle();
    await body();
  } finally {
    await t.pumpWidget(const SizedBox());
    await a.changes.close();
    await p.changes.close();
    await p.docChanges.close();
    t.view.resetPadding();
    t.view.resetViewPadding();
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  }
}

Future<void> tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> fill(WidgetTester t, String key, String value) async {
  final f = find.byKey(ValueKey(key));
  await t.ensureVisible(f);
  await t.enterText(f, value);
}

Future<void> choose(WidgetTester t, {bool professional = false}) async {
  await tap(t, find.byKey(const ValueKey('switchAuthMode')));
  await tap(
    t,
    find.byKey(ValueKey(professional ? 'professionalPath' : 'clientPath')),
  );
  await tap(t, find.byKey(const ValueKey('continuePath')));
}

Future<void> signup(WidgetTester t) async {
  await fill(t, 'fullName', 'Awa Kouassi');
  await fill(t, 'email', 'awa@example.com');
  await fill(t, 'password', 'mot-de-passe-solide');
  await tap(t, find.byKey(const ValueKey('submitAuth')));
}

Future<void> verify(WidgetTester t) async {
  await fill(t, 'code', '012345');
  await tap(t, find.text('Valider mon e-mail'));
}

Future<void> capture(WidgetTester t, int page) async {
  if (!const bool.fromEnvironment('V3_CAPTURE')) return;
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('.dart_tool/v3-preview')
      ..createSync(recursive: true);
    await File(
      '${directory.path}/page-$page.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('V3_CAPTURE')) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (font.existsSync()) {
        await (FontLoader('Roboto')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
    }
  });
  testWidgets(
    'common login validates both credentials and keeps invalid login on screen',
    (t) async {
      final a = FakeAuth()..wrongPassword = true;
      await flow(t, a, FakePro(), () async {
        await tap(t, find.byKey(const ValueKey('submitAuth')));
        expect(find.text('Saisis ton mot de passe.'), findsOneWidget);
        await fill(t, 'email', 'awa@example.com');
        await fill(t, 'password', 'wrong');
        await tap(t, find.byKey(const ValueKey('submitAuth')));
        expect(
          find.text('L’e-mail ou le mot de passe est incorrect.'),
          findsOneWidget,
        );
        expect(a.user, isNull);
      });
    },
  );
  testWidgets(
    'V3 pages 1 to 3: explicit path then short client signup without profession or mandatory phone',
    (t) async {
      final a = FakeAuth();
      await flow(t, a, FakePro(), () async {
        await capture(t, 2);
        await tap(t, find.byKey(const ValueKey('switchAuthMode')));
        await capture(t, 1);
        await tap(t, find.byKey(const ValueKey('clientPath')));
        await tap(t, find.byKey(const ValueKey('continuePath')));
        expect(find.text('Étape 1 sur 3'), findsNothing);
        expect(find.byKey(const ValueKey('profession')), findsNothing);
        await signup(t);
        expect(a.saved!.phone, '');
        expect(a.saved!.registrationPath, 'client');
        expect(find.byKey(const ValueKey('code')), findsOneWidget);
        await verify(t);
        expect(find.byKey(const ValueKey('nav-0')), findsOneWidget);
        expect(a.user!.id, 'uid');
      });
    },
  );
  testWidgets(
    'professional signup preserves the path across verification and V3 activity',
    (t) async {
      final a = FakeAuth();
      final p = FakePro();
      await flow(t, a, p, () async {
        await choose(t, professional: true);
        await capture(t, 3);
        expect(find.text('Étape 1 sur 3'), findsOneWidget);
        await signup(t);
        await verify(t);
        expect(find.text('Parlons de ton activité'), findsOneWidget);
        await capture(t, 4);
        expect(p.profile.status, ProfessionalStatus.draft);
        expect(a.user!.profile.registrationPath, 'professional');
      });
    },
  );
  testWidgets(
    'Google follows the chosen professional path and uses the same UID',
    (t) async {
      final a = FakeAuth();
      await flow(t, a, FakePro(), () async {
        await choose(t, professional: true);
        await tap(t, find.byKey(const ValueKey('googleAuth')));
        expect(a.googlePath, 'professional');
        expect(a.requests, 0);
        expect(a.user!.id, 'uid');
        expect(find.text('Parlons de ton activité'), findsOneWidget);
      });
    },
  );
  testWidgets(
    'new Google login requires explicit account confirmation and existing login remains common',
    (t) async {
      final a = FakeAuth();
      await flow(t, a, FakePro(), () async {
        await tap(t, find.byKey(const ValueKey('googleAuth')));
        expect(find.text('C’est ta première visite'), findsOneWidget);
        await tap(t, find.text('Créer mon compte'));
        expect(find.byKey(const ValueKey('nav-0')), findsOneWidget);
      });
    },
  );
  testWidgets(
    'published terms require explicit consent and save their version',
    (t) async {
      final a = FakeAuth()
        ..legal = const LegalDocuments(
          version: 'v1',
          terms: 'Conditions de test',
          privacy: 'Confidentialité de test',
        );
      await flow(t, a, FakePro(), () async {
        await choose(t);
        await signup(t);
        expect(a.registrations, 0);
        expect(
          find.text('Accepte les CGU et la politique de confidentialité.'),
          findsOneWidget,
        );
        await tap(t, find.byKey(const ValueKey('acceptTerms')));
        await tap(t, find.byKey(const ValueKey('submitAuth')));
        expect(a.saved!.termsVersion, 'v1');
      });
    },
  );
  testWidgets('incorrect code or SMTP outage cannot skip verification', (
    t,
  ) async {
    final a = FakeAuth(user: account(verified: false))..failSending = true;
    await flow(t, a, FakePro(), () async {
      expect(find.text('Envoi indisponible.'), findsOneWidget);
      a.failSending = false;
      a.wrongCode = true;
      await tap(t, find.text('Recevoir mon code'));
      await verify(t);
      expect(find.text('Ce code est incorrect.'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-0')), findsNothing);
    });
  });
  testWidgets('password reset retains its generic confirmation', (t) async {
    final a = FakeAuth();
    await flow(t, a, FakePro(), () async {
      await tap(t, find.text('Mot de passe oublié ?'));
      await fill(t, 'resetEmail', 'awa@example.com');
      await tap(t, find.text('Envoyer le lien'));
      expect(a.resets, 1);
      expect(
        find.textContaining('Si cette adresse correspond à un compte'),
        findsOneWidget,
      );
    });
  });
  testWidgets(
    'draft reconnect resumes step 3 with already uploaded documents; V3 pages 5 and 6',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.draft,
          step: 3,
          activity: activity,
        ),
      );
      p.documents = [
        const ProfessionalDocument('identity', 'identite.pdf', true),
      ];
      await flow(t, FakeAuth(user: account()), p, () async {
        expect(find.text('Dossier à compléter'), findsOneWidget);
        await capture(t, 6);
        await tap(t, find.text('Reprendre mon dossier'));
        expect(find.text('Vérifie ton profil'), findsOneWidget);
        expect(find.text('identite.pdf'), findsOneWidget);
        await capture(t, 5);
        final button = t.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Soumettre mon dossier'),
        );
        expect(button.onPressed, isNull);
        await tap(t, find.text('Enregistrer et terminer plus tard'));
        expect(find.text('Dossier à compléter'), findsOneWidget);
      });
    },
  );
  testWidgets(
    'partial activity auto-saves and can be resumed without restarting account registration',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(status: ProfessionalStatus.draft),
      );
      await flow(t, FakeAuth(user: account()), p, () async {
        await tap(t, find.text('Reprendre mon dossier'));
        await fill(t, 'businessName', 'Mon activité');
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(p.profile.activity.businessName, 'Mon activité');
        await tap(t, find.text('Enregistrer et terminer plus tard'));
        await tap(t, find.text('Reprendre mon dossier'));
        expect(
          t
              .widget<TextFormField>(find.byKey(const ValueKey('businessName')))
              .controller!
              .text,
          'Mon activité',
        );
      });
    },
  );
  testWidgets(
    'failed draft save stays editable and shows retryable network error',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(status: ProfessionalStatus.draft),
      )..failSave = true;
      await flow(t, FakeAuth(user: account()), p, () async {
        await tap(t, find.text('Reprendre mon dossier'));
        await fill(t, 'businessName', 'Mon activité');
        await tap(t, find.text('Enregistrer et terminer plus tard'));
        expect(find.text('Parlons de ton activité'), findsOneWidget);
        expect(find.textContaining('Brouillon non synchronisé'), findsWidgets);
        p.failSave = false;
        await tap(t, find.text('Enregistrer et terminer plus tard'));
        expect(find.text('Dossier à compléter'), findsOneWidget);
      });
    },
  );
  testWidgets(
    'client can activate professional onboarding without another Firebase account',
    (t) async {
      final a = FakeAuth(user: account());
      await flow(t, a, FakePro(), () async {
        await tap(t, find.byKey(const ValueKey('nav-4')));
        await tap(t, find.text('Devenir professionnel'));
        expect(find.text('Parlons de ton activité'), findsOneWidget);
        expect(a.registrations, 0);
        expect(a.user!.id, 'uid');
      });
    },
  );
  testWidgets(
    'all documents and certification permit pending but never grant professional permissions; V3 page 7',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.draft,
          step: 3,
          activity: activity,
        ),
      );
      p.documents = [
        const ProfessionalDocument('identity', 'identity.pdf', true),
        const ProfessionalDocument('qualification', 'pro.pdf', true),
      ];
      await flow(t, FakeAuth(user: account()), p, () async {
        await tap(t, find.text('Reprendre mon dossier'));
        await tap(t, find.byKey(const ValueKey('certifyProfile')));
        await tap(t, find.text('Soumettre mon dossier'));
        expect(find.text('Vérification en attente'), findsOneWidget);
        await capture(t, 7);
        expect(p.profile.approved, false);
        await tap(t, find.text('Suivre mon dossier  ›'));
        expect(find.text('Vérification en attente'), findsOneWidget);
        await tap(t, find.text('Retour à l’accueil'));
        expect(find.byKey(const ValueKey('nav-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('homeSpaceSelector')), findsNothing);
      });
    },
  );
  testWidgets(
    'approval arrives live and space changes are UI-only without logout',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(status: ProfessionalStatus.pending),
      );
      final a = FakeAuth(user: account());
      await flow(t, a, p, () async {
        p.emit(const ProfessionalProfile(status: ProfessionalStatus.approved));
        await t.pumpAndSettle();
        await tap(t, find.byKey(const ValueKey('nav-4')));
        expect(find.text('Professionnel vérifié'), findsOneWidget);
        await tap(t, find.text('Changer d’espace  ›'));
        await tap(t, find.text('Espace professionnel'));
        await tap(t, find.byKey(const ValueKey('confirmSpace')));
        expect(find.byKey(const ValueKey('professionalHome')), findsOneWidget);
        expect(a.modeWrites, 0);
        expect(p.accessChecks, 0);
        expect(a.user!.profile.preferredMode, 'client');
        await tap(t, find.byKey(const ValueKey('homeSpaceSelector')));
        await tap(t, find.text('Espace client'));
        await tap(t, find.byKey(const ValueKey('confirmSpace')));
        expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
        expect(a.user!.id, 'uid');
        expect(a.signOuts, 0);
      });
    },
  );
  testWidgets(
    'suspension immediately returns to client even with a professional display preference',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(status: ProfessionalStatus.approved),
      );
      final a = FakeAuth(
        user: account(data: profile.copyWith(preferredMode: 'professional')),
      );
      await flow(t, a, p, () async {
        expect(find.byKey(const ValueKey('professionalHome')), findsOneWidget);
        p.emit(const ProfessionalProfile(status: ProfessionalStatus.suspended));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('professionalHome')), findsNothing);
        expect(find.byKey(const ValueKey('clientHome')), findsOneWidget);
        expect(find.byKey(const ValueKey('homeSpaceSelector')), findsNothing);
        await tap(t, find.byKey(const ValueKey('nav-4')));
        expect(
          t.widget<Text>(find.byKey(const ValueKey('currentSpace'))).data,
          'Client',
        );
        expect(a.modeWrites, 0);
      });
    },
  );
  testWidgets(
    'missing references do not invent categories or allow completion',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(status: ProfessionalStatus.draft),
      )..references = const ProfessionalCatalog();
      await flow(t, FakeAuth(user: account()), p, () async {
        await tap(t, find.text('Reprendre mon dossier'));
        expect(find.textContaining('sont en préparation'), findsOneWidget);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continuer'),
              )
              .onPressed,
          isNull,
        );
        await fill(t, 'businessName', 'Mon activité');
        await tap(t, find.text('Enregistrer et terminer plus tard'));
        expect(p.profile.activity.businessName, 'Mon activité');
      });
    },
  );
  testWidgets(
    'correction request displays reason and allows resuming without pro access',
    (t) async {
      final p = FakePro(
        profile: const ProfessionalProfile(
          status: ProfessionalStatus.needsChanges,
          reviewReason: 'Document illisible',
        ),
      );
      await flow(t, FakeAuth(user: account()), p, () async {
        expect(find.text('Document illisible'), findsOneWidget);
        await tap(t, find.text('Reprendre mon dossier'));
        expect(find.byKey(const ValueKey('businessName')), findsOneWidget);
        expect(p.accessChecks, 0);
      });
    },
  );
  testWidgets('small screen and large text remain scrollable', (t) async {
    await flow(t, FakeAuth(), FakePro(), () async {
      t.view.physicalSize = const Size(320, 568);
      t.platformDispatcher.textScaleFactorTestValue = 1.5;
      try {
        await t.pumpAndSettle();
        await choose(t, professional: true);
        await t.ensureVisible(find.byKey(const ValueKey('googleAuth')));
        expect(t.takeException(), isNull);
      } finally {
        t.platformDispatcher.clearTextScaleFactorTestValue();
      }
    });
  });
}
