# Correction des noms dans Explorer « Toutes »

Réparation appliquée sur `foundi-7c837`, vérifiée le **12 novembre 2026 à 15:21:16 Europe/Paris** (`2026-11-12T14:21:16.947Z`).

## Cause vérifiée

Explorer « Toutes » lit directement les documents publics `requests`. Les 15 demandes publiques encore ouvertes n’avaient pas de champ `authorPublicName`, alors que leur compte propriétaire possédait un nom exploitable. Le repli Flutter « Membre Foundi » était donc affiché.

Le déploiement précédent imposait le nom à la création et à la modification, mais ne remplissait pas les anciennes fiches. La dernière demande publique retrouvée lors du diagnostic avait été créée à 14:08:49, avant la mise à jour de `publishRequest` à 14:16:39. Le code effectivement déployé a été inspecté en lecture seule : `request-service.js`, le résolveur de nom et le lecteur d’opportunités correspondent aux sources locales validées. Il n’était pas nécessaire de redéployer Explorer ou de modifier son interface.

## Réparation réalisée

- Simulation de 15 demandes publiques ouvertes ; les 15 étaient éligibles, sans exclusion.
- Vérification du lien entre `requestOwnership`, le compte propriétaire et la copie `userRequests` de chaque demande.
- Récupération du nom depuis le compte, sans valeur fournie par un client.
- Mise à jour atomique du seul champ `authorPublicName` sur la demande publique et sa copie « Mes demandes » : **15 paires, 30 documents existants**.
- Relecture des 15 paires après réparation : tous les noms correspondent à la valeur attendue. La comparaison des empreintes confirme que tous les autres champs des demandes et de leurs copies sont restés identiques.

Aucun identifiant, contenu, budget, photo, statut, date, proposition ou sélection n’a été modifié. Le script ne possède aucun chemin d’écriture vers les quotas. Aucune demande n’a été recréée. Les demandes clôturées, supprimées et privées sont exclues de cette réparation, et les noms déjà renseignés ne sont pas écrasés.

Le plan inclut les anciennes valeurs des seuls champs de nom pour permettre une restauration contrôlée. Les contrôles de propriétaire, de nom source et d’empreinte refusent toute fiche modifiée depuis la simulation. Un second passage est idempotent.

## Validation et preuves

Les **136 tests Node** passent, dont cinq nouveaux scénarios de réparation : absence d’écriture en simulation, préservation des autres champs, refus en cas de modification concurrente, retour arrière atomique si une écriture échoue, et impossibilité de fournir un nom arbitraire dans le plan. Un test supplémentaire exécuté avec Firestore en émulateur confirme la réparation et le refus lorsque le nom source change après la simulation. Les anciens ports étant occupés, ce test utilise `firebase.author-repair.emulators.json`, ports 1561 à 1566, sans arrêter les processus existants.

Les outils sont `functions/src/request-author-repair.js`, `functions/scripts/repair-public-request-authors.cjs` et `functions/scripts/verify-public-request-author-repair.cjs`. Les scripts d’audit sont en lecture seule et ne publient ni coordonnées ni dossiers utilisateur complets dans leur sortie.

Les preuves locales sont `.dart_tool/public-author-repair-plan.json`, `.dart_tool/public-author-repair-result.json` et `.dart_tool/public-author-repair-verification.json`. Le dernier fichier confirme **15 / 15** noms attendus et **15 / 15** paires sans autre champ changé. Les diagnostics initiaux sont conservés dans `.dart_tool/request-author-audit.json` et `.dart_tool/request-author-private-audit.json`.

Le fil public doit maintenant recevoir les noms par ses mises à jour Firestore. Rouvrir Explorer « Toutes » permet également de rétablir sa souscription si l’application était en arrière-plan.

**Aucun nouveau déploiement de Cloud Functions, de règles ou d’index et aucun APK n’ont été réalisés pour cette réparation.**
