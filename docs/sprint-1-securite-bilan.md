# Foundi V1 — Sprint 1 : sécurité et modération

Implémentation depuis `ae377f4211366225670ef480d280e31f3439b2dc`, en conservant le volet Professionnels. Le propriétaire a validé la clôture du sprint et demandé son push. Ce commit de clôture regroupe l’implémentation, les correctifs de recette, les tests, les captures et la documentation sur `codex/foundi-explorer-professionnels-v1`. La partie serveur a été autorisée et [déployée le 13 novembre 2026](sprint-1-deploiement-serveur.md). Aucun APK n’a été généré ou distribué ; la publication Hosting/Admin reste distincte du push Git.

État final : 77 Functions actives. Les correctifs de recette couvrent les [notifications de modération](sprint-1-notifications-moderation.md), [l’identification du contenu et le réexamen des décisions](sprint-1-reexamen-contenu.md), puis la [fermeture persistante des avis après lecture](sprint-1-fermeture-avis.md). Les derniers contrôles sont consignés dans les [résultats des tests](sprint-1-resultats-tests.md), avec la distinction entre suites complètes historiques et validations ciblées finales.

Documents : [audit et conception](sprint-1-securite-conception.md), [procédure humaine](sprint-1-procedure-moderation.md), [plan de déploiement à valider](sprint-1-plan-deploiement.md), [captures réelles](sprint-1-securite-captures/README.md), [inventaire des fichiers](sprint-1-fichiers.md).

Après les captures d’erreur sur les clients installés : [diagnostic de l’activation serveur et correctifs d’affichage](sprint-1-diagnostic-activation.md). L’absence d’endpoints/index constatée lors du diagnostic a été résolue par le déploiement serveur autorisé ; voir son compte rendu pour les vérifications de production.

## Correspondance du cahier des charges

| US | Implémentation | Ticket Jira |
| --- | --- | --- |
| US-SEC-01 | Menus demandes/détails, profils publics et chat/messages ; formulaire, résolution serveur de l’auteur, déduplication/budget, preuves privées | Recherche impossible : instance connectée, réponse 404 « Site temporarily unavailable ». Aucune clé inventée ni ticket créé. |
| US-SEC-02 | Blocage/déblocage, liste privée, garde bidirectionnelle et historique conservé, contrôles des anciens endpoints | Même indisponibilité Jira ; référence locale US-SEC-02 |
| US-SEC-03 | File Admin filtrée/paginée, détail privé, décisions/révisions/audit, avertissement, retrait/restauration, suspension applicative/restauration | Référence locale US-SEC-03 |
| US-SEC-04 | Règles de conduite dans les écrans existants, aide avec adresse fournie, prévention de répétitions, rétention et procédure humaine | Référence locale US-SEC-04 |

## Contrats serveur

Toutes les callables se trouvent dans `europe-west1`. Les entrées de sécurité rejettent les champs supplémentaires. L’authentification et l’état actif/vérifié sont contrôlés au serveur. Chaque endpoint historique authentifié dispose également d’une garde de compte suspendu ; les contrôles transactionnels s’appliquent aux nouvelles interactions. La consultation et la confirmation de ses propres avis restent possibles pendant une suspension, avec une exception strictement limitée à ces avis pour la résolution/livraison des notifications.

Une **cible** vaut `{targetType, targetId, conversationId?}` avec `request`, `professional`, `conversation` ou `message`. Pour un message, `conversationId` est obligatoire. L’UID concerné est résolu depuis les dossiers/propriétaires/participants serveur ; `targetUid` ou `reportedUid` venant du client sont refusés. Les comptes ne peuvent pas se signaler ou se bloquer eux-mêmes.

