# Déploiement des corrections des demandes privées

Déploiement autorisé et terminé sur `foundi-7c837`, région `europe-west1`, codebase `auth`.

Contrôle final : **12 novembre 2026 à 11:51:47, Europe/Paris** (`2026-11-12T10:51:47.546Z`).

Les six fonctions concernées sont **ACTIVE** : cinq mises à jour et une création. Les 54 autres fonctions conservent leur révision. Le projet compte maintenant 60 fonctions dans cette région.

| Fonction | Opération | Révision active |
| --- | --- | --- |
| `publishDirectRequest` | Mise à jour | `publishdirectrequest-00002-jet` |
| `manageRequest` | Mise à jour | `managerequest-00009-zez` |
| `readProfessionalShowcase` | Mise à jour | `readprofessionalshowcase-00002-xij` |
| `readRequestRecommendation` | Mise à jour | `readrequestrecommendation-00003-tux` |
| `readRequestRespondentProfile` | Mise à jour | `readrequestrespondentprofile-00002-veq` |
| `readDirectRequestAuthors` | Création | `readdirectrequestauthors-00001-rel` |

Le serveur impose désormais le nom du compte à la création d’une demande privée. La catégorie et la spécialité sont vérifiées contre l’activité du dossier professionnel approuvé, et ne peuvent pas être changées en modification. Les lectures des profils fournissent cette activité au formulaire Flutter verrouillé. La nouvelle fonction résout le nom pour les anciennes demandes privées après vérification de chaque accès, sans migration ni modification des documents existants.

Les cinq fonctions de lecture et modification ont été déployées puis contrôlées en premier ; `publishDirectRequest` a été mise à jour ensuite. Les comptes de service des fonctions restent cohérents avec leurs équivalents existants.

Les hooks de prédéploiement ont exécuté les **129 tests serveur avec succès**, ainsi que les vérifications syntaxiques. La validation locale du lot comprenait 150 tests Flutter réussis, une analyse sans anomalie, huit scénarios ciblés et quatre tests exécutés avec Firestore en émulateur : voir [le compte rendu d’implémentation](demandes-directes-v2.md).

Le contrôle final a vérifié :

- le changement de révision des cinq fonctions mises à jour et la création de la seule fonction attendue ;
- l’état actif des six fonctions et la conservation des 54 autres ;
- la même version de règles Firestore et les mêmes 23 index, dont l’index `directRequests` toujours `READY` ;
- la conservation du paramètre de push pour `deliverNotificationPush` et `drainNotifications` ;
- le refus **HTTP 401 / UNAUTHENTICATED** par `publishDirectRequest`, `manageRequest`, `readProfessionalShowcase`, `readRequestRecommendation` et `readDirectRequestAuthors` lors d’un appel anonyme ;
- le refus **HTTP 400 / INVALID_ARGUMENT** des paramètres absents sur le lecteur public `readRequestRespondentProfile`.

Ces contrôles utilisent les adresses Firebase appelées par les clients. Ils ne créent aucune demande réelle et n’envoient aucune notification à un professionnel. La validation métier avec deux comptes reste à effectuer dans la version Flutter à jour ; les tests métier automatisés ont été réalisés localement et en émulateur.

La première tentative a échoué pendant la découverte locale des fonctions par la CLI (`fetch failed` sur le serveur local), avant toute mise en ligne. La relance du même déploiement ciblé a réussi, sans modification du code métier.

Les preuves locales sont conservées dans `.dart_tool/direct-v2-deploy-before.json`, `.dart_tool/direct-v2-deploy-prerequisites.json`, `.dart_tool/direct-v2-deploy-after.json` et les journaux `.dart_tool/direct-v2-deploy-prerequisites-retry.log`, `.dart_tool/direct-v2-deploy-publish.log`, `.dart_tool/direct-v2-deploy-after.log`.

Le contrôle se reproduit en lecture seule avec `node functions/scripts/verify-direct-requests-deploy.cjs --private-ux --before .dart_tool/direct-v2-deploy-before.json --output .dart_tool/direct-v2-deploy-after.json`.

**Aucun APK n’a été généré ou distribué.** Aucun déploiement Hosting, changement de règles Firestore ou Storage, ni déploiement d’index n’a été réalisé dans ce lot.
