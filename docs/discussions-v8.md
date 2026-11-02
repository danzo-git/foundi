# Foundi V8 — Choix d'une proposition et discussions privées

V7 validé committé et poussé sur `origin/codex/foundi-v7-propositions`, commit `a75bbd4`. V8 développé sur la nouvelle branche `codex/foundi-v8-selection-messages`. Le dernier message utilisateur autorise le déploiement Firebase nécessaire aux tests sur téléphone ; aucun changement Jira, Hosting ou Store n'est prévu.

## Audit et décisions

Réutilisés : `FoundiRequest`, `Proposal`, leurs repositories et composants ; le shell et la barre V4 ; `ProfessionalProfile.status` ; les fonctions Node 22, génération 2, région `europe-west1` ; Firestore public `requests`, historique privé `userRequests/{uid}/items`, propositions privées et registre propriétaire V7.

V7 ne contenait ni conversation ni message ; l'onglet Messages était une fonctionnalité absente. La sélection n'existait pas et les demandes ne connaissaient que `published`, `closed`, `deleted`. La propriété d'une proposition est déjà fiable : ses UIDs et sa demande ont été attribués par le serveur V7. La sélection vérifie aussi l'instantané privé de l'auteur ; aucune migration ni recherche globale de propriétaires n'est nécessaire pour V8.

Plan exécuté : sélection transactionnelle et confirmation ; conversation liée et onglet Messages ; envoi de texte contrôlé côté serveur et lecture temps réel ; règles, tests à plusieurs comptes et non-régression ; déploiement ciblé après validation locale.

Les neuf maquettes PNG fournies servent de référence UI/UX, adaptées aux composants Flutter actuels. Aucun contenu fictif de la planche n'est codé dans les écrans connectés.

## Sélection atomique

`selectProposal({requestId, proposalId})` : compte authentifié, actif et vérifié ; proposition appartenant à la demande et au client courant ; auteur distinct du professionnel ; demande et miroir auteur `published` ; proposition `sent` ; profil professionnel `approved` lu dans la transaction.

Une transaction lit d'abord proposition, demande publique, miroir privé, conversation déterministe, profil utilisateur et profil professionnel. Puis elle écrit ensemble :

- Demande publique : seulement le statut `in_discussion` et la date de mise à jour, en conservant les champs publics. Aucun UID de participant ni identifiant de conversation n'est ajouté au public.
- Miroir privé auteur : `status: in_discussion`, `selectedProposalId`, `selectedProfessionalUid`, `conversationId`, `updatedAt`. Le compteur et les autres champs sont conservés.
- Proposition choisie : `status: selected`, `conversationId`, `selectedAt`. Les autres propositions restent `sent` et consultables ; elles ne sont pas rejetées automatiquement.
- `conversations/{requestId}` : une conversation déterministe unique avec `requestId`, `selectedProposalId`, `clientUid`, `professionalUid`, `participantUids`, noms d'affichage, titre et instantané des seuls champs publics de la demande, `status: active`, dates et aperçu du dernier message.

Le même choix répété renvoie la conversation existante, sans nouvelle écriture. Un choix différent est refusé avec `already-exists`. Une répétition de la sélection initiale après clôture peut seulement retrouver la conversation historique : elle ne réouvre rien. Une demande clôturée sans sélection antérieure ne peut pas être choisie.

Les lectures précèdent les écritures et aucun effet externe n'est exécuté dans le callback transactionnel, suivant la [documentation des transactions Firestore](https://firebase.google.com/docs/firestore/manage-data/transactions).

## Compatibilité FOUN-40 et FOUN-52

La demande En discussion quitte automatiquement Explorer et Pour moi, qui ne lisent que `published`. Les nouvelles propositions sont déjà refusées par le contrôle V7 exigeant ce statut ; aucun assouplissement des permissions professionnelles.

Le propriétaire retrouve En discussion et la discussion dans Mes demandes. L'édition reste réservée à `published`. La clôture et la suppression FOUN-40 sont étendues au nouvel état sans réouverture ni clôture automatique. Elles passent la conversation en `read_only` dans la même transaction et actualisent le statut de son instantané de demande. L'historique des messages et propositions est conservé pour les parties ; tout nouvel envoi est refusé.

Depuis la conversation, le détail lié réutilise `RequestContent` avec l'instantané privé de champs publics. Ainsi le professionnel choisi peut consulter le contexte alors que la fiche n'est plus publique, sans obtenir le profil privé ou les coordonnées de l'auteur.

## Messages et confidentialité

`sendConversationMessage({conversationId, messageId, text})` vérifie compte actif/vérifié, appartenance au couple client/professionnel, conversation active et demande privée toujours En discussion avec la même sélection. Texte trimé de 1 à 2000 caractères ; champs supplémentaires refusés. Le serveur attribue `senderUid` depuis l'authentification et l'horodatage, jamais depuis le payload.

