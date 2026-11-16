import 'dart:async';

/// The absence of a local deletion marker cannot authorize private history.
/// Each side invalidates its retained state on error, so an update on the other
/// side cannot restore a conversation whose access has just failed.
Stream<T?> watchVisibleConversation<T extends Object>({
  required Stream<T?> conversation,
  required Stream<({bool exists, bool fromCache})> deletion,
  required bool Function() isCurrent,
}) => Stream<T?>.multi((output) {
  T? value;
  var received = false, known = false, visible = false, active = true;
  void publish() {
    if (active && isCurrent() && known) {
      if (!visible) {
        output.add(null);
      } else if (received) {
        output.add(value);
      }
    }
  }

  final source = conversation.listen(
    (next) {
      value = next;
      received = true;
      publish();
    },
    onError: (Object error, StackTrace stack) {
      value = null;
      received = false;
      if (active && isCurrent()) output.addError(error, stack);
    },
  );
  final marker = deletion.listen(
    (next) {
      if (next.fromCache && !next.exists) return;
      known = true;
      visible = !next.exists;
      publish();
    },
    onError: (Object error, StackTrace stack) {
      known = false;
      visible = false;
      if (active && isCurrent()) output.addError(error, stack);
    },
  );
  output.onCancel = () async {
    active = false;
    await Future.wait([source.cancel(), marker.cancel()]);
  };
});

// Fetch older pages when recent rows have been removed from this user's inbox.
// A fixed limit followed by filtering would otherwise hide older conversations.
Future<List<T>> loadVisibleConversationRows<T>({
  required List<T> firstPage,
  required String Function(T) idOf,
  required Future<Set<String>> Function(List<String>) deletedIds,
  required Future<List<T>> Function(T) nextPage,
  required bool Function() isCurrent,
  int pageSize = 30,
}) async {
  final visible = <T>[], seen = <String>{}, cursors = <String>{};
  var page = firstPage;
  while (page.isNotEmpty && isCurrent()) {
    final deleted = await deletedIds(page.map(idOf).toList());
    if (!isCurrent()) return [];
    for (final row in page) {
      if (seen.add(idOf(row)) && !deleted.contains(idOf(row))) visible.add(row);
      if (visible.length == pageSize) return visible;
    }
    if (page.length < pageSize) break;
    if (!cursors.add(idOf(page.last))) {
      throw StateError('Conversation pagination did not advance');
    }
    page = await nextPage(page.last);
  }
  return visible;
}
