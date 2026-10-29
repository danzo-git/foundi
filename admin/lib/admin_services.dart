import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

const labels = {
  'pending': 'En attente',
  'approved': 'Approuvés',
  'rejected': 'Refusés',
  'needs_changes': 'À corriger',
  'suspended': 'Suspendus',
};
final db = FirebaseFirestore.instance;
final functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
