# Authentification Foundi V3

La connexion e-mail/mot de passe, Google, la vérification numérique de l’e-mail et la récupération du mot de passe restent communes. Les comptes historiques conservent leur UID et leurs données. Le champ historique `profession` est conservé en base pour compatibilité, mais retiré des formulaires clients. Le téléphone est facultatif.

## Parcours

- Inscription client : choix → compte → vérification e-mail si nécessaire → compte client.
- Inscription professionnelle : choix → compte et vérification → activité → justificatifs → `pending` → décision administrative.
- Google respecte le choix initial. Une première connexion Google depuis la connexion commune demande confirmation et choix du parcours.
- Un compte client peut sélectionner « Devenir professionnel » sans créer un autre utilisateur Firebase.
- Une reconnexion retrouve le brouillon et son étape. L’activité est sauvegardée après 700 ms d’inactivité, lors du passage en arrière-plan et avec l’action explicite de sauvegarde. Une fermeture forcée avant la fin d’une synchronisation ne garantit pas la sauvegarde des derniers caractères ; les échecs réseau restent affichés et empêchent la sortie explicite sans sauvegarde.
- Le dossier conserve ses fichiers lors des modifications et d’un remplacement qui échoue. Le serveur recalcule les pièces requises avant soumission.
- `pending`, `rejected`, `suspended`, `draft` et `none` n’accordent aucun droit professionnel. L’écran de mode ne constitue jamais une autorisation.
- Une décision est visible en direct dans l’application ouverte et à la prochaine connexion ; une notification privée est aussi enregistrée sous `users/{uid}/notifications/professionalDecision`. Aucune notification push hors application n’est encore configurée.

## Références et textes légaux

Les références professionnelles réelles restent à fournir. Aucun secteur ni document réglementaire n’est inventé dans la configuration de production. Les exemples de référence dans `config/` sont volontairement désactivés.

Les CGU et la politique de confidentialité provisoires de la préversion ont été rédigées à la demande de Denzel KOUAME, avec l’adresse de contact `kouamdenzel09@gmail.com`. Leur configuration est `config/legal-documents.json`, version `2026-10-27-provisoire-1`. Les sources lisibles et les points à compléter avant le lancement public sont dans `docs/legal/`. La future administration pourra remplacer les textes avec une nouvelle version sans modifier silencieusement les acceptations existantes.

`referenceData/professionalOnboarding` :

```json
{
  "enabled": true,
  "version": "VERSION_VALIDEE",
  "categories": [{
    "id": "ID_SECTEUR",
    "label": "LIBELLE_VALIDE",
    "specialties": [{"id": "ID_SPECIALITE", "label": "LIBELLE_VALIDE"}],
    "requirements": {"independent": ["ID_PIECE_METIER"], "company": ["ID_PIECE_METIER"]}
  }],
  "zones": [{"id": "ID_ZONE", "label": "LIBELLE_VALIDE"}],
  "documentTypes": [
    {"id": "identity", "label": "Pièce d’identité"},
    {"id": "ID_PIECE_METIER", "label": "LIBELLE_VALIDE"}
  ]
}
```

La pièce `identity` est toujours obligatoire. Chaque catégorie doit définir explicitement les exigences pour les deux types ; un tableau vide signifie qu’aucune pièce métier supplémentaire n’est nécessaire. Les identifiants sont stables et uniques ; `active: false` retire une référence des sélections. Les spécialités sont liées aux catégories choisies. Les justificatifs sont l’union des exigences des catégories sélectionnées. Sans configuration complète, le brouillon textuel reste enregistrable et la soumission est refusée côté serveur.

`legalDocuments/current` contient `published`, `version`, `terms` et `privacy` (textes complets). En l’absence de textes publiés, l’inscription reste disponible et aucune acceptation fictive n’est enregistrée. Une fois les textes publiés, l’inscription demande la case d’acceptation et enregistre leur version avec un horodatage serveur. Les comptes déjà créés les acceptent dans « CGU et confidentialité » avant la soumission professionnelle. Cette dérogation de lancement devra être revue avant l’ouverture publique.

Pour valider un fichier administratif local puis le publier avec une identité de service autorisée (Application Default Credentials) :

```powershell
node functions/scripts/configure-onboarding.js --project foundi-7c837 --catalog config/professional-onboarding.example.json --legal config/legal-documents.example.json
# Après remplacement par les contenus validés, ajouter --apply pour publier.
```

Le script ne publie rien sans `--apply`. Les clients Flutter ne peuvent jamais écrire ces documents.

## Données et sécurité

