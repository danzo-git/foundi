import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<FirebaseAuthRepository> _initialization = _initialize();

  Future<FirebaseAuthRepository> _initialize() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (const bool.fromEnvironment('USE_FIREBASE_EMULATORS')) {
      const configuredHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
      final host = configuredHost.isNotEmpty
          ? configuredHost
          : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
                ? '10.0.2.2'
                : 'localhost');
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).useFunctionsEmulator(host, 5001);
    }
    return FirebaseAuthRepository();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return FoundiApp(authRepository: snapshot.requireData);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Impossible de démarrer Foundi. Réessaie dans un instant.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() {
                            _initialization = _initialize();
                          }),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}
