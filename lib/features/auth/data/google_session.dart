import 'package:google_sign_in/google_sign_in.dart';

// The plugin requires exactly one initialization for the process, including
// reauthentication from account deletion after an earlier Google login.
Future<void>? _initialization;
bool get googleSessionInitialized => _initialization != null;
Future<void> initializeGoogleSession() =>
    _initialization ??= GoogleSignIn.instance.initialize();
