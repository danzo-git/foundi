# Foundi Admin

Application Flutter Web séparée, connectée au projet existant `foundi-7c837`. Aucun déploiement ni changement de rôle n'est effectué par l'installation.

## Architecture constatée et extensions

- Mobile : `lib/features/professional`, dépôt Firebase, observation temps réel du dossier.
- `professionalProfiles/{uid}` : `type`, `businessName`, `categoryIds`, `specialtyIds`, `zoneIds`, `description`, `onboardingStep`, `revision`, dates en millisecondes Unix.
- Statuts existants : `draft`, `pending`, `approved`, `rejected`, `suspended`. Ajout compatible : `needs_changes`. Mettre à jour le mobile avant d'utiliser ce statut. Les anciens clients traitent les statuts inconnus comme suspendus (accès fermé).
- `professionalProfiles/{uid}/documents/{kind}` : métadonnées privées et génération Storage ; objets `professionalDocuments/{uid}/{kind}/{uploadId}`.
- Références : `referenceData/professionalOnboarding`. Coordonnées : `users/{uid}`.
- Functions JavaScript v2 existantes en `europe-west1`, même codebase `auth`. Pas de backend supplémentaire.
- Décisions transactionnelles : motif obligatoire pour refus/correction, contrôle de révision, notification privée, audit immuable `professionalAudit`. `needs_changes` autorise la correction puis une nouvelle soumission.
- Le claim `admin: true` remplace `professionalReviewer` pour les décisions. Les anciens reviewers doivent être explicitement autorisés par un opérateur. Aucun compte n'est migré automatiquement.
- Documents : téléchargement authentifié via callable avec vérification du claim actuel dans Auth ; ni URL signée ni token public. Téléchargement en mémoire puis fichier local, image/PDF uniquement.
- Les propositions restent intégralement interdites côté Firestore. Le produit existant ne possède pas encore de fonction de publication de propositions. Sa future implémentation devra vérifier `approved` dans la transaction de publication ; `checkProfessionalAccess` seul ne suffit pas.

## Lancement

Depuis `admin/` :

```powershell
flutter pub get
flutter run -d chrome
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run
```

La configuration Web existante est réutilisée depuis `admin/lib/firebase_options.dart`. Une application Web Firebase dédiée peut être enregistrée ultérieurement dans **le même projet**, puis sa configuration remplacée dans ce fichier. Aucune clé Admin SDK dans le navigateur. La clé API Firebase Web est une configuration publique.

Pour les émulateurs, démarrer depuis la racine :

```powershell
firebase emulators:start --project demo-foundi --only auth,firestore,storage,functions
```

Puis lancer `flutter run -d chrome --dart-define=USE_EMULATORS=true` dans `admin/`. Utiliser uniquement des comptes/dossiers de test dans les émulateurs.

La recherche nom/UID et les filtres catégorie, zone et dates portent sur la page de 25 dossiers chargée ; l'interface le signale. Le filtre statut est serveur, avec index fourni. Les compteurs sont globaux. La pagination charge progressivement les pages précédentes ; prévoir une recherche serveur et des curseurs pour de gros volumes.

## Premier administrateur — procédure opérateur uniquement

Obtenir d'abord la confirmation du responsable pour un UID précis. Créer ou identifier un compte Auth actif avec e-mail vérifié. Utiliser des Application Default Credentials d'un opérateur IAM autorisé, jamais une clé embarquée ni un endpoint public d'attribution.

```powershell
cd functions
$env:CONFIRM_ADMIN_CHANGE = 'foundi-7c837:UID_EXACT:grant'
node scripts/admin-role.js foundi-7c837 UID_EXACT grant
Remove-Item Env:CONFIRM_ADMIN_CHANGE
```

Le script conserve les autres claims et révoque les refresh tokens. Se reconnecter. Pour retirer le rôle, remplacer `grant` par `revoke` aux deux endroits. Les décisions et lectures de pièces revérifient immédiatement le rôle actuel. Les lectures Firestore suivent la durée de vie du jeton ID ; le client le renouvelle toutes les cinq minutes. Aucun bouton d'inscription admin.

## Vérification backend

Depuis la racine :

```powershell
npm --prefix functions test
npm --prefix functions run check
firebase emulators:exec --project demo-foundi --only firestore,storage "npm --prefix functions run test:rules"
flutter analyze
flutter test
```

Les tests de règles sont ignorés sans émulateurs : un résultat ignoré n'est pas une validation des règles.

## Préparation Hosting et déploiement — après confirmation seulement

La cible `hosting:admin` pointe vers `admin/build/web` ; aucune cible de site n'a été attribuée. Choisir un ID Hosting disponible dans le projet existant et vérifier le plan de déploiement. Les commandes suivantes modifient la production, ne pas les exécuter sans autorisation :

```powershell
firebase hosting:sites:create ID_SITE_ADMIN --project foundi-7c837
firebase target:apply hosting admin ID_SITE_ADMIN --project foundi-7c837
cd admin
flutter build web --release --no-wasm-dry-run
cd ..
firebase deploy --project foundi-7c837 --only firestore:rules,firestore:indexes,storage
firebase deploy --project foundi-7c837 --only functions:auth:reviewProfessionalProfile,functions:auth:readProfessionalDocument,functions:auth:startProfessionalProfile,functions:auth:saveProfessionalActivity,functions:auth:uploadProfessionalDocument,functions:auth:submitProfessionalProfile
firebase deploy --project foundi-7c837 --only hosting:admin
```

Ajouter le domaine Hosting aux domaines autorisés de Firebase Authentication si nécessaire. Déployer la version mobile comprenant `needs_changes` avant la première demande de correction. Ne pas utiliser `firebase deploy` sans sélection de ressources. La configuration SMTP existante n'est pas modifiée.

## Résultats de validation

35 tests unitaires backend et 8 tests de règles Firestore/Storage sur émulateurs réussis. Test widget de connexion Admin réussi. Les 17 tests mobiles existants passent après remplacement de la hauteur intrinsèque du formulaire partagé par une colonne scrollable, corrigeant un débordement de 8 pixels. Aucun déploiement ni attribution de rôle effectué.


Analyse Flutter Admin et mobile : aucun avertissement. Test mobile ciblé de demande de corrections : réussi.

Compilation validée : flutter build web --release --no-wasm-dry-run ; sortie admin/build/web. Avertissement bénin de police Cupertino non fournie (l’interface utilise Material Icons).


## Gestion des catégories, spécialités et zones

Consulter [le guide du catalogue partagé](../docs/catalogue-et-validation.md) pour la configuration, la compatibilité, les émulateurs et le déploiement ciblé de la nouvelle fonction.
