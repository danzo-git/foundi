import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi_admin/main.dart';
void main() {
  testWidgets('connexion mobile sans inscription publique ni débordement', (tester) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: Login()));
    expect(find.text('Foundi Admin'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.textContaining('inscription'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
