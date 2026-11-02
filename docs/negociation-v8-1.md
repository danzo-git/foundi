# Foundi V8.1 — Discuter, comparer, décider

## Audit et périmètre

Implémentation sur `codex/foundi-v8-1-negociation`. V8 a été préservé dans le commit local `14148c4` avant de créer cette branche. Aucun push V8/V8.1 effectué dans ce sprint. V7 reste poussé sur sa branche.

Références lues : prompt technique, plan de sprint et source du prototype interactif V8.1 fournis dans Downloads. Le prototype définit le parcours ; ses données et son JavaScript de démonstration ne sont pas intégrés à l'application.

L'audit de Flutter et Firebase confirme les noms réels : `requests`, miroirs `userRequests/{uid}/items/{requestId}`, `proposals` et `conversations/{id}/messages`. V8 plaçait la demande en `in_discussion`, marquait la proposition `selected`, mémorisait une sélection unique sur le miroir auteur et utilisait le requestId comme ID de conversation. FOUN-40 rendait cette conversation en lecture seule à la clôture. Explorer, Pour moi et l'envoi V7 exigent `published`.

V8.1 conserve cette architecture, le shell, les composants et les autorisations existantes. Aucun nouveau système de rôles, notification, paiement, contrat, appel, média, pièce jointe, avis ou Jira.

## Modèle et opérations

| Entité | État V8.1 | Effet |
| --- | --- | --- |
| Demande | `published` / `closed` / `deleted` | Publication indépendante de la négociation |
| Proposition | `sent` / `discussing` / `retained` / `rejected` | Reçue, En discussion, Retenue, Refusée |
| Conversation | `active` / `read_only` | Messages autorisés ou historique archivé |

Le miroir privé peut contenir `retainedProposalId` et `retainedProfessionalName`. Ces champs ne sont jamais ajoutés à la demande publique. Le libellé de `published` devient Ouverte. Le vieux `in_discussion` est toléré pour la transition, sans être un nouvel état de publication utilisé par V8.1.

### Discuter

La callable existante `selectProposal` est conservée pour la compatibilité technique ; elle signifie désormais uniquement ouvrir/retrouver une discussion. Son nom ne constitue pas une retenue.

Seul l'auteur vérifié et actif peut l'ouvrir pour une proposition reçue liée à son miroir privé. Une nouvelle discussion exige la demande et son miroir `published`, le professionnel `approved`, une proposition `sent` ou déjà `retained`. La transaction ne modifie pas le statut de demande. Elle crée `conversations/{proposalId}`, passe la proposition en `discussing` sauf si elle est déjà `retained`, et conserve les instantanés publics existants.

Si `proposal.conversationId` existe, le serveur vérifie la liaison et renvoie cet ID, y compris pour consulter une archive. Les anciennes URLs/IDs V8 sont donc conservés. Chaque proposition peut avoir sa discussion, sans imposer une seule discussion par demande. Le champ `proposalId` devient la référence explicite ; `selectedProposalId` reste un alias technique compatible dans les conversations.

### Retenir / Refuser

Nouvelle callable `decideProposal` : `requestId`, `proposalId`, `action`, `decisionId`, `expectedRetainedProposalId` et motif facultatif, trimé, de 300 caractères maximum. Compte actif/vérifié, auteur, liaison et transitions sont contrôlés côté serveur. Les décisions restent possibles sur une demande ouverte ou clôturée, jamais supprimée. Retenir exige un professionnel actuellement approuvé ; refuser n'en dépend pas.

Une retenue vérifie atomiquement que la référence actuelle correspond à `expectedRetainedProposalId`. Une autre retenue apparue depuis la confirmation provoque une erreur : il faut relire et confirmer. Le dialogue nomme le professionnel désélectionné. L'ancienne proposition revient à `discussing` si elle possède une conversation, sinon `sent`. La nouvelle devient `retained`. Les autres conversations continuent. Aucun contrat, paiement, résultat de prestation ni clôture n'est implicite.

Le refus passe uniquement la proposition visée à `rejected` et sa conversation, si elle existe, à `read_only` avec `archivedReason: proposal_rejected`. Si elle était retenue, la référence privée est effacée dans la même transaction. Aucun retour d'une proposition refusée n'est possible dans ce sprint.

Un journal serveur est écrit sous `userRequests/{uid}/items/{requestId}/decisions/{decisionId}` : acteur, action, référence précédente, attente confirmée, motif et date. La répétition du même identifiant/payload renvoie le résultat déjà enregistré ; réutiliser l'ID pour un autre payload est refusé. Le client garde le même ID après un échec de la même tentative. Ce journal n'est ni public ni modifiable par le client.

