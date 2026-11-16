import 'dart:async';

/// Bounds the initial wait without timing out an idle, already loaded stream.
/// A delayed source remains attached after the error so reconnection can recover.
Stream<T> withInitialEventTimeout<T>(
  Stream<T> source, {
  Duration timeout = const Duration(seconds: 12),
}) => Stream<T>.multi((output) {
  StreamSubscription<T>? subscription;
  Timer? deadline;
  var signaled = false, canceled = false;
  deadline = Timer(timeout, () {
    if (canceled || signaled) return;
    signaled = true;
    output.addError(TimeoutException('Le chargement ne répond pas.', timeout));
  });
  subscription = source.listen(
    (value) {
      if (canceled) return;
      signaled = true;
      deadline?.cancel();
      output.add(value);
    },
    onError: (Object error, StackTrace stack) {
      if (canceled) return;
      signaled = true;
      deadline?.cancel();
      output.addError(error, stack);
    },
    onDone: () {
      deadline?.cancel();
      if (canceled) return;
      if (!signaled) {
        output.addError(StateError('Le chargement s’est arrêté sans réponse.'));
      }
      output.close();
    },
  );
  output.onPause = () => subscription?.pause();
  output.onResume = () => subscription?.resume();
  output.onCancel = () async {
    canceled = true;
    deadline?.cancel();
    await subscription?.cancel();
  };
}, isBroadcast: source.isBroadcast);
