# Foundi V6 — FOUN-40 et FOUN-52

## Audit et compatibilité

Le répertoire contenait déjà les modifications V3/V4/V5 non commitées. Elles ont été conservées. Aucun ticket Jira, fichier Figma en ligne ou migration de production n'a été modifié. Le déploiement, autorisé ultérieurement, est décrit en fin de document.

- Modèle V5 : `RequestDraft`, `FoundiRequest`, interface `RequestRepository`, implémentation `FirebaseRequestRepository`. Le shell conserve ses routes internes Explorer, Publier, Mes demandes et détail. Le formulaire `RequestComposer`, les cartes et le détail publics sont réutilisés.
- `requests/{id}` est la projection publique, sans UID ni coordonnées de compte. `userRequests/{uid}/items/{id}` est l'instantané privé. Le chemin fournit la propriété ; aucun nouveau champ propriétaire ni migration ne sont nécessaires.
- V5 ne définissait que `published`. Les champs éditables sont titre, description, catégorie, spécialité, zone et budget entier FCFA facultatif. `createdAt` est un nombre de millisecondes produit par le serveur. Les libellés proviennent de `referenceData/professionalOnboarding`.
- Les règles V5 interdisent déjà toutes les écritures directes, y compris administrateur, et limitent les lectures publiques à `status == published`. Les nouvelles écritures passent donc par les callables ; aucune ouverture des règles n'est nécessaire.
- Le profil approuvé est `professionalProfiles/{uid}.status == approved`, avec `categoryIds`, `specialtyIds`, `zoneIds`. Les autres statuts sont `draft`, `pending`, `needs_changes`, `rejected`, `suspended`. Le contrôle serveur ne repose pas sur l'espace affiché ni sur une sélection locale.
- Le shell utilise `preferredMode` pour initialiser l'espace, puis un état local ; une suspension live ramène au client. La navigation commune et la validation professionnelle existantes sont conservées.
- Les tests V5 Flutter, serveur, règles et intégration ont été réutilisés. Le dépôt fournit Firebase Emulator Suite, des JAR locaux, `firebase.v5.emulators.json` et un générateur de ports libres.

## FOUN-40

`manageRequest` vérifie l'UID authentifié et le compte non désactivé, puis lit exclusivement le chemin privé de cet UID dans une transaction. Un tiers est refusé. L'interface de gestion est séparée de `RequestRepository` pour préserver les implémentations et les tests V5 existants.

L'édition est autorisée seulement pour `published`, sur le même identifiant et avec le même `createdAt`. Le serveur valide une liste fermée de champs, recalcule les libellés et exige des références actives, ancêtres de zone compris. Le formulaire reprend les identifiants, titre, description et budget existants. Une ancienne référence indisponible doit être remplacée explicitement. Le contrôle `expectedRevision` utilise `updatedAt`, ou `createdAt` pour V5 ; une édition concurrente obsolète est refusée. Le formulaire conserve la saisie en cas d'erreur.

Les transitions sont `published → closed`, puis `published|closed → deleted`. Clôture et suppression répétées sont idempotentes. Aucune réouverture n'est proposée. `updatedAt` est fixé par le serveur et augmente même si deux opérations partagent la même milliseconde. Les deux documents sont actualisés atomiquement ; la projection publique est reconstruite par liste blanche, sans recopier d'éventuels champs privés.

La suppression logique est le plus petit ajout compatible : statut `deleted` dans les deux instantanés. Les règles existantes rendent immédiatement les documents non publics illisibles aux visiteurs. La liste habituelle de l'auteur masque `deleted`, tandis que `closed` reste consultable dans son historique. Les documents sont conservés sans nouvelle promesse de durée, purge ou politique RGPD.

Le menu auteur apparaît uniquement dans Mes demandes. Confirmation en feuille basse, indicateur de chargement, prévention des clics répétés et erreur sans faux succès. Les demandes clôturées ont un détail personnel ; les détails publics continuent de vérifier les règles serveur.

## FOUN-52

`listOpportunities` vérifie le compte actif et son adresse e-mail vérifiée, comme `requireApproved` existant, puis le statut approuvé avant et après ses lectures. Les filtres sont des sous-ensembles des catégories, spécialités et zones du dossier serveur. Une liste vide donne zéro résultat ; un filtre absent reprend tout le domaine déclaré. Sans zone déclarée, aucun résultat. La comparaison géographique porte sur l'identifiant exact, sans extension aux parents ou enfants. Une catégorie qui possède des spécialités doit correspondre à une spécialité du dossier ; une catégorie sans spécialité utilise l'identifiant vide de V5.

