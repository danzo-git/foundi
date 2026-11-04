# Foundi V9.1 — badges séparés et push contextualisés

Implémenté et déployé le 4 novembre 2026 sur `foundi-7c837`, conformément à la demande explicite « déploie le nécessaire ». Le périmètre reste les deux correctifs demandés. L'affichage immédiat des messages V9.1 est conservé.

## Diagnostic de V9

Dans `notification-service.js`, `message()` passait par `emit()` : chaque message final texte/image/PDF/contact créait une entrée générale, incrémentait `notificationState/inbox` et créait une outbox FCM. La cloche affichait donc un compteur mixte. `deliver()` reprenait le titre/corps génériques du catalogue. Aucun curseur de lecture ni compteur de messages entrants n'existait ; ouvrir un chat ne marquait pas ses messages lus.

Le client conserve son listener Firestore de messages et son outbox optimiste validée. `NotificationPush` traite déjà `onMessageOpenedApp` et `getInitialMessage`, avec intention différée jusqu'à l'authentification puis résolution serveur. Au premier plan, la présentation FCM et les bannières locales sont désactivées ; le nouveau badge et le chat constituent la présentation des messages. Cette politique évite les doubles bannières.

## Schéma et droits

| Document | Rôle |
| --- | --- |
| `users/{uid}/messageInbox/{hash}` | Reçu serveur stable par message entrant : conversationId, messageId, senderUid, createdAt, unread. Aucun texte, numéro ou nom de fichier ; accès client interdit. |
| `users/{uid}/messageReads/{conversationId}` | Curseur serveur monotone `readThroughAt`, issu d'un message enregistré ; lecture propriétaire uniquement, écriture via callable validé. |
| `users/{uid}/messageState/inbox` | Total persistant de messages entrants non lus, commun aux modes client/pro ; lecture propriétaire, écriture serveur. |
| `notifications/{id}.isGeneral` | Vrai pour les événements métier, faux pour les anciens messages privés. Aucun ancien document ni `readAt` supprimé. |
| `notificationPreferences/push.messagePreview` | Booléen facultatif ; absent signifie **aperçu désactivé**. Les quatre préférences V9 restent valides. |
| Outbox privée | `kind=chat_message`, conversationId/messageId ; le contenu privé n'y est pas recopié. |

Le centre général interroge `isGeneral=true` et filtre défensivement les types `message.created` et `chat_message`. `conversation.opened` reste un événement métier général, dans « Discussions ». Les autres événements V9 sont conservés. Aucun workflow de fin de discussion absent du produit n'est inventé.

Les anciens clients restent compatibles avec les quatre préférences : réécrire un document sans `messagePreview` revient à masquer l'aperçu. Les nouveaux push gardent `notificationId` et `recipientUid`, avec `type=chat_message`, conversationId et messageId. `resolveNotification` sait résoudre une outbox privée sans entrée générale puis revalide le destinataire, les participants et le message. L'APK V9.1 est nécessaire pour le nouveau badge, le filtrage de l'historique général et le réglage d'aperçu.

## Compteurs et lecture

`notifyMessageCreated` crée transactionnellement le reçu du destinataire, l'incrément éventuel et l'outbox. L'identifiant stable rend les reprises idempotentes. Un message sortant ne compte pas pour son auteur et aucun push ne lui est adressé.

`markConversationRead` exige un compte actif/vérifié, vérifie le participant et le message cible, puis avance le curseur. Les reçus sont marqués lus et le compteur décrémenté dans une transaction, par pages bornées de 200, poursuivies par le repository si nécessaire. Le curseur empêche un trigger de création retardé de réincrémenter un message déjà lu. Deux appareils partagent ces états serveur, indépendamment du mode client/pro.

`ConversationReadTracker` agit **après la frame**, quand la conversation est active, la route visible, l'application au premier plan et la liste sur les messages récents. Une route recouverte, une application en arrière-plan ou un historique parcouru plus haut ne lit pas les nouveaux messages. Le retour visible/en bas relance la lecture. Une erreur réseau conserve le compteur serveur et fait réessayer pendant que la vue reste ouverte.

