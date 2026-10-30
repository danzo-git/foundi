import 'package:flutter/material.dart';

import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/account_screen.dart';
import 'features/auth/presentation/verification_screen.dart';
import 'features/professional/domain/professional_repository.dart';
import 'features/professional/presentation/professional_gate.dart';
import 'features/navigation/presentation/foundi_shell.dart';
import 'features/requests/domain/request_repository.dart';
import 'features/requests/presentation/request_views.dart';

class FoundiApp extends StatefulWidget {
  const FoundiApp({
    super.key,
    required this.authRepository,
    this.professionalRepository,
    this.requestRepository,
  });
  final AuthRepository authRepository;
  final ProfessionalRepository? professionalRepository;
  final RequestRepository? requestRepository;
  @override
  State<FoundiApp> createState() => _FoundiAppState();
}

class _FoundiAppState extends State<FoundiApp> {
  bool _authRequested = false;
  AuthRepository get authRepository => widget.authRepository;
  ProfessionalRepository? get professionalRepository =>
      widget.professionalRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Foundi',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F9F7),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF107865)),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: const Color(0xFF153F38),
        displayColor: const Color(0xFF153F38),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDCE7E2)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFDCE7E2)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF107865),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF153F38),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: StreamBuilder<FoundiUser?>(
      stream: authRepository.authStateChanges(),
      initialData: authRepository.currentUser,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AccountLoadErrorScreen(repository: authRepository);
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) {
          if (widget.requestRepository != null && !_authRequested) {
            return GuestRequests(
              catalog: professionalRepository,
              repository: widget.requestRepository!,
              onAuthenticate: () => setState(() => _authRequested = true),
            );
          }
          return AuthScreen(
            repository: authRepository,
            onExplore: widget.requestRepository == null
                ? null
                : () => setState(() => _authRequested = false),
          );
        }
        if (user.needsGoogleConfirmation) {
          return GoogleRegistrationScreen(
            user: user,
            repository: authRepository,
          );
        }
        if (user.needsPasswordSetup) {
          return PasswordSetupScreen(user: user, repository: authRepository);
        }
        if (user.needsClassicProfile) {
          return ProfileScreen(
            user: user,
            repository: authRepository,
            onboarding: true,
          );
        }
        if (!user.emailVerified) {
          return VerificationScreen(
            key: ValueKey('${user.id}-${user.email}'),
            user: user,
            repository: authRepository,
          );
        }
        return professionalRepository == null
            ? FoundiShell(
                user: user,
                auth: authRepository,
                requestRepository: widget.requestRepository,
                catalogRepository: professionalRepository,
              )
            : ProfessionalGate(
                key: ValueKey(user.id),
                user: user,
                auth: authRepository,
                repository: professionalRepository!,
                requestRepository: widget.requestRepository,
              );
      },
    ),
  );
}