Chaque requête cible `published` et une combinaison exacte catégorie/spécialité/zone. Aucun téléchargement global du fil. Une page renvoie au plus 30 résultats, examine au plus 60 documents et exécute au plus 10 requêtes de demandes. Les vérifications de propriété utilisent des lectures groupées des chemins privés du professionnel, sans exposer d'UID. Les filtres dédupliqués produisent des combinaisons disjointes ; le client déduplique aussi par identifiant.

L'ordre parcourt les combinaisons du dossier, puis les dates décroissantes et l'identifiant décroissant dans chaque combinaison. Le curseur contient l'index de combinaison et le couple date/identifiant. Ce choix évite de charger chaque catégorie entière pour fabriquer un tri global. Une page intermédiaire vide peut proposer « Charger la suite ». Les filtres réinitialisent la pagination. Le bouton Actualiser recharge les résultats ; la liste n'est pas un abonnement temps réel. Le détail public refuse une demande clôturée depuis le chargement de la page.

L'accueil professionnel donne accès aux opportunités. Cartes et détail publics réutilisés ; filtres limités au dossier, chargement, erreur/réessai, état vide et pagination. Aucun droit d'écriture ou de proposition n'est ajouté. Aucun message, paiement, notification ou jeu de données fictif.

## Fichiers concernés par V6

- `functions/src/request-service.js`, `functions/src/index.js` : gestion transactionnelle et exports des deux nouvelles callables.
- `functions/src/opportunity-service.js` : contrôle d'accès, filtres et pagination.
- `lib/features/requests/domain/request_repository.dart`, `data/firebase_request_repository.dart` : identifiants de références, révision, gestion et pages d'opportunités.
- `lib/features/requests/presentation/request_composer.dart`, `request_views.dart`, `opportunity_view.dart` : formulaire réutilisé, actions auteur et vue professionnelle.
- `lib/features/navigation/presentation/foundi_shell.dart` : accès et routes V6.
- `firestore.indexes.json` : nouvel index `requests(status ASC, categoryId ASC, zoneId ASC, specialtyId ASC, createdAt DESC, __name__ DESC)`. L'index V5 est conservé. `firestore.rules` n'a pas été modifié par V6.
- Tests : `test/requests_v6_test.dart`, `test/opportunities_v6_test.dart`, `functions/test/request-service.test.js`, `functions/test/opportunity-service.test.js`, `functions/rules-test/requests.test.cjs`, `functions/integration-test/request-flow.test.cjs`. `functions/package.json` inclut la vérification syntaxique du nouveau service.

## Vérifications

Les commandes Flutter ont été lancées via `flutter analyze` / `flutter test`, puis via le même outil Flutter directement (`dart.exe <SDK>/bin/cache/flutter_tools.snapshot analyze --no-pub` et `test --no-pub`) pour contourner le démarrage du wrapper Windows et permettre l'accès au verrou du SDK. Le formatage Dart a été exécuté. Les premiers passages ont révélé un encodage Windows non UTF-8, un libellé de statut absent et des informations de lint ; corrigés avant les passages finaux.

Les résultats finaux et les éventuelles limites sont consignés ci-dessous. À la livraison initiale, aucun déploiement n'avait été lancé. Le déploiement des deux fonctions et de l'index a ensuite été autorisé explicitement par l'utilisateur et réalisé, comme décrit en fin de document. Le code mobile V6 doit être utilisé pour accéder aux nouvelles vues.

### Résultats exécutés

| Vérification | Résultat |
| --- | --- |
| Outil Flutter `analyze --no-pub` | Aucun problème |
| Outil Flutter `test --no-pub` | 46 tests réussis |
| Dernière vérification ciblée `test --no-pub test/requests_v6_test.dart test/navigation_v4_test.dart`, après ajustement du retour système | 13 tests réussis ; analyse relancée sans problème |
| `node.exe --test functions/test/*.test.js` | 53 tests réussis ; le service opportunités a aussi été revérifié après alignement sur l'e-mail vérifié |
| `npm.cmd --prefix functions run check` et `git diff --check` | Réussis |
| Emulator Suite : `npm.cmd --prefix functions run test:rules` | 12 tests réussis, aucun ignoré (Firestore et Storage) |
| Emulator Suite : `npm.cmd --prefix functions run test:integration` | 2 tests réussis, aucun ignoré : validation professionnelle existante et callables V5/V6 |