Le badge Messages écoute un seul document agrégé, affiche 1–99 puis `99+`, disparaît à zéro et fournit le total exact au lecteur d'écran. Son abonnement ne dépend pas du mode. Ouvrir uniquement l'onglet Messages ou la cloche ne lit aucune conversation. Les messages non lus dans les historiques encore autorisés restent comptés.

## Push et confidentialité

Au moment de livrer, le serveur relit le message enregistré et la conversation. Le titre utilise le nom professionnel actuel (`businessName`) ou le profil utilisateur (`fullName`), avec fallback « Un utilisateur Foundi ».

Avec `messagePreview=true`, le corps contient un aperçu de 100 graphèmes maximum, espaces/sauts de ligne normalisés et contrôles/bidi parasites retirés ; la troncature conserve les emoji. Les médias utilisent `📷 Photo`, `📄 Document PDF`, `📞 Contact partagé`. Aucun numéro partagé ni contenu/nom de fichier n'est transmis.

Sans aperçu : titre expéditeur, corps « Nouveau message ». `data` ne contient que des identifiants. La préférence est relue juste avant construction du push. `messages=false` coupe sa livraison, tout en conservant le message et son état non lu. Un message déjà lu est ignoré par la livraison différée. Les claims par appareil, tokens, reprises et protections V9 contre les doublons sont conservés.

Le réglage d'aperçu est distinct de la réception des push de messages et désactivé par défaut pour préserver la confidentialité des comptes existants. Après installation : **Paramètres → Notifications → Afficher l’aperçu des messages dans les notifications**.

## Migration conservant les historiques

`migrate-message-badges-v91.cjs` a été exécuté d'abord en lecture seule puis avec `--apply`. Il classe les entrées métier V9, exclut les anciens messages privés du général et retire leur contribution au compteur en réutilisant le reçu de décrément V9. Un ancien trigger, une lecture concurrente et une réexécution ne peuvent donc décrémenter deux fois. Les documents et leurs dates de lecture sont conservés.

Les messages historiques sont projetés sans déclencher de nouveaux push. Les lectures connues via `readAt` sont préservées. En l'absence d'état historique exploitable, le message est considéré prudemment non lu ; ouvrir effectivement le chat établit le curseur. Les curseurs créés entretemps sont respectés.

Audit initial : 14 notifications dont 11 privées, 18 messages. À l'application, un événement métier supplémentaire existait : **15 notifications conservées, 11 privées exclues, 1 événement général V9 classé, 18 messages historiques examinés**, aucun parent manquant, aucune ancienne outbox en attente à convertir. Les autres documents antérieurs à V9 restent conservés.

Audit transactionnel après migration : **aucun écart** entre compteurs et sources sur les trois comptes ayant des états de compteur ; instantané de 1 notification générale non lue et 8 messages privés non lus au total. Ces valeurs peuvent évoluer avec l'activité. Les sauvegardes de métadonnées n'exportent pas le contenu des messages.

## Tests et non-régression

| Vérification finale | Résultat |
| --- | --- |
| Suite Flutter complète | **102/102** |
| Suite ciblée finale badges/lecture | **6/6** |
| Backend, relancé aussi avant déploiement | **92/92**, aucun ignoré |
| Analyse Flutter | **No issues found** |
| Syntaxe backend et migration | réussie |
| Firestore/Storage Rules émulées | **27/27**, aucun ignoré |
| Intégrations Firebase émulées | **10/10**, aucun ignoré |
| Compilation APK Android debug | réussie, 244,8 s |

Couverture : A/B et A/C avec tiers D ; 3+2 messages et 2 événements métier ; lecture partielle, doubles triggers, deux lecteurs concurrents et restauration des états Firestore ; triggers retardés ; auteur exclu ; historiques en lecture seule ; badge 99+, UID et accessibilité ; route recouverte, arrière-plan et défilement ; refus des écritures frauduleuses et préférences mal typées. Push texte/photo/PDF/contact, aperçu activé/désactivé, refus de réception, absence de nom, texte long, accents/apostrophes/contrôles/emoji, destinataire révoqué, routage et déduplication. Migration dry-run puis deux applications émulées sans destruction ni vieux push.

