# Résultats des tests — 13 novembre 2026

**Fermeture des avis après lecture :** 175 tests Node, 30 tests Flutter ciblés, 36 tests de règles et 2 parcours Firebase Emulator réussis ; analyse Flutter sans problème. La suite Flutter complète a été interrompue par la mémoire Windows avant une relance ciblée réussie. Voir [la confirmation de lecture persistante et ses captures](sprint-1-fermeture-avis.md).

**Correctif suivant — contenu concerné et réexamen :** 172 tests Node, 14 tests Admin, 27 tests Flutter ciblés, 36 tests de règles et 2 parcours Firebase Emulator réussis ; analyses statiques sans problème et compilation web Admin réussie. Les tests d’intégration vérifient une première alerte sur une demande, sa réouverture, le masquage, puis sa restauration avec historique conservé. Voir [les détails, captures et conditions de publication Admin](sprint-1-reexamen-contenu.md). Cette passe ciblée ne remplace pas les résultats historiques complets ci-dessous.

**Correctif des notifications de modération :** 168 tests Node, 179 tests Flutter complets, 12 tests Admin, 36 tests de règles et 22 tests d’intégration Firebase Emulator réussis. Analyses Flutter et Admin : zéro problème. Les 17 tests Flutter ciblés avec captures sont inclus dans cette validation ; la dernière passe complète couvre en plus l’accès aux avis après refus du chargement du compte ou du dossier professionnel. Le premier lancement Flutter concurrent a été interrompu par Windows (`Could not start thread DartWorker`) ; les suites complètes suivantes ont réussi avec `--no-pub --concurrency=1`. Les émulateurs ont terminé avec le code 0 ; leurs avertissements de redémarrage/arrêt ne correspondent pas à des échecs de tests. Voir le [correctif et son périmètre client](sprint-1-notifications-moderation.md).

**Activation serveur ultérieure autorisée :** [76 Functions actives, règles publiées, 5 index prêts, 2 TTL actifs et 18 contrôles HTTP sans écriture métier](sprint-1-deploiement-serveur.md). Les mentions d’absence de déploiement ci-dessous décrivent les validations initiales du sprint, effectuées avant cet accord.

Après réception des captures `NOT_FOUND` / `internal [0]`, un [diagnostic en lecture seule](sprint-1-diagnostic-activation.md) a confirmé l’absence d’activation serveur du sprint. Le correctif de remontée d’erreur a été revalidé avec **166 tests Node**, **16 tests Flutter ciblés** et **7 tests Admin ciblés**, tous réussis. Les résultats complets ci-dessous restent ceux de la livraison initiale du sprint ; le correctif ne modifie aucune règle ni écriture métier.

Base : `ae377f4211366225670ef480d280e31f3439b2dc`. Exécutions locales uniquement. Aucun compte ni donnée de test créés en production ; aucun APK généré. Les émulateurs utilisent `demo-foundi` et les appels FCM sont interceptés par des doubles de test.

| Vérification | Résultat final |
| --- | --- |
| `dart format .` | Réussi |
| `flutter analyze --no-pub` à la racine, incluant les sources Admin | Aucun problème détecté |
| `flutter test --no-pub --reporter expanded` | **171 tests réussis**, aucun échec |
| Tests sécurité Flutter avec thèmes réels et captures | **11 tests réussis**, aucun échec |
| Suite Flutter complète Foundi Admin | **7 tests réussis**, aucun échec |
| Tests modération Admin avec thème réel et captures | **3 tests réussis**, aucun échec |
| `npm test` dans `functions` | **163 tests réussis**, aucun échec ni test ignoré ; 18 nouveaux tests sécurité |
| `npm run check` dans `functions` | Réussi, syntaxe des services et tests ajoutés incluse |
| Firebase Emulator — suite complète de règles Firestore/Storage | **35 tests réussis**, aucun échec ni test ignoré |
| Firebase Emulator — suite complète d’intégration | **21 tests réussis**, aucun échec ni test ignoré |
| `git diff --check` | Aucune erreur d’espacement |
| Captures de widgets réels | **10 PNG** générés et contrôlés, avec données de test |

## Scénarios de sécurité couverts

