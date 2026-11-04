import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../auth/domain/auth_repository.dart';
import '../domain/conversation_repository.dart';
import 'message_send_trace.dart';

enum TextDelivery { sending, sent, failed }

class OutgoingText {
  OutgoingText(this.message, this.trace);
  final ConversationMessage message;
  final MessageSendTrace trace;
  TextDelivery delivery = TextDelivery.sending;
  String? error;
  bool inFlight = false;
  bool observedOnServer = false;
}

/// Session outbox scoped by repository, authenticated sender and conversation.
/// Operations survive leaving/reopening the view, without a second listener
/// or client writes bypassing the callable's security checks.
class TextMessageOutbox extends ChangeNotifier {
  TextMessageOutbox._(this.repository, this.uid, this.conversationId);
  static final _sessions = Expando<Map<(String, String), TextMessageOutbox>>();
  static TextMessageOutbox forConversation(
    ConversationRepository repository,
    String uid,
    String conversationId,
  ) {
    final sessions = _sessions[repository] ??= {};
    return sessions.putIfAbsent((
      uid,
      conversationId,
    ), () => TextMessageOutbox._(repository, uid, conversationId));
  }

  final ConversationRepository repository;
  final String uid, conversationId;
  final _items = <String, OutgoingText>{};
  int _latestOrder = 0;
  Iterable<OutgoingText> get items => _items.values;
  OutgoingText? item(String id) => _items[id];

  void send(String text, Stopwatch clock) {
    final id = repository.newMessageId(conversationId);
    final trace = MessageSendTrace.start(id, clock);
    final now = DateTime.now().millisecondsSinceEpoch;
    _latestOrder = now > _latestOrder ? now : _latestOrder + 1;
    final outgoing = OutgoingText(
      ConversationMessage(
        id: id,
        senderUid: uid,
        text: text,
        createdAt: _latestOrder,
      ),
      trace,
    );
    _items[id] = outgoing;
    trace.mark('T2_local_insert');
    notifyListeners();
    unawaited(_deliver(outgoing));
  }

  void retry(String id) {
    final outgoing = _items[id];
    if (outgoing == null ||
        outgoing.inFlight ||
        outgoing.delivery != TextDelivery.failed) {
      return;
    }
    outgoing.delivery = TextDelivery.sending;
    outgoing.error = null;
    notifyListeners();
    unawaited(_deliver(outgoing));
  }

  Future<void> _deliver(OutgoingText outgoing) async {
    outgoing.inFlight = true;
    outgoing.trace.attempt++;
    outgoing.trace.mark('T3_callable_start');
    try {
      await repository.sendConversationMessage(
        conversationId,
        outgoing.message.id,
        outgoing.message.text,
      );
      outgoing.trace.mark('T4_callable_ack');
      outgoing.delivery = TextDelivery.sent;
    } catch (e) {
      outgoing.trace.mark('callable_failed');
      // A non-cache snapshot proves the commit even if its response was lost.
      if (!outgoing.observedOnServer) {
        outgoing.delivery = TextDelivery.failed;
        outgoing.error = e is AuthFailure
            ? e.message
            : 'Envoi non confirmé. Vérifie ta connexion et réessaie.';
      }
    } finally {
      outgoing.inFlight = false;
      if (outgoing.observedOnServer) _items.remove(outgoing.message.id);
      notifyListeners();
    }
  }

  /// Called on stream events, never on rebuild. Cache alone is not an ACK.
  void observe(MessageBatch batch) {
    for (final message in batch.messages) {
      if (message.createdAt > _latestOrder) _latestOrder = message.createdAt;
      final outgoing = _items[message.id];
      MessageSendTrace.snapshot(
        message.id,
        fromCache: batch.fromCache,
        pendingWrites: batch.hasPendingWrites,
      );
      if (outgoing != null && !batch.fromCache && !batch.hasPendingWrites) {
        outgoing.observedOnServer = true;
        outgoing.delivery = TextDelivery.sent;
        outgoing.error = null;
        if (!outgoing.inFlight) _items.remove(message.id);
      }
    }
  }

  List<ConversationMessage> merge(MessageBatch batch) {
    final byId = {for (final m in batch.messages) m.id: m};
    for (final outgoing in _items.values) {
      byId.putIfAbsent(outgoing.message.id, () => outgoing.message);
    }
    return byId.values.toList()..sort((a, b) {
      final order = b.createdAt.compareTo(a.createdAt);
      return order == 0 ? b.id.compareTo(a.id) : order;
    });
  }
}
