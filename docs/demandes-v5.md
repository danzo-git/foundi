# Foundi V5 — Publication et consultation des demandes

Branche : `codex/foundi-v5-demandes`. Périmètre : FOUN-38, FOUN-39, FOUN-42. Déploiement Firebase autorisé par l’utilisateur et effectué le 29 octobre 2026 ; état détaillé en fin de document.

## Audit de l’existant

- Flutter utilise `FoundiApp`, les repositories injectés et des streams Firebase. `ProfessionalGate` conserve la session et le shell V4 ; `FoundiShell` gère l’accueil, les espaces, le compte et les paramètres. La barre `FoundiBottomBar`, `FoundiPanel`, `FoundiBrand`, les couleurs `FoundiUi` et l’authentification V3 sont réutilisés.
- Explorer et Publier étaient des actions « Bientôt disponible ». Les cartes « Mes demandes » n’avaient ni route de consultation ni repository. Le dépôt ne contenait aucun modèle, collection ou statut de demande ; les propositions étaient et restent interdites par les règles.
- Les catégories, spécialités et zones sont dans l’unique document existant `referenceData/professionalOnboarding` : `enabled`, `version`, `categories[{id,label,active,specialties[{id,label,active}],requirements}]`, `zones[{id,label,active,parentId,type,countryCode}]`, `documentTypes`. Aucune collection parallèle de références n’a été ajoutée.
- `ProfessionalCatalog.fromMap` et `activeGeographicChoices` servent le formulaire. La fonction réutilise `activeZones` pour vérifier également les ancêtres des zones. Les exigences documentaires professionnelles ne conditionnent pas la publication d’un besoin.
- Les collections existantes `users`, `professionalProfiles`, leurs justificatifs et les documents Storage restent privées. Les règles et les index des dossiers professionnels sont conservés.
- Les spécifications Markdown et les huit écrans de `Foundi_V5_Planche_Import_Figma.svg` ont été lus ; la planche a été rendue et inspectée. Le ZIP `Foundi_V5_Maquettes_Figma.zip` mentionné dans le document n’était pas fourni. Aucun import ni changement Figma n’a été réalisé.

## Parcours livrés

- **FOUN-38** : choix des références actives et titre, détails et budget facultatif, prévisualisation du contenu public, modification avant publication, publication serveur, confirmation après succès, accès au détail et à Mes demandes. Fonctionne depuis les deux espaces, sans contrôle du rôle professionnel. Les valeurs sont conservées lors des changements d’étape et d’onglet. Le brouillon est uniquement local à la session du shell, sans promesse de restauration après arrêt de l’application.
- **FOUN-39** : liste personnelle accessible depuis Compte et les cartes d’accueil existantes, tri décroissant, statut enregistré, détail et état vide avec accès à Publier. Aucun exemple de demande n’est injecté dans l’application. Liste limitée aux 50 dernières publications, annoncée dans l’interface.
- **FOUN-42** : au démarrage sans session, Explorer présente les 30 dernières demandes publiques et leur détail. Publier et Compte ouvrent l’authentification existante, qui offre aussi « Explorer sans compte ». Après connexion, l’utilisateur retrouve le shell existant et son bouton Publier ; aucune seconde authentification n’est introduite.
- Messages, notifications, opportunités personnalisées, propositions professionnelles et actions de cycle de vie de FOUN-40 restent hors périmètre.

## Schéma minimal ajouté

Il n’existait pas de statut de demande dans le dépôt. V5 introduit uniquement `published` (libellé « Publiée »). Aucun statut professionnel n’est réutilisé pour une demande.

### Projection publique : `requests/{requestId}`

Champs autorisés par la fonction : `title`, `description`, `categoryId`, `categoryLabel`, `specialtyId`, `specialtyLabel`, `zoneId`, `zoneLabel`, `budget`, `status`, `createdAt`.

`specialtyId`/`specialtyLabel` sont vides pour une catégorie sans spécialité active. `budget` est un entier FCFA ou `null`. `createdAt` est un nombre de millisecondes Unix issu de l’horloge serveur, jamais du client. Les libellés sont calculés depuis les références dans la transaction puis conservés avec la publication, pour préserver le contenu visible lors de renommages ultérieurs.

Cette projection ne contient **aucun UID auteur, nom, e-mail, téléphone, justificatif ou métadonnée de validation**. Le titre et la description sont des textes intentionnellement publics saisis par l’utilisateur : un avertissement de confidentialité figure dans le formulaire et la prévisualisation. Il ne s’agit pas d’un filtre automatique de données personnelles dans le texte libre.

### Liste privée : `userRequests/{uid}/items/{requestId}`

