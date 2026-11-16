import 'package:firebase_auth/firebase_auth.dart';

int _readEpoch = 0;

// Revalidation after resume, a changed photo or a security mutation must never
// borrow a request which started before that boundary.
void invalidateFirebaseReadScope() {
  _readEpoch++;
}

Object? firebaseReadScope() {
  final user = FirebaseAuth.instance.currentUser;
  return (
    user?.uid,
    user?.metadata.lastSignInTime?.millisecondsSinceEpoch,
    _readEpoch,
  );
}
