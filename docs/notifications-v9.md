# Foundi V9 — Notifications transversales

Évolution déployée le 4 novembre 2026 : [badges et push V9.1](badges-push-v9-1.md). Les messages privés disposent désormais de leur compteur et sont exclus du centre général ; les aperçus de push sont réglables et masqués par défaut. Les sections ci-dessous décrivent la base V9 et son déploiement initial.

## Base et audit (3 novembre 2026)

V8.2 enregistrée dans `704d8ee` et poussée sur `origin/codex/foundi-v8-2-messagerie` avant création de `codex/foundi-v9-notifications`. La phase d’implémentation s’est terminée sans déploiement. Le déploiement autorisé ensuite par l’utilisateur est consigné ci-dessous.

Pack consulté : prompt technique, plan sprint, matrice CSV et source du prototype HTML dans Downloads. Ces documents définissent les besoins ; leurs utilisateurs, compteurs et actions simulées ne deviennent pas des données ni des workflows de production.

Flutter installé 3.44.3, Dart 3.12.2 ; Firebase Core 5.1, Auth 7.0, Firestore 7.1, Functions Flutter 7.0 ; backend Node 22, Admin SDK 14.5, Functions 7.4. Foundi Admin utilise déjà `reviewProfessionalProfile` et `professionalAudit`. Pas de FCM mobile avant V9. La notification serveur historique `users/{uid}/notifications/professionalDecision` était écrasée à chaque décision et contenait le motif privé. V9 remplace cette écriture par l’observation du journal existant et ne reprend pas les anciens documents dans l’inbox V9. Aucun changement des décisions admin.

Navigation existante : shell Flutter à états, `ProfessionalGate`, `RequestDetailView`, propositions reçues, `ProposalDetailView`, `ConversationView`. Les resources privées restent chargées par leurs repositories et règles existants.

## Contrat des événements réellement disponibles

| Événement | Source exacte / opération existante | Transition | Destinataire / destination | État V9 |
| --- | --- | --- | --- | --- |
| professional.approved | création `professionalAudit/{id}` par `professional-service.decide` | pending → approved | candidat / dossier | implémenté |
| professional.rejected | même journal admin | pending → rejected | candidat / dossier | implémenté, résumé neutre |
| professional.more_info_requested | même journal admin | pending → needs_changes | candidat / dossier existant | implémenté P2 réel |
| professional.suspended | même journal admin | approved → suspended | candidat / dossier | implémenté |
| proposal.created | création `proposals/{id}` par `proposal-service.send` | absent → sent | auteur / propositions reçues de la demande | implémenté |
| conversation.opened | création `conversations/{proposalId}` par `conversation-service.select` | absent → active | professionnel lié / chat | implémenté |
| message.created | création `conversations/{id}/messages/{messageId}` par `send` ou `attachment-service` | message final persistant text/image/pdf/contact | autre participant / chat | implémenté |
| proposal.retained | création journal `userRequests/{uid}/items/{requestId}/decisions/{id}` par `decide` | action retain effective, précédente référence différente | pro lié / proposition | implémenté |
| proposal.rejected | même journal de décision | action reject → rejected | pro lié / proposition historique | implémenté |
| request.closed | mise à jour miroir auteur par `request-service.manage` | published ou ancien in_discussion → closed | pros ayant proposé, dédupliqués / proposition privée liée | implémenté |
| request.matched | création initiale `requests/{id}` + `requestOwnership` serveur | absent → published | pros approuvés FOUN-52 sauf auteur / demande ouverte | implémenté par pages |
| conversation.ended | aucune action de fin partagée dans `conversation-service` ou UI | inexistante | deux participants in-app, push seulement à l’autre lorsque le workflow sera ajouté | **non existant, non émis** |
| archivage personnel | aucune opération partagée équivalente | action locale éventuelle | aucun autre destinataire | aucun trigger de changement de conversation |
| réouverture demande/discussion | aucun workflow | inexistante | — | non émis |
| signalement traité | aucun workflow de modération P2 | inexistant | — | non émis |
| dépôt de dossier / activité admin | soumission pending existe, pas de boîte d’activité admin | disponible / centre admin absent | — | P2 hors cœur retenu |