| Endpoint | Entrée | Réponse / effet |
| --- | --- | --- |
| `submitSafetyReport` | cible, `reason`, `comment?` ≤ 500 | `reportId`, `duplicate` ; auteur résolu, preuve privée bornée, statut New |
| `readSafetyContext` | cible | `own`, `blocked` (relation propre), `contactAllowed` ; aucune liste inverse divulguée |
| `blockUser` | cible | relation privée propre idempotente |
| `unblockSafetyTarget` | cible | retire uniquement la relation propre correspondante |
| `unblockUser` | `blockedUid` provenant de sa liste | supprime uniquement cette relation sous son propre UID ; ne permet pas de créer une relation arbitraire |
| `listBlockedUsers` | `cursor?` | page de 30, curseur éventuel ; noms et UID des comptes que le demandeur a bloqués |
| `listSafetyNotices` | aucune donnée métier | 10 derniers avis privés contextualisés, identifiants stables et état de lecture ; textes non fermés conservés dans le champ historique `items` |
| `acknowledgeSafetyNotice` | `noticeId` | confirme la lecture de son seul avis, le retire du profil et marque sa notification comme lue ; aucune mesure de modération modifiée |
| `listSafetyReports` | `status`, `reason?`, `targetType?`, `cursor?` | Admin courant : 25 dossiers, plus anciens d’abord, métadonnées minimales |
| `readSafetyReport` | `reportId` | Admin courant : détail, actions autorisées, preuves privées et jusqu’à 100 entrées d’audit |
| `decideSafetyReport` | `reportId`, `action`, justification interne ≤ 500, `publicMessage?` ≤ 500, `expectedRevision`, `decisionId` | Admin courant : nouvelle révision, décision idempotente, audit conservé ; `reopen` permet le réexamen sans lever les mesures actives |
| HTTP `readSafetyReportAttachment` | GET `reportId`, Bearer Auth | Admin courant : fichier historique référencé dans ce seul dossier, génération vérifiée, accès sans cache ni URL permanente |
| Scheduler `cleanupSafetyEvidence` | quotidien | purge bornée des preuves/commentaires expirés ; nettoyage des anciennes entrées d’audit maintenues après archivage |

Motifs : fraude, menaces/harcèlement, contenu inapproprié, spam, usurpation, autre. Même compte/cible/motif/jour = même dossier. Budget : 20 signalements ordinaires/jour, avec 10 places supplémentaires réservées aux motifs fraude/menaces. Le lendemain et les nouveaux messages ont leurs propres identifiants de plainte. Aucun nombre de plaintes ne suspend automatiquement un compte.

## Données et confidentialité

- `safetyReports` contient le signalant, la cible, l’UID résolu, le motif/commentaire nettoyé, les dates serveur, la priorité, la révision et les preuves minimales. Les miniatures privées restent bornées à 32 Kio chacune ; les textes de message sont copiés uniquement pour le message ciblé. Les numéros de contacts partagés ne sont pas copiés dans les preuves.
- `safetyAudit` est append-only pour les décisions de l’application. Le même `decisionId` ne peut pas servir à une décision différente. Deux traitements de la même révision ne réussissent pas tous les deux. La suppression de fin de rétention reste une opération serveur distincte des décisions.
- `userBlocks/{owner}/items/{target}` n’est lisible/inscriptible par aucun SDK client. L’API de liste ne donne que les relations du compte authentifié.
- `accountSafety` et `safetyContent` sont privés et font autorité. Les nouveaux dossiers ne sont jamais exposés par une lecture directe Firestore, même avec un claim admin périmé ; leurs API exigent le claim dans le token **et** le claim courant Auth ainsi qu’un compte actif/vérifié.
- Aucun signalement ne notifie son auteur à la personne visée. L’avertissement est un avis privé générique visible dans les paramètres. Les journaux ne contiennent pas le texte privé, les commentaires ni des documents professionnels.

## Blocage et concurrence

Une même garde lit les deux relations de blocage et les restrictions des deux comptes dans la transaction qui crée le contact. Elle s’applique à la demande directe, à l’accès/envoi de proposition, à l’ouverture de conversation, au texte/contact et aux réservations/confirmations finales de fichiers. Les réessais d’un envoi déjà commis n’émettent pas de nouveau message. Un fichier préparé avant le blocage ne peut pas être confirmé après celui-ci.

Les recommandations vérifient les paires recommendeur/auteur/professionnel. Les notifications vérifient les relations à la création et de nouveau avant livraison différée. Les UID nécessaires à cette garde restent dans l’outbox privée lorsque l’ancienne notification devait rester neutre. Aucune modification du quota, de l’identifiant, du statut métier d’une demande ou suppression de proposition n’est déclenchée par un blocage.

