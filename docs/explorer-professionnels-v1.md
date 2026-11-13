# Foundi V1 — Professionnels dans Explorer

## Périmètre et audit

Travail démarré depuis l’état local propre `1c145e70cf167376c8aecc65d3107059ab28efba`, sur la nouvelle branche `codex/foundi-explorer-professionnels-v1`. Le cahier des charges lu est `Foundi_Prompt_Codex_Volet_Professionnels_V1.md`, accompagné de la maquette validée.

L’existant fournissait déjà le profil public commun à Mon compte, les réalisations publiques, la consultation depuis les répondants/recommandations et le parcours de demande directe privée. Il manquait une lecture publique indépendante de tout contexte de proposition ou de demande. La recherche de recommandation existante, liée à une demande et à ses contrôles d’accès, n’a pas été détournée en annuaire.

Réutilisation : `FoundiPanel`, `FoundiUi`, logo officiel, `ProfessionalShowcaseScreen`, en-tête/sections/galerie partagés, `DirectRequestsScope`, `DirectProfessionalTarget`, `DirectRequestFormPage`, `RequestComposer`, catalogue administratif et validations serveur existantes. Les quatre onglets des espaces Client et Professionnel restent inchangés.

## Comportement livré

- Sélecteur Demandes / Professionnels à l’intérieur d’Explorer. La vue Demandes, Pour moi / Toutes, ses photos et actions sont conservées.
- Annuaire de professionnels approuvés, avec compte actif et adresse e-mail vérifiée. Recherche par nom, activité et libellés publics ; casse, accents et espaces normalisés côté serveur.
- Recherche différée de 400 ms, rejet des réponses périmées, filtres cumulables catégorie / spécialité dépendante / zone déclarée, remise à zéro et pagination serveur.
- Cartes avec nom commercial public, portrait réel ou initiales, statut vérifié confirmé, activité/références publiques, zones déclarées et jusqu’à trois réalisations réelles chargées à la demande. Aucune photo factice si la galerie est vide.
- Profil public existant ouvert par identifiant indépendant, sans lecture Firestore publique du dossier privé.
- Retour du profil conserve recherche, filtres et position de liste. Le retour Android depuis le volet Professionnels revient d’abord aux Demandes.
- Revalidation à l’ouverture du profil, avant la demande directe, au retour dans la liste, à la reprise de l’application et toutes les 30 secondes. La vérification périodique porte sur les cartes montées, au maximum 24. Une expiration ou une panne retire le badge et désactive l’action du profil ; un retrait d’approbation confirmé rend le profil indisponible et ferme sa photo agrandie éventuelle.
- Demande directe via le formulaire existant : destinataire fixé, nom du compte automatique, catégorie et spécialité verrouillées, zone / budget / photos / prévisualisation / reprise sur erreur conservés. Aucun nouvel envoi public ni ouverture automatique de conversation.

## Nouvelles lectures serveur

Quatre fonctions callable, région `europe-west1`, acceptent les lectures publiques anonymes et authentifiées. Tous les objets d’entrée rejettent les champs supplémentaires.

| Fonction | Entrée | Réponse autorisée |
| --- | --- | --- |
| `listPublicProfessionals` | `query` ≤ 80 caractères, `categoryId?`, `specialtyId?`, `zoneId?`, `cursor?` | `items` ≤ 12, curseur opaque ou null, validité 30 s |
| `readPublicProfessionalProfile` | `professionalId` | Projection `ProfessionalShowcase` publique et activité canonique pour le formulaire privé |
| `readPublicProfessionalMedia` | `professionalId`, `photoId?` | Sans photo : identifiants de portrait et de trois réalisations au plus. Avec photo : miniature JPEG réencodée ≤ 16 Kio |
| `checkPublicProfessionals` | `professionalIds`, distincts, ≤ 24 | Identifiants encore consultables, validité 30 s |

Une entrée de liste contient uniquement `professionalId`, `name`, `trade`, `categories`, `specialties`, `zones`, `portraitId`. Une projection de profil contient uniquement révision, nom, métier, présentation, zone publique, portrait/couverture/galerie publiques, identité de routage et activité destinée au formulaire. Les textes publics sont nettoyés ; les images doivent correspondre à leur empreinte SHA-256 et respecter les limites de taille déjà appliquées aux réalisations.

Les e-mails, téléphones privés, documents administratifs, justificatifs et propositions ne figurent dans aucune réponse. Les photos des demandes privées et de la messagerie ne sont jamais utilisées comme réalisations. Les règles `professionalProfiles` restent fermées ; les nouveaux curseurs et budgets sont également couverts par le refus par défaut. Aucun changement de `firestore.rules` ou de Storage.

