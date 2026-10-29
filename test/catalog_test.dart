import 'package:flutter_test/flutter_test.dart';
import 'package:foundi/features/professional/domain/professional_repository.dart';

void main() {
  test(
    'legacy IDs are restored while disabled ancestor zones and specialties are excluded',
    () {
      final catalog = ProfessionalCatalog.fromMap({
        'enabled': true,
        'categories': [
          {
            'id': 'cat',
            'label': 'Métier',
            'specialties': [
              {'id': 'active', 'label': 'Active'},
              {'id': 'disabled', 'label': 'Inactive', 'active': false},
            ],
            'requirements': {'independent': [], 'company': []},
          },
        ],
        'zones': [
          {'id': 'root', 'label': 'Pays', 'active': false},
          {'id': 'child', 'label': 'Commune', 'parentId': 'root'},
          {'id': 'legacy', 'label': 'Ancienne zone'},
        ],
        'documentTypes': [
          {'id': 'identity', 'label': 'Identité'},
        ],
      });
      expect(catalog.zones.map((z) => z.id), ['legacy']);
      expect(catalog.categories.single.specialties.map((s) => s.id), [
        'active',
      ]);
      final activity = ProfessionalActivity.fromMap({
        'categoryIds': ['cat'],
        'specialtyIds': ['active'],
        'zoneIds': ['legacy'],
      });
      expect(catalog.requiredFor(activity)?.single.id, 'identity');
      expect(
        catalog.requiredFor(
          const ProfessionalActivity(
            categoryIds: ['cat'],
            specialtyIds: ['disabled'],
            zoneIds: ['legacy'],
          ),
        ),
        isNull,
      );
    },
  );
  test('zone path is displayed, cycles and missing parents fail closed', () {
    final zones = activeGeographicChoices([
      {'id': 'ci', 'label': 'Côte d’Ivoire'},
      {'id': 'city', 'label': 'Ville test', 'parentId': 'ci'},
      {'id': 'cycle', 'label': 'Cycle', 'parentId': 'cycle'},
      {'id': 'missing', 'label': 'Absente', 'parentId': 'unknown'},
    ]);
    expect(zones.map((z) => z.label), [
      'Côte d’Ivoire',
      'Côte d’Ivoire › Ville test',
    ]);
  });
}
