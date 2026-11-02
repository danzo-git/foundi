# Foundi V7 — Envoyer et consulter des propositions privées

Travail sur `codex/foundi-v7-propositions`. Le travail V5/V6 validé a été poussé sur `origin/codex/foundi-v5-demandes`, commit `b407b5d`. Le déploiement V7, autorisé ultérieurement le 31 octobre 2026, est décrit en fin de document. Aucune migration de production, modification Jira ou mise à jour Figma.

## Audit et plan retenu

- Flutter : repositories injectés, `FoundiShell`, `RequestComposer`, `RequestListView`, détail public et Explorer commun. Les erreurs utilisent `AuthFailure` et `AuthActionState`. Les demandes ont un ID stable et les statuts `published`, `closed`, `deleted`. Le propriétaire est le chemin privé `userRequests/{uid}/items/{id}` ; la projection `requests/{id}` ne contient pas d'UID.
- Vérification professionnelle : `professionalProfiles/{uid}.status == approved`, contrôlée côté serveur avec compte actif et e-mail vérifié. Le mode Client/Professionnel est une préférence visuelle, pas une autorisation d'envoi. Les catégories et zones de Pour moi ne conditionnent pas l'autorisation de proposer depuis Tout Explorer.
- Firebase : Cloud Functions 2e génération Node 22, région `europe-west1`, SDK Admin, transactions et wrapper d'erreurs existants. Les règles refusaient toute lecture/écriture de `proposals`, collection réservée sans modèle implémenté. Aucun modèle de propositions concurrent à préserver.
- Plan exécuté : mutation atomique et contrôle de propriété ; formulaire/prévisualisation/confirmation ; historique envoyé ; propositions reçues avec compteur privé ; tests serveur, Flutter, règles et intégrations.

Le prototype HTML joint contient les dix maquettes SVG intégrées. Ses écrans ont servi à reprendre les parcours et libellés, avec les composants Foundi existants ; aucune donnée fictive du prototype n'a été injectée dans l'application.

## Compatibilité de propriété V5/V6

L'UID auteur ne peut pas être déduit de la projection publique seule. La référence privée `requestOwnership/{requestId} = {ownerUid}` est exclusivement serveur. La publication enregistre cette référence avec les deux instantanés ; aucun UID n'est ajouté au public. La création d'une proposition confirme encore le chemin privé et la date de création dans sa transaction.

Pour une demande historique sans référence, le serveur récupère au plus 50 documents du collection group `items` ayant exactement le même `createdAt`, puis ne conserve que l'ID exact et un chemin `userRequests/{uid}/items/{requestId}`. Une seule correspondance est requise. Zéro correspondance, ambiguïté, instantané absent ou incohérent : refus explicite, sans écriture ni attribution supposée. Le registre est mémorisé seulement lors d'un envoi réussi. Il n'y a ni parcours global de toutes les demandes ni migration de données de production.

Limite volontaire : si plus de 50 publications partagent la même milliseconde et masquent la correspondance dans ce lot, la résolution peut refuser une ancienne demande. Elle ne choisit jamais arbitrairement un auteur. Une correction de données exceptionnelle demanderait une opération séparée et autorisée.

## Modèle et sécurité

`proposals/{id}` est privé. L'ID est SHA-256 de `requestId + séparateur nul + professionalUid` : une proposition par couple, y compris entre deux appareils et après réponse réseau perdue. Champs : `requestId`, `professionalUid`, `clientUid` dérivé du serveur, `requestTitle`, `professionalName` (nom d'activité au moment de l'envoi), `description`, `amount`, `delay`, `status: sent`, `createdAt` serveur.

Description obligatoire de 10 à 3000 caractères ; montant entier FCFA strictement positif, facultatif, maximum 999 999 999 999 ; délai libre facultatif de 120 caractères au plus. Les champs supplémentaires sont refusés. Aucun statut, UID ni timestamp n'est accepté dans le corps de proposition.

La transaction lit le profil approuvé, la demande publique ouverte, l'instantané auteur et la proposition déterministe avant toute écriture. Elle refuse l'auto-réponse et les statuts non publics. Au succès, elle écrit la proposition et incrémente `proposalCount` uniquement dans l'instantané privé auteur. Elle ne modifie ni statut de demande, ni timestamp d'édition, ni données publiques, et n'écrit aucune notification. Les répétitions ne réincrémentent pas le compteur.

Les règles autorisent la lecture d'une proposition uniquement à son professionnel émetteur ou son client destinataire. Les listes exigent une requête de partie autorisée et une limite de 50 au plus. Toutes les écritures directes restent interdites, même pour un client avec claim admin. Le registre de propriété n'est jamais lisible par le frontend. Une suspension ou clôture/suppression de demande ne retire pas l'accès historique des parties à leurs propositions ; aucun nouvel envoi n'est permis. Aucun droit privé sur les profils de l'autre partie n'est ajouté.