### Pagination et coût borné

Le service parcourt les profils approuvés dans l’ordre de leur identifiant, par lots de 40, avec au plus 120 profils examinés par appel et 12 résultats retournés. Les critères sont appliqués côté serveur sur tout le parcours. Une page vide peut donc avoir une suite ; le client poursuit trois pages vides au plus par interaction puis propose « Continuer la recherche ». Il n’annonce aucun résultat absent avant épuisement du parcours.

Le curseur aléatoire de 256 bits reste dans `professionalDirectoryCursors`, lié à l’acteur de transport/authentification, aux critères et à la version du catalogue, avec expiration de dix minutes. Il ne révèle pas l’identifiant des profils exclus. La position stockée est celle du dernier profil réellement traité, y compris si les douze résultats sont atteints au milieu d’un lot. Les profils sélectionnés sont revérifiés avant retour.

Cette pagination est déterministe, mais ne représente pas un instantané transactionnel de tout l’annuaire : un profil nouvellement créé ou modifié avant la position parcourue apparaît lors d’une actualisation. Une modification du catalogue peut nécessiter de relancer la recherche. Le parcours est linéaire en V1 ; il n’y a ni index de recherche externe payant ni chargement de tous les dossiers sur le téléphone.

Les lectures de liste ne récupèrent que les champs publics utiles du dossier et `name`, `trade`, `portrait.id` du showcase ; aucune galerie base64 dans les résultats de recherche. Un appel maximal représente environ 270 lectures de documents, selon les résultats et les curseurs, plus les vérifications Auth. Les lectures d’images ne concernent que les cartes construites par la liste paresseuse : manifeste puis portrait et trois miniatures au plus. La galerie complète n’est renvoyée que lors de l’ouverture du profil, avec le plafond existant de six réalisations. Le client borne le cache média à 96 objets et 2 Mio, avec durée de 30 s et quatre téléchargements simultanés.

Budgets par minute fixe, contrôlés en transaction : recherche 30 par acteur / 120 global ; profil 30 / 180 ; médias 180 / 900 ; vérification 30 / 240. L’acteur est une empreinte du contexte réseau et de l’identité authentifiée éventuelle, jamais une identité fournie dans le corps de la requête. Les limites sont conservatrices et devront être suivies au regard du trafic réel. Un dépassement produit une erreur récupérable, pas de résultats inventés. Les fonctions réutilisent les plafonds d’instances existants ; le traitement d’image limite sa concurrence à un par instance.

## Fichiers de code et configuration

| Fichier | Rôle |
| --- | --- |
| `lib/features/professional/domain/professional_directory.dart` | Contrat et modèles publics de l’annuaire |
| `lib/features/professional/data/firebase_professional_directory_repository.dart` | Appels callable, cache média borné et concurrence |
| `lib/features/professional/presentation/professional_directory_view.dart` | Recherche, filtres, cartes, pagination, états et disponibilité |
| `lib/features/requests/data/firebase_request_repository.dart` | Raccordement au dépôt injecté existant |
| `lib/features/requests/presentation/explorer_view.dart` | Sélecteur et conservation des deux vues |
| `lib/features/navigation/presentation/foundi_shell.dart` | Visibilité active et retour Android |
| `lib/features/requests/presentation/request_views.dart` | Même parcours Explorer pour les visiteurs |
| `lib/features/professional/presentation/professional_showcase_screen.dart` | Réutilisation du profil, revalidation et activité fraîche avant demande privée |
| `lib/features/professional/presentation/professional_profile_widgets.dart` | Badge conditionné par une vérification valide |
| `functions/src/professional-directory-service.js` | Projection, recherche, pagination, contrôles Auth/statut et miniatures |
| `functions/src/professional-directory-store.js` | Adaptateur Firestore, masques de champs, curseurs et budgets |
| `functions/src/index.js` | Export des quatre nouvelles fonctions |
| `firestore.indexes.json` | Deux politiques TTL, sans nouvel index composite |
| `firebase.directory.emulators.json` | Configuration locale isolée, projet demo-foundi |
| `test/professional_directory_test.dart` | Tests de l’annuaire et captures Flutter |
| `test/request_actions_test.dart` | Défilement explicite jusqu’à la carte paresseuse avant l’action Répondre |
| `functions/test/professional-directory.test.js` | Tests unitaires du service |
| `functions/integration-test/professional-directory-flow.test.cjs` | Intégration avec l’adaptateur Firestore réel en émulateur |
| `functions/rules-test/professional-directory.test.cjs` | Refus des lectures/écritures privées par visiteurs et autres membres |

