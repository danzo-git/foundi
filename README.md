# Foundi

Application Flutter de mise en relation, avec Firebase Authentication et Firestore. Branche de travail : `codex/authentification-email-google`.

## Parcours d’authentification

### Inscription classique

1. Nom complet, téléphone international et profession / activité.
2. Adresse e-mail, mot de passe et confirmation. Le formulaire demande au moins 12 caractères.
3. Vérification de l’adresse par un code de six chiffres envoyé via SMTP.

Firebase crée le compte e-mail/mot de passe. Tant que le profil obligatoire ou la vérification manque, l’application reprend cette étape au lieu d’ouvrir Mon compte. Le téléphone est enregistré sans SMS et n’est pas déclaré vérifié. Une profession renseignée ne donne aucun droit de professionnel vérifié.

### Connexion classique

L’e-mail et le mot de passe suffisent pour un compte vérifié. Une inscription inachevée reprend le profil ou la vérification. Le lien Mot de passe oublié envoie un lien de réinitialisation via Firebase Authentication, avec une confirmation générique pour ne pas révéler l’existence d’une adresse.

### Google

Un compte existant ouvre directement Mon compte. Depuis l’écran d’inscription, le compte Google peut être créé sans remplir le profil classique. Depuis la connexion, un nouveau compte Google demande une confirmation de création. Une confirmation en attente est conservée si l’utilisateur quitte l’application.

Le nom disponible chez Google est prérempli. Téléphone et profession sont facultatifs au départ et peuvent être ajoutés, même partiellement, dans Mon compte → Informations personnelles. Une invitation à compléter le profil reste visible tant qu’il est incomplet.

### Anciens comptes par code

L’option Compte créé avec un code ? Définir mon mot de passe envoie un lien pour définir un mot de passe sur le compte existant, avec le même UID. Les sessions anciennes sans mot de passe ni Google sont dirigées vers cette étape. Il n’est pas nécessaire de recréer le compte.

## Serveur de vérification

Les fonctions `requestEmailCode` et `verifyEmailCode` utilisent la région `europe-west1`. Elles exigent maintenant une session Firebase authentifiée et ne vérifient que l’adresse du compte de cette session. Elles ne prennent plus une adresse libre et ne créent plus de compte ni de jeton de connexion personnalisé. Elles ne retirent jamais le mot de passe.

Le code est lié à l’UID, à l’adresse et au protocole de vérification. Les anciens codes du parcours sans mot de passe sont rejetés. Les mots de passe passent exclusivement par le SDK Firebase Auth et ne sont stockés ni dans Firestore ni dans les fonctions.

Limites côté serveur : dix minutes de validité, un usage, cinq essais, soixante secondes avant renvoi, cinq envois par adresse et vingt par IP sur quinze minutes. Chaque renvoi invalide le code précédent. Le code est conservé sous forme d’empreinte HMAC.

`changeRegistrationEmail` permet de corriger une adresse uniquement sur un compte classique non vérifié, après confirmation récente du mot de passe. Les anciens codes ne peuvent pas vérifier la nouvelle adresse.

## Profils Firestore

Les documents `users/{uid}` contiennent `fullName`, `phone`, `profession`, `registrationConfirmed`, `createdAt` et `updatedAt`. Chaque utilisateur peut uniquement lire et modifier son propre document. Les écritures sont limitées aux champs de profil : aucun rôle ou statut professionnel ne peut être ajouté ou modifié par le client. Les collections techniques de codes restent totalement interdites aux clients.

Les futurs accès métier devront exiger l’e-mail vérifié dans leurs propres règles. L’accès à son brouillon de profil reste permis avant vérification pour terminer l’inscription.

## Installation

Flutter avec Dart 3.12 et Node.js 22 sont nécessaires.

```powershell
flutter pub get
npm.cmd --prefix functions ci
```

La configuration FlutterFire cible `foundi-7c837`. Les fichiers de configuration clients ne sont pas des clés privées de compte de service. Les secrets SMTP doivent rester dans Secret Manager.

## Configuration Firebase et déploiement

