import 'dart:async';

class AccountPhotoChanges {
  static final _events = StreamController<void>.broadcast();
  static Stream<void> get stream => _events.stream;
  static void notify() => _events.add(null);
}
