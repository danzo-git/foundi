# Sprint 2.5 — résultats réels de vérification

> Extension Rennes uniquement : **207 tests backend, 24 tests Flutter ciblés, 18 tests Admin et 1 scénario Firebase réussis**, analyses sans anomalie. Voir [la recette Rennes](rennes-localisation-2026-11-15.md).

> Dernière révision : profils auteurs et localisation — **207 tests Flutter, 204 tests backend, 2 scénarios Firebase réussis, analyse sans anomalie et compilation Android réussie**. Voir [le détail et les limites de recette GPS](profils-auteurs-localisation-2026-11-15.md).

> Révision photo de compte commune : **197 tests Flutter, 190 tests backend et 4 scénarios Firebase ciblés réussis**, analyse sans anomalie. Résultats et captures détaillés dans [la recette du 15 novembre](photo-identite-compte-2026-11-15.md). Les résultats ci-dessous décrivent la recette initiale du sprint.

Exécutions locales du 15 novembre 2026, branche `codex/foundi-sprint-2-5-finitions`. Aucune opération de déploiement, de publication ou de suppression de compte réel.

| Contrôle | Résultat | Trace locale |
| --- | --- | --- |
| `npm --prefix functions test` | 189 tests réussis, 0 échec | `.dart_tool/sprint25-node-final.log` |
| `npm --prefix functions run check` | Contrôle serveur/scripts réussi | `.dart_tool/sprint25-check-final.log` |
| `flutter test --no-pub --concurrency=1 --dart-define=SPRINT25_CAPTURE=true` | 194 tests réussis, 0 échec | `.dart_tool/sprint25-flutter-final.log` |
| Recette ciblée finale formulaires/directes/captures | 27 tests réussis, 0 échec | `.dart_tool/sprint25-captures-final.log` |
| Suite Admin avec captures | 16 tests réussis, 0 échec | `.dart_tool/sprint25-admin.log` |
| `flutter analyze --no-pub` | Aucune anomalie | `.dart_tool/sprint25-analyze-final.log` |
| Analyse Admin | Aucune anomalie | `.dart_tool/sprint25-admin-analyze.log` |
| `npm --prefix functions run test:sprint25:emulators` | 40 tests de règles et 5 scénarios d’intégration réussis, code de sortie 0 | `.dart_tool/sprint25-emulators-final.log` |
| Recette complémentaire de reprise Storage | 3 tests réussis, 0 échec | `.dart_tool/sprint25-media-recovery.log` |
| Analyse complémentaire des fichiers ajustés | Aucune anomalie | `.dart_tool/sprint25-analyze-targeted.log` |
| `git diff --check` | Aucun défaut d’espace | Contrôle local |

Les comptes/demandes/images/notifications Firebase appartiennent exclusivement aux projets `demo-foundi*` et aux émulateurs locaux. Les appels push sont simulés ou désactivés. L’avertissement Java lors de l’arrêt de Firestore est distinct des résultats TAP et du code de sortie 0.

Les scénarios d’intégration vérifient :

- Une audience de 87 professionnels éligibles, après toutes les pages, avec trois zones communes, catégories et spécialités différentes ; exclusion de l’auteur, des comptes hors zone, pending/rejetés/désactivés/suspendus/en suppression et des deux directions de blocage.
- Classification précise → catégorie sans spécialité → non classé ; rejeu et concurrence sur les tâches ; une seule alerte finale par destinataire. Une alerte au format historique est également reconnue sans duplication.
- Présence de l’alerte dans l’application malgré la préférence push désactivée ; respect de cette préférence pour l’outbox ; conservation des protections FCM existantes.
- Image JPEG réellement normalisée en WebP 256 × 256 sans EXIF ; consentement explicite, aucun import Google, remplacement avec version, refus de l’ancien média après révocation, données privées jamais exposées, résolution historique bornée et purge complète du fichier/mapping.
- Parcours existants de notifications et de suppression de compte : Auth supprimé en dernier, anciens jetons refusés, données et mesures des autres membres préservées.

Les tests Flutter couvrent l’image autorisée, absente, révoquée et en erreur réseau ; les sélections de une à trois zones et leur retrait ; l’aperçu ; le consentement ; les références historiques ; les demandes privées verrouillées ; les écrans 320 px/grandes polices. Le contrôle complémentaire `sprint25-captures-verified.log` ajoute la double sélection sans duplication et régénère les captures après raccourcissement du bouton de confirmation pour l’accessibilité. L’analyse complémentaire de ces fichiers est dans `sprint25-analyze-targeted.log`. La recette ciblée `test:sprint25:media:emulators` contrôle aussi une panne temporaire de suppression Storage : retrait public conservé, entrée de nettoyage persistante, reprise horaire et disparition du fichier ; trace `sprint25-media-recovery.log`. Cette recette utilise aussi les véritables callables de photo et le endpoint HTTP local pour vérifier envoi, résolution, lecture WebP, cache interdit et révocation.

Le GPS réel n’est pas simulé comme une fonctionnalité livrée : le bouton explique son indisponibilité, aucune permission ou coordonnée n’est demandée et la sélection manuelle demeure intacte. Les cas de précision insuffisante, refus de permission et hors Côte d’Ivoire restent liés au futur mécanisme GPS → zone.

Les captures sont générées par le rendu Flutter des widgets de production avec le thème Foundi et des données fictives ; elles incluent les fenêtres du Navigator. Elles ne sont ni des maquettes redessinées ni des captures de comptes de production. La photo de test est un bitmap synthétique. Voir [le dossier des captures](sprint-2-5-captures/README.md).

Les totaux des suites générales et ciblées ne s’additionnent pas : plusieurs tests sont communs. Les premières exécutions ont servi à corriger les attentes devenues obsolètes (spécialité désormais facultative), les sélecteurs à grandes polices, le libellé de notification et l’aperçu du service non classé. Les résultats ci-dessus correspondent aux exécutions corrigées.