`selectProposal` ouvre une discussion, sans retenir une proposition ni clôturer la demande. Retenir ne ferme pas la demande. Refuser une proposition archive seulement sa discussion avec `proposal_rejected`. Supprimer une demande archive ses discussions avec `request_deleted`. Ces deux cas **ne sont pas** une fin partagée volontaire et ne génèrent pas `conversation.ended`. Clôturer une demande préserve les chats et arrête les nouvelles propositions. Aucun statut métier V9 ajouté.

Le futur hook de fin partagée devra lire un événement serveur durable contenant l’acteur et les deux participants, produire deux entrées avec le même eventId et utiliser l’acteur pour supprimer son propre push. Ne pas brancher ce hook sur un simple `status: read_only`.

## Architecture et sécurité

- `notification-policy.js` : catalogue neutre, IDs SHA-256 et matching exact FOUN-52.
- `notification-service.js` : normalisation, destinataires, création atomique in-app + compteur + outbox, jobs et envoi FCM injectables pour les tests.
- `users/{uid}/notifications/{hash(eventId,uid)}` : schemaVersion 9, catégorie, titre, bodySafe, IDs internes, dates serveur, occurrence métier, readAt. Pas de texte de chat, contact, nom de fichier ou motif de refus.
- `users/{uid}/notificationState/inbox` : compteur global serveur indépendant du mode client/pro. Une réception incrémente atomiquement ; un passage readAt null → timestamp décrémente par trigger avec reçu idempotent `notificationReceipts`.
- Le client peut uniquement marquer sa notification lue avec un timestamp serveur. Création, suppression, contenu, type, cible et compteur interdits. Préférences : quatre booléens propres, validés par règles. Lecture d’une notification d’autrui interdite, y compris admin.
- `users/{uid}/notificationPreferences/push` : messages, proposals, opportunities, account ; n’efface et ne filtre jamais la boîte in-app.
- `registerNotificationDevice` / `unregisterNotificationDevice` sont les seules écritures de devices. Identité issue de Firebase Auth, compte vérifié et actif, maximum 10 appareils. Registre privé `notificationTokens/{hash(token)}` avec propriétaire unique ; rotation, transfert de compte et invalidation sont transactionnels. Aucun token lisible/inscriptible depuis Firestore client.
- `notificationOutbox` + sous-collection deliveries, `notificationJobs`, `notificationReceipts`, `notificationTokens` sont serveur seulement.
- `resolveNotification` relit l’entrée du compte connecté et contrôle la ressource actuelle : participants pour chat/proposition, miroir pour propositions reçues, approbation + FOUN-52 pour opportunité, propre dossier pour statut pro. Une demande publique clôturée s’ouvre par la proposition privée du destinataire, car les règles interdisent sa lecture publique. Fallback neutre si objet absent ou accès révoqué. Aucun payload FCM ne détermine une URL ou une autorisation.

## Flutter et push

Cloche réelle commune depuis le bandeau d’accueil/compte, centre avec Tout/Non lues/catégories, Aujourd’hui/Plus tôt, lecture idempotente, tout lire, erreurs avec reprise, chargement et vide. Les 30 premières entrées sont en temps réel ; les suivantes se chargent avec un curseur Firestore, sans plafond total de 100 entrées. Tri sur l’heure de l’événement métier `occurredAt` afin de résister aux triggers livrés dans le désordre ; `createdAt` reste la date serveur d’insertion et la borne de « tout lire ». Réglages accessibles depuis l’inbox et Paramètres > Notifications.

Le tap FCM fournit seulement notificationId + recipientUid. `onMessageOpenedApp` et `getInitialMessage` alimentent une intention qui attend l’authentification complète ; un autre compte ne peut l’ouvrir. Le shell réutilise les écrans existants et la revalidation serveur. Les opportunités passent en mode pro uniquement après validation actuelle. Les historiques restent accessibles selon V8.1, même hors mode pro.

FCM Android/iOS uniquement ; boîte et préférences disponibles sur les autres plateformes. Permission demandée depuis l’action expliquée des réglages, jamais au lancement ; trace locale de demande pour ne pas répéter le prompt après refus, y compris Android 13 où refus et absence de demande peuvent partager un état. État OS relu au retour de l’application. Auto-init désactivé initialement dans Android et iOS. Présentation foreground FCM désactivée : l’inbox temps réel est la présentation unique, y compris chat visible. Pas de présence serveur fiable introduite : un push réseau peut encore être envoyé quand le chat est affiché, mais aucune bannière locale en double.