Même instantané public, associé à l’auteur par le chemin privé. Aucun document racine `userRequests/{uid}` n’est créé. L’application ne récupère pas d’UID depuis la projection publique et ne télécharge pas les demandes d’autrui pour les filtrer localement.

Les deux documents sont créés **atomiquement** par `publishRequest` dans la même transaction. Les futurs changements de statut de FOUN-40 devront actualiser les deux projections ensemble ; aucun changement de statut n’est implémenté ici. Aucune migration de données historiques n’a été nécessaire.

## Publication, validations et sécurité

- Nouvelle callable `publishRequest`, région `europe-west1`, même codebase Firebase `auth`. L’UID provient exclusivement de la session authentifiée ; le compte doit exister et ne pas être désactivé. Aucun rôle ni dossier professionnel n’est requis.
- Un identifiant Firestore est généré une fois par formulaire. Double clic bloqué dans l’interface ; la transaction rend les tentatives avec le même auteur et identifiant idempotentes, même après une réponse perdue. Une tentative répétée renvoie le contenu effectivement enregistré ; la confirmation utilise cette réponse. Un autre auteur ne peut pas réutiliser cet identifiant.
- Validation serveur et locale : titre de 3 à 120 caractères, description de 10 à 3 000 caractères, références actives, spécialité de la catégorie sélectionnée si elle en possède, ancêtres géographiques actifs, budget facultatif entier de 0 à 999 999 999 999 FCFA. Les espaces de groupement des milliers sont acceptés par le champ budget. Les valeurs négatives, décimales et les notations exponentielles sont refusées.
- Le catalogue est relu dans la transaction de publication pour éviter une course avec sa modification par Foundi Admin. Aucun statut, horodatage, libellé ou champ supplémentaire injecté par le client n’est recopié.
- Firestore : lecture anonyme uniquement des documents `requests` au statut `published`. Les listes publiques doivent filtrer ce statut et utiliser une limite de 50 maximum. Le repository utilise une limite de 30 et l’ordre `createdAt desc`.
- Les listes privées sont accessibles au propriétaire ou au claim `admin` existant, avec limite de 50 maximum. Toutes les écritures directes vers les deux projections sont interdites, même aux clients portant un claim admin ; création exclusivement par la fonction serveur. Aucune ouverture de `users`, des dossiers ou de Storage.
- Nouvel index composé : `requests(status ASC, createdAt DESC)`. La liste privée n’utilise que l’index simple `createdAt`, disponible par défaut.

## Fichiers V5

- `lib/features/requests/domain/request_repository.dart` : modèles, budget et contrat.
- `lib/features/requests/data/firebase_request_repository.dart` : callable, requêtes bornées, détail public.
- `lib/features/requests/presentation/request_composer.dart` : quatre étapes de publication.
- `lib/features/requests/presentation/request_views.dart` : listes, cartes, détail, état vide et accès visiteur.
- `lib/app.dart`, `lib/main.dart` : injection et accès public avec retour vers l’authentification existante.
- `lib/features/navigation/presentation/foundi_shell.dart`, `space_widgets.dart` : raccordement V4 et état de l’onglet actif.
- `lib/features/auth/presentation/account_screen.dart`, `auth_screen.dart` : accès Mes demandes/Publier et Explorer sans compte.
- `lib/features/professional/presentation/professional_gate.dart` : transmission du repository au shell, sans changement du workflow de validation.
- `functions/src/request-service.js`, `functions/src/index.js` : service et export callable.
- `firestore.rules`, `firestore.indexes.json` : droits et index V5.
- `test/requests_v5_test.dart`, `functions/test/request-service.test.js`, `functions/rules-test/requests.test.cjs`, `functions/integration-test/request-flow.test.cjs` : tests.
- `functions/package.json` : vérification des nouveaux fichiers et tests d’intégration séquentiels pour éviter les conflits du catalogue partagé dans l’émulateur.
- `firebase.v5.emulators.json` : ports dédiés aux tests locaux, sans modifier la configuration de production.

Les modifications d’authentification professionnelle déjà présentes avant le sprint restent conservées sur la nouvelle branche.

## Vérification locale

```powershell
flutter analyze --no-pub lib test
flutter test --no-pub --dart-define=V5_CAPTURE=true test
npm.cmd --prefix functions test
npm.cmd --prefix functions run check
firebase emulators:exec --only firestore,storage --config firebase.v5.emulators.json --project demo-foundi "npm.cmd --prefix functions run test:rules"
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
$env:FIREBASE_FUNCTIONS_DISCOVERY_OUTPUT_PATH = 'true'
$env:FUNCTIONS_EMULATOR_HOST = '127.0.0.1:5159'
firebase emulators:exec --only auth,firestore,storage,functions --config firebase.v5.emulators.json --project demo-foundi "npm.cmd --prefix functions run test:integration"
```

