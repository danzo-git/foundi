import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/professional/domain/professional_showcase.dart';
import 'package:foundi/features/professional/presentation/professional_showcase_screen.dart';
import 'package:foundi/features/professional/presentation/professional_profile_widgets.dart';

const initial = ProfessionalShowcase(
  name: 'Initial',
  trade: 'Service',
  area: 'Zone',
);
const fresh = ProfessionalShowcase(
  name: 'Actualisé',
  trade: 'Service',
  area: 'Zone',
);

Widget page({
  required Future<ProfessionalShowcase> Function() load,
  ProfessionalShowcase? seed,
  Future<ProfessionalShowcase?> Function()? refresh,
  String id = 'professional-A',
}) => MaterialApp(
  home: ProfessionalShowcaseScreen.recommended(
    key: const ValueKey('profile'),
    professionalId: id,
    initialProfile: seed,
    loadRecommended: load,
    refreshRecommended: refresh,
  ),
);

void main() {
  for (final pause in [false, true]) {
    testWidgets(
      'an open photo closes when ${pause ? 'the app pauses' : 'the lease expires and refresh fails'}',
      (t) async {
        final renewal = Completer<ProfessionalShowcase?>();
        final profile = ProfessionalShowcase(
          name: 'Profil avec photo',
          gallery: [
            ShowcasePhoto(
              File('functions/test/fixtures/photo.png').readAsBytesSync(),
            ),
          ],
        );
        await t.pumpWidget(
          page(
            seed: profile,
            load: () async => profile,
            refresh: () => renewal.future,
          ),
        );
        await t.pumpAndSettle();
        final gallery = t.widget<ShowcaseGallery>(find.byType(ShowcaseGallery));
        gallery.onPhoto!(0);
        await t.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        if (pause) {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        } else {
          await t.pump(const Duration(seconds: 31));
          renewal.completeError(StateError('offline'));
        }
        await t.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.text('Profil avec photo'), findsOneWidget);
        await t.pumpWidget(const SizedBox.shrink());
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pump();
      },
    );
  }
  testWidgets(
    'an authorized initial profile renders without a second read or loading flash',
    (t) async {
      var reads = 0;
      final renewal = Completer<ProfessionalShowcase?>();
      await t.pumpWidget(
        page(
          seed: initial,
          load: () async {
            reads++;
            return fresh;
          },
          refresh: () {
            reads++;
            return renewal.future;
          },
        ),
      );
      expect(find.text('Initial'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(reads, 0);
      await t.pump(const Duration(seconds: 31));
      await t.pump();
      expect(reads, 1);
      expect(find.text('Initial'), findsOneWidget);
      expect(find.text('Professionnel vérifié'), findsNothing);
      renewal.complete(fresh);
      await t.pumpAndSettle();
      expect(find.text('Actualisé'), findsOneWidget);
      expect(find.text('Initial'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a missing profile response stops loading and a retry rejects the old result',
    (t) async {
      final old = Completer<ProfessionalShowcase>();
      var reads = 0;
      await t.pumpWidget(
        page(load: () => ++reads == 1 ? old.future : Future.value(fresh)),
      );
      await t.pump(const Duration(seconds: 21));
      await t.pump();
      expect(find.textContaining('prend trop de temps'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.text('Réessayer'));
      await t.pumpAndSettle();
      expect(find.text('Actualisé'), findsOneWidget);
      old.complete(initial);
      await t.pumpAndSettle();
      expect(find.text('Initial'), findsNothing);
      expect(reads, 2);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'a new profile identity never reuses the initial seed of the old identity',
    (t) async {
      var reads = 0;
      Future<ProfessionalShowcase> load() async {
        reads++;
        return fresh;
      }

      await t.pumpWidget(page(seed: initial, load: load));
      expect(reads, 0);
      await t.pumpWidget(page(seed: initial, id: 'professional-B', load: load));
      await t.pumpAndSettle();
      expect(reads, 1);
      expect(find.text('Actualisé'), findsOneWidget);
      expect(find.text('Initial'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
