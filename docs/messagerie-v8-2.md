# Foundi V8.2 — Messagerie enrichie

**Configuration actuelle : analyse antivirus facultative pour la phase de test, sur demande explicite de l'utilisateur le 2 novembre 2026.** `ATTACHMENT_REQUIRE_SCAN=false` est déployé sur la fonction d'envoi. Les contrôles de format, taille, structure, quotas et confidentialité restent actifs. Les fichiers partagés ainsi ne sont pas analysés par un antivirus ; ils portent `antivirusStatus: skipped`.

## Périmètre et audit

Branche `codex/foundi-v8-2-messagerie`, après sauvegarde V8.1 au commit local `689ab47`. Aucun push V8.2. Le déploiement Firebase autorisé le 2 novembre 2026 est détaillé en fin de rapport. Les documents techniques, plan et prototype HTML V8.2 de Downloads ont été lus ; aucun fichier SVG `maquettes/` n'était joint aux chemins fournis. Le HTML sert de référence UX et n'est pas recopié comme application.

P1 : images JPEG/PNG/WebP, PDF, partage volontaire du numéro et proposition liée. Les conversations, messages texte et décisions V8.1 sont conservés. Une discussion ou un média ne ferme pas la demande. Plusieurs conversations par demande restent possibles ; la clôture volontaire arrête les nouvelles propositions, les conversations non refusées continuent. Les fichiers validés restent consultables dans l'historique après refus/suppression logique.

P2 signalement reporté : la recherche dans Foundi Admin et Firebase n'a trouvé aucun dispositif de signalement ni circuit de traitement. Aucun bouton ne laisse croire qu'un signalement est transmis. Notifications, appels intégrés, audio et paiements restent hors périmètre ; Appeler ouvre seulement l'action système `tel:` demandée par US-3.

## Architecture et sécurité

Les données existantes restent dans `conversations/{id}/messages`. Les messages historiques sans `type` se lisent comme texte. Les nouveaux types sont `text`, `contact`, `image`, `pdf`. L'UID expéditeur et les horodatages sont attribués par le serveur. Aucun URL public, token de téléchargement ou téléphone de profil adverse n'est copié dans les conversations.

Le contrôle `readConversation` extrait le même prédicat d'écriture V8.1 et est partagé par l'envoi de texte/contact et les médias. Les transitions métier ne changent pas. Le numéro doit être E.164 et accompagné de `consent: true` dans la callable ; la confirmation montre sa valeur exacte. Seul le téléphone du compte courant est proposé au départ, et un numéro saisi pour cet envoi ne modifie aucun profil. Un contact déjà vu ou copié ne peut pas être révoqué.

### Transfert des fichiers

1. `prepareConversationAttachment` réserve un ID imprévisible et lie le message, l'auteur, la conversation, le type, nom nettoyé, taille et SHA-256. Les répétitions du même payload réutilisent cette réservation ; un payload différent est refusé.
2. `uploadConversationAttachment` reçoit le binaire avec ID token Firebase dans l'en-tête Authorization, vérifie sa taille, son hash, sa signature et les droits actuels. Le brut est écrit sous `conversations/{cid}/quarantine/{attachmentId}` avec précondition de création, sans écrasement et sans token public.
3. `ATTACHMENT_REQUIRE_SCAN=true` exige une réponse clean de l'antivirus ; cette valeur reste le défaut du code. La dérogation de test `false` ignore cet appel. Dans les deux modes viennent ensuite le décodage/réencodage des images (métadonnées retirées, 20 millions de pixels maximum, 2560 pixels de côté, JPEG/WebP qualité 85) ou les contrôles structurels PDF (non chiffré, 500 pages maximum, rejet de plusieurs éléments actifs explicites). Les contrôles MIME/signature et le parsing ne remplacent pas l'antivirus.
4. Un objet validé est créé sous `conversations/{cid}/attachments/{messageId}/{attachmentId}`. Une transaction revérifie les droits et la réservation puis crée ensemble le message final et son aperçu privé. Aucun message média final n'est créé avant cette étape.
5. `readConversationAttachment` délivre les octets après vérification du participant, du message et de la génération GCS. Cache-Control privé/no-store, nosniff, aucun jeton dans l'URL. Le client n'emploie pas `getDownloadURL`.

