# Catalogue partagé et validation professionnelle

## Analyse et compatibilité

Le mobile et Foundi Admin utilisent `foundi-7c837`. Le référentiel commun reste le document existant `referenceData/professionalOnboarding` avec `categories`, leurs `specialties`, `zones` et `documentTypes`. Aucune nouvelle collection métier ni migration des identifiants.

Les dossiers restent dans `professionalProfiles/{uid}`, leurs métadonnées privées dans `documents/{kind}`, les pièces dans `professionalDocuments/{uid}/{kind}/{uploadId}`. Les notifications et décisions existantes sont conservées. Les modifications du catalogue sont auditées dans `professionalAudit` avec `type: catalog`, administrateur, avant/après, version et date serveur.

Les zones acceptent désormais `type`, `parentId`, `countryCode: CI` et `description`. Types : country, district, region, department, subprefecture, city, commune, quartier, intervention. La hiérarchie peut sauter un niveau ; le parent doit être d'un niveau supérieur. Les anciennes zones sans parent/type restent valides. Désactiver un parent rend ses descendants indisponibles sans effacer leurs données. Aucun annuaire officiel n'est importé automatiquement : l'administrateur saisit les zones pertinentes de Côte d'Ivoire.

Les catégories et spécialités possèdent un libellé, une description, un statut actif ; les catégories ont une icône et `requirements.independent` / `requirements.company`. Les identifiants sont immuables et générés côté serveur, sauf l'identifiant d'un type de justificatif saisi lors de sa création (notamment `identity`). La désactivation est utilisée à la place de la suppression. Les champs historiques inconnus sont conservés.

Le catalogue demeure un document unique pour rester compatible. La fonction limite sa taille à 800 Ko, 1 000 catégories/zones/types et 100 spécialités par catégorie. Une migration explicite sera nécessaire si ces limites sont atteintes.

## Préparer les inscriptions dans Foundi Admin

Après déploiement autorisé de la nouvelle fonction :

1. Catalogue → Justificatifs : créer `identity` avec le libellé « Pièce d'identité », puis les autres pièces nécessaires.
2. Catégories : créer les activités, leur description/icône et sélectionner les justificatifs requis pour les indépendants et les entreprises. `identity` est systématiquement exigée côté serveur.
3. Ouvrir une catégorie pour ajouter ses spécialités, ou utiliser la rubrique Spécialités.
4. Zones géographiques : créer la racine « Côte d'Ivoire » de type Pays, puis les zones avec leur type et parent. Les racines plates historiques restent acceptées.
5. Activer le référentiel. L'activation exige une catégorie, une zone et le type `identity` actifs, et des exigences documentaires cohérentes.

Le professionnel voit les choix actifs en temps réel dans « Parlons de ton activité ». Les sélections multiples restent enregistrées par identifiant. Les libellés des zones indiquent le chemin hiérarchique. Un ancien choix désactivé est signalé et peut être retiré. Si des spécialités actives sont proposées pour les catégories sélectionnées, au moins une est requise.

La soumission vérifie le catalogue courant, les zones et leurs parents, les spécialités, les champs métier, les documents privés effectivement présents et l'acceptation des textes légaux publiés. La configuration des textes dans `legalDocuments/current` reste gérée par la procédure existante : les exemples provisoires ne sont pas publiés automatiquement.

Désactiver une référence bloque les nouvelles soumissions utilisant ce choix, sans suspendre les professionnels déjà approuvés. L'administrateur peut examiner les dossiers déjà soumis à partir de leurs données historiques.

## Autorisations

`updateProfessionalCatalog` (Functions v2, europe-west1, codebase auth) vérifie le claim `admin: true`, puis le rôle actuel et l'état du compte dans Firebase Authentication. Chaque modification inclut `expectedVersion`, comparée dans une transaction Firestore. Un conflit demande de relire les données, sans écrasement silencieux. Aucune attribution de rôle dans les écrans.

Les règles Firebase existantes conviennent : lecture publique du référentiel, écriture client interdite même pour un administrateur. Les modifications passent exclusivement par la fonction. Les justificatifs restent privés. Les propositions demeurent interdites par les règles ; la publication de propositions et les formulaires de demandes clients ne sont pas encore implémentés dans ce dépôt. Les futurs formulaires clients doivent réutiliser ce référentiel et la même validation serveur, pas dupliquer les catégories.

L'interface suit la maquette : navigation latérale verte, tableau desktop des dossiers, fiches et formulaires de catalogue, arborescence géographique. Sur petit écran, le menu s'ouvre dans un tiroir et les dossiers deviennent des cartes. Les liens Utilisateurs/Paramètres de la maquette ne sont pas ajoutés car ces fonctions ne sont pas demandées.

