import 'package:flutter/services.dart';
import 'package:foundi_admin/main.dart' show AdminApp;
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/deletions_page.dart';

class Repo implements DeletionsRepository {
  int resumed = 0;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> list(String? cursor) async {
    if (fail) throw Exception();
    return {
      'items': [
        {
          'requestId': 'emulator-reference',
          'state': 'needs_review',
          'lastErrorCode': 'privacy/ownership-conflict',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> detail(String id) async => {
    'requestId': id,
    'state': 'needs_review',
    'step': 'storage_global',
    'lastErrorCode': 'privacy/ownership-conflict',
  };
  @override
  Future<void> resume(String id, String reason) async {
    resumed++;
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('PRIVACY_CAPTURE')) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
      final bytes = await File('C:/Windows/Fonts/$name').readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(bytes.buffer.asByteData()))).load();
    }
  });

  testWidgets(
    'private deletion queue requires a reason to resume an existing job',
    (t) async {
      final repo = Repo(), boundary = GlobalKey();
      t.view.physicalSize = const Size(1100, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        Builder(
          builder: (context) => MaterialApp(
            theme: (const AdminApp().build(context) as MaterialApp).theme,
            home: RepaintBoundary(
              key: boundary,
              child: Scaffold(body: DeletionsPage(repository: repo)),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Vérification requise'), findsOneWidget);
      if (const bool.fromEnvironment('PRIVACY_CAPTURE')) {
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../docs/sprint-2-captures/admin-suppressions.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.tap(find.text('Vérification requise'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reprendre ce dossier'));
      await t.pump();
      expect(repo.resumed, 0);
      expect(find.text('Indique le contrôle effectué.'), findsOneWidget);
      await t.enterText(
        find.byType(TextField),
        'Génération du fichier vérifiée.',
      );
      await t.tap(find.text('Reprendre ce dossier'));
      await t.pumpAndSettle();
      expect(repo.resumed, 1);
    },
  );
}
