import 'dart:async';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
  AppLifecycleListener? _lifecycle;
  Future<void> _serial = Future.value();
  bool _signingOut = false;
  String? _uid;
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  Future<T> _queue<T>(Future<T> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {
        debugPrint('Foundi: synchronisation push indisponible.');
      },
    );
    return result;
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
    _refresh = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      final uid = _uid;
      if (uid != null) _queue(() => _register(uid, token));
    });
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
    _lifecycle = AppLifecycleListener(onResume: () => _queue(_sync));
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

  bool _canRegister(String uid) {
    final user = FirebaseAuth.instance.currentUser;
    return !_signingOut &&
        _uid == uid &&
        user?.uid == uid &&
        user?.emailVerified == true;
  }

  Future<bool> _register(String uid, String token) async {
    if (!_canRegister(uid)) return false;
    final deviceId = await _deviceId();
    if (!_canRegister(uid)) return false;
    await _functions.httpsCallable('registerNotificationDevice').call<void>({
      'deviceId': deviceId,
      'token': token,
      'platform': defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
    });
    return _canRegister(uid);
  }

  Future<bool> _sync() async {
    final uid = _uid;
    if (uid == null || !_canRegister(uid)) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (![
      AuthorizationStatus.authorized,
      AuthorizationStatus.provisional,
    ].contains(settings.authorizationStatus)) {
      return false;
    }
    // APNs may not be ready immediately after a restore. A later resume/enable retries safely.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await FirebaseMessaging.instance.getAPNSToken() == null) {
      return false;
    }
    if (!_canRegister(uid)) return false;
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    // ignore: deprecated_member_use
    final token = await FirebaseMessaging.instance.getToken();
    return token != null && await _register(uid, token);
  }

  @override
  Future<String> status() async {
    if (!supported) return 'Push disponibles sur Android et iOS.';
    final s = await FirebaseMessaging.instance.getNotificationSettings();
    if (s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional) {
      try {
        if (await _queue(_sync)) return 'Alertes actives sur ce téléphone.';
      } catch (_) {
        // The settings screen can retry registration after a temporary error.
      }
      return 'Notifications autorisées. Réessaie pour enregistrer ce téléphone.';
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
    await _queue(_sync);
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
    _lifecycle?.dispose();
    await Future.wait([
      if (_auth case final auth?) auth.cancel(),
      if (_refresh case final refresh?) refresh.cancel(),
      if (_opens case final opens?) opens.cancel(),
    ]);
  }
}
