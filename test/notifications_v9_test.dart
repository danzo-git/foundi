import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/app.dart';
import 'package:foundi/features/notifications/domain/notification_repository.dart';
import 'package:foundi/features/notifications/presentation/notification_views.dart';
import 'widget_test.dart' as fixtures;

class InboxFake implements NotificationRepository {
  final changes = StreamController<List<FoundiNotification>>.broadcast();
  List<FoundiNotification> items = [];
  List<FoundiNotification> older = [];
  final reads = <String>[];
  int allReads = 0, pages = 0;
  bool unavailable = false;
  final prefs = StreamController<Map<String, bool>>.broadcast();
  Map<String, bool> preferences = {
    for (final k in ['messages', 'proposals', 'opportunities', 'account'])
      k: true,
  };
  final resolved = <String>[];
  NotificationTarget target = const NotificationTarget('professional', 'u');
  @override
  Stream<List<FoundiNotification>> watchInbox(
    String uid, {
    int limit = 30,
  }) async* {
    if (unavailable) {
      throw StateError('offline');
    }
    yield items;
    yield* changes.stream;
  }

  @override
  Future<List<FoundiNotification>> loadOlder(String uid, String afterId) async {
    pages++;
    return older;
  }

  @override
  Stream<int> watchUnread(String uid) =>
      Stream.value(items.where((n) => n.unread).length);
  @override
  Future<void> markRead(String uid, String id) async {
    reads.add(id);
  }

  @override
  Future<void> markAllRead(String uid) async {
    allReads++;
    items = [];
    changes.add(items);
  }

  @override
  Future<NotificationTarget> resolve(String id) async {
    resolved.add(id);
    if (unavailable) throw StateError('forbidden');
    return target;
  }

  @override
  Stream<Map<String, bool>> watchPreferences(String uid) async* {
    yield preferences;
    yield* prefs.stream;
  }

  @override
  Future<void> savePreferences(String uid, Map<String, bool> p) async {
    preferences = p;
    prefs.add(p);
  }

  Future<void> close() async {
    await changes.close();
    await prefs.close();
  }
}

class PermissionFake implements PushPermission {
  int asked = 0;
  String message = 'Autorisation du téléphone non demandée.';
  @override
  Future<String> status() async => message;
  @override
  Future<void> enable() async {
    asked++;
    message =
        'Notifications refusées. Autorise-les dans les réglages du téléphone.';
  }
}

