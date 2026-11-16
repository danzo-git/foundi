# Complément Sprint 2.6 — profils, répondants et conversations

Ce complément traite les lenteurs signalées après recompilation de l’application. Les mesures du premier passage, centrées sur Explorer avec des dépôts fictifs, ne suffisaient pas à valider ces parcours.

## Causes et corrections

| Parcours | Cause relevée | Correction |
|---|---|---|
| Profil d’un demandeur professionnel | Le parent lisait l’auteur avec son profil complet, puis le sous-écran relançait immédiatement la même lecture | Réponse déjà autorisée transmise au sous-écran pour le premier affichage : un seul appel initial. La réponse initiale ne remplace jamais une relecture ultérieure |
| Profils | Attente sans borne locale fiable, réponses pouvant arriver après une pause ou un changement de cible | Délai de lecture de 20 s, tentative suivante possible, générations de réponse et masquage des médias pendant une revalidation non confirmée |
| Liste des répondants | Jusqu’à vingt vérifications de professionnels successives ; pages filtrées parfois vides ; état de chargement non borné | Quatre vérifications serveur simultanées, ordre conservé ; poursuite de trois pages vides au maximum ; délai global de 20 s et rejet des réponses d’une ancienne demande |
| Ouverture d’un profil de répondant | Pas de revalidation périodique sur ce chemin | Le profil complet fraîchement vérifié remplace l’ancien lors du renouvellement, avec retrait du répondant devenu indisponible |
| Messagerie | Attente conjointe du document et de l’absence du marqueur de suppression confirmée serveur ; flux pouvant rester silencieux | Erreur initiale après 12 s, possibilité de réessayer et écoute conservée pour la reconnexion. Le silence n’autorise jamais l’affichage privé |
| Liste des conversations | Des changements fréquents de contenu invalidaient continuellement une vérification en cours | Les modifications sur les mêmes identifiants utilisent les valeurs les plus récentes sans affamer le premier affichage. Une suppression ou un changement d’ensemble invalide toujours la lecture |
| Erreurs des conversations | Un événement de l’autre flux pouvait republier un ancien état après erreur | L’état correspondant est retiré sur erreur ; les deux conditions doivent à nouveau être satisfaites. La réécoute du flux messages après récupération est préservée |
| Images | Une file d’attente pouvait ajouter plusieurs délais réseau successifs | Quatre chargements et 96 attentes au maximum ; un budget de 20 s inclut la file et le réseau, transmis au transport. Les tâches expirées en attente ne partent pas ensuite |

Les lectures simultanées identiques peuvent partager une requête en cours, sans conserver de réponse achevée. La portée comprend l’identité, sa session et une génération de validation. Une reprise, une modification de photo/profil ou un blocage impose une nouvelle portée. Le cache médias réalise déjà sa propre déduplication : son transport n’emprunte pas un ancien RPC après invalidation. Les erreurs réseau de pagination conservent les réponses visibles ; un retrait/refus d’accès réel les retire.

Les validations serveur finales, les vérifications de blocage/suspension/suppression et les quotas sont conservés. Le masque des champs limite les documents de dossier téléchargés par le backend, sans changer les informations publiques renvoyées. Le décodage des images du profil est adapté à leur taille affichée. Aucun nouveau service ni changement d’instances permanentes.

Une réalisation ouverte en grand se ferme dès que le bail de consultation doit être revérifié ou que l’application passe en arrière-plan. Une erreur réseau ou un délai dépassé ne laisse ainsi pas sa photo visible dans un dialogue au-dessus du profil masqué. Seule la route de cette photo est retirée.

## Observation des API publiques en production, avant ce complément serveur

Une sonde anonyme a effectué trois lectures par endpoint depuis le PC. Les identifiants utilisés et les réponses personnelles ne sont pas enregistrés. La sélection est limitée à des demandes publiquement lisibles ; aucun compte connecté ni conversation privée n’a été consulté. La sonde mesure HTTP, pas Flutter sur téléphone.

| Endpoint public | Premier appel | Deux suivants | Médiane des 3 | Corps JSON décodé par réponse |
|---|---:|---:|---:|---:|
| `listPublicProfessionals` | 4 652 ms | 695 / 610 ms | 695 ms | 1 179 octets |
| `readPublicProfessionalProfile` | 6 346 ms | 802 / 577 ms | 802 ms | 517 octets |
| `listRequestRespondents` | 3 456 ms | 185 / 165 ms | 185 ms | 76 octets |
| `readRequestAuthorProfile` | 4 797 ms | 1 188 / 1 044 ms | 1 188 ms | 94 octets |

Ces petites réponses ne représentent pas un profil avec toutes ses photos ni une page de vingt professionnels. Les écarts entre premier appel et suivants sont compatibles avec un coût d’initialisation, mais la sonde ne sépare pas les cold starts, l’authentification serveur, le réseau et le temps Firestore. Aucun p95 n’est publié avec seulement trois échantillons. Les octets sont ceux du corps décodé, pas un volume réseau complet ou une facture Firebase.

