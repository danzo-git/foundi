# Messagerie — déploiement du 16 novembre 2026

Déploiement explicitement autorisé par l’utilisateur pour les photos de profil sur les cartes et la suppression personnelle des conversations. Projet `foundi-7c837`, région `europe-west1`, branche `codex/foundi-sprint-2-5-finitions`.

Vérification finale : **16 novembre 2026 à 00 h 25, heure de Paris** (`2026-11-15T23:25:35.870Z`).

## Résultat

Les règles Firestore et les huit fonctions nécessaires sont déployées et vérifiées actives :

| Fonction | Révision vérifiée |
| --- | --- |
| `resolveConversationAvatars` | `resolveconversationavatars-00001-xud` |
| `syncConversationDeletion` | `syncconversationdeletion-00001-foz` |
| `notifyMessageCreated` | `notifymessagecreated-00005-biw` |
| `notifyConversationOpened` | `notifyconversationopened-00005-sax` |
| `resolveNotification` | `resolvenotification-00009-kiy` |
| `deliverNotificationPush` | `delivernotificationpush-00010-coh` |
| `drainNotifications` | `drainnotifications-00010-nup` |
| `deleteConversation` | `deleteconversation-00001-muq` |

La récupération des photos réutilise la photo de compte Foundi existante, uniquement pour les participants à la conversation. La suppression retire durablement la carte de la messagerie du demandeur, sans supprimer l’historique de l’autre participant ni modifier la proposition retenue. Les nouveaux messages ne rétablissent pas cette carte.

## Déploiement contrôlé

Les règles ont été publiées en premier. Leur comparaison avec la version précédente confirme que seuls les blocs de lecture personnelle `users/{uid}/deletedConversations/{id}` et `users/{uid}/conversationState/inbox` sont ajoutés. Les autres règles sont identiques après normalisation des fins de ligne. Les écritures SDK sur ces nouvelles données restent interdites.

Les sept services de photo, de nettoyage et de notification ont ensuite été déployés et vérifiés actifs. Le callable `deleteConversation` a été déployé seulement après cette vérification ; les dates de modification distantes confirment cet ordre.

Firebase exigeait l’option `--force` pour autoriser la politique de reprise du nouveau déclencheur. Cette option a été appliquée uniquement à la sélection explicite des sept services. Le déclencheur `syncConversationDeletion` écoute bien les écritures sur `users/{uid}/deletedConversations/{conversationId}` avec `RETRY_POLICY_RETRY`. Son traitement atomique et rejouable a été testé, notamment sur 450 messages non lus après interruption du client.

## Contrôles finaux

- Les 238 tests backend et les contrôles de pré-déploiement ont réussi avant chaque étape de déploiement des fonctions.
- Les 87 autres fonctions conservent leur révision, date de modification et compte de service. Le projet passe de 92 à 95 fonctions, avec trois créations et cinq mises à jour.
- Les paramètres de notifications push de `deliverNotificationPush` et `drainNotifications` sont conservés.
- L’index de nettoyage des messages était déjà `READY`. Aucun index ou politique de champ/TTL n’a été modifié.
- Catalogue public, configuration Authentication, configuration de stockage, règles Storage et politique de suppression du compte inchangés.
- `resolveConversationAvatars`, `deleteConversation` et `resolveNotification` refusent les appels anonymes avec HTTP 401 / `UNAUTHENTICATED`.
- Les lectures anonymes de marqueurs de suppression, d’état personnel de conversation et de documents privés de photo sont refusées avec HTTP 403.
- Aucune donnée de compte, conversation de recette ou suppression réelle n’a été créée ou exécutée en production par les contrôles. Les cas authentifiés, les règles propriétaire/tiers et les parcours complets sont validés par les tests Firebase locaux décrits dans les [cartes compactes](messagerie-cartes-compactes-2026-11-15.md) et la [suppression personnelle](suppression-conversations-2026-11-15.md).

## Application et traces

Le backend est prêt. Les photos sur les cartes et l’appui long nécessitent l’application contenant le code de ces deux évolutions. Aucun APK, Hosting ou texte juridique publié n’a été distribué par cette intervention.

Le script `functions/scripts/verify-messaging-deployment.cjs` contrôle les phases de préparation, de services prêts et de validation finale. Les états et résultats sont conservés dans `.dart_tool/messaging-deploy-before.json`, `messaging-deploy-plan.json`, `messaging-runtime-before.json`, `messaging-deploy-services-ready.json`, `messaging-deploy-after.json`, `messaging-deploy-verification.json` et les journaux `.dart_tool/messaging-*.log`, ignorés par Git.
