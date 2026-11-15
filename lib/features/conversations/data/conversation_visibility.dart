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
