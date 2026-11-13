# Sprint 1 — déploiement serveur du 13 novembre 2026

**Fermeture des avis publiée côté serveur :** création de `acknowledgeSafetyNotice` et mise à jour des trois Functions de consultation/livraison concernées. 77 Functions actives, paramètres préservés, quatre contrôles HTTP réussis. Le bouton nécessite une mise à jour mobile ; aucun APK n’a été généré. Voir [la confirmation de lecture et ses captures](sprint-1-fermeture-avis.md). Les bilans antérieurs ci-dessous gardent leurs compteurs historiques.

**Deuxième correctif publié :** `decideSafetyReport` et `readSafetyReport` contextualisent les avis et autorisent le réexamen tracé d’un dossier traité. 76 Functions actives, 74 autres empreintes inchangées, quatre contrôles HTTP réussis. Les nouveaux boutons Admin attendent l’accord de publication du client web. Voir [le bilan du réexamen et du contenu concerné](sprint-1-reexamen-contenu.md).

**Correctif complémentaire publié :** cinq Functions et les règles Firestore ont ensuite été mises à jour pour notifier les décisions de modération, y compris la suspension. Les 76 Functions restent actives ; les 71 autres empreintes sont inchangées. Voir le [bilan des notifications, les tests et les limites des clients installés](sprint-1-notifications-moderation.md). Les résultats ci-dessous décrivent la première activation complète du sprint.

Déploiement en production autorisé explicitement par le propriétaire : Functions, règles Firestore/Storage, index et TTL. **Aucun APK généré ou distribué. Aucun déploiement Hosting/Admin.**

Projet : `foundi-7c837`. Région Functions : `europe-west1`. Source : état local du Sprint 1, incluant les corrections des erreurs `NOT_FOUND` et `internal [0]`, après la base Git `ae377f4211366225670ef480d280e31f3439b2dc`. Les déploiements ont précédé le commit de clôture du sprint ; le déploiement serveur et le push Git constituent deux opérations distinctes.

## Résultat confirmé

| Élément | Vérification après publication |
| --- | --- |
| Functions existantes | **64 mises à jour**, toutes ACTIVE ; empreintes de déploiement renouvelées |
| Nouvelles Functions | **12 créées**, toutes ACTIVE |
| Total Functions | **76**, correspondance exacte avec les exports locaux, toutes dans `europe-west1` |
| Règles Firestore | Publiées ; source distante identique à `firestore.rules` local |
| Règles Storage | Publiées ; source distante identique à `storage.rules` local |
| Index de modération | **5 READY** : quatre variantes de file et un index d’audit |
| TTL de modération | **2 ACTIVE** : `safetyReports.deleteAt`, `safetyAudit.deleteAt` |
| Purge des preuves | Job `firebase-schedule-cleanupSafetyEvidence-europe-west1` **ENABLED**, toutes les 24 heures |
| Paramètres de production | SMTP, politique des pièces jointes et notifications conservés |
| Secrets | Références et versions Secret Manager des Functions existantes conservées ; aucune valeur de secret affichée |
| Contrôles HTTP | **18 réussis**, sans compte ni donnée métier de test |

Les politiques TTL sont actives ; leur traitement demeure asynchrone. La purge quotidienne est planifiée : elle n’a pas été déclenchée manuellement en production pour fabriquer une preuve d’exécution.

## Ordre réellement exécuté

1. Sauvegarde privée des configurations distantes des Functions, index et deux versions de règles ; contrôle des paramètres de production et empreintes des sources locales.
2. Publication des cinq index et des deux TTL, puis suivi jusqu’à READY / ACTIVE.
3. Mise à jour des 64 Functions existantes, avant d’exposer les opérations nouvelles de blocage et de sanction. Les 166 tests Node et le contrôle de syntaxe sont passés dans les hooks de déploiement.
4. Attribution au seul agent de service Storage du rôle Firebase standard `roles/firebaserules.firestoreServiceAgent`, nécessaire à l’évaluation des règles Storage lisant l’état de suspension dans Firestore. Les autres liaisons IAM ont été conservées.
5. Publication des règles Firestore et Storage.
6. Création des 12 Functions nouvelles, puis vérification des états, des paramètres, des règles, de Scheduler et des endpoints.

La première tentative de découverte des Functions a atteint le délai HTTP local de 10 secondes, avant publication des Functions. La relance a utilisé la découverte par fichier prise en charge par le CLI et un délai local de 120 secondes. Cela ne modifie aucun paramètre d’exécution en production. Les trois phases de publication (index, règles, Functions) se sont terminées avec succès.

## Contrôles HTTP sans écriture métier

Quinze callables ont été appelées **sans authentification**, avec `{data:{}}` : les dix nouvelles callables de sécurité et les endpoints historiques `publishDirectRequest`, `sendProposal`, `selectProposal`, `sendConversationMessage`, `prepareConversationAttachment`.

Toutes ont retourné **HTTP 401 / UNAUTHENTICATED**, et non 404. Leurs en-têtes CORS autorisent l’origine web contrôlée. L’accès anonyme à `readSafetyReportAttachment` est également refusé avec HTTP 401. Les prévols OPTIONS de `submitSafetyReport` et `listSafetyReports` retournent HTTP 204 avec les en-têtes CORS attendus.

Ces vérifications confirment la présence des endpoints et leur protection anonyme. Elles ne prétendent pas remplacer un parcours authentifié de modération en production. Les scénarios complets A/B/C/D, blocage, décisions et réversibilité ont été validés dans les émulateurs avant cette publication. Aucun compte, signalement, blocage ou sanction de test n’a été créé en production, et aucun push ni e-mail de test n’a été envoyé.

## Paramètres et artefacts conservés

- Valeurs SMTP inchangées.
- `ATTACHMENT_REQUIRE_SCAN=false` conservé, ainsi que l’hôte et le port précédemment configurés : aucun antivirus ni fournisseur supplémentaire activé.
- `NOTIFICATION_PUSH_ENABLED=true` conservé pour les fonctions qui l’utilisaient.
- Références et versions des secrets inchangées pour les fonctions existantes.
- Les 35 empreintes de fichiers serveur/configuration contrôlées avant publication sont restées inchangées pendant le déploiement.

Sauvegardes et journaux locaux privés, ignorés par Git : `.dart_tool/sprint1-predeploy-*.json`, `.dart_tool/sprint1-deploy-*.log`, `.dart_tool/sprint1-deploy-source.json`, `.dart_tool/sprint1-functions-verification.json`, `.dart_tool/sprint1-rules-verification.json`, `.dart_tool/sprint1-index-status.json`, `.dart_tool/sprint1-endpoint-checks.json`. La sauvegarde des Functions peut contenir des paramètres opérationnels ; ne pas la publier.

## Suite côté utilisateur

Actualiser Foundi Admin et réessayer le signalement depuis le téléphone. Les écrans installés utilisent déjà les noms d’endpoints maintenant publiés. Les améliorations locales d’affichage des erreurs nécessiteront une publication distincte des clients pour apparaître dans ces clients ; aucun binaire ni site Admin n’a été publié ici.

La procédure humaine et les validations juridiques du Sprint 2 restent des travaux distincts. Pour toute réversibilité, conserver les protections serveur et suivre [le plan](sprint-1-plan-deploiement.md) : ne pas restaurer les anciens endpoints dépourvus de contrôles pendant que des mesures de sécurité sont actives.
