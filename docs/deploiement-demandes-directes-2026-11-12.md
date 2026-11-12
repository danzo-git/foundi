Le déploiement des demandes directes privées a été autorisé puis réalisé sur le projet `foundi-7c837`, dans la région `europe-west1`, codebase `auth`.

Vérification finale : 12 novembre 2026 à 02:44:35 (Europe/Paris).

Les règles Firestore publiées correspondent exactement au fichier local validé, après normalisation des fins de ligne. Leur empreinte SHA-256 est `4e644deda705399623b17097b709c23a867a18467472705a097614be61667311`. Le nouvel index `directRequests` est à l’état **READY**, sur `directProfessionalId` croissant, `status` croissant et `createdAt` décroissant. Les 22 index précédents sont conservés ; le projet compte maintenant 23 index composites.

Les 13 fonctions concernées sont actives : deux créations et onze mises à jour. Les 46 autres fonctions existantes n’ont pas changé de révision. Le paramètre `NOTIFICATION_PUSH_ENABLED=true` est conservé pour la livraison et le drainage des notifications.

| Fonction | Opération | État | Révision |
| --- | --- | --- | --- |
| `publishDirectRequest` | Création | ACTIVE | `publishdirectrequest-00001-poh` |
| `notifyDirectRequestCreated` | Création | ACTIVE | `notifydirectrequestcreated-00001-pay` |
| `publishRequest` | Mise à jour | ACTIVE | `publishrequest-00007-qux` |
| `manageRequest` | Mise à jour | ACTIVE | `managerequest-00008-miy` |
| `proposalAccess` | Mise à jour | ACTIVE | `proposalaccess-00002-vir` |
| `sendProposal` | Mise à jour | ACTIVE | `sendproposal-00002-yil` |
| `selectProposal` | Mise à jour | ACTIVE | `selectproposal-00003-rem` |
| `uploadRequestPhoto` | Mise à jour | ACTIVE | `uploadrequestphoto-00003-dop` |
| `readRequestPhoto` | Mise à jour | ACTIVE | `readrequestphoto-00002-zib` |
| `readRequestRecommendation` | Mise à jour | ACTIVE | `readrequestrecommendation-00002-tap` |
| `resolveNotification` | Mise à jour | ACTIVE | `resolvenotification-00005-fum` |
| `deliverNotificationPush` | Mise à jour | ACTIVE | `delivernotificationpush-00005-rav` |
| `drainNotifications` | Mise à jour | ACTIVE | `drainnotifications-00005-fim` |

Les règles et l’index ont été déployés en premier. Le déclencheur de notification et les fonctions de réception, de réponse, de photos et de résolution ont ensuite été publiés et vérifiés. `publishDirectRequest` a été activée en dernier, après disponibilité de ces composants. Les comptes de service de la nouvelle publication et du nouveau déclencheur correspondent à ceux des fonctions existantes équivalentes.

Les hooks de prédéploiement ont exécuté avec succès les 122 tests serveur et les vérifications syntaxiques. La dernière validation locale comprenait aussi 148 tests Flutter, une analyse sans anomalie et quatre tests exécutés en émulateur. Le déploiement n’a introduit aucune modification du code métier.

Les trois points d’entrée `publishDirectRequest`, `proposalAccess` et `resolveNotification` ont été appelés sans authentification par leurs adresses Firebase utilisées par les clients. Tous répondent HTTP **401 UNAUTHENTICATED**. Ces contrôles ne créent aucune demande et n’envoient aucune notification à un professionnel. La confidentialité entre comptes avait été vérifiée en émulateur avec les règles identiques à celles publiées ; aucune recette authentifiée impliquant des utilisateurs réels n’a été lancée en production.

La CLI a nécessité un délai de découverte local de 120 secondes et une relance de communication locale. Le mode de reprise déjà prévu pour le nouveau déclencheur idempotent a été confirmé sur le déploiement ciblé. Ces ajustements concernent la commande de déploiement et ne modifient pas la configuration métier de l’application.

Les états avant et après sont conservés dans `.dart_tool/direct-deploy-before.json` et `.dart_tool/direct-deploy-after.json`. Les journaux de référence sont `.dart_tool/direct-deploy-firestore.log`, `.dart_tool/direct-deploy-index.log`, `.dart_tool/direct-deploy-functions-prerequisites-final.log`, `.dart_tool/direct-deploy-publish-retry.log` et `.dart_tool/direct-deploy-after.log`.

Le contrôle se reproduit en lecture seule avec `node functions/scripts/verify-direct-requests-deploy.cjs --before .dart_tool/direct-deploy-before.json --output .dart_tool/direct-deploy-after.json`.

Aucun APK n’a été généré ou distribué. Aucun déploiement Hosting ni changement des règles Storage n’a été réalisé. Le parcours peut maintenant être testé avec la version Flutter à jour : nouvelle demande privée depuis un profil, réception par le professionnel, notification, réponse et consultation réservée aux deux participants.
