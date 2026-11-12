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
import 'features/requests/presentation/direct_requests.dart';

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
  final _navigator = GlobalKey<NavigatorState>();
  late String? _sessionUid = widget.authRepository.currentUser?.id;
  void _sessionChanged(String? uid) {
    if (_sessionUid == uid) return;
    _sessionUid = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navigator.currentState?.popUntil((route) => route.isFirst);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }

  bool _authRequested = false;
  final _directNavigation = ValueNotifier<DirectRequestIntent?>(null);
  DirectProfessionalTarget? _pendingDirect;
  @override
  void dispose() {
    _directNavigation.dispose();
    super.dispose();
  }

  void _requestDirect(DirectProfessionalTarget target) {
    final user = authRepository.currentUser;
    if (user?.id == target.id) return;
    if (user == null ||
        !user.emailVerified ||
        user.needsClassicProfile ||
        user.needsGoogleConfirmation ||
        user.needsPasswordSetup) {
      _pendingDirect = target;
      _navigator.currentState?.popUntil((route) => route.isFirst);
      setState(() => _authRequested = true);
      return;
    }
    final catalog = professionalRepository;
    final requests = widget.requestRepository;
    if (catalog == null || requests is! DirectRequestRepository) return;
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => DirectRequestFormPage(
          repository: requests!,
          catalog: catalog,
          target: target,
          user: user,
          navigation: _directNavigation,
        ),
      ),
    );
  }

  AuthRepository get authRepository => widget.authRepository;
  ProfessionalRepository? get professionalRepository =>
      widget.professionalRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'Foundi',
    debugShowCheckedModeBanner: false,
    builder: (context, child) => DirectRequestsScope(
      auth: authRepository,
      navigation: _directNavigation,
      onRequest:
          widget.requestRepository is DirectRequestRepository &&
              professionalRepository != null
          ? _requestDirect
          : null,
      child: child!,
    ),
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
        _sessionChanged(user?.id);
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
        final pending = _pendingDirect;
        if (pending != null) {
          _pendingDirect = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && authRepository.currentUser?.id == user.id) {
              _requestDirect(pending);
            }
          });
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
