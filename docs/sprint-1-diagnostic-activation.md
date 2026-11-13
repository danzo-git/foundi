# Signalements : diagnostic des captures du 13 novembre 2026

**Mise à jour :** l’activation serveur a ensuite été autorisée et exécutée. Les 76 Functions sont actives, les cinq index prêts et les deux TTL actifs. Les endpoints ne répondent plus 404. Voir [le compte rendu de déploiement](sprint-1-deploiement-serveur.md). Les sections suivantes décrivent le constat initial et les corrections locales.

## Cause vérifiée en lecture seule

Projet configuré par l’application et Admin : `foundi-7c837`, région `europe-west1`.

Au moment du contrôle, Firebase expose **64 fonctions**, mais aucune des **12 fonctions nouvelles du Sprint 1**. Les deux URL utilisées dans les captures répondent `HTTP 404` à une requête HEAD non authentifiée :

- `https://europe-west1-foundi-7c837.cloudfunctions.net/submitSafetyReport`
- `https://europe-west1-foundi-7c837.cloudfunctions.net/listSafetyReports`

La liste Firebase confirme leur absence, au-delà du seul code HTTP. Le SDK mobile expose cette absence comme `NOT_FOUND` ; le SDK web peut la remonter comme une erreur de transport `internal [0]`. Le texte saisi dans le formulaire n’est pas en cause.

La lecture de la configuration distante des index confirme aussi **0/5 index de modération** et **0/2 politiques TTL de modération** présents. Les index déjà en production sont tous représentés dans la configuration locale ; seuls les cinq nouveaux index sont à ajouter (comparaison sans le champ implicite `__name__`).

Fonctions absentes :

```text
blockUser
cleanupSafetyEvidence
decideSafetyReport
listBlockedUsers
listSafetyNotices
listSafetyReports
readSafetyContext
readSafetyReport
readSafetyReportAttachment
submitSafetyReport
unblockSafetyTarget
unblockUser
```

Ces observations sont cohérentes avec la livraison précédente : code et tests locaux, **sans déploiement en production**, conformément à la demande du propriétaire.

## Correctifs locaux

- Les dépôts Firebase Flutter/Admin traduisent désormais les erreurs de service/transport en messages français compréhensibles. Les messages métier précis, tels qu’un contenu retiré, une restriction de compte, un quota ou une révision concurrente, restent conservés.
- Un code `not-found` générique ne prétend plus que la demande a disparu. Une erreur interne ne révèle plus un lien de console ou une exception d’infrastructure.
- Le formulaire conserve son motif et son commentaire après un échec ; il n’affiche pas de succès sans réponse positive du serveur.
- Admin conserve une erreur explicite et l’action Réessayer ; une panne ne devient pas une fausse file vide.
- En détail Admin, une erreur de décision ou de téléchargement revient en haut du dossier pour rester visible sur une fenêtre étroite.
- Le serveur transforme une erreur Firestore d’index manquant en précondition compréhensible pour l’admin, sans contourner les index ni lire tous les dossiers. Les erreurs de permissions continuent d’être refusées.

Les nouveaux tests simulent les erreurs réelles du SDK, y compris `NOT_FOUND` et `internal [0]`. L’émulateur Firestore ne reproduit pas l’absence d’index de production ; ce cas est donc couvert par un test Node dédié.

Revalidation du correctif : **166 tests Node**, **16 tests Flutter ciblés**, **7 tests Admin ciblés**, tous réussis ; contrôle de syntaxe Node et analyse Flutter. Les suites Emulator du sprint précédent n’ont pas été rejouées pour ce correctif de remontée d’erreur ; aucun contrat, règle ou flux d’écriture métier n’est modifié ici.

## Activation requise, non exécutée

Il faut approuver le [plan de déploiement serveur du Sprint 1](sprint-1-plan-deploiement.md) pour rétablir les parcours sur le téléphone et dans Admin : index/TTL, toutes les Functions concernées, puis règles Firestore/Storage. Ne pas déployer uniquement les deux endpoints visibles dans les captures : les contrôles de blocage doivent aussi mettre à jour les endpoints de contact existants.

Conserver les paramètres actuels de production (SMTP, politique des pièces jointes, notifications) lors de cette activation. Aucun nouveau fournisseur ou antivirus ne doit être activé implicitement.

Les vérifications distantes effectuées pour ce diagnostic sont uniquement `functions:list`, `firestore:indexes` et deux requêtes HEAD. Aucun signalement n’a été envoyé, aucune décision de modération appliquée, aucune règle modifiée et aucun index créé. Aucun déploiement ni APK n’a été produit.

Le déploiement du serveur permettra aux écrans déjà installés d’utiliser leurs endpoints existants. Les améliorations de présentation des erreurs restent locales jusqu’à une publication séparée des clients correspondants.