L’installation conserve un ID aléatoire local. Restauration de session autorisée, token refresh, rotation, multi-appareils et déconnexion sont gérés. Avant signOut, révocation serveur ; si indisponible, invalidation FCM locale requise. Si aucune révocation n’aboutit, la déconnexion retourne une erreur au lieu de laisser un token de compte actif. Invalidation locale également lors de changement d’identité observé.

La version du plugin conserve `getToken`, `onTokenRefresh` et `deleteToken` (dépréciés dans son API récente), intentionnellement pour le contrat registration-token de `Admin SDK messaging.send`. Les suppressions de lint sont locales et commentées ; aucune dépendance à une API serveur FID non vérifiée.

## Reprises, charge et coûts

Événements de création/journaux identifiés par leur chemin stable. Clôture identifiée par requestId + updatedAt serveur monotone. ID final contient aussi recipientUid. Répéter un trigger, un journal ou une page ne répète pas l’inbox ni l’outbox. Une simple édition, lecture, navigation ou mise à jour du chat ne produit aucun événement métier.

Opportunités : même politique que `opportunity-service.list` : IDs catégorie, spécialité et zone déclarés, catégories sans spécialité prises en charge ; **aucune expansion implicite aux parents/enfants de zone** car FOUN-52 actuel utilise des IDs exacts. Les libellés de zone sont hiérarchiques mais ce n’est pas une autorisation de ciblage supplémentaire.

Fanout paginé par 40 profils approuvés ou propositions, curseur durable, bail de page 120 s. Création de job lance une première page ; scheduler poursuit jusqu’à 10 pages/minute (400 lignes/minute). Déduplication request + pro même si plusieurs propositions. Push opportunités retardé d’au moins 60 s, résumé générique, quota partagé entre jobs d’un même appareil : un push maximum par heure ; toutes les opportunités restent in-app.

Push : bail global et claim par appareil avant appel FCM. Revalidation de l’accès à la cible juste avant livraison ; les outboxes âgées de plus de 24 heures expirent sans envoi. Erreurs explicites server-unavailable/quota-exceeded : au plus trois essais espacés. Token invalide : suppression conditionnelle protégeant la rotation. Résultat réseau ambigu ou crash après claim : pas de réenvoi aveugle, afin de privilégier l’absence de doublons ; une alerte peut manquer. FCM ne fournit pas une garantie de réception/affichage exactement une fois. L’inbox reste la source durable.

Coût indicatif en opérations, sans tarif chiffré : pour chaque destinataire, vérification Auth + lecture d’idempotence + création notification/outbox et mise à jour compteur (3 écritures hors reçus/appareils) ; lecture ajoute un reçu et un décrément. Fanout opportunités parcourt tous les profils approuvés une fois par publication, soit O(nombre de profils approuvés), avec pages bornées et jobs indépendants du cœur. À gros volume, prévoir un index inversé de ciblage avant montée en charge. Push ajoute lectures préférences/appareils/registre/claims et écritures d’état par appareil. Scheduler toutes les minutes, borné à 100 outboxes par exécution. Surveiller backlog, coûts Firestore/Auth, erreurs quota et logs structurés sans tokens.

## Activation proposée — à exécuter uniquement après accord

1. Revoir la matrice, les règles/index et les résultats de tests ci-dessous, puis valider les contrôles sur vrais appareils.
2. Préparer APNs dans Firebase, capacité Push Notifications du provisioning Apple et identifiants d’application réels. Entitlements ajoutés : développement Debug, production Release/Profile, background remote-notification ; Windows ne peut pas vérifier signature/provisioning iOS. Ne pas changer les secrets SMTP/antivirus existants.
3. Déployer d’abord index/règles compatibles, attendre les index prêts. Déployer ensuite le backend et le client comme un même lot validé. Les anciennes callables restent identiques ; aucun backfill ni migration de données requis.
4. `NOTIFICATION_PUSH_ENABLED` vaut **false** par défaut : inbox et jobs actifs, aucun appel FCM via les triggers/scheduler. Ne pas laisser un backlog de test partir lors de l’activation : inspecter et traiter/expirer les outboxes avant de passer à true après validation.
5. Tester approbation admin, client/pro/tiers, demande correspondante, messages et pièces jointes V8.2, clôture indépendante, permissions refusées/révoquées et deux téléphones. Activer FCM progressivement, surveiller logs/backlog ; false est le coupe-circuit d’envoi. Aucun push mobile admin.