Les captures des huit écrans sont générées dans `.dart_tool/v5-preview/` avec des données de test explicitement fictives. Les jeux de tests vérifient les erreurs réseau, la validation, le double clic, la reprise interne des saisies, les deux espaces, l’accès visiteur, les limites de lecture et la confidentialité des projections. Le test d’intégration appelle la vraie callable sur les émulateurs ; il ne se limite pas à un faux repository.

Résultats de validation du sprint :

| Vérification | Résultat |
| --- | --- |
| `flutter analyze --no-pub lib test` | Aucune erreur ni avertissement |
| `flutter test --no-pub test` | 41 tests réussis, dont 8 V5 |
| `npm.cmd --prefix functions test` | 48 tests réussis |
| `npm.cmd --prefix functions run check` | Réussi |
| Règles Firestore/Storage sur émulateurs | 12 tests réussis, aucun ignoré |
| Intégration Firebase sur émulateurs | 2 parcours réussis, aucun ignoré : V3 professionnel et V5 demandes |

Les huit captures ont été inspectées visuellement. Les essais couvrent aussi un écran de 320 × 568 avec texte agrandi. Un essai sur téléphone réel du module V5 reste à faire ; aucun build APK de livraison ni aucune validation en production n’est revendiqué. Les émulateurs ont émis un avertissement Java à l’arrêt, après la réussite des tests et une sortie de commande à code 0.

## Démonstration

1. Avec un compte connecté, utiliser Publier au centre, choisir catégorie/spécialité/zone actives et un titre. Continuer, saisir une description, laisser le budget vide ou saisir un entier.
2. Prévisualiser, choisir Modifier, constater que les données sont conservées. Revenir à la prévisualisation et publier. La confirmation apparaît après la réponse serveur.
3. Accéder à Mes demandes et ouvrir le détail. Vérifier le titre, le budget, la zone et le statut. Refaire le parcours depuis l’espace Professionnel avec le même UID.
4. Ouvrir une session sans compte : Explorer doit afficher la demande et son détail public. Publier ouvre la connexion existante ; « Explorer sans compte » revient au fil.
5. Avec un autre compte, Mes demandes ne doit pas inclure les publications du premier compte.

Pour tester localement, démarrer les émulateurs V5, préparer un catalogue de test local, puis lancer Flutter avec `USE_FIREBASE_EMULATORS=true`, `FIREBASE_EMULATOR_PROJECT=demo-foundi`, et les ports `9359` (Auth), `8259` (Firestore), `5159` (Functions). Sur téléphone physique, fournir aussi `FIREBASE_EMULATOR_HOST` avec l’IP LAN de la machine ; Android émulateur utilise `10.0.2.2` par défaut.

## Déploiement autorisé du 29 octobre 2026

Commande exécutée sur le projet existant `foundi-7c837` :

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
$env:FIREBASE_FUNCTIONS_DISCOVERY_OUTPUT_PATH = 'true'
firebase deploy --only "functions:auth:publishRequest,firestore:rules,firestore:indexes" --project foundi-7c837 --non-interactive
```

Firebase a confirmé la création de `publishRequest` en `europe-west1`, la publication des règles et le déploiement des index. Les 48 tests serveur et les contrôles de syntaxe ont réussi avant le déploiement et pendant son étape de préparation.

Contrôles de production effectués en lecture seule : fonction `ACTIVE`, code du service déployé identique au code local testé, règles publiées identiques au fichier local. Un appel anonyme de `publishRequest` est refusé avec HTTP 401 / `UNAUTHENTICATED`, sans création de demande. Aucun compte ni aucune demande de démonstration n’a été créé en production.

**Au dernier contrôle, l’index `requests(status ASC, createdAt DESC)` était encore `CREATING`.** Attendre son état prêt/activé dans Firebase pour tester Explorer. La vérification en ligne suivante n’a pas été autorisée : la fin de construction de l’index et la consultation anonyme effective du fil en production restent à confirmer. La requête REST de contrôle sans clé publique avait été rejetée ; elle ne constitue pas une validation du fil utilisé par le SDK de l’application.

Sur téléphone, lancer `flutter run` depuis la branche V5 pour utiliser la configuration Firebase habituelle, sans l’option `USE_FIREBASE_EMULATORS=true`. Le parcours de publication peut être testé avec un compte connecté ; la consultation triée du fil dépend de la disponibilité de l’index. `flutter run` seul ne réalise aucun déploiement Firebase supplémentaire.
