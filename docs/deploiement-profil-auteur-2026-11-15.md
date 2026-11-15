# Déploiement du profil auteur — 15 novembre 2026

Autorisation explicite de l’éditeur : déployer la nouvelle fonction du profil de l’auteur. Projet `foundi-7c837`, région `europe-west1`, branche locale `codex/foundi-sprint-2-5-finitions`.

`readRequestAuthorProfile` a été créée et vérifiée **ACTIVE** le 15 novembre 2026 à 14 h 37 (Paris). Révision : `readrequestauthorprofile-00001-qas`.

## Périmètre vérifié

- Une seule fonction créée : `readRequestAuthorProfile`.
- Les 90 fonctions existantes gardent leur révision et leur compte de service.
- Règles Firestore/Storage, index, politiques de champs/TTL, configuration Authentication, stockage et politique de suppression du compte inchangés.
- Aucun déploiement Hosting, publication juridique ou distribution d’APK.

Les 204 tests backend et les contrôles serveur ont réussi au pré-déploiement. Vérifications HTTP distantes : identifiant de demande invalide refusé avec 400 `INVALID_ARGUMENT`, tentative de fournir un propriétaire refusée avec 400, demande aléatoire inexistante refusée avec 404 `NOT_FOUND`. Aucune identité ni donnée de compte n’est renvoyée dans ces réponses.

Aucun compte ni demande réelle n’a été modifié par les contrôles. La sonde sur une demande inexistante utilise le budget technique de lecture normal de l’API. Le parcours positif et les blocages/suppressions ont été testés avec des comptes fictifs sur les émulateurs lors de la recette, sans créer de compte de recette en production.

Le clic sur le nom ou la photo de l’auteur nécessite la version de l’application contenant le nouveau parcours. La localisation native relève également de la mise à jour de l’application ; cette intervention publie uniquement la fonction de profil auteur.

Traces locales ignorées par Git : `.dart_tool/author-deploy-before.json`, `.dart_tool/author-deploy-after.json`, `.dart_tool/author-deploy.log`, `.dart_tool/author-deploy-verification.json`. Vérification reproductible avec `functions/scripts/verify-author-deployment.cjs` et les paramètres explicites `--project`, `--before`, `--after` et `--output`.

[Recette et captures du parcours](profils-auteurs-localisation-2026-11-15.md).
