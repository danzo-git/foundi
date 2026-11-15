# Suppression personnelle des conversations — 15 novembre 2026

## Parcours

Les clients et les professionnels peuvent maintenir une carte de conversation pour ouvrir le menu « Supprimer la conversation ». Un second écran demande confirmation. Annuler conserve la carte ; une suppression non confirmée par le serveur conserve l’affichage et permet de réessayer. Une progression remplace la date pendant l’opération.

Conformément au choix de l’utilisateur, la conversation reste supprimée de sa propre messagerie : de nouveaux messages ne la font pas réapparaître. L’autre participant garde son historique et peut supprimer sa propre entrée indépendamment. La demande, la proposition retenue et les messages partagés ne sont pas supprimés ni modifiés par cette action. Le dialogue l’explique explicitement.

La suppression est synchronisée entre les appareils utilisant cette version de l’application. Les suppressions des conversations récentes ne masquent pas accidentellement les conversations plus anciennes : la liste parcourt les pages nécessaires pour afficher jusqu’à 30 conversations visibles. Le menu et la confirmation restent utilisables en 320 × 568 px avec une taille de texte de 180 %.

## Serveur et données

- `deleteConversation` vérifie le compte actif et vérifié, son appartenance à la conversation et la concordance du compte qui avait ouvert la confirmation. Le champ `viewerUid` est une précondition de compte, jamais une autorisation : il doit correspondre à l’identité authentifiée. Un administrateur extérieur à la conversation n’obtient pas de droit de suppression supplémentaire.
- Le marqueur privé `users/{uid}/deletedConversations/{conversationId}` conserve la date initiale et l’état de nettoyage. Il n’est pas accessible à l’autre participant ni modifiable par le SDK client. La répétition d’une suppression ne change pas la date initiale.
- `users/{uid}/conversationState/inbox` porte une révision de visibilité propre au compte. La liste observe cette révision et ses conversations récentes. Chaque requête de conversations et de marqueurs est limitée à 30 documents ; les pages suivantes complètent la liste après filtrage. Les résultats obsolètes sont ignorés lors d’un changement de compte, d’onglet ou de version.
- Les messages non lus de cette conversation sont retirés du compteur personnel par transactions de 200 éléments au maximum. Les compteurs des autres conversations et de l’autre participant sont préservés. Le nouveau déclencheur `syncConversationDeletion` poursuit le nettoyage à partir du marqueur persistant si l’application s’arrête après la première page. Chaque page et son compteur sont atomiques et rejouables.
- Les nouveaux événements de message et les notifications tardives d’ouverture de conversation ignorent la conversation supprimée pour cet utilisateur. Les anciens liens de notification deviennent indisponibles. La livraison des push relit le marqueur avant envoi ; une notification déjà confiée au fournisseur ne peut pas être rappelée, mais ne rétablit pas la carte dans l’application.
- Le marqueur est permanent tant que le compte existe. La suppression complète du compte reste le parcours distinct existant : son nettoyage récursif de `users/{uid}` efface ces marqueurs. Le travail de fond vérifie le cycle de vie du compte et ne recrée pas son arborescence pendant l’effacement.

## Vérifications

- 238 tests backend réussis, dont huit tests de suppression : portée personnelle, sécurité, compte changé, réessai, historique en lecture seule, plus de 200 non lus, échec atomique et effacement du compte.
- Suite Flutter complète : 237 tests réussis. Après l’ajustement du menu défilable pour petit écran, huit tests ciblés de suppression réussis, dont un cas supplémentaire en 320 × 568 px et texte agrandi.
- Analyse Flutter complète : aucun problème signalé ; les deux fichiers ajustés ensuite ont également fait l’objet d’un contrôle ciblé.
- Contrôles serveur et scripts : réussis.
- Quatre scénarios Firebase locaux réussis : règles d’accès et suppression personnelle, véritable callable et poursuite automatique du nettoyage de 450 messages, non-régression des badges et livraison privée, migration des anciens badges. Le service de messagerie FCM des tests de livraison est simulé ; aucun push réel n’a été envoyé. Le projet utilisé par les vrais callables est exclusivement `demo-foundi`.

Traces dans `.dart_tool/conversation-deletion-*.log`. Le lanceur d’émulateurs a terminé avec le code 0 et restauré l’environnement local. L’avertissement Java d’arrêt du moteur de règles est postérieur à la réussite des essais.

Captures des widgets Flutter avec le thème Foundi et des données fictives :

- [Menu après appui long](sprint-2-5-captures/messagerie-menu-suppression.png)
- [Confirmation de la suppression personnelle](sprint-2-5-captures/messagerie-confirmer-suppression.png)

## Mise en service

Les fonctions et les règles nécessaires ont été déployées après autorisation explicite et vérifiées le 16 novembre 2026 à 00 h 25, heure de Paris. Voir le [compte rendu de déploiement](deploiement-messagerie-2026-11-16.md). Aucun APK n’a été distribué.

Les règles de lecture personnelle de `deletedConversations` et `conversationState` ont été publiées en premier. `notifyMessageCreated`, `notifyConversationOpened`, `resolveNotification`, `deliverNotificationPush` et `drainNotifications` ont été mis à jour, avec création de `syncConversationDeletion` et `resolveConversationAvatars`. Le callable `deleteConversation` a été activé en dernier. La distribution de l’application mise à jour reste soumise à autorisation.

Aucun nouvel index n’est ajouté : le nettoyage utilise l’index existant de `messageInbox` sur `conversationId`, `unread` et `createdAt`. Aucun catalogue, rôle professionnel, règle Storage, politique de suppression de compte ou donnée de production n’est modifié par cette livraison locale.
