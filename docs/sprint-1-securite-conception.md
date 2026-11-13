# Sprint 1 — audit et conception

Base locale auditée : `ae377f4211366225670ef480d280e31f3439b2dc` (le SHA exact est consigné dans le bilan final), branche Professionnels, arbre propre. Aucun module de signalement ou blocage préexistant.

## Chemins existants

| Interaction | Source d'identité serveur | Point de contrôle |
| --- | --- | --- |
| Demande directe | professionnel approuvé et compte Auth, auteur authentifié | `request-service.publish` |
| Proposition | `requestOwnership` et miroir privé `userRequests` | `proposal-service.context` |
| Ouverture / texte / coordonnées | proposition et participants de `conversations` | `conversation-service.select`, `readConversation`, `send` |
| Pièce jointe | conversation, réservation privée, message serveur | préparation et confirmation finale dans `attachment-service` |
| Recommandation | propriétaire résolu, professionnel approuvé | `request-interaction-service.recommend` |
| Notification / push différé | documents serveur et participants | émission et nouvelle vérification avant livraison |

Les règles refusent déjà toute écriture directe des interactions. Les conversations et leurs fichiers restent des preuves privées consultables par les participants après blocage.

## Décisions avant implémentation

- `safetyReports`, preuves intégrées bornées et audit privé : accès seulement par callables administratives. Aucun UID cible libre dans une soumission.
- `userBlocks/{owner}/items/{target}` écrit uniquement au serveur. Cible résolue depuis profil, demande ou conversation. Un lecteur transactionnel commun vérifie les deux sens, ainsi que les suspensions, avant tout nouveau contact. La lecture des documents de blocage participe aux conflits Firestore.
- Signalement dédupliqué par compte/cible/motif ; budget quotidien avec réserve pour fraude et menaces. Pas de sanction automatique.
- Décisions administratives avec claim frais et compte vérifié, révision attendue et identifiant idempotent, audit append-only. Masquage réversible d'une demande : retrait de sa projection `requests`, sauvegarde privée, garde serveur indépendante empêchant la republication par modification d'un ancien client. Miroir et quotas conservés. Aucun filtre nouveau imposé aux anciens APK.
- Suspension applicative faisant autorité dans `accountSafety`, appliquée par les règles, les endpoints et les transactions de contact. Ne pas détourner le statut professionnel. Les identifiants Firebase Auth restent inchangés ; les sessions déjà émises ne contournent pas la suspension. Le bilan décrira précisément la stratégie Auth et les limites.
- Menus discrets sur demande, profil et chat ; formulaire court ; paramètres Comptes bloqués et aide. Aucune nouvelle navigation principale.
- Admin : file paginée, détail, justification et confirmation ; traitement en concurrence par révision.
- Prévention : quotas V9.2 préservés, répétitions exactes publiques limitées au serveur. Aucun fournisseur d'analyse ou antivirus supplémentaire.
- Aucune écriture distante, aucun déploiement, aucun APK. Captures issues de widgets réellement rendus, jeux de données de test explicitement identifiés.

Les références Google Play UGC et Apple 1.2 ont été consultées le 13 novembre 2026. Ces travaux ne constituent pas une validation de conformité store. La rétention, l'assistance publique et les textes juridiques du Sprint 2 conditionnent la distribution.
