import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'admin_shell.dart';
import 'admin_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const emulated =
      bool.fromEnvironment('USE_EMULATORS') ||
      bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  const project = String.fromEnvironment(
    'FIREBASE_EMULATOR_PROJECT',
    defaultValue: 'demo-foundi',
  );
  const options = DefaultFirebaseOptions.web;
  await Firebase.initializeApp(
    options: emulated
        ? FirebaseOptions(
            apiKey: options.apiKey,
            appId: options.appId,
            messagingSenderId: options.messagingSenderId,
            projectId: project,
            authDomain: '$project.firebaseapp.com',
            storageBucket: '$project.appspot.com',
          )
        : options,
  );
  await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
  if (emulated) {
    await FirebaseAuth.instance.useAuthEmulator(
      '127.0.0.1',
      const int.fromEnvironment(
        'FIREBASE_AUTH_EMULATOR_PORT',
        defaultValue: 9099,
      ),
    );
    db.useFirestoreEmulator(
      '127.0.0.1',
      const int.fromEnvironment('FIRESTORE_EMULATOR_PORT', defaultValue: 8080),
    );
    functions.useFunctionsEmulator(
      '127.0.0.1',
      const int.fromEnvironment('FUNCTIONS_EMULATOR_PORT', defaultValue: 5001),
    );
  }
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Foundi Admin',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F9F7),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF107865)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDCE6E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDCE6E8)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE3EAEC)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF00856F),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
    ),
    home: const SessionGate(),
  );
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});
  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(minutes: 5), (_) {
      FirebaseAuth.instance.currentUser
          ?.getIdToken(true)
          .catchError((Object e) => null);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.idTokenChanges(),
    builder: (context, s) {
      if (s.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (s.data == null) return const Login();
      return FutureBuilder<IdTokenResult>(
        future: s.data!.getIdTokenResult(),
        builder: (context, t) {
          if (t.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (t.hasError || t.data?.claims?['admin'] != true) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Accès non autorisé'),
                    TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: const Text('Se déconnecter'),
                    ),
                  ],
                ),
              ),
            );
          }
          return const AdminShell();
        },
      );
    },
  );
}

class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Connexion impossible. Vérifiez vos identifiants et votre connexion.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 420,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 48),
                  const Text(
                    'Foundi Admin',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(
                      labelText: 'Adresse e-mail',
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                    ),
                    onSubmitted: (_) {
                      if (!busy) login();
                    },
                  ),
                  if (error != null) Text(error!),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : login,
                    child: Text(busy ? 'Connexion…' : 'Se connecter'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