Les captures et ce compte rendu sont les seuls autres livrables ajoutés. Aucun changement des services de publication, quotas, photos de demandes, propositions, notifications ou conversations.

## Vérification

Résultats finaux exécutés le 12 novembre 2026 :

| Vérification | Résultat |
| --- | --- |
| `dart format .` | Projet formaté |
| `flutter analyze --no-pub` | Aucun problème détecté |
| Suite complète Flutter | **160 tests réussis**, aucun échec |
| Passe Flutter avec captures | **10 tests réussis**, sept PNG produits |
| Suite complète Node | **145 tests réussis**, aucun échec ni test ignoré |
| Rejeu des tests du service après nettoyage des noms | **9 tests réussis** |
| Sécurité/intégration Firestore en émulateur | **3 tests réussis**, aucun échec ni test ignoré |
| `git diff --check` | Aucune erreur d’espacement |

Les commandes exécutées sont :

```powershell
dart format .
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub test/professional_directory_test.dart --dart-define=DIRECTORY_CAPTURE=true --reporter expanded
cd functions
npm test
node --test test/professional-directory.test.js
```

Depuis la racine, sécurité et intégration Firestore :

```powershell
firebase emulators:exec --only firestore --project demo-foundi --config firebase.directory.emulators.json "node --test --test-concurrency=1 functions/rules-test/professional-directory.test.cjs functions/integration-test/professional-directory-flow.test.cjs functions/integration-test/direct-request-flow.test.cjs"
```

Résultats établis : 145 tests Node réussis, dont neuf nouveaux tests d’annuaire ; les neuf ont été rejoués après le nettoyage supplémentaire des noms. Trois tests Firestore réussis, sans test ignoré : intégration de recherche/masques/TTL/limites, règles privées et parcours existant de demande directe/notification.

Les tests annuaire couvrent : filtres cumulés et accents, résultat situé après les 120 premiers profils, 85 résultats paginés sans perte/doublon, curseur falsifié/expiré/changement d’acteur, statuts et Auth exclus, révocation avant divulgation, projection sans coordonnées ni propositions, images réencodées et plafonnées, recherche périmée, retours Android, reprise après authentification, activité verrouillée, envoi privé idempotent et écran 320 px avec texte agrandi.

Anomalies corrigées pendant les passes : référence de navigation erronée à la compilation ; notification d’erreur asynchrone lors d’une révocation dans le profil ; ancien test supposant le bouton Répondre déjà construit avant défilement ; chemin du fichier de règles dépendant du répertoire courant. Une seconde tentative d’émulateur a rencontré un port local occupé ; la passe réussie utilise les ports 1581/1584–1586. Les messages PERMISSION_DENIED de la passe de sécurité correspondent aux refus attendus.

La suite de régression couvre également Pour moi/Toutes, J’aime/Recommander/Répondre, répondants publics, Mon compte/profil, noms issus du compte, publication V9.2 et quotas, ajout/retrait des photos, demandes directes, notifications et messagerie. Aucun test en production ni notification push sur appareil réel n’est prétendu par cette validation locale.

## Captures Flutter réelles et comparaison

Rendus réalisés par `flutter test` via `RenderRepaintBoundary.toImage`, sans image générée ni retouche. Taille logique 430 × 932 pour le parcours principal, export 2×. Police Segoe UI chargée localement sous l’alias de la police de test ; le rendu système d’un Android réel peut différer.

Les services sont remplacés par les dépôts de test. Les médias et la présentation autolinkci viennent de la copie de projection publique déjà présente localement, sans nouvelle lecture ni écriture en production. Le compte client, les identifiants de routage et les libellés « Catégorie de test / Spécialité de test / Zone de test » sont des fixtures locales visibles volontairement. Ils ne remplissent pas l’annuaire de production. Aucune demande de ces captures n’a été envoyée à un vrai professionnel.

| Capture | Vérification |
| --- | --- |
| [Demandes](explorer-professionnels-v1-captures/00-explorer-demandes.png) | Vue existante avec le sélecteur ajouté ; ce n’est pas une capture avant modification |
| [Professionnels](explorer-professionnels-v1-captures/01-explorer-professionnels.png) | Quatre onglets, recherche, carte et réalisation réelle |
| [Recherche](explorer-professionnels-v1-captures/02-recherche.png) | Résultat filtré par texte avec fiche publique |
| [Profil public](explorer-professionnels-v1-captures/03-profil-public.png) | En-tête et sections partagés avec Mon compte |
| [Demande directe](explorer-professionnels-v1-captures/04-demande-directe.png) | Formulaire existant, destinataire fixé et activité grisée |
| [État vide](explorer-professionnels-v1-captures/05-vide.png) | Réinitialisation après filtres cumulés |
| [Indisponible](explorer-professionnels-v1-captures/06-indisponible.png) | Profil non approuvé, aucune action de demande |

