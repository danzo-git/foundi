# Correctif — notifications des décisions de modération

**Amélioration suivante publiée côté serveur :** les avis identifient désormais le contenu concerné et le dossier peut être réexaminé pour une nouvelle décision. L’interface Admin est compilée, en attente d’accord pour publication. Voir [les détails, tests et captures du réexamen](sprint-1-reexamen-contenu.md) ; les informations ci-dessous décrivent la première correction des notifications.

Le retour de recette du 13 novembre 2026 a révélé deux manques : seul l’avertissement créait un texte dans les paramètres ; aucune décision ne créait de notification standard ou de push. De plus, le contrôle des comptes suspendus empêchait leur livraison.

## Comportement corrigé

- Avertissement, masquage public, suspension et levée de ces mesures créent un avis privé, une notification dans la cloche et un élément de la file push.
- Ces écritures et la décision sont dans la même transaction Firestore. Une décision refusée ne crée rien ; les réessais avec le même identifiant ne doublent ni notification ni compteur.
- Le destinataire est l’auteur du contenu résolu côté serveur. Aucun signalant, commentaire, preuve, identifiant de dossier ou motif privé de décision n’est transmis dans le texte ou le push. Le lien d’événement est une empreinte opaque.
- Le push utilise les appareils déjà enregistrés et les préférences de la catégorie Compte. L’autorisation système et un token FCM valide restent nécessaires. L’avis dans l’application est conservé même si le push est désactivé.
- Pour les comptes suspendus, seules les notifications liées à un avis de modération serveur authentique peuvent contourner le filtre de suspension lors de la livraison/résolution. Un simple type `safety.suspended` ou une catégorie `account` ne suffit pas. Un compte désactivé dans Firebase Auth reste exclu.
- Les règles autorisent la lecture de ses propres avis et de sa boîte de notifications, ainsi que le passage à lu, pendant une suspension. Elles n’ouvrent aucun accès aux discussions, profils, appareils ou données des autres membres. Les autres opérations serveur restent bloquées.
- Les anciennes décisions ne sont pas rejouées automatiquement. Le correctif concerne les décisions prises après sa publication ; répéter un ancien identifiant reste un réessai sans effet.

## Sens du statut d’examen

`take` signifie qu’un administrateur commence l’analyse et devient le référent indiqué dans le dossier. Le dossier passe de Nouveau à En cours d’examen, avec révision et audit. C’est un suivi interne : aucune sanction et aucune notification à l’utilisateur signalé. Les autres administrateurs habilités peuvent toujours examiner et décider ; ce n’est pas un verrou exclusif. Une deuxième prise en charge est refusée ; la décision finale reste possible.

Le code Admin remplace « Prendre en charge » par « Commencer l’examen » et explicite l’absence de sanction. Les dialogues indiquent quelles décisions notifient et rappellent que la justification reste privée.

## Périmètre client

La cloche existante affiche les nouveaux titres et textes reçus du serveur lorsque le compte peut charger son interface. Le code mobile ajoute l’ouverture des avis et de l’assistance depuis un push, ainsi que le libellé « Compte et sécurité » dans les préférences. Il ajoute aussi un accès « Avis de modération et aide » aux erreurs de chargement du compte et du dossier professionnel : un membre suspendu peut ainsi consulter sa décision sans que les règles autorisent à nouveau ses activités.

Cette navigation détaillée et l’accès depuis une erreur de chargement nécessitent une mise à jour future du client. Un ancien client ne connaît pas la destination `safetyNotice` et peut afficher son message de contenu indisponible après un clic ; après suspension, il peut également rester sur son écran habituel de compte indisponible. Le push système ne dépend pas de cette mise à jour. Aucun accès métier n’est rouvert pour contourner cette limitation de l’ancien client.

Aucun APK n’est généré ou distribué. Les changements de libellé Admin restent locaux tant que le client Admin n’est pas publié.

## Validation et publication

Validation finale : **168 tests Node**, **179 tests Flutter complets**, **12 tests Admin**, **36 tests de règles** et **22 tests d’intégration Firebase Emulator**, tous réussis. Les deux analyses statiques Flutter ne signalent aucun problème. La livraison FCM est testée avec un transport simulé sur Firestore Emulator ; aucun faux signalement, compte, sanction ou push de test n’est créé en production.

Les contrôles portent notamment sur les trois sanctions, les restaurations, l’unicité des avis et compteurs, le refus d’une deuxième prise en charge, l’anonymat, le blocage de l’admin par le destinataire, le respect des préférences, le compte Firebase Auth désactivé, les fausses notifications, l’isolation entre utilisateurs et le refus des notifications ordinaires mises en attente avant la suspension.

La dernière passe Flutter couvre aussi les erreurs de chargement du profil de compte et du dossier professionnel : dans les deux cas, les avis et l’aide restent accessibles sans revenir aux activités de l’application.

Publication serveur **terminée et vérifiée** sur `foundi-7c837`, région `europe-west1`, dans le périmètre déjà autorisé :

1. `deliverNotificationPush`, `drainNotifications`, `resolveNotification`, `listSafetyNotices` mis à jour avec succès.
2. Règles Firestore publiées ; lecture distante identique au fichier local.
3. `decideSafetyReport` mis à jour après les mécanismes de livraison et les règles.
4. **76 Functions ACTIVE**, dont les cinq ci-dessus avec une empreinte renouvelée ; les 71 autres empreintes sont inchangées. Paramètres applicatifs, secrets, compte de service, runtime et limites d’exécution préservés.
5. **6 contrôles HTTP** réussis : refus 401 des trois callables modifiés sans authentification, refus 401 de l’accès aux pièces de preuve et deux prévols CORS 204. Aucune donnée métier ni notification réelle créée pour ces contrôles.
6. Règles Storage inchangées et identiques à la source locale ; purge quotidienne toujours ENABLED. Les index/TTL ne nécessitent aucun changement pour ce correctif.

La CLI a retiré la métadonnée de signature HTTP explicite par défaut de deux callables (`decideSafetyReport`, `resolveNotification`), sans modifier les paramètres applicatifs. Les contrôles HTTP confirment le protocole callable et le refus JSON `UNAUTHENTICATED` ; les autres métadonnées comparées sont conservées. Les sauvegardes avant publication, empreintes et vérifications restent privées dans `.dart_tool/sprint1-moderation-*`.

Captures de vrais widgets Flutter avec données fictives de test, et non de comptes de production :

- [Dossier en cours d’examen](sprint-1-securite-captures/11-admin-examen-en-cours.png).
- [Avis de modération et accès à la contestation](sprint-1-securite-captures/12-notification-moderation.png).

## Publications clientes restant à valider

1. Publier Foundi Admin pour rendre visibles « Commencer l’examen », « En cours d’examen » et les explications des décisions. Cette publication Hosting n’a pas été effectuée.
2. Après accord explicite sur la livraison mobile, préparer une version de recette incluant la destination des avis et les accès d’assistance lorsque le compte ne charge plus. Aucun APK n’a été produit pour ce correctif.
3. Valider sur un téléphone de recette les permissions système, la préférence Compte, le push des trois sanctions et l’ouverture des avis après suspension. Les tests actuels vérifient l’appel FCM simulé, pas la réception matérielle par un téléphone de production.

La liste complète des fichiers du sprint et de ce correctif est dans [l’inventaire](sprint-1-fichiers.md). Ce correctif a d’abord été validé et déployé depuis l’arbre local, puis intégré au commit de clôture du Sprint 1.
