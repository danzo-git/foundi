# Plan de déploiement — partie serveur autorisée et exécutée

La partie serveur de ce plan a été autorisée explicitement par le propriétaire le 13 novembre 2026, puis exécutée. Voir [le compte rendu de déploiement](sprint-1-deploiement-serveur.md). Aucun compte ni donnée métier de test n’a été créé en production ; aucun APK n’a été généré ou distribué. Les étapes de distribution de l’application et de publication Hosting/Admin restent distinctes.

## Conditions préalables

1. Relire le bilan, les résultats de tests, les captures et le diff depuis `ae377f4211366225670ef480d280e31f3439b2dc`.
2. Valider la procédure humaine de modération et nommer un responsable ainsi qu’un remplaçant. Vérifier la réception de `kouamedenzel09@gmail.com`, adresse fournie par le propriétaire. Aucun message de test n’a été envoyé.
3. Faire valider les CGU/confidentialité du Sprint 2 : signalements, identité du signalant, preuves privées, blocages, restrictions et durées de conservation. Les durées techniques proposées ici ne constituent pas une validation juridique. Pas de publication sur store avant cette revue et la checklist finale.
4. Tester sur un projet Firebase de recette distinct de la production, avec comptes de recette A/B/C/D. Vérifier les permissions interservices Storage → Firestore des nouvelles règles. Les tests automatisés livrés utilisent uniquement `demo-foundi`.
5. Exporter les données/configurations et conserver les versions courantes de Functions, règles et index. Déterminer le projet, la région et les comptes administrateurs habilités. Ne pas ouvrir la rubrique de modération pendant une mise à niveau serveur partielle.

## Ordre proposé

1. **Index et TTL** : créer les index des files filtrées `safetyReports` et de l’audit ; attendre leur disponibilité. Activer les politiques TTL de `safetyReports` et `safetyAudit` sur `deleteAt`. Les mesures actives portent `deleteAt: null` afin de conserver leur dossier de restauration. Le job de purge de preuves ne dépend pas du TTL.
2. **Functions, ensemble complet** : déployer les nouveaux services et **tous les endpoints existants modifiés**, notamment demandes directes, propositions, conversations, préparation/confirmation de pièces jointes, profils publics/recommandations et notifications/triggers/livraison différée. Confirmer que toutes les instances de l’ancienne version sont drainées avant d’autoriser des sanctions ou des blocages réels. Ne pas déployer seulement les nouveaux boutons/endpoints.
3. **Règles Firestore et Storage** : nouvelles collections privées, interdiction d’écritures directes conservée, suspension vérifiée pour les ressources privées. Vérifier avec un compte non admin que les dossiers de modération restent illisibles. Confirmer aussi les tests d’accès Storage après l’activation des permissions interservices nécessaires.
4. **Smoke tests de recette, puis contrôles de production autorisés** : aucun jeu de données automatique en production. Pour toute vérification de production, convenir d’un protocole limité et explicitement autorisé. Contrôler blocage dans les deux sens, vieux client, historique, déblocage, masquage/restauration, ancien lien de demande, conflit de révision, suspension/restauration et absence de push interdit. Tester un vrai appareil et le transport FCM en recette ; les tests automatisés interceptent FCM et n’envoient aucun push réel.
5. **Admin** : publier la nouvelle rubrique uniquement après validation du serveur complet et des règles. Vérifier le claim `admin` courant via le service. Effectuer une prise en charge et une décision justifiée en recette ; vérifier l’audit et l’accès privé aux preuves.
6. **Application Flutter** : une fois l’accord explicite reçu, produire la version prévue et vérifier le contenu de l’aide, les CGU mises à jour et les captures sur appareil. Distribuer uniquement au canal validé. Aucun nouvel onglet principal ni changement d’identifiant/quota métier.
7. **Suivi** : surveiller erreurs par code sans PII, refus de contact, délais de la file et fonctionnement du job `cleanupSafetyEvidence`. Vérifier l’exécution effective de la purge quotidienne et les TTL, qui ne sont pas instantanés. Revoir les coûts des consultations périodiques de contexte et des miniatures.

## Compatibilité avec les anciens APK

- Les anciens clients appellent les mêmes endpoints d’envoi : les contrôles serveur s’appliquent aussi à eux. Ils peuvent afficher un bouton devenu invalide ; l’action est refusée au serveur.
- Un masquage retire la projection `requests/{id}`. Les anciennes requêtes `status == published` continuent à fonctionner sans nouveau filtre ni migration du fil. Un ancien accès direct échoue aux règles. Les endpoints de photos publiques, répondants et engagement échouent aussi sans projection publique.
- Le miroir `userRequests` reste privé à l’auteur/admin. Modifier un contenu masqué avec un ancien client ne recrée pas sa projection ; une restauration explicite utilise le miroir courant, uniquement si son statut est encore `published`.
- Les profils masqués sont exclus des différentes lectures serveur publiques, pas seulement de l’annuaire Flutter.
- L’historique de conversation et ses fichiers restent consultables par les participants non suspendus après blocage. Les anciennes pièces jointes ne deviennent pas publiques.
- Aucune technologie ne retire une copie de texte ou d’image déjà téléchargée sur un appareil. Le retrait empêche les nouvelles lectures serveur ; les caches locaux existants ne constituent pas une source autorisée pour un nouvel envoi.

## Réversibilité

- Restaurer un contenu ou un compte depuis le **dossier qui porte la mesure active**, avec justification et nouvelle entrée d’audit. Un dossier plus ancien ne peut pas annuler une sanction plus récente. La restauration d’une demande supprimée/fermée ne la republie pas.
- La suspension est **applicative**, dans `accountSafety`, et s’impose aux callables, HTTP privés, règles de lecture et transactions de contact. Firebase Auth reste utilisable pour l’authentification ; son champ `disabled` n’est pas modifié. Une restauration n’active donc jamais un compte désactivé indépendamment dans Auth. Les sessions existantes n’autorisent pas à contourner la suspension.
- Pour un incident UI, revenir à l’application/Admin précédent tout en conservant les protections serveur et les données de sécurité. Les anciennes UI ne permettent plus toutes les actions de modération, mais ne contournent pas les refus serveur.
- **Ne jamais revenir aux anciens endpoints d’envoi pendant que des blocages/suspensions/masquages sont actifs.** Préférer un correctif serveur compatible ou une maintenance bloquant les écritures. Un rollback de données brut peut remettre du contenu public ou rouvrir un contact et nécessite une procédure distincte validée.
- Ne pas supprimer les nouvelles collections pour revenir en arrière : elles portent les décisions, la confidentialité et les restrictions. Toute suppression de données relève de la politique de rétention validée.

## Validation attendue

L’autorisation de déployer Functions, règles et index/TTL a été reçue et exécutée. Elle ne vaut pas accord de distribution d’APK, de publication sur store ou de validation juridique. L’organisation humaine et le canal de distribution restent à formaliser dans leurs volets respectifs.
