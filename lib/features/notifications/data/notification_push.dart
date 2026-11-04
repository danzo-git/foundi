import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/notification_repository.dart';
import '../presentation/notification_views.dart';

/// Mobile FCM only. Inbox works on every existing Foundi platform.
class NotificationPush implements PushPermission {
  NotificationPush(this.intent);
  final ValueNotifier<NotificationIntent?> intent;
  final _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
  StreamSubscription<User?>? _auth;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _opens;
  Future<void> _serial = Future.value();
  bool _signingOut = false;
  String? _uid;
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  void _queue(Future<void> Function() action) {
    _serial = _serial.then((_) => action()).catchError((Object _) {
      // Do not log tokens or private payloads. Inbox remains available after FCM errors.
      debugPrint('Foundi: synchronisation push indisponible.');
    });
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('foundi.notification.device');
    if (existing != null) return existing;
    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await prefs.setString('foundi.notification.device', id);
    return id;
  }

  Future<void> initialize() async {
    if (!supported) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(false);
    // The realtime inbox is the sole foreground presentation. No duplicate banners, including active chat.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
    _opens = FirebaseMessaging.onMessageOpenedApp.listen(_open);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _open(initial);
    // Keep registration-token semantics used by Admin SDK messaging.send.
    // ignore: deprecated_member_use
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) => _queue(() => _register(token)),
    );
    _auth = FirebaseAuth.instance.userChanges().listen((user) {
      final uid = user != null && user.emailVerified ? user.uid : null;
      _queue(() async {
        if (_uid != null && _uid != uid) {
          // Also invalidate locally if authentication expired before a server unregister was possible.
          // ignore: deprecated_member_use
          await FirebaseMessaging.instance.deleteToken();
        }
        _uid = uid;
        if (uid != null && !_signingOut) await _sync();
      });
    });
  }

  void _open(RemoteMessage message) {
    final id = message.data['notificationId'],
        uid = message.data['recipientUid'];
    if (id is String &&
        uid is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(id) &&
        RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(uid)) {
      intent.value = NotificationIntent(uid, id);
    }
  }

  Future<void> _register(String token) async {
    final current = FirebaseAuth.instance.currentUser;
    if (_signingOut ||
        current == null ||
        current.uid != _uid ||
        !current.emailVerified) {
      return;
    }
    await _functions.httpsCallable('registerNotificationDevice').call<void>({
      'deviceId': await _deviceId(),
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
    });
  }

  Future<void> _sync() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (![
      AuthorizationStatus.authorized,
      AuthorizationStatus.provisional,
    ].contains(settings.authorizationStatus)) {
      return;
    }
    // APNs may not be ready immediately after a restore. A later resume/enable retries safely.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await FirebaseMessaging.instance.getAPNSToken() == null) {
      return;
    }
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _register(token);
  }

  @override
  Future<String> status() async {
    if (!supported) return 'Push disponibles sur Android et iOS.';
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    if (s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional) {
      _queue(_sync);
      return 'Notifications autorisées sur ce téléphone.';
    }
    if (s.authorizationStatus == AuthorizationStatus.denied) {
      return 'Notifications refusées. Tu peux les autoriser dans les réglages du téléphone.';
    }
    return 'Autorisation du téléphone non demandée.';
  }

  @override
  Future<void> enable() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (![
          AuthorizationStatus.authorized,
          AuthorizationStatus.provisional,
        ].contains(settings.authorizationStatus) &&
        prefs.getBool('foundi.notification.asked') != true) {
      await prefs.setBool('foundi.notification.asked', true);
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    // Serialize against account switches/token refresh; never attach the old token to a new account.
    final registration = _serial.then((_) => _sync());
    _serial = registration.catchError((Object _) {
      debugPrint('Foundi: synchronisation push indisponible.');
    });
    await registration;
  }

  Future<void> beforeSignOut() async {
    if (!supported) return;
    _signingOut = true;
    await _serial;
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      // Complete one revocation path before signing out. Do not silently keep a live account token.
      try {
        await _functions
            .httpsCallable('unregisterNotificationDevice')
            .call<void>({'deviceId': await _deviceId()});
      } catch (_) {
        // ignore: deprecated_member_use
        await FirebaseMessaging.instance.deleteToken();
      }
      try {
        // ignore: deprecated_member_use
        await FirebaseMessaging.instance.deleteToken();
      } catch (_) {
        /* Server unregister already revoked this installation. */
      }
      _uid = null;
    } finally {
      _signingOut = false;
    }
  }

  Future<void> dispose() async {
    await _auth?.cancel();
    await _refresh?.cancel();
    await _opens?.cancel();
  }
}