### Clôture, suppression, messages

FOUN-40 reste réservé à l'auteur. La confirmation explique l'arrêt des nouvelles propositions. La transaction recherche les conversations liées au requestId : clôturer conserve leurs états et actualise leur instantané de demande ; supprimer les archive toutes, en conservant les historiques. Le rejet reste indépendant.

`sendConversationMessage` conserve le texte de 1 à 2000 caractères, l'ID stable, le sender issu de l'authentification, les dates serveur monotones et l'écriture atomique de l'aperçu. Il contrôle la proposition liée et l'activité de sa conversation. Une demande `published` ou `closed` permet les échanges existants ; une demande supprimée ou une proposition refusée les bloque. La tolérance au vieux `in_discussion` évite d'interrompre l'historique avant migration.

Les opérations lisent les données nécessaires avant les écritures et utilisent les [transactions Firestore](https://firebase.google.com/docs/firestore/manage-data/transactions). Les listes gardent leurs filtres et limites prouvables par les [règles de requête](https://firebase.google.com/docs/firestore/security/rules-query).

## Sécurité, fonctions et index

- Mise à jour : `selectProposal`, `sendConversationMessage`, `manageRequest`.
- Création : `decideProposal`.
- `sendProposal`, `proposalAccess`, `listOpportunities` restent inchangés : leur contrôle `published` devient suffisant une fois discussion et publication séparées.
- Règles et index Firestore inchangés. Les écritures de demandes, propositions, conversations et messages sont déjà interdites aux clients. Le journal de décisions reste interdit par défaut. Seuls les deux participants lisent une conversation et ses messages ; aucun privilège de lecture des chats n'est ajouté à l'admin ni à un concurrent.
- La recherche serveur des conversations d'une demande utilise l'index simple automatique `requestId`. Les index de listes de conversations V8 sont réutilisés ; aucun composite supplémentaire.

## Transition des données V8

L'utilisateur a autorisé la correction des données fictives de production le 2 novembre 2026. Un dry-run en lecture seule a été effectué sur `foundi-7c837` :

| Collection | Inventaire |
| --- | --- |
| `requests` et miroirs auteur | 2 `published`, 1 `in_discussion`, 1 `deleted` chacun |
| `proposals` | 1 `selected`, 1 `sent` |
| `conversations` | 1 `active` |

Une demande pouvait être rétablie en publication ; aucune anomalie détectée. Ces premiers inventaires n'ont modifié aucun document de production. Plan contenant les avant/après privés sauvegardé hors Git dans `.dart_tool/v81-production-plan.json`. Un second inventaire a confirmé ces mêmes comptes et sauvegardé `.dart_tool/v81-production-plan-review.json` avec le planificateur validé. Un nouveau plan a ensuite été créé au déploiement autorisé, comme détaillé plus bas.

`functions/src/negotiation-migration.js` est un planificateur pur. Il ne propose un changement que si sélection, auteur, demande, miroir, dates d'origine, proposition et conversation concordent. Un état ambigu ou une archive explicitement motivée est signalé et laissé intact. Les seuls `in_discussion` cohérents reviennent à `published` ; les demandes vraiment clôturées ou supprimées conservent leur état.

L'ancien `selected` devient `discussing` : aucun engagement Retenir n'est déduit du geste V8. La conversation conserve son ID et tous ses messages, noms et dates. Les références exclusives sur le miroir sont retirées. Les anciennes conversations clôturées peuvent redevenir actives pour correspondre à V8.1 ; celles des demandes supprimées restent archivées. Un marqueur `schemaVersion: 81` rend l'inventaire réexécutable.

Le script `functions/scripts/migrate-negotiation-v81.cjs` utilise l'API Firestore avec les identifiants administrateur locaux. Il ne consulte pas les messages et ne les réécrit pas. Le backup encode aussi les types Firestore inconnus pour préserver les timestamps et métadonnées. Le dry-run est le mode par défaut ; le fichier de plan est créé sans écraser un fichier existant.

```powershell
# Lecture seule, toujours produire un nouveau plan avant une application réelle.
node functions/scripts/migrate-negotiation-v81.cjs --project foundi-7c837 --dry-run --output .dart_tool/v81-production-plan-next.json

# Après déploiement du backend V8.1 seulement, avec le plan fraîchement contrôlé.
node functions/scripts/migrate-negotiation-v81.cjs --project foundi-7c837 --apply --plan .dart_tool/v81-production-plan-next.json

# Retour arrière conditionnel, si aucun document concerné n'a changé entre-temps.
node functions/scripts/migrate-negotiation-v81.cjs --project foundi-7c837 --rollback --plan .dart_tool/v81-production-plan-next.json
```

Chaque groupe de demande est vérifié et écrit dans une transaction avec lecture groupée. Déjà appliqué : pas de nouvelle écriture. Divergence depuis la sauvegarde : conflit et aucune écriture pour cette demande. Le retour arrière vérifie de même l'état après migration ; il ne doit jamais écraser une décision ou un message ultérieur. Des groupes antérieurs peuvent avoir été appliqués avant un conflit : reprendre après examen du conflit, sans modifier le backup. Les sauvegardes contiennent des données privées et doivent rester hors du dépôt.

Le backend V8 exigeait `in_discussion` pour écrire un message : appliquer la transition avant son remplacement aurait interrompu ce parcours. L'ordre de mise en service retenu est donc backend V8.1, inventaire frais, migration vérifiée, application mobile compilée depuis cette branche et recette à plusieurs comptes. L'utilisateur a ensuite donné son accord explicite pour les quatre fonctions, la migration et les vérifications en production le 2 novembre 2026.

## Validation

Résultats finaux du 2 novembre 2026 :

- **69 tests Flutter réussis**, incluant les régressions V3–V8 et trois nouveaux tests V8.1 : plusieurs discussions, annulation et remplacement nommé, refus depuis la conversation avec motif, professionnel sans commandes de décision réservées au client, erreur serveur et reprise avec ID stable. Analyse Flutter : **aucun problème**.
- **70 tests Node réussis**, dont les transitions métier V8.1 et le planificateur pur de migration. Les anciens tests d'exclusivité V8 sont remplacés par les nouvelles règles V8.1 ; la simulation de stockage est extraite dans `functions/test/helpers/conversation-fixture.js`.
- **18 tests de règles réussis** : demandes publiques bornées, références, profils, propositions privées, conversations et messages réservés aux participants, impossibilité de forger retenue, décision, journal ou réactivation d'une archive.
- **5 intégrations Firebase réussies** : parcours V8.1 avec un client et trois professionnels, migration réelle sur émulateur, validation professionnelle antérieure, propositions V7 et cycle des demandes V5/V6. Code de sortie final de l'Emulator Suite : **0**.
- Migration : dry-run sans écriture, application, répétition sans mutation, conservation des types Timestamp et des messages, refus de rollback après modification concurrente, puis retour arrière vérifié après restauration de la condition attendue.
- Syntaxe Node et `git diff --check` réussis. Les avertissements de conversion LF/CRLF correspondent au paramétrage Git Windows.
- Contrôle en lecture seule du backend encore en production : six combinaisons de filtres Explorer HTTP 200 avec les résultats attendus, cas vide correct, clôturées/supprimées et requête sans statut refusées avec HTTP 403. Les six index publics sont READY. Ce contrôle confirme la conservation de la production V8 actuelle, pas le déploiement de V8.1.

La nouvelle confirmation FOUN-40 a aussi été corrigée après détection d'un débordement de 26 pixels par la suite existante : contenu défilable et hauteur disponible, puis suite entière repassée. L'exception Java connue du runtime Storage à l'arrêt survient après les résultats réussis et le code 0 ; elle ne concerne pas le service métier.

| Acceptation | Vérification |
| --- | --- |
| A01–A03 | Publication inchangée, Pour moi/Explorer accessibles, proposition supplémentaire et deux conversations privées distinctes |
| A04–A05 | Retenue distincte, unicité transactionnelle et attente explicite de la retenue précédente, confirmation UI nominative |
| A06 | Refus ciblé, référence retenue effacée si nécessaire, archive et historique, nouvelle retenue ou message refusés |
| A07–A08 | Offres possibles après retenue ; arrêt après clôture, poursuite des messages non refusés, archivage à la suppression |
| A09 | Auteur seul aux décisions ; concurrent, falsification et accès directs refusés |
| A10 | Contention de vraies transactions sur retenue, double ouverture sans doublon, clôture concurrente à une proposition ; garde de double clic et reprise UI |
| A11 | Données anciennes, cas ambigus laissés intacts, demande vraiment clôturée non rouverte, script réexécutable et retour arrière conditionnel |
| A12 | Suites précédentes Flutter, serveur, règles et intégrations conservées et réussies |

Les modifications se concentrent dans le service de conversations et les points d'entrée request-service/index, les modèles et repositories Flutter de conversations/propositions/demandes, le panneau `proposal_negotiation.dart`, les vues de conversation/propositions/FOUN-40 et une injection du repository de propositions dans le shell. Le script et le planificateur de migration sont séparés des opérations courantes. `functions/package.json` déclare la bibliothèque Google Auth déjà utilisée par les outils administratifs et ajoute les nouvelles vérifications de syntaxe ; aucun changement du moteur Node ou des dépendances Flutter.

Les fonctions de l'Emulator Suite sont exécutées avec `--inspect-functions=12999`, donc sérialisées pour limiter la mémoire. Les tests de contention, eux, appellent directement le même service métier avec de **vraies transactions Firestore concurrentes** via Admin SDK, sans passer par cette file sérialisée. Cela vérifie la concurrence transactionnelle mais ne constitue pas un test de charge des instances déployées.

Les premières passes ont révélé un mauvais accès administrateur dans l'adaptateur d'émulateur de migration, puis une attente sur les GET REST transactionnels. Corrigés par authentification locale owner et lecture transactionnelle `batchGet` ; aucun contournement des règles en production. Les captures ont nécessité de charger une police de texte réelle et d'exécuter le rendu d'image hors de l'horloge simulée des tests. Les avertissements Dart et un test réutilisant un écran de conversation sans changer sa clé ont été corrigés. Les captures utilisent des comptes simulés et une police locale, pas des données de production.

Captures Flutter réelles : [propositions](v81-captures/01-propositions.png), [discussion](v81-captures/02-discussion.png), [refus archivé](v81-captures/03-refus-archive.png).

Limites conservées : 30 conversations les plus récentes ; historique de 30 messages élargi jusqu'à 100. Les messages plus anciens restent persistés. Aucun test sur téléphone physique ni test de charge multi-instance. L'application déjà installée n'est pas mise à jour par un déploiement Firebase.

## Mise en service en production — 2 novembre 2026

Déploiement ciblé terminé avec code de sortie 0 sur `foundi-7c837`, région `europe-west1`. Les 70 tests serveur et les vérifications de syntaxe ont repassé dans les préhooks.

```text
firebase deploy --project foundi-7c837 --only functions:auth:selectProposal,functions:auth:decideProposal,functions:auth:sendConversationMessage,functions:auth:manageRequest --non-interactive
```

| Fonction | État vérifié | Révision |
| --- | --- | --- |
| `selectProposal` | ACTIVE | `selectproposal-00002-pob` |
| `decideProposal` | ACTIVE | `decideproposal-00001-lal` |
| `sendConversationMessage` | ACTIVE | `sendconversationmessage-00002-feh` |
| `manageRequest` | ACTIVE | `managerequest-00003-run` |

Les fonctions antérieures `sendProposal` et `listOpportunities` sont toujours ACTIVE. Les deux index de listes de conversations et les six index de demandes sont READY. Les règles publiées correspondent exactement au fichier local normalisé : ruleset `7d073ac3-1846-4bef-9430-28f3c332484a`, SHA-256 `8af833524696a458d4de22c012343aaefefde9c229327e7fe95190e8a767f381`. Aucun changement de règles ou d'index n'était nécessaire ; aucun déploiement Hosting, Storage, Store ou Jira.

### Migration effectivement appliquée

Inventaire frais et sauvegarde avant/après dans `.dart_tool/v81-deployment-migration-20261102.json`, hors Git. Une demande, sans anomalie : application transactionnelle réussie (`changed: 1`). Réexécution du même plan : `changed: 0`, `alreadyApplied: 1`. Les quatre documents concernés correspondent aux après attendus ; la demande rétablie est lisible publiquement, sans UID ni référence privée.

Avant l'application, les deux messages de la conversation existante ont été comptés et leur contenu complet haché dans `.dart_tool/v81-migration-history-baseline.json`. Après migration, mêmes identifiants, contenu et empreinte : **historique inchangé, deux messages conservés**. L'identifiant de conversation reste celui de V8. Aucune retenue n'est déduite de l'ancienne sélection.

Inventaire après migration et nettoyage des tests : trois demandes `published`, une `deleted` et les mêmes états sur les miroirs auteur ; une proposition `discussing`, une `sent` ; une conversation `active`. Zéro ancien `in_discussion`, zéro conversation V8 à migrer, zéro anomalie. La demande supprimée n'a pas été rouverte.

### Vérifications sur les services déployés

Les quatre callables refusent l'anonyme avec HTTP 401 / UNAUTHENTICATED. Conversation, message et liste privée anonymes : HTTP 403. Les requêtes de listes/historique sont exécutables avec les index publiés.

Une recette **réelle en production**, avec un client et trois professionnels temporaires, s'est terminée avec code 0 :

- Publication, ouverture de deux discussions distinctes et répétition du même choix sans doublon ; demande toujours publique et présente dans Pour moi.
- Refus d'ouverture par le professionnel, de lecture du chat concurrent et de falsification directe d'une retenue ou d'un message dans Firestore.
- Listeners temps réel sur deux comptes : message client, réponse professionnelle, ordre et répétition d'envoi sans doublon.
- Deux retenues envoyées simultanément aux fonctions déployées : un seul succès. Répétition idempotente, remplacement explicite, proposition supplémentaire acceptée pendant la négociation.
- Refus de la proposition retenue : référence effacée, seule sa conversation archivée, nouvel envoi et nouvelle retenue refusés ; l'autre discussion reste active.
- Reconnexion dans une nouvelle instance Firebase : listes Mes clients et historique retrouvés. Clôture : nouvelles propositions impossibles, disparition de Pour moi et des lectures publiques, messages encore possibles dans le chat non refusé. Suppression : toutes les conversations du test deviennent en lecture seule et restent consultables aux participants avant nettoyage.

Les quatre comptes temporaires et les seize chemins de documents associés ont été supprimés après ce test. Un contrôle indépendant a confirmé leur absence, ainsi que l'absence de messages orphelins dans leurs conversations. Les manifestes privés `.dart_tool/v81-smoke-manifest-*.json` conservent seulement les identifiants nécessaires au suivi du nettoyage, sans mot de passe ni jeton. Les données applicatives préexistantes ne faisaient pas partie de ce nettoyage.

Dernier contrôle public Explorer après nettoyage : six combinaisons de filtres HTTP 200, trois demandes dans le fil sans filtre, cas vide correct ; demandes `closed` / `deleted` et requête sans statut refusées avec HTTP 403. Les erreurs PERMISSION_DENIED affichées par le SDK pendant les tentatives de falsification sont les refus attendus du test, dont le résultat final est réussi.

La recette réelle utilise les SDK Firebase et les fonctions déployées ; elle ne constitue pas un test de l'application sur appareil physique. Un APK Android V8.1 a ensuite été compilé pour le test utilisateur.

### APK Android pour le téléphone

Compilation réussie, code 0, en 161,2 secondes :

```text
flutter build apk --debug --no-pub --dart-define=USE_FIREBASE_EMULATORS=false
```

Fichier prêt à installer : `C:/laragon/www/foundi/build/app/outputs/flutter-apk/foundi-v8.1-debug.apk` (172 155 148 octets). Il utilise les nouveaux écrans de la branche V8.1 et Firebase en production. SHA-256 : `22CFF4A08E11E30E799A2AEA2AD3C655DD711616252D4B5DE976796A62DD7985`.

Contrôle du manifeste avec `aapt` : package `com.example.foundi`, version `1.0.0` / code `1`, SDK minimum 24, cible 36, architectures `arm64-v8a`, `armeabi-v7a` et `x86_64`. Signature de l'APK vérifiée par `apksigner.jar`, code 0. Le cache Kotlin créé par ce build est exclu de Git dans `android/.gitignore`.

Le build affiche un avertissement de compatibilité future KGP des plugins Firebase ; la compilation actuelle aboutit. Aucune mise à jour de plugins n'a été ajoutée à ce déploiement ciblé. Aucune installation sur téléphone n'a été effectuée : installer cet APK ou lancer `flutter run --dart-define=USE_FIREBASE_EMULATORS=false` depuis la branche V8.1 pour tester les nouveaux écrans.

## Recette manuelle

1. A publie ; B et C professionnels approuvés proposent. A ouvre les deux discussions et envoie/reçoit du texte dans chacune ; elles restent privées et indépendantes.
2. Vérifier la demande dans Explorer et Pour moi ; D peut toujours envoyer une nouvelle proposition, y compris après que A a retenu B.
3. A retient B, puis demande de retenir C : le dialogue nomme B. Annuler ne change rien ; confirmer remplace atomiquement la retenue et préserve les deux historiques.
4. A refuse C avec ou sans motif : C est Refusée, sa discussion est en lecture seule, la référence retenue est vide et celle de B reste active.
5. A clôture volontairement : la demande disparaît des fils actifs, D ne peut plus envoyer de proposition, la discussion non refusée continue à fonctionner.
6. Fermer/réouvrir les applications et vérifier les historiques depuis Mes recherches / Mes clients. Après suppression logique, toutes les discussions restent consultables en lecture seule.
