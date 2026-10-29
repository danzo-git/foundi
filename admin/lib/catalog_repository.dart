import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

abstract interface class CatalogRepository {
  Stream<Map<String, dynamic>> watch();
  Future<void> update(Map<String, dynamic> operation);
}

class FirebaseCatalogRepository implements CatalogRepository {
  @override
  Stream<Map<String, dynamic>> watch() => FirebaseFirestore.instance
      .doc('referenceData/professionalOnboarding')
      .snapshots()
      .map(
        (s) =>
            s.data() ??
            {
              'enabled': false,
              'version': '',
              'categories': [],
              'zones': [],
              'documentTypes': [],
            },
      );
  @override
  Future<void> update(Map<String, dynamic> operation) async {
    await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('updateProfessionalCatalog').call(operation);
  }
}

const zoneLabels = {
  'country': 'Pays',
  'district': 'District',
  'region': 'Région',
  'department': 'Département',
  'subprefecture': 'Sous-préfecture',
  'city': 'Ville',
  'commune': 'Commune',
  'quartier': 'Quartier',
  'intervention': 'Zone d’intervention',
};
const catalogIcons = {
  'home': 'Immobilier',
  'car': 'Automobile',
  'build': 'Artisanat',
  'storefront': 'Commerce',
  'event': 'Événementiel',
  'favorite': 'Bien-être',
  'school': 'Formation',
  'work': 'Activité',
};
List<Map<String, dynamic>> catalogEntries(
  Map<String, dynamic> catalog,
  String key,
) => (catalog[key] as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e))
    .toList();
