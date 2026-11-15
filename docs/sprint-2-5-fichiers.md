# Sprint 2.5 — fichiers modifiés et créés

Base locale : `66839dc`, branche `codex/foundi-sprint-2-5-finitions`. Les fichiers .env, secrets, traces `.dart_tool` et SDK restent exclus du suivi Git.

## Backend, tests et outils Firebase

- [functions/scripts/verify-avatar-deployment.cjs](../functions/scripts/verify-avatar-deployment.cjs)

- [functions/integration-test/notifications-flow.test.cjs](../functions/integration-test/notifications-flow.test.cjs)
- [functions/integration-test/privacy-flow.test.cjs](../functions/integration-test/privacy-flow.test.cjs)
- [functions/integration-test/sprint25-flow.test.cjs](../functions/integration-test/sprint25-flow.test.cjs)
- [functions/package.json](../functions/package.json)
- [functions/rules-test/sprint25.test.cjs](../functions/rules-test/sprint25.test.cjs)
- [functions/scripts/configure-onboarding.js](../functions/scripts/configure-onboarding.js)
- [functions/scripts/test-v82-emulators.cjs](../functions/scripts/test-v82-emulators.cjs)
- [functions/src/catalog-service.js](../functions/src/catalog-service.js)
- [functions/src/index.js](../functions/src/index.js)
- [functions/src/notification-policy.js](../functions/src/notification-policy.js)
- [functions/src/notification-service.js](../functions/src/notification-service.js)
- [functions/src/opportunity-service.js](../functions/src/opportunity-service.js)
- [functions/src/personal-avatar-service.js](../functions/src/personal-avatar-service.js)
- [functions/src/privacy-purge.js](../functions/src/privacy-purge.js)
- [functions/src/professional-service.js](../functions/src/professional-service.js)
- [functions/src/request-matching.js](../functions/src/request-matching.js)
- [functions/src/request-photo-service.js](../functions/src/request-photo-service.js)
- [functions/src/request-service.js](../functions/src/request-service.js)
- [functions/src/safety-service.js](../functions/src/safety-service.js)
- [functions/test/catalog-service.test.js](../functions/test/catalog-service.test.js)
- [functions/test/notification-policy.test.js](../functions/test/notification-policy.test.js)
- [functions/test/opportunity-service.test.js](../functions/test/opportunity-service.test.js)
- [functions/test/request-service.test.js](../functions/test/request-service.test.js)

## Application Flutter

- [lib/main.dart](../lib/main.dart)
- [lib/features/auth/data/firebase_auth_repository.dart](../lib/features/auth/data/firebase_auth_repository.dart)
- [lib/features/auth/domain/personal_avatar_repository.dart](../lib/features/auth/domain/personal_avatar_repository.dart)
- [lib/features/auth/presentation/account_screen.dart](../lib/features/auth/presentation/account_screen.dart)
- [lib/features/auth/presentation/personal_avatar.dart](../lib/features/auth/presentation/personal_avatar.dart)
- [lib/features/professional/domain/professional_repository.dart](../lib/features/professional/domain/professional_repository.dart)
- [lib/features/requests/data/firebase_request_repository.dart](../lib/features/requests/data/firebase_request_repository.dart)
- [lib/features/requests/domain/request_repository.dart](../lib/features/requests/domain/request_repository.dart)
- [lib/features/requests/presentation/request_composer.dart](../lib/features/requests/presentation/request_composer.dart)
- [lib/features/requests/presentation/request_views.dart](../lib/features/requests/presentation/request_views.dart)
- [lib/features/requests/presentation/request_zone_picker.dart](../lib/features/requests/presentation/request_zone_picker.dart)

## Administration

- [admin/lib/catalog_page.dart](../admin/lib/catalog_page.dart)
- [admin/test/sprint25_catalog_test.dart](../admin/test/sprint25_catalog_test.dart)

## Documentation et captures

- [docs/deploiement-photos-demandes-2026-11-15.md](../docs/deploiement-photos-demandes-2026-11-15.md)

- [docs/legal/sprint-2/confidentialite-v1-projet.md](../docs/legal/sprint-2/confidentialite-v1-projet.md)
- [docs/sprint-2-5-captures/README.md](../docs/sprint-2-5-captures/README.md)
- [docs/sprint-2-5-captures/admin-reference-autre.png](../docs/sprint-2-5-captures/admin-reference-autre.png)
- [docs/sprint-2-5-captures/apercu-multi-zone.png](../docs/sprint-2-5-captures/apercu-multi-zone.png)
- [docs/sprint-2-5-captures/besoin-non-classe.png](../docs/sprint-2-5-captures/besoin-non-classe.png)
- [docs/sprint-2-5-captures/compte-photo-consentement.png](../docs/sprint-2-5-captures/compte-photo-consentement.png)
- [docs/sprint-2-5-captures/explorer-avatar-absent-ou-revoque.png](../docs/sprint-2-5-captures/explorer-avatar-absent-ou-revoque.png)
- [docs/sprint-2-5-captures/explorer-avatar-autorise.png](../docs/sprint-2-5-captures/explorer-avatar-autorise.png)
- [docs/sprint-2-5-captures/selection-zones.png](../docs/sprint-2-5-captures/selection-zones.png)
- [docs/sprint-2-5-captures/zones-320px-grandes-polices.png](../docs/sprint-2-5-captures/zones-320px-grandes-polices.png)
- [docs/sprint-2-5-fichiers.md](../docs/sprint-2-5-fichiers.md)
- [docs/sprint-2-5-livraison.md](../docs/sprint-2-5-livraison.md)
- [docs/sprint-2-5-plan-migration.md](../docs/sprint-2-5-plan-migration.md)
- [docs/sprint-2-5-tests.md](../docs/sprint-2-5-tests.md)

## Pages juridiques locales non publiées

- [public-privacy/confidentialite/index.html](../public-privacy/confidentialite/index.html)

## Configuration juridique en brouillon

- [config/legal-documents.sprint-2.draft.json](../config/legal-documents.sprint-2.draft.json)

## Tests Flutter

- [test/direct_requests_test.dart](../test/direct_requests_test.dart)
- [test/requests_v5_test.dart](../test/requests_v5_test.dart)
- [test/sprint25_test.dart](../test/sprint25_test.dart)

## Règles et index

- [firestore.indexes.json](../firestore.indexes.json)
- [firestore.rules](../firestore.rules)

## Nouveaux index déclarés (non déployés)

- `requests` : `status ASCENDING`, `categoryId ASCENDING`, `zoneIds CONTAINS`, `specialtyId ASCENDING`, `createdAt DESCENDING`, `__name__ DESCENDING`.
- `requests` : `status ASCENDING`, `zoneIds CONTAINS`, `createdAt DESCENDING`, `__name__ DESCENDING`.
- `requests` : `status ASCENDING`, `categoryId ASCENDING`, `zoneIds CONTAINS`, `createdAt DESCENDING`, `__name__ DESCENDING`.
- `professionalProfiles` : `status ASCENDING`, `zoneIds CONTAINS`, `__name__ ASCENDING`.