Les suites conservent les parcours V8.1/V8.2/V9 : décisions, clôture, upload/quarantaine/annulation, confidentialité, tokens, préférences et vraie chaîne callable → triggers → états serveur. Un test maintient l'accusé de lecture bloqué pendant qu'un texte apparaît en « Envoi en cours ».

Le benchmark de dix envois conserve **16 ms médiane/p95/pire cas d'affichage local en temps virtuel**, avec confirmations simulées de 8–10 secondes. C'est une mesure de non-régression, pas une mesure sur téléphone. Le gestionnaire d'envoi et l'outbox optimiste V9.1 ne sont pas réécrits ; ils n'attendent aucune lecture, aucun compteur ni push.

Les essais initiaux d'émulateurs ont rencontré un port occupé puis un serveur de découverte bloqué. La relance sur les ports V9.1 dédiés 1420–1426 a terminé avec code 0. Les avertissements Java d'arrêt surviennent après les tests réussis. L'environnement local et les secrets factices du driver ont été restaurés/supprimés.

## Déploiement et APK vérifiés

Projet **foundi-7c837**, région **europe-west1** : règles publiées conformes au fichier validé ; **22 index READY**, dont quatre ajouts, aucun ancien index supprimé. Douze fonctions de notification mises à jour et `markConversationRead` créé : **13/13 ACTIVE**. `NOTIFICATION_PUSH_ENABLED=true` conservé sur `deliverNotificationPush` et `drainNotifications`. Les appels non authentifiés à `markConversationRead` et `resolveNotification` retournent **401**.

Fonctions ciblées : `notifyProfessionalDecision`, `notifyProposalCreated`, `notifyProposalDecision`, `notifyConversationOpened`, `notifyMessageCreated`, `notifyRequestPublished`, `notifyRequestClosed`, `countNotificationRead`, `runNotificationJob`, `deliverNotificationPush`, `drainNotifications`, `resolveNotification`, `markConversationRead`.

L'enregistrement des messages, les uploads, l'authentification, les paramètres antivirus/SMTP et l'hébergement Admin ne sont pas redéployés. Un premier filtre CLI sans groupe a été refusé avant modification des fonctions ; la reprise `functions:auth:<nom>` a abouti.

APK : `build/app/outputs/flutter-apk/app-debug.apk`, **165 640 747 octets**, `com.example.foundi`, version **1.0.1 (2)**, SDK minimal 24 / cible 36.

SHA-256 : `e1ce9d47ee0ac5ceb47b5428495a0ba578c93525a935c0ad221af6ea061e42ee`.

Traces locales sous `.dart_tool` : `v91-badges-state-before.json`, `v91-badges-state-after.json`, `v91-badges-migration-dry.json`, `v91-badges-migration-applied.json`, `v91-badges-counters-after.json`, `v91-badges-apk-record.json`, journaux de tests et déploiement correspondants.

Aucun téléphone n'est connecté à ADB. L'APK est compilé mais non installé à distance. La réception FCM physique, le démarrage Android par un vrai push et les vérifications iOS/APNs restent à faire sur appareils. Aucun faux message ou push de test n'a été créé en production.

## Fichiers concernés

- Backend : `notification-service.js`, `notification-policy.js`, export dans `index.js`, règles et index Firestore.
- Flutter : modèle/repository/vue de notifications, nouveau `conversation_read_tracker.dart`, badge dans `space_widgets.dart`, branchement du shell, suivi après frame dans `conversation_views.dart`.
- Validation : tests unitaires/Rules/intégrations, `message-badges-flow.test.cjs`, `message_badges_v91_test.dart`, attentes V9/V8.2 adaptées, driver/config d'émulateurs V9.1, scripts de migration et d'audit.

Les modifications V9 et l'optimisation de performance déjà présentes dans le workspace sont conservées.