FoundiNotification n(
  String id, {
  String type = 'conversation.opened',
  String category = 'messages',
  String title = 'Nouveau message',
  bool read = false,
  int minutes = 1,
}) => FoundiNotification(
  id: id,
  type: type,
  category: category,
  title: title,
  body: 'Ton activité est disponible dans Foundi.',
  createdAt: DateTime.now().subtract(Duration(minutes: minutes)),
  readAt: read ? DateTime.now() : null,
);
const captureKey = ValueKey('v9-capture');
Future<void> showScreen(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF107865)),
          scaffoldBackgroundColor: const Color(0xFFF6F9F7),
          cardTheme: CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFDCE7E2)),
            ),
          ),
          fontFamily: const bool.fromEnvironment('V9_CAPTURE')
              ? 'FoundiCapture'
              : null,
        ),
        home: child,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('V9_CAPTURE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(captureKey),
  );
  await t.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1.5),
        bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await Directory('docs/v9-captures').create(recursive: true);
    await File(
      'docs/v9-captures/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    img.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('V9_CAPTURE')) return;
    await ui.loadFontFromList(
      await File('C:/Windows/Fonts/segoeui.ttf').readAsBytes(),
      fontFamily: 'FoundiCapture',
    );
    await ui.loadFontFromList(
      await File(
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      ).readAsBytes(),
      fontFamily: 'MaterialIcons',
    );
  });
  testWidgets(
    'V9 inbox filters, marks an entry before navigating and marks all read',
    (t) async {
      final r = InboxFake()
        ..items = [
          n('msg'),
          n(
            'approval',
            type: 'professional.approved',
            category: 'account',
            title: 'Profil professionnel approuvé',
          ),
          n(
            'closed',
            type: 'request.closed',
            category: 'proposals',
            title: 'Demande clôturée',
            read: true,
            minutes: 2000,
          ),
        ];
      final opened = <String>[];
      await showScreen(
        t,
        NotificationInbox(
          repository: r,
          uid: 'u',
          onOpen: (id) async {
            expect(r.reads, contains(id));
            opened.add(id);
          },
        ),
      );
      expect(find.text('Profil professionnel approuvé'), findsOneWidget);
      await capture(t, '01-centre-notifications');
      await t.tap(find.text('Non lues'));
      await t.pumpAndSettle();
      expect(find.text('Demande clôturée'), findsNothing);
      await t.tap(find.text('Nouveau message'));
      await t.pumpAndSettle();
      expect(opened, ['msg']);
      await t.tap(find.text('Tout marquer comme lu'));
      await t.pumpAndSettle();
      expect(r.allReads, 1);
      expect(find.text('Rien à afficher'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets('V9 empty and error states recover without fabricated events', (
    t,
  ) async {
    final r = InboxFake();
    await showScreen(
      t,
      NotificationInbox(
        key: const ValueKey('empty'),
        repository: r,
        uid: 'u',
        onOpen: (_) async {},
      ),
    );
    expect(find.text('Rien à afficher'), findsOneWidget);
    await capture(t, '02-vide');
    r.unavailable = true;
    await showScreen(
      t,
      NotificationInbox(
        key: const ValueKey('error'),
        repository: r,
        uid: 'u',
        onOpen: (_) async {},
      ),
    );
    expect(find.text('Notifications indisponibles.'), findsOneWidget);
    await capture(t, '03-erreur');
    r.unavailable = false;
    r.items = [n('new')];
    await t.tap(find.text('Réessayer'));
    await t.pumpAndSettle();
    expect(find.text('Nouveau message'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await r.close();
  });
  testWidgets(
    'V9 preferences only affect push; permission requested from the explicit settings action',
    (t) async {
      final r = InboxFake(), permission = PermissionFake();
      await showScreen(
        t,
        NotificationSettings(repository: r, uid: 'u', permission: permission),
      );
      expect(permission.asked, 0);
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(r.preferences['messages'], false);
      expect(find.text('Impossible d’enregistrer. Réessaie.'), findsNothing);
      await capture(t, '04-preferences');
      await t.ensureVisible(find.text('Activer les alertes sur ce téléphone'));
      await t.pumpAndSettle();
      await t.tap(find.text('Activer les alertes sur ce téléphone'));
      await t.pumpAndSettle();
      expect(permission.asked, 1);
      expect(find.text('Impossible d’enregistrer. Réessaie.'), findsNothing);
      expect(find.textContaining('Notifications refusées.'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'V9 pagination continues past the realtime page and retains both pages',
    (t) async {
      final r = InboxFake()
        ..items = List.generate(
          30,
          (i) => n('id$i', title: 'Activité $i', minutes: i),
        )
        ..older = [n('older', title: 'Activité ancienne', minutes: 40)];
      await showScreen(
        t,
        NotificationInbox(repository: r, uid: 'u', onOpen: (_) async {}),
      );
      await t.scrollUntilVisible(
        find.text('Afficher plus'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Afficher plus'));
      await t.pumpAndSettle();
      expect(r.pages, 1);
      await t.scrollUntilVisible(
        find.text('Activité ancienne'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Activité ancienne'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'V9 global bell is uid scoped and independent of client/professional space',
    (t) async {
      final r = InboxFake()..items = [n('one'), n('two')];
      var opened = false;
      await showScreen(
        t,
        Scaffold(
          body: NotificationBell(
            repository: r,
            uid: 'u',
            onOpen: () => opened = true,
          ),
        ),
      );
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('notificationBell')));
      expect(opened, true);
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
  testWidgets(
    'V9 old push and another uid never navigate; pending push waits until authentication',
    (t) async {
      final r = InboxFake()
        ..target = const NotificationTarget('conversation', 'chat');
      final auth = fixtures.FakeAuth(), pro = fixtures.FakePro();
      final intent = ValueNotifier<NotificationIntent?>(
        const NotificationIntent('uid', 'delayed'),
      );
      await t.pumpWidget(
        NotificationScope(
          repository: r,
          intent: intent,
          child: FoundiApp(authRepository: auth, professionalRepository: pro),
        ),
      );
      await t.pumpAndSettle();
      expect(r.resolved, isEmpty);
      auth.emit(fixtures.account());
      await t.pumpAndSettle();
      expect(r.resolved, contains('delayed'));
      r.resolved.clear();
      intent.value = const NotificationIntent('another-uid', 'forged');
      await t.pumpAndSettle();
      expect(r.resolved, isEmpty);
      r.unavailable = true;
      intent.value = const NotificationIntent('uid', 'removed');
      await t.pumpAndSettle();
      expect(
        find.textContaining('Ce contenu n’est plus disponible'),
        findsWidgets,
      );
      await t.pumpWidget(const SizedBox());
      intent.dispose();
      await r.close();
    },
  );
  testWidgets(
    'V9 real event presentations include approval, message and request closure',
    (t) async {
      final r = InboxFake();
      final scenarios = [
        (
          '05-professionnel-approuve',
          n(
            'approval',
            type: 'professional.approved',
            category: 'account',
            title: 'Profil professionnel approuvé',
          ),
        ),
        ('06-message', n('message', title: 'Nouveau message')),
        (
          '07-demande-cloturee',
          n(
            'closure',
            type: 'request.closed',
            category: 'proposals',
            title: 'Demande clôturée',
          ),
        ),
      ];
      for (final (file, notification) in scenarios) {
        r.items = [notification];
        await showScreen(
          t,
          NotificationInbox(
            key: ValueKey(file),
            repository: r,
            uid: 'u',
            onOpen: (_) async {},
          ),
        );
        expect(find.text(notification.title), findsOneWidget);
        await capture(t, file);
      }
      await t.pumpWidget(const SizedBox());
      await r.close();
    },
  );
}
