# Adresses d’intervention — déploiement du 15 novembre 2026

Déploiement explicitement autorisé par l’utilisateur. Projet `foundi-7c837`, région `europe-west1`, branche `codex/foundi-sprint-2-5-finitions`.

Vérification finale terminée le 15 novembre 2026 à **20 h 55, heure de Paris** (`19:55:52 UTC`).

## Fonctions actives

| Fonction | État vérifié | Révision |
| --- | --- | --- |
| `publishRequest` | ACTIVE | `publishrequest-00011-jip` |
| `publishDirectRequest` | ACTIVE | `publishdirectrequest-00005-kub` |
| `manageRequest` | ACTIVE | `managerequest-00013-suz` |
| `listOpportunities` | ACTIVE | `listopportunities-00006-zid` |
| `decideSafetyReport` | ACTIVE | `decidesafetyreport-00005-faj` |
| `getRequestAddressCapabilities` | ACTIVE | `getrequestaddresscapabilities-00001-xot` |

Les cinq premières fonctions ont été déployées puis vérifiées actives avec de nouvelles révisions. La nouvelle fonction de capacité a été déployée seulement après cette vérification. Les dates de modification distantes confirment cet ordre. Les deux commandes Firebase ont terminé avec le code 0.

## Contrôles

- Les 221 tests backend et les contrôles de pré-déploiement ont réussi avant chacune des deux étapes. Les 44 tests ciblés adresse/opportunités/modération ont aussi réussi avant la première étape.
- Les six points d’entrée de production ont été appelés sans connexion : tous refusent l’accès avec HTTP 401 et `UNAUTHENTICATED`. Aucun jeton ni compte client réel n’a été utilisé.
- Les 86 autres fonctions gardent leur révision, leur date de modification et leur compte de service.
- Catalogue public strictement identique avant/après, avec les mêmes métadonnées Firestore : aucune zone ou activité modifiée.
- Règles Firestore/Storage, index, politiques de champs/TTL, configuration Authentication, configuration de stockage et politique de suppression inchangés.
- Aucune demande de recette, adresse ou donnée de compte n’a été créée ou modifiée en production par les contrôles. Les tests de sauvegarde authentifiée, lecture publique, confidentialité des demandes directes et effacement du compte ont été effectués sur les émulateurs, comme décrit dans la [livraison](adresse-intervention-2026-11-15.md).

## Application

Le backend accepte maintenant l’adresse d’intervention confirmée et la renvoie dans les demandes publiques/opportunités. L’interface de reconnaissance, de confirmation et d’affichage nécessite l’application contenant cette évolution. Aucun APK n’a été distribué par cette intervention. La reconnaissance du numéro/rue reste à recetter sur téléphone réel en France et en Côte d’Ivoire. Aucun Hosting ni texte juridique publié n’a été déployé.

## Traces locales

Script de vérification : `functions/scripts/verify-address-deployment.cjs`.

Les fichiers `.dart_tool/address-deploy-before.json`, `address-deploy-main-ready.json`, `address-deploy-after.json`, `address-catalogue-before.json`, `address-deploy-main.log`, `address-deploy-capability.log` et `address-deploy-verification.json` conservent les états et résultats de cette session. Ils sont ignorés par Git.