## Validation et captures

| Vérification exécutée | Résultat |
| --- | --- |
| Backend `node --test test/*.test.js` | **88/88**, aucun ignoré |
| Syntaxe backend `npm run check` | OK |
| Suite Flutter complète (V3 à V9, V8.1/V8.2 incluses) | **87/87** |
| Nouvelle suite V9 au format téléphone, préférences et intentions authentifiées | **7/7**, relancée après les corrections de navigation/préférences |
| Suite complète Firestore/Storage Rules émulées | **26/26**, dont 4 V9 |
| Suite complète d’intégration Firebase initiale | **7/7** |
| Suite ciblée V9 enrichie, ports dédiés 1320–1326 | **8/8** : 4 règles V9 + 4 intégrations (V8.2 + notifications service + chaîne réelle V9 + vérification pro) |
| Analyse Flutter finale après les derniers ajustements | **No issues found** |
| Compilation Android `flutter build apk --debug --no-pub` | **Réussie**, APK local `build/app/outputs/flutter-apk/app-debug.apk`, non installé |

La suite ciblée vérifie la vraie chaîne `reviewProfessionalProfile`/`publishRequest`/`sendProposal`/`selectProposal`/`sendConversationMessage`/`decideProposal`/`manageRequest` → triggers → inbox/compteur. A/B/C, refus d’accès tiers, approbation admin, propositions/réessais, discussion et messages, retenue/refus, clôture indépendante, préférences et register/unregister sont couverts. Le test V8.2 vérifie qu’à chaque message final texte/image/PDF/contact correspond exactement une entrée pour l’autre participant, aucun événement pour les fichiers annulés. Fanout de plus de deux pages de profils approuvés, multiples propositions du même pro, concurrence de livraison, quota opportunités, rotation/transfert de token, tokens invalides, erreurs FCM explicites et ambiguës : testés avec Firestore réel émulé et transport FCM simulé.

Commandes reproductibles depuis la racine :

```powershell
npm --prefix functions test
npm --prefix functions run check
flutter analyze
flutter test
npm --prefix functions run test:v82:emulators
npm --prefix functions run test:v9:emulators
flutter test test/notifications_v9_test.dart --dart-define=V9_CAPTURE=true
```

Le driver utilise exclusivement le projet `demo-foundi`, restaure `.env.local` et crée/supprime des secrets locaux factices si aucun `.secret.local` n’existe déjà. Les premiers essais ont rencontré l’interdiction réseau du bac à sable puis un port occupé par une ancienne instance ; les suites réussies ci-dessus ont été relancées avec les accès nécessaires et des ports V9 dédiés. Les messages Java à l’arrêt du runtime Storage surviennent après les sorties de tests réussies, sans échec d’assertion. Aucun test FCM réel n’est émulé.

La compilation Android a pris environ 48 minutes sur cette machine à mémoire très contrainte. Les avertissements KGP concernent les plugins Firebase déjà présents (`cloud_functions`, `firebase_auth`, `firebase_core`) ; ils ne bloquent pas l’APK. L’analyse finale, ralentie dans le même contexte, reste sans problème. Aucun changement de configuration mémoire/Gradle effectué.

Captures dans `docs/v9-captures` : centre, vide, erreur, préférences, professionnel approuvé, message et clôture de demande. Générées depuis les widgets Flutter en 390 × 844 avec des fixtures de test explicites et inspectées visuellement, sans comptes de production. Pas de capture de fin partagée fictive : le workflow n’existe pas.

Limites à valider sur téléphone : réception FCM sur vrais Android/iOS (premier plan/arrière-plan/app terminée), rotation et deux appareils physiques, révocation OS, APNs/provisioning Apple et comportement OS des alertes. Les tests de transport injecté ne prouvent pas la réception sur téléphone. L’utilisateur a ensuite autorisé l’activation pour son test Android ; voir le suivi du déploiement.

