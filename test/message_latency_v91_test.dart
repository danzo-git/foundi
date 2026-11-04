import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/conversations/presentation/conversation_views.dart';
import 'package:foundi/features/conversations/presentation/rich_message_widgets.dart';
import 'conversations_v8_test.dart' show Conversations, large, reset;
import 'proposals_v7_test.dart' show request;

void main() {
  testWidgets('ten sends: deterministic delayed callable visibility benchmark', (
    t,
  ) async {
    await large(t);
    addTearDown(() => reset(t));
    final r = Conversations();
    r.chats[request.id] = r.makeChat();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationView(
            repository: r,
            id: request.id,
            uid: r.me,
            onBack: () {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final samples = <int>[];
    final confirmations = <int>[];
    for (var i = 0; i < 10; i++) {
      r.sendingMessage = Completer<void>();
      final text = 'Benchmark $i';
      await t.enterText(find.byKey(const ValueKey('messageText')), text);
      await t.tap(find.byKey(const ValueKey('sendMessage')));
      // Deliberately virtual time: this measures the UI dependency, not Firebase.
      final timer = Timer(Duration(milliseconds: 8000 + (i % 3) * 1000), () {
        r.sendingMessage!.complete();
      });
      final bubble = find.descendant(
        of: find.byType(RichMessageBody),
        matching: find.text(text),
      );
      var elapsed = 0;
      do {
        await t.pump(const Duration(milliseconds: 16));
        elapsed += 16;
      } while (bubble.evaluate().isEmpty && elapsed < 12000);
      expect(bubble, findsOneWidget);
      samples.add(elapsed);
      expect(elapsed, lessThan(200));
      expect(find.text('Envoi en cours'), findsOneWidget);
      while (!r.messageRows.containsKey(r.sendIds.last) && elapsed < 12000) {
        await t.pump(const Duration(milliseconds: 16));
        elapsed += 16;
      }
      expect(r.messageRows.containsKey(r.sendIds.last), isTrue);
      confirmations.add(elapsed);
      await t.pumpAndSettle();
      timer.cancel();
    }
    samples.sort();
    confirmations.sort();
    debugPrint(
      'V91 virtual UI milliseconds: $samples; median=${(samples[4] + samples[5]) / 2}; p95=${samples[9]}; max=${samples.last}',
    );
    debugPrint('V91 virtual confirmation milliseconds: $confirmations');
    await t.pumpWidget(const SizedBox());
    await r.close();
  });
}