Les tests de règles couvrent lecture anonyme bornée, exclusion de `closed`/`deleted`, confidentialité des chemins auteur et refus d'écritures directes auteur/tiers/admin. Les tests serveur couvrent propriété, champs protégés, références actives, contrôle de version, idempotence et projection publique. Les tests widget couvrent préremplissage et sauvegarde sur le même ID, erreur sans succès, confirmations, clôture, suppression, filtres et détail public. La suite existante vérifie publication, authentification, navigation et changements d'espace.

La commande initiale sur les ports V5 a rencontré des ports occupés. `node.exe functions/test-support/prepare-emulators.cjs` a produit la configuration locale ignorée `.firebase-integration.json` et des ports libres. Une première exécution complète a passé les 12 tests de règles mais échoué aux deux tests de callables (chargement Functions `fetch failed`, puis 404). Après arrêt des processus de cette session restés actifs, la relance suivante a passé les deux tests :

```powershell
$v6EmulatorConfig = Get-Content .firebase-integration.json -Raw | ConvertFrom-Json
$env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:' + $v6EmulatorConfig.emulators.functions.port
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
$env:NO_PROXY = '127.0.0.1,localhost,::1'
node.exe C:\Users\kouam\AppData\Roaming\npm\node_modules\firebase-tools\lib\bin\firebase.js emulators:exec --config .firebase-integration.json --project demo-foundi --only auth,firestore,storage,functions "npm.cmd --prefix functions run test:integration"
```

Le runtime de règles Storage affiche une exception Java à l'arrêt de la suite, après les assertions et le code de sortie 0 ; aucun test n'a échoué sur ce dernier passage. L'émulateur ne prouve pas la construction de l'index en production. Aucun test sur appareil physique ou Firebase de production n'a été exécuté pour V6. Le pack ZIP/prototype HTML n'a pas été importé : l'aperçu fourni sert de référence visuelle, avec adaptation au formulaire V5 existant.

## Déploiement autorisé et contrôlé — 30 octobre 2026

Projet explicitement ciblé : `foundi-7c837`. Commande exécutée avec le CLI Firebase installé :

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
$env:NO_PROXY = '127.0.0.1,localhost,::1'
node.exe C:\Users\kouam\AppData\Roaming\npm\node_modules\firebase-tools\lib\bin\firebase.js deploy --project foundi-7c837 --only functions:auth:manageRequest,functions:auth:listOpportunities,firestore:indexes --non-interactive
```

Déploiement terminé avec code de sortie 0. Les hooks pré-déploiement ont repassé les 53 tests serveur et la vérification syntaxique. Seules les deux nouvelles fonctions du codebase `auth` et les index ont été ciblés ; aucun déploiement des règles, de l'application Flutter, de Foundi Admin ou des fonctions existantes.

Contrôles réels après déploiement, en lecture seule, avec les API Google Cloud et les endpoints publics :

| Contrôle de production | Résultat |
| --- | --- |
| `manageRequest`, région `europe-west1` | `ACTIVE`, révision `managerequest-00001-dor`, mise à jour `2026-10-30T13:02:44.114165679Z` |
| `listOpportunities`, région `europe-west1` | `ACTIVE`, révision `listopportunities-00001-rap`, mise à jour `2026-10-30T13:02:47.358872655Z` |
| Index V6 `CICAgJim14AK` | `READY`, champs exacts catégorie/zone/spécialité/statut/date/identifiant attendus |
| Requête utilisant l'index V6 avec des valeurs de filtre de sonde sans correspondance | Réussie, aucune écriture |
| Appel anonyme de chaque nouvelle callable | HTTP 401, `UNAUTHENTICATED` |
| Fil anonyme `published`, tri `createdAt DESC`, limite 1 | Réussi ; un document public retourné, uniquement les champs V5 autorisés, aucune donnée d'auteur |
| Requêtes anonymes sans filtre de statut, ou filtrées `closed` / `deleted` | HTTP 403 dans les trois cas |
| Lecture anonyme d'un chemin privé auteur de sonde | HTTP 403 |

Un premier contrôle exécuté pendant la création avait vu `DEPLOYING` puis une fonction encore absente ; la vérification finale a confirmé les deux états `ACTIVE`. Le premier identifiant de sonde du chemin privé utilisait un nom réservé Firestore et renvoyait HTTP 400 ; corrigé vers un identifiant valide, le contrôle de droits renvoie bien HTTP 403.

Aucun compte, dossier professionnel ou demande de test n'a été créé en production. Les scénarios connectés d'édition/clôture/suppression et de consultation par un professionnel approuvé ont été validés sur émulateur, pas rejoués avec un compte réel en production. Le parcours mobile sur appareil reste à valider avec l'application V6 ; le présent déploiement concerne le backend et l'index.
