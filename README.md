# Foundi

Application Flutter de mise en relation, avec Firebase Authentication, Firestore, Cloud Storage et Cloud Functions. Branche de travail : `codex/authentification-email-google`.

## Authentification V3

Une seule application et un seul UID Firebase donnent accès au compte client et, après approbation administrative, au profil professionnel facultatif.

- Client : choix du parcours, nom, e-mail, mot de passe (12 caractères minimum), téléphone international facultatif et consentement lorsque les textes sont publiés. Vérification numérique de l’e-mail avant l’accès au compte.
- Professionnel : même compte, puis activité, justificatifs confidentiels et soumission d’un dossier. Les brouillons sont sauvegardés et reprenables. Le statut `pending` ne donne aucun droit professionnel.
- Google : connexion commune et conservation du parcours sélectionné. Un nouveau compte depuis la connexion demande confirmation. Le téléphone peut être complété plus tard dans les paramètres.
- Connexion classique : e-mail et mot de passe ; une inscription inachevée reprend la vérification ou le profil nécessaire.
- Mot de passe oublié : lien Firebase avec confirmation générique. Les anciens comptes par code définissent un mot de passe sur le même UID.

Les écrans, le modèle de données, les règles, les fonctions administratives, les références et la validation sont détaillés dans [docs/authentification-v3.md](docs/authentification-v3.md).

Les catégories, zones et exigences documentaires réelles restent à fournir. Les CGU et la confidentialité provisoires sont dans `docs/legal/` et leur configuration publiable dans `config/legal-documents.json`. La soumission professionnelle exige les références configurées et l’acceptation de la version publiée des textes.

## Installation

Le sprint V5 (FOUN-38, FOUN-39, FOUN-42) ajoute la publication, Mes demandes et Explorer sans compte. Le schéma public/privé, les adaptations Firebase, les tests locaux et les étapes de démonstration sont décrits dans [docs/demandes-v5.md](docs/demandes-v5.md). La livraison V5 nécessite un accord distinct avant tout déploiement Firebase.

Flutter avec Dart 3.12 et Node.js 22 sont nécessaires.

```powershell
flutter pub get
npm.cmd --prefix functions ci
```

La configuration FlutterFire cible `foundi-7c837`. Les fichiers clients ne sont pas des clés privées de compte de service. Les secrets SMTP restent dans Secret Manager.

## Configuration Firebase

1. Activer E-mail/Mot de passe dans Authentication (12 caractères minimum côté application) et conserver Google activé.
2. Initialiser Firestore, le bucket Cloud Storage et les fonctions avec le forfait Blaze. Le compte de service des fonctions doit disposer de l’accès au bucket.
3. Renseigner `functions/.env.foundi-7c837` à partir de `.env.example` : `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_REQUIRE_TLS=true`.
4. Enregistrer les secrets si nécessaire, en gardant les valeurs existantes :

```powershell
firebase functions:secrets:set SMTP_USER --project foundi-7c837
firebase functions:secrets:set SMTP_PASSWORD --project foundi-7c837
firebase functions:secrets:set OTP_HMAC_KEY --project foundi-7c837
```

`OTP_HMAC_KEY` contient au moins 32 caractères aléatoires. Le SMTP envoie les codes numériques ; les liens de récupération du mot de passe sont envoyés par Firebase.

## Vérification et déploiement

```powershell
flutter analyze
flutter test
npm.cmd --prefix functions test
npm.cmd --prefix functions run check
firebase emulators:exec --only firestore,storage --project demo-foundi "npm.cmd --prefix functions run test:rules"
flutter build apk --debug --no-pub
firebase deploy --only "functions:auth,firestore:rules,storage" --project foundi-7c837
flutter run
```

Déployer ensemble le backend et les règles avant d’essayer le client V3. Un redémarrage complet de Flutter est nécessaire après l’ajout du sélecteur natif de fichiers. Les tests émulateurs utilisent un projet de démonstration sans accès aux services de production et nécessitent Java 21 ou supérieur.

## Vérification e-mail

`requestEmailCode`, `verifyEmailCode` et `changeRegistrationEmail` sont en `europe-west1`. Les codes exigent une session authentifiée et vérifient uniquement l’adresse du compte courant. Ils ne créent aucun compte ni jeton de connexion, et ne retirent jamais le mot de passe. Les mots de passe passent exclusivement par Firebase Auth.

Limites serveur : 10 minutes, un usage, 5 essais, 60 secondes avant renvoi, 5 envois par adresse et 20 par IP sur 15 minutes. Un renvoi invalide le précédent. Seule une empreinte HMAC est conservée. Les anciens codes sans mot de passe sont refusés.

La correction d’adresse demande une authentification récente sur un compte classique non vérifié. Les codes de l’ancienne adresse ne peuvent pas vérifier la nouvelle.

Un TTL sur `deleteAfter` des collections `authEmailChallenges` et `authEmailRateLimits` permet leur nettoyage après 24 heures ; les contrôles d’expiration restent explicites.

## Google

Android utilise `android/app/google-services.json` et les empreintes SHA-1/SHA-256 des certificats enregistrées dans Firebase. Le domaine Web doit être autorisé dans Auth. Sur iOS/macOS, ajouter le schéma `REVERSED_CLIENT_ID` selon la configuration Google. Google natif n’est pas proposé sur Windows ou Linux.

## Émulateurs complets

Ports : Auth 9099, Firestore 8080, Functions 5001, Storage 9199. Les paramètres SMTP locaux vont dans `functions/.env.local`, les secrets de développement dans `functions/.secret.local`, jamais versionnés.

```powershell
firebase emulators:start --only auth,firestore,functions,storage --project foundi-7c837
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

Toujours démarrer Storage avec les fonctions pour les essais de justificatifs. Android Emulator utilise `10.0.2.2`, les autres plateformes `localhost`. Sur téléphone physique : `--dart-define=FIREBASE_EMULATOR_HOST=ADRESSE_LAN_DU_PC` et émulateurs accessibles depuis ce réseau de développement. Sans l’option explicite, l’application utilise les services réels.

## Foundi Admin et catalogue partagé

L'application Flutter Web distincte se trouve dans `admin/`. Les dossiers professionnels, catégories, spécialités, zones hiérarchiques et exigences documentaires utilisent le projet Firebase existant.

- [Lancer et préparer Foundi Admin](admin/README.md)
- [Catalogue partagé, validation et tests sur émulateurs](docs/catalogue-et-validation.md)

## Interface mobile V4

Navigation commune aux espaces Client et Professionnel, bouton Publier central, Compte épuré et Paramètres accessibles par l'engrenage. La bascule d'espace est locale et réservée aux professionnels approuvés. Les modules métier non développés affichent « Bientôt disponible ».

- [Périmètre, architecture de présentation et vérification V4](docs/ui-ux-v4.md)

Les déploiements Firebase et l'attribution de rôles restent des opérations explicites ; un push Git ne les déclenche pas dans ce dépôt.