1. Activer E-mail/Mot de passe dans Firebase Authentication. Configurer une politique de mot de passe adaptée côté Firebase ; le formulaire impose au moins 12 caractères. Conserver Google activé.
2. Disposer de Cloud Firestore et du forfait Blaze pour les fonctions.
3. Renseigner `functions/.env.foundi-7c837` à partir de `.env.example` avec `SMTP_HOST`, `SMTP_PORT`, `SMTP_FROM`, `SMTP_REQUIRE_TLS=true`.
4. Enregistrer les secrets, si ce n’est pas déjà fait :

```powershell
firebase functions:secrets:set SMTP_USER --project foundi-7c837
firebase functions:secrets:set SMTP_PASSWORD --project foundi-7c837
firebase functions:secrets:set OTP_HMAC_KEY --project foundi-7c837
```

`OTP_HMAC_KEY` doit contenir au moins 32 caractères aléatoires. Garder la clé déjà utilisée pour le projet. Les e-mails de récupération du mot de passe sont envoyés par Firebase, tandis que SMTP sert aux codes de vérification. Leurs modèles sont distincts.

5. Vérifier puis déployer ensemble les fonctions et les nouvelles règles avant de tester cette version de l’application :

```powershell
npm.cmd --prefix functions test
npm.cmd --prefix functions run check
flutter analyze
flutter test
firebase deploy --only "functions:auth,firestore:rules" --project foundi-7c837
flutter run
```

La version serveur précédente utilisait un autre protocole sans mot de passe : ne pas tester le nouveau client avec cet ancien serveur. Les nouvelles fonctions n’utilisent plus la signature de jetons personnalisés. Aucun changement IAM n’est nécessaire pour ce parcours.

Configurer un TTL sur `deleteAfter` des collections `authEmailChallenges` et `authEmailRateLimits` permet leur nettoyage après 24 heures. La sécurité ne dépend pas de ce nettoyage : les vérifications d’expiration sont explicites.

## Google sur les plateformes

Android utilise `android/app/google-services.json` et les empreintes SHA-1/SHA-256 des certificats de debug et de publication enregistrées dans Firebase. Pour le Web, le domaine doit être autorisé dans Firebase Auth.

Sur iOS et macOS, ajouter la configuration Google à la cible et le schéma `REVERSED_CLIENT_ID` selon la documentation du plugin. Le premier pilote reste Android. Google natif n’est pas proposé sur Windows ou Linux.

## Émulateurs

Les ports locaux sont Auth 9099, Firestore 8080 et Functions 5001. Les paramètres SMTP locaux vont dans `functions/.env.local`, les secrets de développement dans `functions/.secret.local`, jamais versionné.

```powershell
firebase emulators:start --only auth,firestore,functions --project foundi-7c837
flutter run --dart-define=USE_FIREBASE_EMULATORS=true
```

Android Emulator utilise `10.0.2.2`, le Web et les autres plateformes `localhost`. Un téléphone physique nécessite `--dart-define=FIREBASE_EMULATOR_HOST=ADRESSE_LAN_DU_PC` et des émulateurs accessibles depuis ce réseau de développement. Sans l’option explicite, l’application utilise les services réels.

## Vérification manuelle

- Créer un compte classique, vérifier les champs obligatoires et les mots de passe, puis valider le code.
- Quitter avant la validation puis se reconnecter : reprendre la vérification, sans accéder au compte.
- Essayer un mauvais code, un code expiré et le renvoi ; corriger aussi une adresse erronée.
- Se déconnecter et revenir avec le mot de passe, sans nouveau code.
- Tester le lien de récupération et la définition du mot de passe d’un ancien compte, en conservant son UID.
- Essayer un nouveau Google depuis Connexion (confirmation), puis depuis Inscription (accès direct).
- Compléter ou modifier un profil Google dans Informations personnelles et vérifier sa conservation après reconnexion.

Les tests Node couvrent la propriété des codes, le maintien du mot de passe, les anciens protocoles, les expirations, les quotas et les accès concurrents. Les tests Flutter utilisent un dépôt simulé pour vérifier les parcours et ne remplacent pas ces essais avec les services réels.
