# Foundi V9.2 — sécurisation des publications

V9.2 validée puis déployée le 5 novembre 2026 avec l'accord de l'utilisateur. Le périmètre fonctionnel est limité à `publishRequest` et à son retour d'erreur Flutter.

## Diagnostic et changements

`createRequestService.publish` vérifiait l'identité et `account.disabled`, mais autorisait un compte non vérifié. La fixture unitaire positive utilisait explicitement `emailVerified:false`. Aucun quota de création n'existait. Le formulaire Flutter conservait déjà ses contrôleurs, l'étape de prévisualisation et son identifiant `late final` après une erreur ; ce comportement est conservé.

La publication consulte désormais `auth.getUser(uid)` et exige `emailVerified === true` sur un compte actif. Un booléen du payload ou `registrationConfirmed` ne constitue pas une preuve. Le refus de vérification utilise `failed-precondition` et « Vérifie ton adresse e-mail avant de publier une demande. ». La gestion des demandes existantes n'a pas été modifiée : les droits antérieurs s'appliquent et un propriétaire actif non vérifié peut toujours modifier, clôturer ou supprimer sa demande.

Les constantes sont centralisées dans `REQUEST_PUBLICATION_LIMITS` : **60 secondes minimum**, **5 créations sur 24 heures glissantes**, **20 créations sur 7 jours glissants**. Les messages serveur suivent les valeurs des constantes. Un refus de quota utilise `resource-exhausted`.

## Compteur et transaction

Un seul document serveur par UID :

```text
requestPublicationLimits/{uid}
  schemaVersion: 92
  createdAtMs: [horodatages serveur des créations, au plus 20]
```

La transaction :

1. lit d'abord `userRequests/{uid}/items/{requestId}` ; si le miroir existe, renvoie son état enregistré sans lire ni modifier le quota, y compris après réponse perdue, changement des références ou suppression logique ;
2. pour une création nouvelle, valide le contenu, l'occupation de l'identifiant et les références actives ;
3. lit le quota du même UID, prend l'horloge serveur injectable et écarte les dates vieilles d'au moins sept jours ;
4. contrôle l'intervalle, puis les fenêtres de 24 heures et sept jours ;
5. écrit atomiquement la projection publique, le miroir privé, l'ownership et le quota.

Toutes les lectures précèdent les écritures. Une transaction annulée ne conserve ni demande, ni ownership, ni consommation. Deux IDs distincts du même UID partagent le même document de quota et la protection transactionnelle Firestore ; un conflit relit l'état à jour. Deux UID disposent de quotas indépendants, sans dépendance au mode client/pro.

À exactement 60 secondes, la contrainte d'intervalle expire. Une date égale à la borne basse d'une fenêtre de 24 heures ou sept jours en sort : les fenêtres sont glissantes, pas des jours calendaires. L'élagage n'est persisté qu'à la prochaine création réussie. Les réessais ne réécrivent même pas le compteur. Un compteur serveur mal formé provoque un refus, sans réinitialisation permissive.

Les créations invalides, références désactivées, comptes anonymes/désactivés/non vérifiés, collisions d'identifiant et rejets de quota ne consomment rien. Modifier, clôturer et supprimer ne consomment rien et ne remboursent pas les créations passées. Le miroir d'une demande supprimée demeure idempotent : son ID ne recrée pas une demande neuve.

Le document est explicitement interdit en lecture, liste, création, modification et suppression via le SDK client, y compris au propriétaire et à un client disposant d'un claim admin. Aucune règle existante n'est élargie.

## Flutter et brouillons

Le repository affiche pour `resource-exhausted` : « Tu as atteint la limite de publication. Réessaie plus tard. ». Le refus d'e-mail affiche le message du backend et rappelle de terminer la vérification Foundi avec le code reçu par e-mail. Le parcours existant `VerificationScreen` / « Une dernière étape » reste utilisé ; aucun nouveau système OTP n'est créé.

Les autres erreurs `failed-precondition`, notamment les références indisponibles, gardent leur message propre. Aucun délai restant artificiel n'est calculé depuis une erreur réseau. Les contrôles principaux restent côté serveur.