Les accès Storage clients aux conversations sont **tous interdits**, même en lecture pour un participant ; tailles, types, validation et droits sont contrôlés aux points d'entrée serveur. Ce choix évite la création automatique de tokens par un upload ou une lecture Firebase SDK. La recette a confirmé que l'API Firebase de l'émulateur génère un token au premier GET autorisé, même pour un objet initialement écrit sans token par le SDK Admin. Aucun GET direct, accès aux métadonnées ou `getDownloadURL` n'est donc permis par les règles. Les lectures positives A/B passent par `readConversationAttachment` ; C est refusé par ce même endpoint. La lecture HTTP évite aussi d'exiger une configuration CORS publique du bucket. La quarantaine n'est délivrée par aucun endpoint.

La réservation est dans `conversations/{cid}/attachments/{messageId}` et n'est pas accessible directement aux clients. Les quotas sont privés dans `conversationAttachmentRates/{uid}` : 5 réservations/minute, 50/jour et 100 Mio/jour par expéditeur. Une réservation ne consomme le quota qu'une fois. Les tentatives binaires sont limitées à 5/minute et 20 au total par réservation. Image : 10 Mio ; PDF : 15 Mio ; un fichier par message.

L'annulation invalide la réservation avant de nettoyer les objets. Une annulation après publication répond ready et ne prétend pas retirer le message. Une annulation non confirmée peut être réessayée ; quitter l'envoi affiche explicitement l'incertitude. Une panne, une réponse perdue, un lease concurrent ou une analyse indisponible ne deviennent pas un succès local. Le refus intervenu pendant l'envoi bloque la publication ; une simple clôture permet l'envoi existant selon V8.1.

Les réservations non publiées expirent après 24 h. `cleanupConversationAttachments` les traite quotidiennement, par lots bornés, et nettoie quarantaine et objet non référencé. Une panne Storage programme une nouvelle tentative. La suppression effective peut donc survenir après l'expiration, au prochain passage du job ; aucun effacement des médias déjà publiés n'est ajouté sans politique de conservation validée.

### Politique antivirus et dérogation de test

L'utilisateur a confirmé qu'aucun service antivirus n'était disponible. Le connecteur ClamD INSTREAM est préparé avec `ATTACHMENT_SCAN_HOST` et `ATTACHMENT_SCAN_PORT` (3310 par défaut). Seules les adresses réseau privées sont acceptées. Le mode explicite `ATTACHMENT_SCAN_HOST=disabled`, valeur par défaut et configuration déployée, retourne indisponible sans résolution DNS ni connexion réseau. Lorsque `ATTACHMENT_REQUIRE_SCAN=true`, l'absence de hôte/réponse clean, un timeout ou une erreur maintiennent le fichier privé en `awaiting_scan`, sans message final. Aucun service antivirus n'a été provisionné.

Sur instruction ultérieure de l'utilisateur, `ATTACHMENT_REQUIRE_SCAN=false` autorise désormais la livraison après contrôles structurels seuls. Cette décision est réservée à la configuration serveur, jamais à un champ transmis par le client. Réservation et message final indiquent `antivirusStatus: skipped`, et l'objet porte `validation: structural-v1` ; il n'est pas présenté comme analysé/clean. Les fichiers réellement analysés conservent le marquage `clean-v1`. Réactiver l'exigence concerne les futurs envois, sans prétendre réanalyser les fichiers déjà partagés ou révoquer leurs copies.

Pour rétablir une diffusion avec analyse antivirus obligatoire : fournir un service ClamAV maintenu avec signatures à jour, accès privé/VPC depuis les fonctions, limites de scan couvrant 15 Mio, alertes explicites de dépassement et refus des erreurs ; vérifier proprement un fichier sain, un fichier de test de détection et une panne du scanner, puis remettre `ATTACHMENT_REQUIRE_SCAN=true`. ClamD TCP n'est pas authentifié nativement et ne doit pas être exposé à Internet. Scanner et connectivité impliquent une configuration et des coûts d'infrastructure à valider séparément. Ces éléments ne sont pas provisionnés par ce sprint.

Les tests utilisent un simulateur local de protocole ClamD qui ne répond clean qu'aux empreintes des fixtures JPEG/PNG/WebP/PDF du dépôt. Tout autre contenu est refusé ou indisponible. Ce simulateur n'est pas un antivirus et n'est jamais sélectionné automatiquement en production.

## Flutter et plateformes

