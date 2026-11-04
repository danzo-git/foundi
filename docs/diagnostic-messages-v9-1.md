# Foundi V9.1 — affichage immédiat des messages texte

Travail local du 4 novembre 2026. Aucun déploiement, aucune installation sur téléphone et aucune écriture de test en production.

## Conclusion et portée de la preuve

La dépendance responsable de l'attente visuelle est identifiée : **aucune bulle n'était insérée localement**. La liste affichait uniquement les documents reçus par `watchMessages`. Avec une écriture par Cloud Function, le SDK Firestore du téléphone n'a pas d'écriture locale à projeter. L'apparition de la bulle dépendait donc du commit serveur puis du listener.

Cette dépendance a été reproduite **avant la correction**, après ajout de traces uniquement : dix réponses simulées retardées de 8 à 10 secondes retardent également l'affichage de 8 à 10 secondes. Le même scénario corrigé affiche chaque bulle à la première frame de test, sans accélérer artificiellement la confirmation.

Ce résultat ne mesure pas la latence Firebase de production. Le constat de 8 à 10 secondes vient de l'utilisateur. La part exacte de l'authentification, d'un éventuel démarrage de fonction, des lectures/transactions, du transport et du listener n'est pas mesurée sur téléphone. Aucun appareil Android/iOS n'était détecté par `flutter devices` : seulement Windows, Chrome et Edge. Aucun diagnostic de cold start, d'index manquant ou de latence interrégions n'est affirmé sans cette mesure.

## Parcours analysé avant modification fonctionnelle

1. `ConversationView._send` : vérification `busy`, `trim`, contrôle 1–2000 caractères, génération synchrone d'un document ID. L'ID était déjà réutilisé pour une relance tant que le brouillon ne changeait pas.
2. `AuthActionState.perform` : `setState(busy=true)` affiche une progression, **pas un message**. Puis attente de `sendConversationMessage`. Le champ de saisie restait désactivé jusqu'au résultat.
3. `FirebaseConversationRepository.sendConversationMessage` : appel HTTPS callable, sans écriture Firestore cliente et sans chargement explicite de profil, de token FCM ou de compteur de notifications. Les opérations internes Auth/transport du SDK ne sont pas chronométrées individuellement par ce code.
4. `conversation-service.send` : compte authentifié, actif et vérifié via `auth.getUser`, validation stricte des champs/type/longueur, transaction. Lectures attendues successivement : conversation, miroir privé de la demande, proposition liée, document du message existant. Les participants, liens et états métier sont contrôlés. La transaction écrit le message et l'aperçu/date de conversation atomiquement, ou réutilise le message existant si auteur/type/contenu correspondent exactement.
5. `watchMessages` : une requête stable, tri `createdAt DESC` puis document ID DESC, limite 30 puis pagination 60/90/100, `includeMetadataChanges:true`. Le listener de conversation est distinct et nécessaire à l'état métier. Pas de recréation de requête à chaque rebuild dans le code d'origine.
6. Le `StreamBuilder<MessageBatch>` construit les bulles seulement à partir des snapshots ; `RichMessageBody` affiche le texte sans attente réseau supplémentaire. Le champ de saisie n'était vidé qu'après succès du callable. Le snapshot peut arriver **avant** le retour HTTP : le problème n'est donc pas un ordre obligatoire « réponse HTTP puis snapshot ».

Formule du délai initial : **commit serveur + arrivée du snapshot + frame UI**, sans projection locale au tap. L'`await` du gestionnaire bloquait aussi le composeur, mais le flux Firestore restait indépendant de ce Future.

Les messages serveur utilisent un `createdAt` numérique attribué dans la transaction, strictement croissant à partir de `lastMessageAt`. Aucun `serverTimestamp` provisoirement nul ni filtre client sur `status` n'explique le problème observé. Les nouvelles bulles utilisent une date locale monotone jusqu'à leur remplacement par le document final ; le format serveur reste inchangé.

## Notifications V9

`index.js:361` déclenche `notifyMessageCreated` sur la **création du document final**. `notification-service.message` résout l'autre participant ; `emit` crée atomiquement la notification, le compteur et l'outbox avec un identifiant d'événement stable. La livraison FCM est une autre opération.