## Tests locaux

Depuis la racine du dépôt :

```powershell
npm --prefix functions test
npm --prefix functions run check
flutter analyze lib test
flutter test
cd admin
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run
cd ..
```

Pour tester réellement les callables avec Auth, Firestore et Storage locaux :

```powershell
node functions/test-support/prepare-emulators.cjs
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '90'
firebase emulators:exec --config .firebase-integration.json --project demo-foundi --only auth,firestore,storage,functions "npm --prefix functions run test:emulated"
Remove-Item Env:FUNCTIONS_DISCOVERY_TIMEOUT
```

La préparation choisit des ports libres et crée uniquement `.firebase-integration.json` et, s'il manque, `functions/.env.demo-foundi` avec un SMTP factice. Ces fichiers locaux sont ignorés par Git. Le test requiert les variables des émulateurs et n'est pas exécuté en production. Les comptes de test sont créés directement avec e-mail vérifié dans l'émulateur Auth ; le parcours OTP est testé séparément dans les tests existants. Le test utilise les SDK clients et les véritables callables pour créer les références, enregistrer le dossier, téléverser une pièce, soumettre, demander une correction, resoumettre et approuver. Les accès non autorisés, pièces manquantes, références désactivées et écritures de propositions contournées sont également contrôlés. Ce test ne pilote pas les interfaces graphiques ; celles-ci sont couvertes par les tests Flutter.

Pour une vérification manuelle, `firebase.emulators.json` fournit des ports fixes distincts de la configuration normale : Auth 9339, Firestore 8239, Functions 5139, Storage 9439.

```powershell
firebase emulators:start --config firebase.emulators.json --project demo-foundi --only auth,firestore,storage,functions
```

Lancer l'admin depuis `admin/` :

```powershell
flutter run -d chrome --dart-define=USE_EMULATORS=true --dart-define=FIREBASE_AUTH_EMULATOR_PORT=9339 --dart-define=FIRESTORE_EMULATOR_PORT=8239 --dart-define=FUNCTIONS_EMULATOR_PORT=5139
```

Lancer le mobile avec les mêmes ports et `--dart-define=USE_FIREBASE_EMULATORS=true`. L'hôte Android par défaut est `10.0.2.2` ; pour un appareil physique, définir `FIREBASE_EMULATOR_HOST` vers l'adresse locale de la machine. En mode émulateur, les deux applications utilisent `demo-foundi` par défaut, configurable via `FIREBASE_EMULATOR_PROJECT`.

## Déploiement à valider

Aucun déploiement ni modification du référentiel distant n'est effectué. Après validation, déployer la fonction de catalogue et les fonctions professionnelles actualisées dans le projet existant, puis l'admin :

```powershell
firebase deploy --project foundi-7c837 --only functions:auth:updateProfessionalCatalog,functions:auth:saveProfessionalActivity,functions:auth:submitProfessionalProfile,functions:auth:uploadProfessionalDocument,functions:auth:readProfessionalDocument,functions:auth:startProfessionalProfile,functions:auth:reviewProfessionalProfile,functions:auth:checkProfessionalAccess
firebase deploy --project foundi-7c837 --only hosting:admin
```

Compiler l'admin avant déploiement et conserver l'association Hosting décrite dans `admin/README.md`. Distribuer aussi le mobile actualisé pour le suivi temps réel et les zones hiérarchiques. Les règles Firestore/Storage n'ont pas besoin d'être assouplies. Ne pas republier le fichier exemple de catalogue vide par-dessus un référentiel désormais géré dans l'admin.

## Validation exécutée

- 42 tests unitaires Node : réussis.
- 20 tests Flutter mobile : réussis.
- 4 tests Flutter Admin : réussis.
- 9 tests de règles Firestore/Storage sur émulateurs : réussis, aucun ignoré.
- 1 scénario de bout en bout via les véritables callables sur Auth/Firestore/Storage/Functions locaux : réussi (création du référentiel, dossier incomplet, catégorie désactivée, justificatif privé, soumission, accès non administrateur refusé, correction, resoumission, approbation, audit et droits d'accès).
- Analyses Flutter mobile et Admin : aucune anomalie.
- `flutter build web --release --no-wasm-dry-run` : réussi. Avertissement de police Cupertino déjà présent ; l'interface utilise Material Icons.

Le test de refus d'accès aux documents a révélé un défaut du gestionnaire d'erreurs partagé : une `HttpsError` était remplacée par une erreur interne. Le gestionnaire préserve maintenant le code d'autorisation d'origine ; l'accès restait bloqué avant et après la correction.

Aucun catalogue distant, compte réel, rôle réel ou déploiement de production n'a été modifié pendant cette implémentation.