## Déploiement autorisé — 3 novembre 2026

Demande explicite : déployer V9 sur Firebase et activer les push pour tester sur le téléphone. Plateforme de test confirmée : **Android**.

Contrôle final à **18 h 31, heure de Paris** :

| Élément | État vérifié sur le projet `foundi-7c837` |
| --- | --- |
| Firestore Rules V9 | publiées après compilation réussie ; anciennes règles sauvegardées et identiques à la base V8.2 |
| Index | **18 READY**, dont les 6 nouveaux ; aucun index existant supprimé |
| Fonctions | **14 nouvelles fonctions V9 + mise à jour de reviewProfessionalProfile**, les 15 en état **ACTIVE**, région europe-west1 |
| Déclencheurs | **10 Eventarc**, sans condition d’erreur, source Firestore eur3, reprises automatiques activées |
| Push | **NOTIFICATION_PUSH_ENABLED=true** vérifié dans la configuration publiée de deliverNotificationPush et drainNotifications |
| API Android | fcm.googleapis.com et fcmregistrations.googleapis.com **ENABLED** |
| Planification | firebase-schedule-drainNotifications-europe-west1 **ENABLED**, toutes les minutes, dernière tentative sans erreur signalée |
| Sécurité HTTP | registerNotificationDevice, unregisterNotificationDevice et resolveNotification refusent les appels sans authentification : **401 UNAUTHENTICATED** |
| Pré-déploiement | **88/88** tests backend et vérification de syntaxe réussis |
| Application Android | APK réactualisé et recompilé avec succès, sans installation distante |

Le premier essai de création des déclencheurs a rencontré le délai de propagation du rôle de service Eventarc. Le rôle requis était présent ; une reprise ciblée des dix fonctions a réussi. L’option Firebase `--force` a servi à accepter les reprises automatiques des triggers idempotents. Aucun workflow métier ni paramètre SMTP/antivirus modifié. Les autres fonctions et l’hébergement Admin n’ont pas été redéployés.

Avant activation, lecture de contrôle : **0 notificationOutbox, 0 notificationJobs et 0 appareil enregistré** ; aucun ancien lot à envoyer. Aucun faux événement métier ou push de test créé dans les données de production.

APK pour le test : `build/app/outputs/flutter-apk/app-debug.apk` (188 872 194 octets), recompilé le 3 novembre 2026 à 18 h 24 (Paris). SHA-256 : `7aff87e28c81f0054e0901ecfedeb0517aea337ca86784279cdb789740d37816`.

Installer l’APK V9 sur Android, se connecter avec un compte vérifié, puis ouvrir **Paramètres > Notifications > Activer les alertes sur ce téléphone** et accepter l’autorisation Android. Mettre Foundi en arrière-plan puis faire envoyer un **nouveau message depuis l’autre compte**. Au premier plan, l’inbox est actualisée sans bannière locale en double. La réception physique n’a pas été vérifiée à distance : aucun téléphone n’était connecté par ADB.

Trace technique locale : `.dart_tool/v9-deployment-record.json`, journaux de déploiement et sauvegardes des règles/index sous `.dart_tool/`. Pour couper les envois, remettre NOTIFICATION_PUSH_ENABLED=false dans l’environnement du projet puis redéployer deliverNotificationPush et drainNotifications ; les notifications in-app restent disponibles.

Fichiers principaux : `functions/src/notification-policy.js`, `notification-service.js`, `index.js`, remplacement de la seule écriture legacy dans `professional-service.js` ; règles et index Firestore ; `lib/features/notifications/{domain,data,presentation}` ; intégration `main.dart`, hook de déconnexion Auth, shell/bandeau/réglages existants ; dépendances FCM/préférences et configuration Android/iOS ; tests unitaires/règles/intégration/widgets et configuration locale `firebase.v9.emulators.json`. Aucun changement aux règles de négociation, statuts métier, antivirus ou transport V8.2.

Références officielles vérifiées : [réception Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [configuration FCM Flutter](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [livraison des événements Firestore](https://firebase.google.com/docs/functions/firestore-events).