Écarts assumés avec la maquette : catégories réelles en puces plutôt qu’une grille de métiers inventée ; pas de cœurs/favoris, distance, téléphone, compteur total fictif ni filtre « Proches ». Le titre, le logo et les couleurs restent ceux de l’application existante. Une seule réalisation disponible produit une seule miniature, sans dupliquer l’image pour en montrer trois. Le profil conserve ses trois sections existantes et son bouton de demande discret ; le formulaire complet existant garde ses limites et sa prévisualisation, au lieu du formulaire illustratif à 500 caractères. Aucun avatar, chiffre ou donnée illustrative de la maquette n’a été introduit dans le produit.

## Déploiement autorisé et vérifié — 13 novembre 2026

À la suite de l’autorisation explicite de l’utilisateur, les quatre fonctions ont été créées sur **foundi-7c837**, codebase **auth**, région **europe-west1**, runtime **Node.js 22 / deuxième génération**. Leur état distant a été contrôlé :

| Fonction | État | Instances max. | Concurrence | Mémoire |
| --- | --- | --- | --- | --- |
| `listPublicProfessionals` | ACTIVE | 3 | 4 | 256 Mio |
| `readPublicProfessionalProfile` | ACTIVE | 3 | 4 | 256 Mio |
| `readPublicProfessionalMedia` | ACTIVE | 3 | 1 | 512 Mio |
| `checkPublicProfessionals` | ACTIVE | 3 | 4 | 256 Mio |

Les politiques TTL ont été activées sur `professionalDirectoryCursors.expiresAt` et `professionalDirectoryLimits.expiresAt`, puis leurs exemptions d’indexation appliquées. Les deux champs ont été relus via l’API d’administration : **ttlConfig.state = ACTIVE**, aucun index propre au champ, configuration conforme à `indexes: []`. Le ciblage champ par champ évite de redéployer les autres index ou règles du projet.

La requête `status == approved`, ordonnée par identifiant, réutilise l’index de champ standard ; aucun nouvel index composite n’a été créé. L’expiration de curseur est contrôlée par le service même avant sa suppression TTL.

Le déploiement a rejoué les **145 tests Node** ainsi que `npm run check`, avec succès. Deux tentatives se sont arrêtées pendant la découverte locale du code, avant la création des fonctions : accès au serveur local de découverte Windows, puis délai initial de dix secondes. La passe réussie utilise :

```powershell
$env:FIREBASE_FUNCTIONS_DISCOVERY_OUTPUT_PATH = 'true'
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
firebase deploy --only functions:auth:listPublicProfessionals,functions:auth:readPublicProfessionalProfile,functions:auth:readPublicProfessionalMedia,functions:auth:checkPublicProfessionals --project foundi-7c837 --non-interactive
```

Les politiques ont été appliquées avec `gcloud firestore fields ttls update expiresAt --enable-ttl`, puis `gcloud firestore indexes fields update expiresAt --disable-indexes`, chaque commande ciblant séparément les deux groupes ci-dessus, la base `(default)` et le projet `foundi-7c837`.

Vérification réelle des quatre endpoints publics achevée le **13/11/2026 à 00:52 heure de Paris** (`2026-11-12T23:52:12Z` UTC) : liste de quatre professionnels, profil public avec activité canonique, disponibilité confirmée, manifeste contenant une réalisation publique et miniature **JPEG de 2 305 octets** générée par le processeur d’images Linux déployé. Les réponses de liste et de profil ont été comparées à leurs listes de champs autorisés ; aucune coordonnée privée ni proposition n’a été renvoyée. Le contrôle n’a créé aucune demande, conversation, notification ou compte. Il met seulement à jour les budgets techniques des lectures, conformément au service.

Les TTL, lectures et écritures de budgets/curseurs, vérifications Auth et transformations d’images ont un coût à suivre ; aucun service de recherche externe ni abonnement n’a été ajouté. Les suppressions TTL sont asynchrones, elles ne conditionnent pas la sécurité des curseurs expirés.

**Seuls les quatre Cloud Functions et la configuration des deux champs d’expiration prévus ont été déployés. Aucun Hosting, aucune règle Firestore/Storage et aucune autre fonction n’ont été redéployés. Aucun APK n’a été généré ou distribué.** Les tests de parcours restent locaux ; les contrôles de mise en service utilisent exclusivement les lectures publiques du backend distant. La branche reste locale, sans commit ni push automatique de ce sprint.