- Motif/commentaire, confirmation, erreur réseau, réessai, retour, petit écran 320 px et texte agrandi ; menus demandes, profils et conversations/messages ; absence de menu pour la cible propre une fois la propriété résolue ; invitation des visiteurs à se connecter.
- Blocage/déblocage, confirmation, liste privée, conservation de l’historique et désactivation des envois ; message optimiste finalement refusé avec texte conservé, sans réessai activé pendant le blocage.
- Résolution réelle des auteurs, champ UID usurpé refusé, utilisateur D étranger à la conversation refusé, compte désactivé/non vérifié/suspendu refusé, déduplication et budget avec réserve pour plaintes graves.
- L’accès de contexte/signalement à une demande directe respecte également l’approbation du destinataire professionnel imposée par les règles Firestore ; un destinataire dont le dossier n’est plus approuvé est refusé.
- Blocage dans les deux sens sur les demandes directes, propositions, ouverture, texte/contact et pièces jointes préparées avant blocage. Appels aux endpoints historiques utilisés sans dépendre d’un bouton Flutter. Absence de nouveau message/outbox pour les envois refusés ; ancien push en attente non livré après blocage.
- A signale B, C examine/avertit, A bloque B puis débloque, historique A/B lisible ; B reprend le contact après déblocage ; C masque/restaure une demande, suspend/restaure le compte, avec contrôles d’une ancienne session.
- Admin non habilité et claims révoqués refusés ; lecture SDK directe des signalements/blocages refusée même à un token admin ; révision concurrente en transactions Firestore réelles, audit/idempotence ; un ancien dossier ne peut restaurer une sanction plus récente.
- Lecture publique directe et ancienne requête du fil après retrait ; modification d’un miroir privé par un ancien parcours sans republication ; quotas et statut métier conservés.
- Miniatures privées bornées et figées, purge à 90 jours ; pièce jointe PDF réelle envoyée en HTTP, signalée, téléchargée par C via son dossier et refusée à D. Aucun chemin de fichier arbitraire n’est accepté.
- Régressions V5–V9.2, quotas/publication, annuaire Professionnels, notifications, conversations préexistantes, médias privés, recommandations et droits existants exécutées dans les suites complètes.

## Échecs intermédiaires corrigés et avertissements

Le premier passage Node conservait une assertion comptant les lectures d’un réessai : elle a été adaptée à la lecture obligatoire de `accountSafety`, sans retirer les contrôles d’idempotence/quota. Le premier passage Emulator a révélé l’exposition du recommendeur dans une notification qui devait rester neutre : le contrôle de sécurité utilise maintenant l’outbox privée, et le champ public reste neutre. La relance complète passe.

Une relance a rencontré un port Firestore déjà occupé : le runner du sprint choisit désormais ses ports locaux disponibles. Le correcteur automatique Dart a été suivi d’une réparation d’un conflit d’édition/encodage, puis du formatage, de l’analyse et des tests réussis. Aucun échec de validation connu n’est laissé ouvert.

Le runtime Java des règles Storage affiche une exception de fin d’entrée à l’arrêt des émulateurs, après les assertions et après « Script exited successfully (code 0) ». Elle ne correspond pas à un échec des tests. Le Scheduler n’est pas démarré dans cette configuration : la purge est testée via le service, et son déclenchement réel doit être validé en recette.

## Non réalisés et limites

- Pas de déploiement Functions/règles/index, pas de validation IAM de production, pas de production de binaire mobile ni de distribution.
- Pas de push FCM réel ni d’e-mail envoyé à l’adresse d’assistance. Les essais de transport sur vrais appareils restent à faire en recette autorisée.
- Les captures sont des widgets Flutter réels avec les thèmes de l’application et d’Admin, alimentés par des jeux de données de test ; elles ne prétendent pas montrer des comptes de production.
- Le comportement TTL effectif et le déclenchement Cloud Scheduler doivent être confirmés dans le projet de recette. Aucun test n’est présenté comme preuve de conformité juridique ou store.

Les journaux techniques locaux complets sont dans `.dart_tool/sprint1-*.log` (ignorés par Git). Les commandes reproductibles, les contrats, les durées proposées et le plan à faire approuver figurent dans [le bilan](sprint-1-securite-bilan.md).