- `users/{uid}` : informations communes, parcours initial, préférence d’affichage et consentement versionné. Seul le propriétaire modifie les champs ordinaires autorisés ; les champs administratifs sont protégés.
- `professionalProfiles/{uid}` : activité, statut, étape, révision et dates de traitement. Lecture du propriétaire uniquement, écritures via les fonctions backend.
- `professionalProfiles/{uid}/documents/{kind}` : métadonnées confidentielles. Les fichiers se trouvent dans `professionalDocuments/{uid}/{kind}/{uploadId}`.
- Les fichiers sont envoyés par une fonction callable authentifiée (5 Mo maximum, PDF/JPEG/PNG, signature binaire contrôlée). Le backend écrit dans Storage sans jeton public ni URL signée, avec un nom opaque. Les règles interdisent toute écriture directe et n’autorisent la lecture d’un fichier qu’à son propriétaire. La lecture administrative passe par le backend de confiance, jamais un accès public. Un contrôle antivirus et une politique de conservation/effacement devront être définis avant exploitation à grande échelle.
- La soumission vérifie l’activité, les références actives, le consentement, la certification, les métadonnées serveur et la présence/génération des objets Storage. Les éditions, envois de fichiers et transitions partagent une transaction sur le dossier ; un dossier soumis est figé.
- `reviewProfessionalProfile({uid, status})` exige le custom claim `professionalReviewer: true` dans le jeton et dans le compte Auth actuel de l’administrateur. Les transitions autorisées sont `pending → approved/rejected` et `approved → suspended`. La décision est auditée sous `professionalAudit/`. Aucun utilisateur ne peut s’attribuer ce claim dans Firestore.
- `checkProfessionalAccess` relit le statut serveur et l’état Auth actuel ; le mode mémorisé n’accorde aucun droit.
- Le dépôt ne contient encore aucun module de demandes/publication/propositions. Les règles refusent donc toute écriture directe de proposition. Lors de l’implémentation de cette fonctionnalité, sa transaction de publication devra relire le statut `approved` dans la même transaction que l’écriture et vérifier les autres règles métier. Ne pas utiliser uniquement un contrôle préalable d’interface ou `checkProfessionalAccess`.
- Les écrans `rejected` et `suspended` n’ont pas été inventés : ces comptes retrouvent leur espace client sans droits professionnels.

## Déploiement et vérifications

```powershell
flutter pub get
flutter analyze
flutter test
npm.cmd --prefix functions test
npm.cmd --prefix functions run check
firebase emulators:exec --only firestore,storage --project demo-foundi "npm.cmd --prefix functions run test:rules"
flutter build apk --debug --no-pub
firebase deploy --only "functions:auth,firestore:rules,storage" --project foundi-7c837
```

Le bucket Cloud Storage du projet doit exister et le compte de service des fonctions doit pouvoir y lire/écrire. Le déploiement des règles Storage peut demander l’activation de l’intégration des règles si Storage n’a pas encore été initialisé. Effectuer un redémarrage complet de Flutter après l’ajout du sélecteur natif de fichiers.

Le bucket `foundi-7c837.firebasestorage.app` a été initialisé en `EUROPE-WEST1`, dans la région du backend. Le compte de service des fonctions dispose du rôle `roles/storage.objectUser` sur ce bucket uniquement ; aucun accès IAM public n’a été ajouté. Les règles Storage autorisent le propriétaire à lire ses fichiers, et réservent les écritures au backend.

### Blocage lors de la création du dossier professionnel

Le message « Impossible d’enregistrer le dossier. Vérifie ta connexion puis réessaie » peut masquer une fonction callable absente. La seule mise à jour des fonctions e-mail ne déploie pas le parcours professionnel. Celui-ci utilise les six fonctions suivantes :

- `startProfessionalProfile` : création ou reprise du brouillon ;
- `saveProfessionalActivity` : sauvegarde de l’activité ;
- `uploadProfessionalDocument` : envoi privé des pièces ;
- `submitProfessionalProfile` : contrôle puis soumission du dossier ;
- `reviewProfessionalProfile` : décision administrative autorisée ;
- `checkProfessionalAccess` : contrôle des droits côté serveur.

Pour une livraison complète de la V3, déployer ensemble `functions:auth`, `firestore:rules` et `storage`, comme indiqué ci-dessus. Un déploiement partiel doit tenir compte de toutes les fonctions appelées par le parcours essayé.

Après mise à jour du backend, un compte déjà créé peut sélectionner « Réessayer » ou « Devenir professionnel ». La création du brouillon ne nécessite pas le catalogue de référence. Tant que les catégories, zones et exigences documentaires ne sont pas configurées, les informations textuelles du brouillon restent enregistrables et la poursuite vers la soumission est bloquée volontairement.

### Blocage à l’envoi du code d’inscription

Le message « Termine les informations de ton inscription ou actualise ton compte » peut provenir d’une ancienne version serveur qui exige encore une profession ou un téléphone. Déployer uniquement le client Flutter et les règles Firestore ne met pas à jour cette validation. Les fonctions V3 acceptent un profil sans profession, ainsi qu’un téléphone vide ou absent ; elles vérifient toujours le nom, la confirmation d’inscription, la session authentifiée et l’état de vérification de l’e-mail. Un téléphone renseigné doit conserver un format international valide.

Pour mettre à jour ces deux fonctions sans redéployer les autres :

```powershell
firebase deploy --only "functions:auth:requestEmailCode,functions:auth:verifyEmailCode" --project foundi-7c837 --non-interactive
```

Si l’analyse locale échoue avec « Cannot determine backend specification. Timeout after 10000 », augmenter le délai de découverte pour cette session PowerShell avant de relancer la même commande :

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
```

Ce réglage concerne l’analyse locale du déploiement ; il ne modifie pas la durée de validité du code de vérification.

Une fois le serveur mis à jour, le compte déjà créé peut demander son code depuis l’écran de vérification. Il n’est pas nécessaire de recréer le compte ni de réinstaller l’application pour cette correction serveur.

Les tests utilisent uniquement des références explicitement fictives. Pour générer les captures des neuf écrans dans `.dart_tool/v3-preview/` sur Windows :

```powershell
flutter test --dart-define=V3_CAPTURE=true test/widget_test.dart
```

Ces captures utilisent des repositories simulés : elles vérifient l’interface et la navigation ; les tests Node vérifient les transitions et les tests émulateurs vérifient les permissions Firebase. Un essai sur appareil avec le bucket et les références validées reste nécessaire pour le transport réel des justificatifs.