Trois callables : `proposalAccess` vérifie le droit avant d'afficher le CTA et signale une proposition existante ; `sendProposal` revalide et enregistre ; `proposalApproval` retourne seulement le booléen d'approbation actuelle aux parties autorisées. Le badge est vérifié à l'ouverture du détail, sans exposition du dossier professionnel ni abonnement public aux décisions admin.

## Parcours Flutter

- Action « Faire une proposition » dans le détail public pour un professionnel approuvé, quel que soit l'espace actif. Contrôle serveur préalable ; explication pour un profil non approuvé ou sa propre demande. Une proposition déjà envoyée ouvre son détail.
- Formulaire, prévisualisation et bouton « Confirmer et envoyer ». Validation, chargement, anti-double clic et erreur réelle. La confirmation n'apparaît qu'après l'enregistrement serveur ; aucun chat ni acceptation.
- « Mes propositions » depuis l'accueil professionnel et le compte professionnel, avec liste limitée aux 30 derniers envois, état réel Envoyée et détail.
- Dans Mes demandes : compteur privé réel et « Voir les propositions reçues ». Le Compte offre aussi les propositions reçues de l'auteur, y compris l'historique de demandes supprimées. Liste limitée aux 30 dernières propositions correspondant à la requête, annoncée dans l'interface.
- Détails privés : demande liée, nom professionnel, message, montant/délai facultatifs, date et vérification actuelle. Le nom de la demande et de l'activité est conservé comme instantané pour permettre l'historique après suppression ou renommage.
- La barre V4 et Publier restent en place. Les références et filtres Explorer ne sont pas modifiés. Le formulaire d'édition et les transitions FOUN-40 sont conservés ; seules les entrées nécessaires aux propositions sont ajoutées aux cartes/détails existants.

## Fichiers et index

- `functions/src/proposal-service.js`, exports dans `functions/src/index.js`, vérification syntaxique dans `functions/package.json`.
- `lib/features/proposals/domain/proposal_repository.dart`, `data/firebase_proposal_repository.dart`, `presentation/proposal_views.dart`.
- Adaptateur `FirebaseRequestRepository` vers le repository de propositions, compteur privé optionnel dans `FoundiRequest`, points d'entrée dans `request_views.dart`, `account_screen.dart`, `foundi_shell.dart`. Pas de second système d'authentification ni de nouvelle instance Firebase.
- `firestore.rules` : lecture privée des propositions et registre fermé ; droits des demandes, utilisateurs, professionnels et Storage inchangés.
- Trois index composites `proposals` : `(professionalUid ASC, createdAt DESC)`, `(clientUid ASC, createdAt DESC)`, `(clientUid ASC, requestId ASC, createdAt DESC)` ; override `items.createdAt` pour l'égalité serveur de collection group, en conservant les index collection ascendant/descendant. Tous les index V5/V6 restent présents. Leur déploiement autorisé est suivi en fin de document.
- Tests : `functions/test/proposal-service.test.js`, `functions/rules-test/proposals.test.cjs`, `functions/integration-test/proposal-flow.test.cjs`, `test/proposals_v7_test.dart`.

## Vérifications réellement exécutées

- `node.exe --test functions/test/*.test.js` : **58 réussis**, dont unicité concurrente, propriété historique, approbation, auteur distinct, statuts, montants et champs protégés.
- Outil Flutter `test --no-pub` via `dart.exe <SDK>/bin/cache/flutter_tools.snapshot` : **61 réussis**. V7 couvre formulaire, montant invalide, erreur sans faux succès, double clic, confirmation, envoi depuis Tout Explorer par un professionnel resté en espace client, historique/détail, compteur reçu, refus UX et états vides/erreur. Les tests V3/V4/V5/V6 sont conservés et exécutés.
- Firebase Emulator Suite : `emulators:exec --config .firebase-integration.json --project demo-foundi --only auth,firestore,storage,functions "npm.cmd --prefix functions run test:emulated"`, avec `FUNCTIONS_EMULATOR_HOST` sur le port généré, `FUNCTIONS_DISCOVERY_TIMEOUT=120` et `NO_PROXY=127.0.0.1,localhost,::1` : **15 tests de règles et 3 intégrations réussis, aucun ignoré**. L'intégration V7 utilise de vrais clients Firebase sur émulateur, trois comptes plus un visiteur, les callables réelles et une demande dont la référence propriétaire est retirée pour simuler V5. Les intégrations de validation professionnelle et de demandes V5/V6 passent aussi.
- Le runtime Storage affiche son exception Java connue à l'arrêt, après succès des assertions et code de sortie 0 ; aucun test ne s'est terminé en échec sur ce passage.
- Analyse Flutter `analyze --no-pub` via le même outil : **aucun problème** sur la dernière passe, après correction des avertissements de style. `npm.cmd --prefix functions run check` et `git diff --check` : **réussis**.

À la livraison initiale, il n'y avait pas eu de test sur appareil physique ni de validation en production pour V7. L'émulateur ne prouve pas la construction des index réels. Le déploiement ultérieur autorisé et ses contrôles de production sont décrits ci-dessous. Aucun envoi, acceptation, chat ou notification de test n'a été créé en production.

