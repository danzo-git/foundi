import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/main.dart' show AdminApp;
import 'package:foundi_admin/catalog_page.dart';
import 'catalog_test.dart' show FakeCatalog;

void main() {
  testWidgets('Admin enables only Rennes with a guarded server operation', (
    t,
  ) async {
    final repository = FakeCatalog();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogPage(section: 'zones', repository: repository),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('enableRennes')));
    await t.tap(find.byKey(const ValueKey('enableRennes')));
    await t.pumpAndSettle();
    expect(repository.updates.single['operation'], 'enableRennes');
    expect(repository.updates.single['expectedVersion'], 'v1');
    expect(repository.updates.single.containsKey('value'), isFalse);
  });
  testWidgets('Admin preserves France when editing Rennes', (t) async {
    final repository = FakeCatalog(), boundary = GlobalKey();
    repository.data['zones'] = [
      {
        'id': 'ci',
        'label': 'Côte d’Ivoire',
        'type': 'country',
        'countryCode': 'CI',
        'active': true,
      },
      {
        'id': 'fr_commune_35238',
        'label': 'Rennes',
        'type': 'commune',
        'countryCode': 'FR',
        'active': true,
      },
    ];
    t.view.physicalSize = const Size(1000, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      Builder(
        builder: (context) => MaterialApp(
          theme: (const AdminApp().build(context) as MaterialApp).theme,
          builder: (context, child) =>
              RepaintBoundary(key: boundary, child: child!),
          home: Scaffold(
            body: CatalogPage(section: 'zones', repository: repository),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('enableRennes')), findsNothing);
    expect(find.text('Commune • France'), findsOneWidget);
    await t.tap(find.byTooltip('Modifier').last);
    await t.pumpAndSettle();
    final country = t.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('zoneCountry-FR')),
    );
    expect(country.initialValue, 'FR');
    if (const bool.fromEnvironment('SPRINT25_CAPTURE')) {
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../docs/sprint-2-5-captures/admin-rennes-pays-france.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await t.ensureVisible(find.text('Enregistrer'));
    await t.tap(find.text('Enregistrer'));
    await t.pumpAndSettle();
    expect(repository.updates.single['value']['countryCode'], 'FR');
    expect(repository.updates.single['id'], 'fr_commune_35238');
  });
  setUpAll(() async {
    if (!const bool.fromEnvironment('SPRINT25_CAPTURE')) return;
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
    'Admin activates server-owned Autre reference using version-guarded operation',
    (t) async {
      final repository = FakeCatalog(), boundary = GlobalKey();
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
              child: Scaffold(
                body: CatalogPage(
                  section: 'categories',
                  repository: repository,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Activer Autre / Je ne sais pas'), findsOneWidget);
      if (const bool.fromEnvironment('SPRINT25_CAPTURE')) {
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../docs/sprint-2-5-captures/admin-reference-autre.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.tap(find.text('Activer Autre / Je ne sais pas'));
      await t.pumpAndSettle();
      expect(repository.updates.single['operation'], 'enableUnclassified');
      expect(repository.updates.single['expectedVersion'], 'v1');
      expect(repository.updates.single.containsKey('value'), isFalse);
    },
  );
}