Les composants du chat, cartes, couleurs et navigation sont réutilisés. File Picker 13.3 déjà présent est conservé via son API actuelle `pickFile`. Ajouts résolus dans le lock : Dio 5.11.1, image_picker 1.2.4, url_launcher 6.3.3, open_filex 5.0.0, path_provider 2.1.6, crypto 3.0.8 ; web 1.1.1 devient dépendance directe. Aucun paquet Firebase existant n'a été mis à niveau. Sharp 0.35.5 et pdf-lib 1.17.1 servent à la validation serveur.

Caméra proposée sur Android/iOS, avec autorisations explicatives iOS ; bibliothèque et PDF sur plateformes du picker. PDF : accès HTTP authentifié puis fichier temporaire privé ouvert par le système sur mobile, ou Blob local téléchargé sur le Web. Ces URL Blob ne sont pas des URL Storage et sont révoquées. Les fichiers PDF temporaires sont nettoyés au changement de compte et après délai ; les copies volontairement téléchargées ou déjà ouvertes par un autre programme ne peuvent pas être révoquées.

Les images sont gardées en mémoire dans les composants visibles, pas préchargées pour tout l'historique. Le changement d'UID ferme les routes privées et purge le cache d'images ; des widgets sont isolés par UID. L'aperçu et les erreurs de médias ne détruisent pas le brouillon texte. La proposition liée réutilise `ProposalDetailView`, avec montant, délai, statut et retour au chat.

## Fonctions, règles, index et migration

Nouvelles fonctions : prepare/cancelConversationAttachment (callables), upload/readConversationAttachment (HTTP), cleanupConversationAttachments (planifiée). `sendConversationMessage` accepte aussi le type contact confirmé. Aucune modification des transitions de select/decide/manageRequest.

Storage Rules évoluent pour les objets privés validés. Firestore Rules déjà serveur-only pour les mutations et fermées par défaut pour les sous-collections de réservation restent adaptées. Un index simple collection-group `attachments.expiresAt ASC` est préparé pour le nettoyage. Aucune migration destructive ni backfill de messages historiques nécessaire.

L'absence de rôle public dans la politique IAM du bucket réel a été vérifiée au déploiement. Les autorisations des nouvelles fonctions et du planificateur sont gérées par Firebase lors de leur création. L'accès privé au scanner devra être configuré dans les options réseau des fonctions au moment de son raccordement.

### Fichiers concernés

| Ensemble | Fichiers principaux |
|---|---|
| Services Firebase | `functions/src/attachment-service.js`, `attachment-validation.js`, `attachment-scanner.js`, `conversation-service.js`, `index.js` |
| Autorisations / nettoyage | `storage.rules`, `firestore.indexes.json` ; `firestore.rules` inchangé |
| Modèles / transport Flutter | `conversation_repository.dart`, `rich_conversation_repository.dart`, `firebase_rich_conversation_repository.dart`, `firebase_request_repository.dart` |
| Interface et fichiers locaux | `conversation_views.dart`, `rich_message_widgets.dart`, `media_actions.dart`, `pdf_access_io.dart`, `pdf_access_web.dart`, `pdf_access_stub.dart` |
| Session / intégration | `lib/app.dart`, `lib/main.dart`, `foundi_shell.dart`, `ios/Runner/Info.plist` |
| Dépendances | `pubspec.yaml`, `pubspec.lock`, `functions/package*.json` et enregistrements de plugins générés pour desktop |
| Recette | nouveaux tests Flutter, tests Node médias, règles et intégration médias, fixtures, simulateur ClamD, `firebase.v82.emulators.json`, script de recette locale |

Stockage, trafic HTTP/Storage, fonctions 512 Mio, planificateur et analyse antivirus peuvent être facturés selon l'usage. Les plafonds de taille, quotas, concurrence 2/maxInstances 3 et nettoyage bornent l'usage mais ne constituent pas un budget financier absolu. Le déploiement et les données temporaires de recette ont été autorisés séparément après la validation locale. Aucune notification ni modification Jira.

## Résultats de validation

| Vérification locale | Résultat |
|---|---|
| `flutter analyze --no-pub` | Aucun problème |
| Suite Flutter complète | 80/80, dont 9 tests modèle/widgets V8.2 et 2 tests du transport Dio authentifié |
| `npm --prefix functions run check` | Réussi |
| Suite unitaire Node | 85/85, dont les 70 tests antérieurs et 15 tests médias/contact/politique antivirus |
| Compilation Web release | Réussie |
| Règles Firestore/Storage finales | 22/22, avec refus des GET, métadonnées et liens à jeton directs |
| Intégration Auth/Functions/Firestore/Storage | 6/6 ; scénario V8.2 à trois comptes + 5 scénarios de non-régression |
| Compilation Android debug dirigée vers les émulateurs | Réussie (`build/app/outputs/flutter-apk/app-debug.apk`), non installée sur téléphone |