Aucun de ces traitements n'est attendu par `conversation-service.send`. Les notifications ne constituent donc pas une dépendance directe avant affichage/confirmation. Leur charge indirecte éventuelle en production reste non mesurée. La correction ne change ni les triggers V9, ni les badges, ni l'idempotence des notifications, ni leurs préférences.

## Correction

- `conversation_views.dart:377` : validation locale de conversation active/participant et texte ; insertion synchrone, effacement immédiat du composeur et positionnement sur la dernière bulle. Aucun `await` avant insertion. Les autres textes peuvent être composés pendant un envoi.
- `text_message_outbox.dart:44` : projection locale `sending`, libellé **Envoi en cours**, ID stable issu de `newMessageId`. Ce même `messageId` sert d'identifiant client de corrélation et de clé du document serveur ; aucun champ supplémentaire non autorisé n'est ajouté au payload.
- `text_message_outbox.dart:77` : **Envoyé** uniquement après retour réussi du callable validé, ou snapshot non cache et sans écritures en attente prouvant le commit. Un cache seul ne confirme jamais une projection en attente. Un retour réseau perdu après snapshot confirmé ne transforme pas le succès en échec.
- Échec : **Échec de l’envoi**, explication et **Réessayer** sur la bulle. Le réessai conserve ID et texte ; un garde interdit les relances concurrentes du même message. Un double tap ne retrouve pas le brouillon déjà vidé.
- `text_message_outbox.dart:124` : fusion par ID, une seule bulle après snapshot/réessai ; tri déterministe et remplacement de la projection par le document serveur. Les projections confirmées sont libérées après rapprochement.
- L'outbox est partagée dans la session pour le même repository/UID/conversation. Une opération continue quand la vue est fermée et reste consultable au retour. Les listeners sont conservés entre rebuilds, renouvelés seulement pour pagination/reprise/changement de contexte. Les données de l'ancien compte/chat sont réinitialisées au changement de contexte.
- L'erreur ou le chargement du listener ne masque plus les projections locales. Une reprise du listener ne renvoie pas les messages.

Les Security Rules, transactions, contrôles du compte, participants, intégrité des liens, statuts métier, idempotence et limites serveur sont conservés. Aucune écriture Firestore directe n'a été introduite. Photos, PDF, antivirus, upload, partage de contact, négociation V8.1 et notifications V9 gardent leurs chemins existants. Un fichier n'est pas présenté comme transmis avant sa vraie publication.

## Mesures avant/après

**Benchmark de widget Flutter en temps virtuel, pas mesure sur appareil réel.** Même jeu de dix délais serveur injectés : 8000/9000/10000 ms répétés. Première frame sondée toutes les 16 ms ; p95 par rang le plus proche (rang 10 pour n=10).

| Mesure | Avant correction | Après correction |
| --- | ---: | ---: |
| Nombre d'envois | 10 | 10 |
| Bulle locale, médiane | 9008 ms | 16 ms |
| Bulle locale, p95 | 10000 ms | 16 ms |
| Bulle locale, pire cas | 10000 ms | 16 ms |
| Confirmation simulée après correction, médiane / p95 / pire | — | 9008 / 10000 / 10000 ms |
| Confirmation Firebase réelle sur téléphone | non mesurée | non mesurée |
| Réception sur second téléphone | non mesurée | non mesurée |

La confirmation reste retardée de 8 à 10 secondes dans le test ; la bulle ne dépend plus de ce délai. L'objectif <200 ms est vérifié pour ce scénario contrôlé, **pas encore certifié sur téléphone**. Le compteur `Stopwatch` des traces utilise le temps réel du processus de test : ne pas le confondre avec les délais virtuels ci-dessus.

Résultats bruts et nature des mesures : `docs/mesures-messages-v9-1.json`. Journaux locaux : `.dart_tool/v91-baseline.log`, `v91-after.log`, `v91-targeted-final.log`.

## Tests exécutés

| Vérification | Résultat |
| --- | --- |
| `flutter test --no-pub --reporter expanded` | **96/96** |
| Tests ciblés finaux latence + réconciliation, après finalisation des traces | **9/9** |
| `npm --prefix functions test` | **90/90**, aucun ignoré |
| `npm --prefix functions run check` | réussi |
| `flutter analyze --no-pub` | **No issues found**, y compris après finalisation des traces (40,7 s) |
| `npm --prefix functions run test:v82:emulators` | **26/26** tests Rules + **8/8** tests d'intégration, aucun ignoré, code de sortie 0 |