Le formulaire ne navigue pas automatiquement, ne vide pas ses champs et ne remplace pas son ID après un refus. Le test de widget traverse les deux rejets, vérifie titre/description/budget/références, change d'onglet, puis réussit avec trois payloads identiques et le même ID. Cette conservation concerne le formulaire existant dans la session ; aucune nouvelle persistance après arrêt complet de l'application n'est ajoutée.

## Coût et limites

Par création valide : **une lecture et une écriture Firestore supplémentaires** pour le document de quota, hors éventuelles reprises transactionnelles. La transaction passe ainsi de trois à quatre lectures et de trois à quatre écritures. Le lookup Firebase Auth existait déjà. Un retry d'un miroir existant lit uniquement ce miroir dans la transaction, sans opération sur le quota. Le document conserve au plus 20 dates, soit un volume borné de quelques centaines d'octets par UID.

Aucun service, fournisseur, tâche planifiée, index ou abonnement supplémentaire n'est introduit. Les composants Firebase existants restent utilisés. Aucun historique de production n'est migré : le document est initialisé lors de la première nouvelle création sous V9.2 ; les publications antérieures ne sont pas rétrocomptées. Les IDs existants restent des retries sans consommation.

La protection est par UID : plusieurs comptes vérifiés peuvent chacun utiliser leur quota. Elle limite les créations, pas le nombre d'invocations rejetées de la fonction. Aucun contrôle par IP, nouveau CAPTCHA ou autre mécanisme hors périmètre n'est ajouté.

## Fichiers modifiés

- `functions/src/request-service.js` : vérification Auth stricte, constantes, historique borné et quota dans la transaction de création ; `manage` inchangé.
- `firestore.rules` : refus explicite de tout accès client au quota.
- `lib/features/requests/data/firebase_request_repository.dart` : messages des deux refus, sans changement du formulaire.
- `functions/test/request-service.test.js` : fixture vérifiée, horloge pilotable, bornes, idempotence, atomicité et absence de consommation sur rejet/gestion.
- `functions/rules-test/requests.test.cjs` : quota inaccessible à tous les SDK clients.
- `functions/integration-test/publication-limits-flow.test.cjs` : vrai callable et état Auth actuel ; transactions Firestore concurrentes ; fenêtres et élagage sur horloge injectée.
- `functions/integration-test/conversation-flow.test.cjs` : l'horloge du scénario créant une deuxième demande est avancée de 60 secondes, sans contourner le quota ni modifier les conversations.
- `test/publication_security_v92_test.dart` : vrai mapping du repository via doubles SDK et maintien du brouillon/ID dans les widgets.
- `functions/package.json`, `functions/scripts/test-v82-emulators.cjs`, `firebase.v92.emulators.json` : lancement reproductible de la suite locale complète sur les ports V9.2 1520–1526 et contrôle de syntaxe du nouveau test. Le mode V9.2 utilise la découverte de manifeste par fichier, prise en charge par la CLI/SDK installés, pour éviter un serveur de découverte localhost instable sous Windows. Les modes existants et la configuration de production sont conservés.
- `functions/scripts/verify-publication-v92.cjs` : contrôle de production en lecture seule, comparaison des révisions/règles/index et vérification du refus d'un appel anonyme, sans créer de demande.
- `pubspec.yaml` : version Android portée à `1.0.3+4` pour la livraison V9.2.

Les notifications, propositions, médias, antivirus et l'outbox de messages V9.1 ne sont pas modifiés.

## Validation

| Vérification exécutée | Résultat |
| --- | --- |
| `npm --prefix functions test` | **100/100**, aucun ignoré |
| Service de publication ciblé | **15/15**, dont les bornes exactes et les annulations transactionnelles |
| `npm --prefix functions run check` | réussi, nouveau test d'intégration inclus |
| `flutter test --no-pub` | **104/104** |
| Mapping et brouillon Flutter ciblés | **2/2** |
| `flutter analyze --no-pub` | **No issues found** |
| `npm --prefix functions run test:v92:emulators` — Rules | **28/28**, aucun ignoré |
| Même commande — intégrations Firebase | **13/13**, aucun ignoré, sortie globale **0** |