Données brutes : `public-read-baseline.json`. Ce sont des mesures avant déploiement de ce complément ; aucune mesure « après en production » n’est revendiquée.

## Comparaisons contrôlées du code serveur

Avec vingt échantillons chauds par version, ordre alterné et faux I/O différés de 3 ms :

| Parcours | Médiane avant → après | p95 avant → après | Lectures du faux store |
|---|---:|---:|---:|
| 20 répondants | 388,3 → 150,3 ms | 406,1 → 167,4 ms | 104 → 104 |
| Profil professionnel | 130,9 → 96,3 ms | 133,8 → 100,0 ms | 11 → 11 |
| Auteur professionnel | 266,4 → 183,6 ms | 283,3 → 200,0 ms | 26 → 22 |

Il s’agit de scénarios contrôlés, pas de gains garantis au téléphone. Voir `backend-loading-notes.md`, le JSON `backend-loading-comparison.json` et les empreintes des sources qui y figurent. Le double appel initial du client est également vérifié par test : un appel auteur à l’ouverture, y compris pour un auteur professionnel.

## Validation et activation

Validation du 16 novembre 2026 :

- `flutter test --no-pub --reporter expanded` : 280 tests réussis, suite complète.
- Après la dernière protection du dialogue photo, `flutter test test/profile_loading_followup_test.dart --no-pub --reporter expanded` : 5 tests réussis, dont les deux nouveaux cas d’expiration du bail avec erreur réseau et de mise en arrière-plan. Les trois autres tests étaient déjà inclus dans les 280 : 282 scénarios distincts couverts au total.
- `flutter analyze --no-pub` et l’analyse directe finale `dart analyze` : aucune anomalie.
- `npm --prefix functions test` : 248 tests réussis ; `npm --prefix functions run check` réussit.
- `node functions/scripts/test-v82-emulators.cjs --safety-only --loading-only` : 40 tests de règles et 8 intégrations réussis (auteurs, annuaire, répondants, conversations, suppression et avatars). Code de sortie 0 ; les avertissements Java arrivent à l’arrêt des émulateurs, après les tests.
- `git diff --check` réussit. Les fichiers de configuration temporaires des émulateurs ne restent pas dans le dépôt.

Les tests unitaires des flux utilisent explicitement une horloge `fake_async`, déjà présente dans les dépendances transitives Flutter et désormais déclarée en dépendance de développement. Cela évite le blocage du planificateur de frames observé dans le test initial ; la reprise des écrans reste testée avec les vrais widgets. Aucun ajout à l’application livrée.

Les nouveaux tests couvrent les lectures muettes, les réponses tardives après retry, les changements de demande/compte, le retrait d’accès, la reprise après erreur, l’annulation et la réécoute des abonnements, les files saturées/expirées, l’invalidation des photos en vol et les contrôles serveur apparus pendant une lecture.

Le code Flutter doit être recompilé pour les nouvelles corrections côté application. Après autorisation explicite, les cinq fonctions serveur ont été déployées le 16 novembre 2026 sur `foundi-7c837`, codebase `auth`, région `europe-west1` : `listRequestRespondents`, `readRequestRespondentProfile`, `readRequestAuthorProfile`, `readPublicProfessionalProfile`, `readPublicProfessionalMedia`. Firebase confirme cinq opérations de mise à jour réussies et la commande termine avec le code 0. Aucune règle Firebase supplémentaire n’est nécessaire. Aucun APK n’a été distribué.

Commande exécutée :

```powershell
firebase deploy --only 'functions:auth:listRequestRespondents,functions:auth:readRequestRespondentProfile,functions:auth:readRequestAuthorProfile,functions:auth:readPublicProfessionalProfile,functions:auth:readPublicProfessionalMedia' --project foundi-7c837 --non-interactive
```

Les contrôles de pré-déploiement ont rejoué les 248 tests Node, tous réussis, puis `check`, réussi. Le contrôle HTTP après déploiement, effectué à 17:14:24 UTC, obtient HTTP 400 / `INVALID_ARGUMENT` sur chacun des cinq endpoints avec une requête anonyme vide. Il confirme leur disponibilité et la validation des entrées sans sélectionner de compte, de demande ou de photo. Résultats : `five-functions-deployment-smoke.json`. Ce contrôle ne constitue pas une recette connectée des données utilisateur ni une mesure des performances après déploiement.

Les photos restent incluses dans les réponses de profils complets, et les premiers appels peuvent donc encore être longs. Les délais de 12/20 s évitent une attente sans issue ; ils ne rendent pas un appel lent instantané. Une nouvelle recette connectée après livraison reste nécessaire pour mesurer les parcours privés, les photos volumineuses, les coûts réels et le gain sur téléphone. Aucun journal de performance ajouté ne contient de nom, adresse, message, photo ou jeton utilisateur.
