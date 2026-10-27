import 'package:flutter/material.dart';

import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/account_screen.dart';
import 'features/auth/presentation/verification_screen.dart';

class FoundiApp extends StatelessWidget {
  const FoundiApp({super.key, required this.authRepository});
  final AuthRepository authRepository;

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
        if (user == null) return AuthScreen(repository: authRepository);
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
        return AccountScreen(user: user, repository: authRepository);
      },
    ),
  );
}