La couverture vérifie : anonyme/désactivé/non vérifié ; tentative de falsifier la vérification dans le profil et le payload ; compte vérifié ; quota par UID ; double clic/réponse perdue/ID existant même avec catalogue désactivé ; 59 999/60 000 ms ; 24 heures et sept jours à une milliseconde de l'expiration puis à expiration exacte ; plafonds 5 et 20 ; élagage ; créations concurrentes à différents IDs sur de vraies transactions Firestore ; références/payload invalides ; rollback ; édition/clôture/suppression sans consommation ni remboursement ; SDK clients anonymes/propriétaire/tiers/admin refusés sur le quota.

Le test du vrai callable vérifie aussi qu'une modification d'`emailVerified` dans Auth est prise en compte sans rafraîchir le jeton client : l'état actuel du serveur fait autorité. Il refuse la nouvelle création après révocation de la vérification et laisse fonctionner la gestion autorisée de la demande existante.

La suite complète passe les scénarios Explorer, propositions, négociation V8.1, médias/antivirus V8.2, notifications/badges/confidentialité V9/V9.1 et affichage optimiste du chat. Aucun code de ces fonctionnalités n'est modifié. Le benchmark de messagerie existant reste à 16 ms d'affichage local en temps virtuel ; ce n'est pas une mesure sur téléphone.

Les premiers essais d'émulateurs ont échoué à cause d'un port V9.1 occupé puis de la découverte HTTP locale des fonctions. Ils ne sont pas comptés comme des succès. Le passage réussi utilise les ports V9.2 et la découverte par fichier de la CLI/SDK existants ; les fonctions ont été chargées depuis le vrai code. Les avertissements Java pendant l'arrêt du runtime Rules apparaissent après les résultats réussis et la sortie 0. Le driver a restauré l'environnement local et supprimé ses secrets factices/backup temporaire.

Journaux locaux sous `.dart_tool` : `v92-publication-backend.log`, `v92-publication-check-verified.log`, `v92-publication-flutter-all.log`, `v92-publication-flutter-verified.log`, `v92-publication-analyze-final.log`, `v92-publication-emulators-verified.log`. Les tests utilisent uniquement des projets `demo-*`, sans données ni configuration de production.

Commandes reproductibles depuis la racine :

```powershell
npm --prefix functions test
npm --prefix functions run check
npm --prefix functions run test:v92:emulators
flutter test --no-pub
flutter analyze --no-pub
```

## Livraison autorisée du 5 novembre 2026

Déploiement sur `foundi-7c837`, région `europe-west1`, limité aux règles Firestore et à `functions:auth:publishRequest`. Les deux commandes se sont terminées avec succès. Le pré-déploiement a également repassé les **100 tests backend** et les contrôles de syntaxe.

Le contrôle après déploiement confirme :

- `publishRequest` est `ACTIVE`, runtime Node.js 22, révision `publishrequest-00003-yek` ;
- les 39 autres fonctions conservent leur révision, sans ajout ni suppression de fonction ;
- les règles publiées correspondent au fichier validé, et les 22 index restent inchangés et `READY` ;
- un appel anonyme est refusé avec HTTP **401 / UNAUTHENTICATED**.

Aucune demande ni aucun compte de test n'a été créé en production. Aucun historique n'a été migré. Les scénarios de quotas, de concurrence et de vérification d'e-mail ont été exécutés dans les émulateurs.

APK préparé : `build/app/outputs/flutter-apk/app-debug.apk`, version **1.0.3 (4)**, application **Foundi**, package `com.example.foundi`. Compilation debug réussie en 313 secondes ; les ressources des logos Foundi et Google incluses correspondent aux fichiers du projet. Taille : **166 229 439 octets**. SHA-256 :

```text
d346c9354792bd2004f6b1c4fa7b73446d2335da200b183b1f471afbbef33f57
```

Cet APK est destiné à l'installation et à la validation manuelles ; il n'a pas été installé ni testé sur téléphone pendant cette livraison. Aucun package de publication Play Store n'est produit.

Les preuves locales sont conservées sous `.dart_tool` : `v92-deployment-before.json`, `v92-deployment-after.json`, `v92-rules-deploy.log`, `v92-function-deploy.log`, `v92-apk-build.log` et `v92-apk-record.json`. Ces fichiers et l'APK ne sont pas versionnés. Les modifications source, tests, version et présent compte rendu constituent le commit V9.2 sur la branche `codex/foundi-v9-notifications`.