Les tests unitaires médias couvrent formats/signatures, scanner indisponible/infecté, confidentialité, idempotence, annulation concurrente, quotas, clôture/refus et nettoyage avec panne. Les tests Flutter couvrent le consentement au contact, les erreurs d'ouverture, l'aperçu et le retry sans doublon, la progression à 40 % et le bouton désactivé, l'annulation après publication concurrente, la conservation du brouillon, le petit écran avec clavier, le retour depuis la proposition, la lecture seule et la fermeture des routes privées à la déconnexion. Le décodage effectif de la miniature est aussi vérifié. Les tests de transport contrôlent les octets binaires réellement donnés à Dio, les en-têtes d'authentification, les réponses de quarantaine, l'annulation et les refus 403.

L'intégration V8.2 utilise deux participants A/B et un tiers C dans Auth, Firestore, Functions et Storage émulés. Les deux participants reçoivent les quatre types en temps réel et lisent image/PDF via HTTP ; C ne peut pas lire, envoyer ou usurper un expéditeur. Elle vérifie MIME/signature/limites, quarantaine inaccessible, absence de message avant validation, retry sans doublon, absence de token avant/après les lectures, fichier manquant, réouverture, nouveau professionnel toujours autorisé à proposer, clôture volontaire puis refus avec historique encore lisible.

Les erreurs de recette ont été corrigées : bucket de fixture différent du bucket SDK par défaut, concurrence entre tests qui rechargeaient le même jeu de règles, et accès GET Firebase capable de créer un token public. Les règles sont désormais testées en série et tous les accès SDK aux médias du chat sont refusés. Le premier démarrage à froid des fonctions a aussi échoué pendant la découverte locale ; les démarrages suivants ont chargé les 25 exports. Les exécutions en échec ne sont pas comptées comme des passes.