Flutter désactive le contact pendant la résolution, en cas d’erreur ou de restriction. Le contexte est revérifié périodiquement et à la reprise, et invalidé après un blocage/déblocage ou changement de session. Les réponses périmées ne réactivent pas une action après un changement de contexte. L’historique reste consultable par les participants autorisés ; un message optimiste finalement refusé conserve son texte et son état d’échec, sans action de réessai pendant le blocage.

## Modération et rétrocompatibilité

Actions livrées : prise en charge, classement sans suite, avertissement, masquage/restauration de demande ou profil, suspension/restauration applicative. Une justification et une confirmation précèdent chaque décision. La révision attendue est obligatoire. Une restauration ne peut pas annuler une mesure plus récente portée par un autre dossier.

Le masquage d’une demande retire son document public et garde son miroir privé, son identifiant et ses quotas. Modifier le miroir depuis un ancien client ne recrée pas la projection publique. La restauration ne republie que les demandes encore publiées dans leur cycle métier. Les anciens filtres du fil restent valides : aucun champ de filtrage supplémentaire à migrer sur les APK existants. Les profils masqués sont aussi retirés des lectures de répondants et de recommandations.

La suspension vise le compte entier et ne modifie pas le statut professionnel. Elle est appliquée aux règles et endpoints, y compris pour les sessions déjà émises. **Elle ne désactive pas Firebase Auth** : l’utilisateur peut encore s’authentifier, mais n’obtient pas les autorisations applicatives interdites. Une restauration ne réactive jamais un compte désactivé séparément dans Auth. Les contenus qui sont volontairement publics restent soumis à leur politique publique ; une suspension de contact n’est pas un retrait automatique de tout l’historique public.

## Vérification

Les résultats finaux et les limites sont consignés dans [les résultats de tests](sprint-1-resultats-tests.md). Les captures sont des rendus réels des widgets de production Flutter/Admin, exécutés avec des dépôts et comptes **de test**, pas des maquettes ni des captures de production. Elles sont produites par `SAFETY_CAPTURE=true`.

Commandes reproductibles :

```powershell
dart format .
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter test --no-pub test/safety_test.dart --dart-define=SAFETY_CAPTURE=true --reporter expanded
```

Dans `admin` : `flutter pub get --offline`, `flutter analyze --no-pub`, `flutter test --no-pub --dart-define=SAFETY_CAPTURE=true --reporter expanded`.

Dans `functions` : `npm test`, `npm run check`, `npm run test:safety:emulators`. Cette dernière commande sélectionne des ports locaux disponibles, utilise uniquement `demo-foundi` et restaure les fichiers d’environnement locaux à la sortie. Le service d’antivirus des tests est le faux serveur de protocole déjà utilisé par les suites V8.2, pas un service ajouté en production.

## Limites et validations avant distribution

- Aucun filtrage sémantique ou automatique des images ; les contrôles de répétition et les validations structurelles ne détectent pas tous les abus. Les miniatures et signalements servent à l’examen humain. Une image devenue indisponible peut laisser seulement ses références et une mention d’échec de capture.
- Un push déjà remis au transport FCM avant le blocage ne peut pas être rappelé. Les tests vérifient les refus d’actions, l’absence de nouveaux documents/outbox et la suppression de livraison différée ; aucun push réel n’a été envoyé.
- Une donnée déjà téléchargée sur un ancien appareil ne peut pas être effacée à distance par les règles. Les nouvelles lectures serveur de contenu retiré et les nouveaux contacts restent refusés.
- L’audit affiché est borné à 100 entrées par dossier. La purge quotidienne de preuves est bornée à 100 dossiers : suivre la charge et les délais réels avant montée en volume. Les administrateurs restent chargés du triage ; aucun service humain 24/7 n’est présumé.
- Scheduler/TTL de production, droits IAM interservices, FCM et essais manuels sur appareil/store sont à valider en recette avec autorisation. Aucun APK n’a été produit pour ces vérifications.
- Les CGU/confidentialité et la validation des durées de conservation du Sprint 2 restent un **préalable à la distribution sur store**. Le sprint ne revendique pas une conformité totale aux stores.

Références consultées le 13 novembre 2026 : [Google Play — contenu généré par l’utilisateur](https://support.google.com/googleplay/android-developer/answer/9876937?hl=fr), [Apple — App Review Guidelines, 1.2](https://developer.apple.com/app-store/review/guidelines/#user-generated-content).