## Déploiement autorisé — 31 octobre 2026

Projet explicitement ciblé : `foundi-7c837`. Commande exécutée :

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
$env:NO_PROXY = '127.0.0.1,localhost,::1'
node.exe C:\Users\kouam\AppData\Roaming\npm\node_modules\firebase-tools\lib\bin\firebase.js deploy --project foundi-7c837 --only functions:auth:proposalAccess,functions:auth:sendProposal,functions:auth:proposalApproval,functions:auth:publishRequest,firestore:rules,firestore:indexes --non-interactive
```

Déploiement terminé avec code de sortie 0. Les trois nouvelles fonctions ont été créées et `publishRequest` actualisée pour enregistrer le propriétaire dans le registre privé. Les règles Firestore et les index ont été publiés. Les hooks pré-déploiement ont repassé les **58 tests serveur** et la vérification syntaxique. Aucun déploiement Storage, Foundi Admin ou application mobile.

La construction des index a initialement donné `CREATING` ; les fonctions sont passées par `DEPLOYING`. Le contrôle `.dart_tool/v7-production-check.cjs --wait` s'est terminé avec succès (code 0) après leur passage aux états opérationnels.

| Élément vérifié en production | Résultat |
| --- | --- |
| `proposalAccess` | `ACTIVE`, révision `proposalaccess-00001-quf` |
| `sendProposal` | `ACTIVE`, révision `sendproposal-00001-suv` |
| `proposalApproval` | `ACTIVE`, révision `proposalapproval-00001-dew` |
| `publishRequest` mis à jour | `ACTIVE`, révision `publishrequest-00002-vuv` |
| `manageRequest` et `listOpportunities` existantes | `ACTIVE`, révisions V6 inchangées |
| Index propositions émises `CICAgJjFqZMK` | `READY` |
| Index propositions reçues `CICAgNjpgYIK` | `READY` |
| Index propositions reçues par demande `CICAgNiroIEK` | `READY` |
| Index collection group `items.createdAt ASC` | `READY` |
| Règles Firestore publiées | Source identique au fichier local testé après normalisation des fins de ligne |
| Trois requêtes de listes de propositions avec critères de sonde sans correspondance | Réussies, zéro document retourné |
| Requête collection group utilisée pour les anciennes demandes | Réussie |
| Appel anonyme des trois nouvelles fonctions | HTTP 401, `UNAUTHENTICATED` |
| Lecture anonyme des propositions et du registre propriétaire | HTTP 403 |

Ruleset publié : `projects/foundi-7c837/rulesets/7c1a6e0e-3864-4c86-b84d-a19cc41df4ef`. SHA-256 de la source normalisée : `b96f391121718ceb273da84d2521f57b4110a7ae748015db8390071f429d9b3f`.

Non-régression publique réelle : `.dart_tool/explorer-production-check.cjs` a confirmé les six index de demandes `READY`, les six combinaisons de filtres Explorer avec un résultat public correspondant, un résultat vide correct, et le refus anonyme des statuts `closed`, `deleted` et des requêtes sans filtre de statut. Code de sortie 0.

Aucun compte, demande ou proposition de test n'a été créé en production. Les contrôles ci-dessus vérifient le déploiement, les index, la correspondance des règles et les accès anonymes. L'envoi positif avec comptes connectés et la lecture par les parties ont été testés sur émulateur ; ils restent à vérifier sur téléphone avec les comptes de l'utilisateur. La commande de déploiement ne met pas à jour l'application installée.

### Recette sur téléphone

Lancer l'application **V7** depuis cette branche, par exemple `flutter run` dans le projet, sans `--dart-define=USE_FIREBASE_EMULATORS=true`. La configuration par défaut utilise `foundi-7c837`. Un backend déployé ne met pas à jour automatiquement une ancienne application V6 installée.

1. Avec un compte A, publier une demande ou utiliser sa propre demande encore ouverte.
2. Avec un autre compte B dont le dossier professionnel est approuvé, ouvrir cette demande depuis Tout Explorer, puis Faire une proposition. Renseigner la description, éventuellement un montant positif et un délai, prévisualiser et confirmer.
3. B retrouve l'envoi dans Mes propositions. Un nouvel accès à la même fiche doit proposer de consulter l'envoi existant, sans doublon.
4. Avec A, ouvrir Mes demandes puis Voir les propositions reçues. Vérifier le compteur, le contenu privé et le détail. Il n'y a pas d'action d'acceptation ni de conversation.
5. Vérifier qu'un compte tiers ne voit pas ces propositions, qu'un compte non approuvé ne peut pas envoyer et qu'une demande clôturée n'accepte plus de nouvel envoi.

Les scénarios positifs et les trois comptes ont été validés sur émulateur ; les contrôles de production sont en lecture seule et ne remplacent pas cette recette utilisateur sur appareil.