Captures de widgets intégrés : [contact](v82-captures/01-contact.png), [photo](v82-captures/02-photo.png), [PDF](v82-captures/03-pdf.png), [attente d'analyse](v82-captures/04-quarantaine.png). Ce sont des données de test, dont une petite image unie et des horodatages fictifs ; elles ne prouvent pas une recette sur téléphone.

Commande de recette locale : `node functions/scripts/test-v82-emulators.cjs`. Elle démarre le simulateur de scan, ajoute temporairement ses deux paramètres dans `.env.local`, lance exclusivement `demo-foundi`, puis restaure exactement le fichier local. Un backup privé dans `.dart_tool/v82-local-env-backup.bin` protège une interruption brutale. Ne pas l'écraser si une exécution précédente a été interrompue.

Les fonctions de l'émulateur sont sérialisées via inspect-functions pour limiter la mémoire. Les tests de contention transactionnelle V8.1 existants restent exécutés directement sur les vraies transactions Firestore concurrentes de l'émulateur. Le déclenchement Cloud Scheduler n'est pas émulé : la recette locale teste la méthode unitairement, et le déclenchement réel a ensuite été vérifié en production (voir ci-dessous).

La recette finale sort avec le code 0. L'outil Java des règles affiche une exception de fin de flux pendant l'arrêt des émulateurs, après la réussite des tests ; ce bruit d'arrêt n'est pas une erreur de test. Le backup temporaire d'environnement est supprimé après restauration.

La compilation Android a pris environ 15 minutes pendant la génération DEX, sans erreur. Gradle signale l'usage de Kotlin Gradle Plugin par les paquets Firebase déjà présents ; c'est un avertissement de compatibilité avec de futures versions de Flutter, pas un échec de cette compilation. Aucun changement de versions Firebase ou de configuration Gradle n'a été ajouté pour le masquer. L'APK de validation utilise le mode émulateurs et ne constitue pas une livraison connectée à la production.

Restent manuels : sélection de galerie et caméra sur appareil, autorisations natives, ouverture dans une application PDF installée, action téléphonique système, réseau mobile réel, compilation iOS sur macOS et analyse antivirus réelle. Les fichiers temporaires suivis pendant la session sont nettoyés ; le nettoyage après arrêt brutal de l'application n'est pas garanti. Aucun test sur appareil physique n'est revendiqué.

Références officielles : [Storage Rules](https://firebase.google.com/docs/storage/security/rules-conditions), [fonctions HTTP](https://firebase.google.com/docs/functions/http-events), [Sharp](https://sharp.pixelplumbing.com/api-constructor/), [ClamAV](https://docs.clamav.net/manual/Usage/Scanning.html), et documentation des paquets publiée par leurs mainteneurs sur pub.dev.

## Déploiement autorisé — 2 novembre 2026

Déploiement ciblé terminé avec code 0 sur `foundi-7c837`, région `europe-west1`. Les 82 tests serveur et les contrôles de syntaxe ont repassé dans les préhooks. Les premiers essais s'étaient arrêtés avant publication : délai de découverte local de 10 secondes puis paramètres antivirus non renseignés en mode non interactif. Le délai de découverte a été porté à 120 secondes pour la commande, et les paramètres explicites sont `ATTACHMENT_SCAN_HOST=disabled`, `ATTACHMENT_SCAN_PORT=3310`. Le comportement du mode disabled est couvert par le test existant de quarantaine.

| Fonction | État vérifié | Révision |
|---|---|---|
| `sendConversationMessage` | ACTIVE | `sendconversationmessage-00003-gac` |
| `prepareConversationAttachment` | ACTIVE | `prepareconversationattachment-00001-wes` |
| `cancelConversationAttachment` | ACTIVE | `cancelconversationattachment-00001-xeq` |
| `uploadConversationAttachment` | ACTIVE | `uploadconversationattachment-00001-har` |
| `readConversationAttachment` | ACTIVE | `readconversationattachment-00001-juk` |
| `cleanupConversationAttachments` | ACTIVE | `cleanupconversationattachments-00001-cek` |

Les règles Firestore sont inchangées et correspondent au fichier local : ruleset `7d073ac3-1846-4bef-9430-28f3c332484a`. Les règles Storage déployées correspondent au fichier local : ruleset `ef2b2988-3208-48fa-a076-b092bf9dc583`. Le bucket `foundi-7c837.firebasestorage.app` n'accorde aucun rôle IAM à `allUsers` ou `allAuthenticatedUsers`.

L'index collection-group `attachments.expiresAt ASCENDING` a terminé sa construction : **READY**, requête réelle exécutée avec succès. L'API Cloud Scheduler a été activée pour le nouveau job `firebase-schedule-cleanupConversationAttachments-europe-west1`, **ENABLED**, périodicité `every 24 hours`. Aucun déploiement Hosting/Admin ni migration de données historiques.

### Contrôles des services publiés

Les trois callables V8.2/envoi de message refusent l'anonyme avec HTTP 401 ; les endpoints binaires font de même et portent les en-têtes `private, no-store` et `nosniff`. Conversations, messages, réservations, quotas et listes privées refusés sans authentification. Explorer : trois demandes publiées, cinq combinaisons de filtres non vides, résultat vide correct ; demandes clôturées/supprimées et requête sans statut refusées avec HTTP 403. Ces contrôles ne modifient aucune donnée.

La recette réelle, terminée avec code 0, utilise un client et deux professionnels temporaires :

- A/B reçoivent les textes et deux contacts en temps réel ; confirmation obligatoire, répétition du même envoi sans doublon, téléphone de profil inchangé et aperçu de contact sans numéro.
- C ne peut pas lire/lister le chat de A/B, partager un contact dans ce chat, envoyer un fichier ou usurper l'expéditeur. Les écritures directes Firestore sont refusées.
- Image et PDF passent réellement par les endpoints binaires déployés et restent en `awaiting_scan` avec HTTP 202. Aucun message média final ni objet diffusé n'est créé. Lecture privée : 404 pour les participants, 403 pour C ; accès HTTP sans identité : 401. Même un participant ne peut lire la quarantaine, obtenir ses métadonnées ou un lien à jeton, lister les objets ou écraser le brut. L'accès Storage anonyme est refusé ; aucun token public avant/après les tentatives.
- Limite de taille et fausse signature ZIP/image refusées ; annulation PDF effective ; répétition de l'envoi sans succès fictif ni message final.
- Une réservation de ce test seulement a été rendue expirée, puis le job Cloud Scheduler réellement déclenché : réservation devenue `expired` et objet privé supprimé. Cela valide le rôle d'invocation, l'index et les permissions de nettoyage réels.
- La demande reste publique et accepte une deuxième proposition puis une deuxième discussion. Reconnexion et historique conservés. Le refus archive seulement le chat concerné et bloque ses nouveaux fichiers. La clôture volontaire bloque les nouvelles propositions tout en permettant encore les messages dans l'autre chat actif.

Les trois comptes et treize chemins de documents de ce test ont été supprimés. Un contrôle indépendant confirme leur absence, deux préfixes de conversations vides et **zéro message ou média orphelin**. Les données applicatives préexistantes ne faisaient pas partie de ce nettoyage. Les manifestes techniques privés, sans mots de passe ni jetons, restent hors Git dans `.dart_tool/v82-smoke-manifest-*.json`. Le contrôle Explorer après nettoyage retrouve les mêmes trois demandes publiques et les filtres fonctionnels.

Lors de cette première recette, la livraison avec un véritable antivirus n'était pas testable, faute de scanner. Aucune simulation de résultat clean n'a été utilisée. Les refus PERMISSION_DENIED du SDK affichés pendant la recette sont les résultats attendus des tentatives interdites. La dérogation de test demandée ensuite est décrite ci-dessous.

### Test sur téléphone

APK Android debug V8.2 compilé avec `--dart-define=USE_FIREBASE_EMULATORS=false`, connecté à `foundi-7c837` : `build/app/outputs/flutter-apk/app-debug.apk`. Compilation réussie en environ 131 secondes ; aucun appareil physique installé ou piloté par cette recette. SHA-256 : `ceac344d1c2691878804d7045906a974f14fbca455bd011837ac8d1f74c19c35`.

Installer cet APK ou lancer depuis la racine de Foundi : `flutter run --dart-define=USE_FIREBASE_EMULATORS=false`. Le déploiement Firebase ne met pas à jour l'application installée. Cet APK reste compatible avec le mode sans antivirus : aucune recompilation cliente nécessaire pour lever le blocage d'envoi côté serveur.

## Mise à jour : phase de test sans antivirus — 2 novembre 2026

Instruction explicite de l'utilisateur : annuler pour le moment les restrictions liées à l'antivirus. La fonction `uploadConversationAttachment` seule a été redéployée avec `ATTACHMENT_REQUIRE_SCAN=false`, révision **`uploadconversationattachment-00002-tif`**, état **ACTIVE**. Les autres fonctions, les règles et l'index n'ont pas été modifiés par ce déploiement. Aucun service antivirus ni réseau supplémentaire créé.

Les 85 tests Node et les contrôles de syntaxe ont passé dans les préhooks. Trois nouveaux tests couvrent les quatre formats sans appel scanner, le maintien des refus de fichiers invalides et des permissions, puis le retry d'un fichier en attente et le rétablissement de l'exigence antivirus. La recette locale avec `node functions/scripts/test-v82-emulators.cjs --without-antivirus` réussit : **22 tests de règles et 6 scénarios d'intégration**, avec le marquage skipped/structural, la livraison HTTP privée, l'idempotence et les refus du tiers.

La recette réelle en production, avec un client et deux professionnels temporaires, termine avec code 0 : **JPEG, PNG, WebP et PDF envoyés et lus par les participants**, HTTP 200/ready, marquage `skipped`/`structural-v1`, aucun appel à un scanner configuré. Le tiers reçoit HTTP 403. Les métadonnées/liens à jeton et les lectures Storage directes restent refusés même aux participants ; aucun token public n'apparaît après les lectures HTTP autorisées. Les images sont réencodées et le PDF reçu est identique aux octets validés structurellement.

Sont aussi vérifiés : retry sans doublon, fausse image ZIP et taille invalide refusées, annulation avant transfert, annulation après publication répondant ready, reconnexion avec huit messages conservés, nouvelle proposition/discussion toujours possible, lecture historique après refus, clôture volontaire et poursuite de l'autre conversation. Les limites et quotas sont conservés.

Les trois comptes et treize chemins de cette nouvelle recette ont été supprimés. Le contrôle indépendant couvre les deux recettes successives : six comptes absents, vingt-six chemins absents, quatre préfixes de conversations vides, **zéro fichier ou message orphelin**. Explorer retrouve les trois demandes publiques préexistantes avec filtres et états vides corrects. Aucun changement Flutter, aucune nouvelle compilation ou installation sur téléphone : l'APK V8.2 connecté à la production déjà fourni reste utilisable.

Pour rétablir le blocage en attendant un scanner, remettre `ATTACHMENT_REQUIRE_SCAN=true` dans la configuration serveur et redéployer la fonction d'envoi. Cette modification n'est pas un mécanisme automatique de réanalyse ou de rappel des fichiers déjà partagés.