Une transaction crée le message et actualise l'aperçu privé (120 caractères) et les dates de conversation. Les timestamps restent des nombres de millisecondes issus du serveur, comme V5–V7. Le timestamp de message augmente strictement par conversation, même si les horloges coïncident. Un identifiant de message stable pour une tentative rend la nouvelle tentative idempotente ; même ID avec un autre auteur ou texte : refus.

Les clients **n'écrivent aucun message directement dans Firestore**. Les règles refusent toute création, modification ou suppression directe de conversation/message, y compris la falsification de `senderUid`. L'unique création autorisée est la callable, qui impose l'identité et met à jour les métadonnées atomiquement. Il n'y a donc pas de bulle d'écriture locale Firestore considérée à tort comme un succès serveur. L'interface attend la réponse de la fonction, garde le texte et l'identifiant en cas d'échec et déduplique les nouvelles tentatives. Un message déjà committé mais dont la réponse est perdue peut apparaître dans le flux serveur ; sa répétition n'en crée pas un deuxième.

La lecture utilise les [listeners temps réel Firestore](https://firebase.google.com/docs/firestore/query-data/listen). Un historique reçu du cache est indiqué comme tel. Les messages sont affichés chronologiquement, les plus récents en bas. Première requête de 30 messages, élargissable à 60, 90 puis 100 ; la limite de 100 est affichée. Les messages plus anciens sont persistés mais leur pagination au-delà de cette limite n'est pas implémentée dans V8. Les listes de conversations sont limitées aux 30 activités les plus récentes.

Les règles prouvent que le lecteur est `clientUid` ou `professionalUid`, même pour les listes. Les requêtes de conversations filtrent explicitement ce champ selon le contexte ; celles des messages ciblent la sous-collection d'une conversation autorisée. Les limites sont obligatoires : 50 au plus pour les conversations, 100 pour les messages. Cela respecte le principe selon lequel les [règles ne filtrent pas les résultats d'une requête](https://firebase.google.com/docs/firestore/security/rules-conditions).

L'approbation est exigée au moment du choix. La participation à une discussion existante ne dépend pas du mode Client/Professionnel : seules l'identité du participant, l'activité de la conversation/demande et la validité du compte sont vérifiées à l'envoi. Un profil professionnel avec historique conserve Mes clients, y compris après suspension du dossier ; le compte désactivé ne peut pas envoyer.

## Parcours UI

Confirmation en feuille basse, possibilité d'annuler avant toute écriture, garde contre double clic, vrai résultat d'erreur. Au succès : C'est confirmé, En discussion, Ouvrir la discussion et Retour à mes demandes. Une proposition déjà sélectionnée ouvre la conversation ; les autres sont en lecture seule.

Messages : Mes recherches pour les demandes dont le compte est auteur, Mes clients pour ses sélections comme professionnel. Le mode actif détermine seulement le contexte initial. État vide explicatif avant choix, listes réelles, nom de l'interlocuteur, demande et aperçu privés, accès au détail lié et retour. Saisie texte, réception live, chargement d'historique borné, cache, erreurs et lecture seule. L'en-tête se compacte lorsque le clavier est ouvert sur petit écran.

Aucune notification, paiement, appel, pièce jointe, annulation/re-sélection, accusé de lecture, média ou nouvel écran Explorer.

## Fichiers et index

- `functions/src/conversation-service.js` : sélection et envoi ; exports `selectProposal` et `sendConversationMessage` dans `functions/src/index.js`.
- `functions/src/request-service.js` : compatibilité clôture/suppression En discussion et archivage atomique de la conversation.
- `firestore.rules` : nouvelles conversations et messages privés, toutes mutations réservées au serveur.
- `firestore.indexes.json` : seulement deux nouveaux composites `conversations(clientUid ASC, updatedAt DESC)` et `(professionalUid ASC, updatedAt DESC)`. Les messages utilisent l'index simple existant sur leur date. Index V5/V6/V7 conservés.
- `lib/features/conversations/{domain,data,presentation}` : modèles, repository Firebase et vues sélection/liste/discussion.
- Modèles et adaptateur `FirebaseRequestRepository`, détail des propositions, cartes privées et shell : points d'entrée V8 ; les interfaces injectées V3–V7 restent compatibles.
- Tests `conversation-service.test.js`, `conversations.test.cjs` (règles), `conversation-flow.test.cjs` (intégration) et `conversations_v8_test.dart`.

## Validation locale et limites

`node.exe --test functions/test/*.test.js` : **63 réussis**. Les cinq scénarios serveur V8 couvrent choix unique/idempotent, choix concurrents, tiers et statuts refusés, messages des deux participants et falsifications, compatibilité clôture/suppression et blocage des nouvelles propositions.

Emulator Suite : **17 tests de règles réussis** ; **4 intégrations réussies**, dont V8 avec deux participants et un professionnel non sélectionné, sélection concurrente, listeners live des deux côtés, envois répétés, reconnexion dans une nouvelle instance Firebase, confidentialité et historique après clôture/suppression. Les trois intégrations antérieures (validation professionnelle, V7, demandes V5/V6) passent également.

La première exécution parallèle a échoué lors du démarrage d'un worker Functions par manque de mémoire, avec erreur HTTP 415 consécutive. Elle n'est pas comptée comme réussie. La relance complète réussie a utilisé `JAVA_TOOL_OPTIONS=-Xmx512m`, `NODE_OPTIONS=--max-old-space-size=384` et `--inspect-functions=12999`, qui sérialise les fonctions sur l'émulateur. Les requêtes concurrentes sont soumises par le test, mais cette passe n'est pas un test de charge multi-instance ; l'unicité s'appuie sur la transaction Firestore et les tests métier. L'exception Java connue du runtime Storage à l'arrêt survient après le succès de la suite et son code de sortie 0.

Validation finale Flutter : **66 tests réussis**, dont cinq tests V8 (sélection confirmée et erreurs, contextes, échange et reprise idempotente après réponse perdue, historique borné, petit écran avec clavier). **Analyse Flutter sans problème**. Les tests sont exécutés avec `--concurrency=1` pour limiter la mémoire. Une première passe a détecté un débordement de 12 pixels avec le clavier sur 320 × 568 : corrigé par un en-tête compact fondé sur la hauteur réellement disponible, puis test et suite complète repassés. Les premiers avertissements de style et deux collisions de champs dans la simulation de tests ont également été corrigés. Aucun test sur appareil physique ni création de données de démonstration en production.

## Déploiement et vérification en production — 2 novembre 2026

Déploiement ciblé terminé avec code de sortie 0 sur `foundi-7c837` :

```text
firebase deploy --project foundi-7c837 --only functions:auth:selectProposal,functions:auth:sendConversationMessage,functions:auth:manageRequest,firestore:rules,firestore:indexes --non-interactive
```

État vérifié après déploiement :

| Fonction | État | Révision |
| --- | --- | --- |
| `selectProposal` | ACTIVE | `selectproposal-00001-xis` |
| `sendConversationMessage` | ACTIVE | `sendconversationmessage-00001-mom` |
| `manageRequest` | ACTIVE | `managerequest-00002-ban` |

Les fonctions antérieures `sendProposal` et `listOpportunities` sont toujours ACTIVE. Les deux index de conversation sont READY : `clientUid` / `updatedAt` (`CICAgJiH2JAK`) et `professionalUid` / `updatedAt` (`CICAgJiUsZIK`).

Les règles publiées correspondent exactement au fichier local après normalisation des fins de ligne : ruleset `7d073ac3-1846-4bef-9430-28f3c332484a`, SHA-256 `8af833524696a458d4de22c012343aaefefde9c229327e7fe95190e8a767f381`.

Contrôles réels en production, sans écriture : les requêtes privées administratives des deux contextes et de l'historique sont exécutables avec les index publiés ; les deux callables refusent un appel anonyme avec HTTP 401 / UNAUTHENTICATED ; les lectures anonymes d'une conversation, d'un message et d'une liste de conversations sont refusées avec HTTP 403. Ces contrôles de requêtes administratives ne démontrent pas les permissions d'un participant : celles-ci ont été testées avec les comptes distincts dans l'Emulator Suite.

Non-régression Explorer en production : les six combinaisons sans filtre, catégorie, zone, catégorie + zone, catégorie + spécialité, catégorie + spécialité + zone renvoient HTTP 200 et les résultats publics attendus. Résultat vide vérifié ; demandes clôturées, supprimées et requête sans condition de statut refusées avec HTTP 403. Les six index publics existants sont READY. Aucun enregistrement utilisateur, demande, proposition, conversation ou message de test n'a été créé en production.

Le choix et l'échange positifs entre deux comptes restent à essayer sur le téléphone avec les données souhaitées par l'utilisateur ; ils ont été validés sur émulateurs, pas sur appareil physique. Aucun déploiement Hosting ou Store.

## Recette sur téléphone

Utiliser l'application compilée depuis la branche V8, sans `USE_FIREBASE_EMULATORS=true`. Avec A auteur et B/C professionnels approuvés :

1. A publie une demande ; B et C envoient des propositions via le parcours V7.
2. A consulte les propositions reçues, ouvre celle de B, puis confirme Choisir ce professionnel. Aucun paiement ni fin de prestation.
3. La demande est En discussion ; B est Choisi, C reste lisible, aucun second choix ni nouvel envoi de proposition n'est permis.
4. A ouvre la discussion et écrit ; B retrouve la conversation dans Messages → Mes clients et répond. A la retrouve dans Mes recherches.
5. Fermer/réouvrir les applications ; vérifier l'historique et les nouveaux messages sans actualisation manuelle. C ne doit pas accéder à cette conversation.
6. Si A clôture la demande via FOUN-40, vérifier la lecture de l'historique et l'arrêt des nouveaux messages.

Le déploiement backend ne met pas à jour l'application déjà installée : relancer la version V8, par exemple avec `flutter run` depuis le dépôt.