Les huit nouveaux scénarios fonctionnels Flutter couvrent : première frame avant même le snapshot initial ; plusieurs envois et double tap ; réponses hors ordre ; ACK avant snapshot ; snapshot autoritatif avant erreur HTTP ; cache et metadata pending sans faux succès ; échec et double réessai avec ID stable ; confirmation tardive ; fermeture/retour à la vue ; panne et reprise du listener ; refus serveur et lecture seule ; séparation des comptes/chats. Le neuvième test mesure dix envois et conserve des confirmations volontairement lentes.

Les deux nouveaux tests backend vérifient l'ordre et le contenu limité des traces, l'absence de faux commit en cas de refus, et l'absence d'effet d'une panne du journal sur l'envoi et la déduplication.

La suite Firebase utilise uniquement **demo-foundi**, avec Auth/Firestore/Storage/Functions émulés. Elle vérifie A/B/C, interdiction de falsifier auteur/message/métadonnées, transactions concurrentes, décisions et historique V8.1, images/PDF/contact/texte V8.2, et vrais callables → triggers → inbox/compteurs V9. Les transports FCM injectés testent la déduplication/reprise/préférences ; ils ne prouvent pas une réception physique FCM. Les refus `PERMISSION_DENIED` attendus font partie des assertions. Les avertissements Java du runtime Rules surviennent pendant l'arrêt, après la sortie réussie des suites.

Les restrictions du bac à sable ont nécessité une relance autorisée des outils de test. L'environnement local du driver a été restauré après l'interruption initiale puis après la suite finale ; aucun secret factice ni backup temporaire de ce driver ne reste.

## Instrumentation et vérifications restantes

`message_send_trace.dart` journalise uniquement l'ID aléatoire du message, les étapes, tentative, métadonnées de cache et temps : T0 tap/entrée callback, T1 gestionnaire, T2 insertion locale, T3 début de l'opération callable, T4 accusé callable, T5 snapshot, T6 première frame construisant la bulle. T3 précède les opérations Auth/transport internes du SDK ; il ne prétend pas mesurer le premier octet réseau. La collecte est bornée et le contenu, UID, conversation et tokens ne sont pas journalisés. Debug actif ; profil/release sur demande avec `--dart-define=V91_TRACE=true`.

Le serveur instrumenté distingue S0 entrée, S1 compte validé, S2 payload validé, S3 lectures de chaque tentative transactionnelle, S4 retour après transaction et S_failed. Ces traces serveur sont **locales/non déployées**. R0/R1 permettent de corréler snapshot et frame construite sur l'autre appareil ; un élément construit dans le cache de la liste ne prouve pas sa visibilité dans le viewport. Vérifier visuellement la bulle en bas de conversation et synchroniser les horloges pour comparer deux appareils.

Limite de portée : l'outbox des textes non confirmés est en mémoire pour la session, sans nouvelle persistance de contenu privé. Elle survit à la navigation, **pas à un arrêt complet du processus**. Les messages déjà enregistrés sont restaurés par Firestore ; une conservation durable des brouillons/échecs après arrêt n'est pas ajoutée par cette correction.

Avant de considérer l'acceptation mobile complète : faire dix envois avant/après sur Android réel en debug puis profil, relever médiane/p95/pire cas pour affichage, ACK et réception sur un second téléphone. Refaire réseau ralenti/hors ligne, refus, réessai, double tap, retour au chat et séquences rapides. Vérifier FCM réel et compteurs indépendants. Le test refus serveur simulé et les vraies Rules émulées sont distincts de ce contrôle physique.

Après cette validation, soumettre le lot et les mesures à l'utilisateur pour accord explicite. Le changement client peut utiliser le callable existant ; le backend ne change que pour les traces. Aucune modification de Rules, d'index, de migration ou de configuration push n'est requise par V9.1. **Ne rien déployer sans cet accord.**

Les modifications V9 déjà présentes dans le workspace au début du travail sont conservées. Ce rapport et les résultats concernent le correctif d'affichage V9.1 ajouté par-dessus.
