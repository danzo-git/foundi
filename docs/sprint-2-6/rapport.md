# Foundi — Sprint 2.6 : audit et optimisation des performances

Date : 16 novembre 2026. Branche : `codex/foundi-sprint-2-6-performance`.
Référence avant optimisation : `b8546e888d1f2ff7c057a03db0895d78ce461d50`.

Complément après les lenteurs signalées sur l’application recompilée : [profils, répondants et conversations](chargements-profils-conversations.md). Il distingue les mesures HTTP publiques et les comparaisons serveur contrôlées. Après autorisation explicite, les cinq fonctions de ce complément ont été déployées avec succès le 16 novembre 2026 ; le contrôle HTTP des cinq endpoints réussit. Les corrections Flutter nécessitent une nouvelle compilation de l’application.

## Périmètre et fiabilité des mesures

Les deux vues Explorer ont été évaluées en **Flutter profile sur un Samsung SM A556B physique, Android 17/API 37**, avec les vrais widgets et des dépôts synthétiques. Flutter 3.44.3, Dart 3.12.2, compilation Android arm64. Le diagnostic possède le package distinct `com.example.foundi.performance`, sans initialisation Firebase depuis son point d’entrée Dart. Aucun compte réel n’a servi aux scénarios. Il ne constitue pas une recette de l’application connectée à la production.

Le catalogue synthétique répond après 250 ms, les demandes après 80 ms. Ces délais sont des paramètres du scénario, **pas des latences réseau mesurées**. Chaque version effectue 21 ouvertures successives : la première est isolée et les 20 suivantes servent à la médiane et au p95 (rang supérieur, 19e valeur triée). Les durées couvrent la création de la vue jusqu’à la présence du premier titre, puis une fin de frame. La sonde vérifie l’arbre à environ 16 ms d’intervalle : ce n’est pas une mesure au pixel près. La première ouverture ne mesure pas le démarrage complet Firebase/FCM de Foundi.

Le service Node d’avatars est testé séparément sur 12 conversations fictives, avec des lectures mémoire différées de 3 ms. La résolution réelle des timers Windows et la charge de la machine influencent les durées. Même protocole : une première exécution isolée, puis 20 échantillons. Ce test mesure le code du service avec des entrées/sorties simulées, **pas une invocation Cloud Functions déployée**.

Les fichiers JSON adjacents contiennent les échantillons et compteurs bruts, sans identité, message, adresse, jeton ni URL de photo réels. Les p95 portent seulement sur ces scénarios et ces petits échantillons.

## Diagnostic avant optimisation

NM = non mesuré sur le parcours connecté. Les nombres de requêtes ci-dessous décrivent le code, et non une facturation constatée. Les lectures de documents, lectures d’index, contrôles de règles, reconnexions et caches SDK rendent incorrecte l’assimilation « une requête = une lecture ».

| Parcours | Médiane / p95 avant, connecté | Requêtes et chargements observés dans le code avant | Lectures Firestore réelles | Octets transférés réels | Décision |
|---|---|---|---|---|---|
| Explorer — Demandes | NM ; scénario profile ci-dessous | Catalogue attendu avant abonnement ; requête limitée à 30 ; filtre zone : deux requêtes pour compatibilité des anciens documents ; résolution d’avatars attendue avant livraison des lignes | NM | NM | Découpler le catalogue et les avatars du premier affichage ; garder les deux requêtes de compatibilité |
| Explorer — Professionnels | NM | Catalogue à chaque chargement ; recherche paginée ; un manifeste et jusqu’à quatre miniatures par carte ; méthodes de lecture des miniatures relancées à chaque reconstruction | NM | NM | Mutualiser le catalogue et mémoriser les futures par carte ; conserver pagination et vérifications |
| Cartes, avatars et photos | NM | Cache médias existant 96 entrées/2 Mio/30 s ; invalidation n’arrêtant pas une réponse en vol ; avatar personnel validé par projection serveur ; jusqu’à trois photos de demande | NM | NM | Corriger l’invalidation des réponses tardives ; décodage des miniatures d’annuaire adapté à la taille affichée et au ratio écran |
| Profils publics | NM | Chargement frais du profil ; photos intégrées au profil ; vérifications de disponibilité et bail de 30 s | NM | NM | Préserver les validations ; ne pas ajouter un cache de profils qui contournerait suppression, blocage ou suspension |
| Mon compte | NM | Profil professionnel privé lu à l’ouverture si approuvé ; catalogue suivi indépendamment par les écrans | NM | NM | Partager les références publiques ; conserver les chargements privés et frontières d’identité |
| Mes demandes | NM | Abonnement privé limité à 50 ; résolution des auteurs directs historiques si nécessaire ; avatars optionnels attendus avant affichage | NM | NM | Livrer les données autorisées avant les avatars ; conserver la résolution privée des auteurs |
| Messagerie et conversations | NM | Deux abonnements de liste (conversations + état de suppression), événements initiaux pouvant doubler la lecture des suppressions ; pages de 30 jusqu’à remplissage ; résolution d’avatars séquentielle | NM | NM | Fusionner les rafales de rafraîchissement, sérialiser le travail et paralléliser quatre résolutions d’avatar côté service |
| Notifications | NM | Compteurs par document, liste limitée à 30/maximum 100 ; pagination des anciennes notifications avec lecture du curseur ; abonnements déjà stabilisés dans les widgets | NM | NM | Conserver le temps réel et les compteurs ; pas de cache des notifications privées |
| Formulaires / catalogue | NM | `loadCatalog()` relit systématiquement le document ; chaque `watchCatalog()` ouvre son propre abonnement | NM | NM | Une valeur mémoire publique, TTL 30 s, requêtes simultanées partagées, un abonnement partagé et libéré au dernier départ |

Le shell conserve déjà Explorer lors des retours. Les autres écrans privés peuvent être recréés lors de la navigation. Ils ne sont pas tous maintenus artificiellement en arrière-plan : cela ouvrirait davantage d’abonnements et prolongerait la durée de vie des données privées. Les références publiques et médias autorisés bénéficient des optimisations sans supprimer leurs vérifications d’accès.

## Comparaison contrôlée avant / après

Résolution du téléphone : 1080 × 2340, densité Android 450 dpi. Les résultats bruts figurent dans les quatre JSON adjacents.

| Mesure | Avant | Après | Interprétation |
|---|---:|---:|---|
| Explorer : médiane de 20 ouvertures, profile physique | 368,307 ms | 113,970 ms | −69,1 % ; dépôts synthétiques, mêmes délais et 30 demandes |
| Explorer : p95 des ouvertures | 378,472 ms | 118,757 ms | −68,6 % ; premier affichage, réseau de production exclu |
| Première ouverture de la vue dans le diagnostic | 481,999 ms | 467,751 ms | Un seul échantillon par version ; aucun gain de démarrage à froid démontré |
| Miniatures : appels de méthode après 20 reconstructions | 84 | 4 | Inclut les 4 appels initiaux ; ne représente pas 84 RPC Firebase : le cache existant en regroupait déjà une partie |
| Abonnements demandes / annulations, 21 ouvertures | 21 / 21 | 21 / 21 | Pas d’abonnement restant après démontage dans ce scénario |
| Appels catalogue dans le diagnostic | 22 | 22 | Le faux dépôt ne simule pas le nouveau cache ; ce compteur ne mesure donc pas sa réduction réelle |
| Construction des frames : p95 du diagnostic complet | 4,427 ms | 7,474 ms | Distribution de frames différente ; aucun gain de rendu global démontré |
| Rasterisation : p95 du diagnostic complet | 7,641 ms | 9,483 ms | Distribution de frames différente ; valeur supérieure après optimisation |
| Service avatars : médiane, 12 conversations fictives | 1 175,829 ms | 363,772 ms | Environ 69 % de baisse dans ce scénario Node |
| Service avatars : p95 | 1 277,765 ms | 431,105 ms | Environ 66 % de baisse dans ce scénario |
| Service avatars : lectures du faux store par exécution | 196 | 196 | Aucun contrôle supprimé ; pas une mesure de facturation |
| Import d’identité par interlocuteur répété | 1 | 1 | Mutualisation conservée dans une invocation |

Les temps de construction/rasterisation des frames portent sur l’ensemble du diagnostic, y compris les frames de sonde et transitions : 1 096 frames avant, 471 après. La version plus rapide passe moins de temps sur les frames de chargement ; les populations ne sont donc pas identiques. Les p95 supérieurs après doivent rester visibles dans le bilan : ce sprint démontre un premier affichage plus rapide dans le scénario, et ne démontre pas une amélioration générale du rendu. Une mesure de défilement avec durée et contenu identiques reste à réaliser sur des données représentatives.

### Réseau, serveur, images et rendu

| Composante | Ce qui a été mesuré | Limite |
|---|---|---|
| Réseau | Aucun transport distant dans le diagnostic téléphone ; délais de dépôts fixés | Latence HTTP/Firestore, TLS, authentification et transfert réel : NM |
| Serveur | Durée du service Node avec faux store et temporisations ; compteur exact de lectures simulées | Durée Cloud Functions, démarrages à froid et lectures facturées : NM |
| Décodage images | Les images synthétiques sont réellement affichées et le dimensionnement de décodage est couvert par le code | Pas de chronométrage isolé du codec sur un jeu de photos réelles ; NM |
| Rendu | `FrameTiming.buildDuration` et `rasterDuration` sur le téléphone | La rasterisation peut inclure d’autres travaux ; elle n’isole pas le coût du codec |

## Modifications et sécurité

- Le catalogue public partage désormais les lectures simultanées et les abonnements dans une instance de dépôt. Une seule valeur est conservée, pendant 30 s ; une mise à jour du flux remplace la valeur et une erreur l’invalide. Le dernier abonné ferme la source. Aucune donnée de profil ou décision d’autorisation n’y est stockée.
- Le cache des médias d’annuaire reste limité à 96 entrées et 2 Mio de données encodées, TTL 30 s, avec quatre chargements concurrents au maximum. Cette limite ne représente pas le tas Flutter total ni les images décodées du cache du moteur. L’invalidation retire aussi les requêtes en attente du registre : leurs anciennes réponses sont rejetées et ne peuvent ni repeupler le cache ni effacer la requête suivante.
- Les futures de miniatures sont réutilisées tant que la carte et sa validation restent identiques. Changement d’identité, dépôt ou état de validation : remise à zéro et nouvelle clé de widget, empêchant `FutureBuilder` de réafficher une ancienne photo pendant la vérification. Une échéance locale attachée au manifeste conserve sa date d’expiration d’origine même lors d’une réutilisation du cache. Les images visibles expirent et sont rechargées après cette échéance ; un renouvellement très rapide de disponibilité ne prolonge donc pas leur validité. Le timer est annulé au retrait de la carte ou de sa validation. L’expiration ne lance pas de téléchargement lorsque la route est couverte ; le retour vérifie l’échéance.
- Les données de demandes issues du flux autorisé sont livrées avant leurs avatars optionnels. Une nouvelle génération, une erreur ou l’annulation empêche une ancienne réponse asynchrone de réintroduire des lignes. Les demandes sont retirées de l’écran Explorer si le flux signale une erreur.
- Le catalogue n’empêche plus l’affichage des demandes publiques. Une panne du catalogue laisse le contenu utilisable ; les filtres permettent une nouvelle tentative, avec un message discret si elle échoue. Les opportunités professionnelles continuent d’attendre leurs références et validations nécessaires.
- Les rafales de messagerie déclenchent au maximum un traitement à la fois et un traitement final si des changements arrivent pendant l’opération. L’état des suppressions reste vérifié côté serveur, sans cache persistant ; les nouvelles données invalident immédiatement le résultat en cours.
- Les quatre pipelines du service d’avatars conservent les contrôles de compte, appartenance, blocage, suppression et projection publiée, ainsi que leur revérification après import. Le parallélisme est interne à l’invocation ; les réglages d’instances/concurrence Cloud Functions restent identiques.

Ni les photos personnelles ni les messages privés ne sont ajoutés à un cache public. Les baux de disponibilité, le refus d’afficher une photo personnelle à partir d’une projection seulement locale et les contrôles de publication restent en place. Le détail public d’une demande utilise aussi la livraison progressive et les générations de réponse, à la place d’une file `asyncMap` pouvant attendre les anciens avatars. Les profils publics restent chargés frais : c’est une limite explicite de cette livraison.

## Validation

| Vérification | Résultat |
|---|---|
| Analyse Flutter | Aucune anomalie, y compris après le garde d’expiration |
| Suite Flutter complète | 248 tests réussis |
| Caches, vues et annuaire après ajout de l’échéance des médias | 20 tests ciblés réussis lors de la confirmation finale |
| Suite Node | 240 tests réussis |
| Vérifications Node du dépôt et syntaxe du module ajouté | Réussies |
| Firebase Emulator : règles Firestore / Storage | 40 tests réussis, aucun ignoré |
| Firebase Emulator : avatars de conversations | 1 scénario d’intégration réussi, avec comptes, blocages, suspension et retrait de photo |
| Compilation Android profile normale | Réussie ; package normal vérifié avec `aapt`, sans installation de cette version sur le téléphone |

Les nouveaux tests couvrent : déduplication, expiration, erreur réseau et reprise, bornes LRU/octets, invalidation en vol et remplacement, partage/annulation d’abonnements, rafales et annulation de rafraîchissement, catalogue lent/indisponible, retour Explorer conservé et retrait des images pendant revalidation. Le test d’expiration avance le temps au-delà du bail avec une vérification de disponibilité immédiate, puis quitte/revient sur la vue et vérifie la libération des timers. Le diagnostic profile court ne mesure pas ce renouvellement à 30 s ; celui-ci est couvert par ces tests ciblés.

Un test existant sur petit écran attend maintenant la mise en page après `ensureVisible`, pour calculer les coordonnées du geste après défilement. Les huit tests de suppression puis la suite complète passent. Les émulateurs affichent un avertissement Java à leur arrêt forcé ; leurs tests et leurs scripts terminent avec le code 0.

La connexion lente et la perte/reprise de réseau sont simulées dans les dépôts et caches des tests. Il n’a pas été pratiqué de coupure Wi-Fi/données mobiles du téléphone personnel. Le profilage mémoire du processus complet connecté et une session DevTools sur des comptes de recette restent nécessaires pour confirmer l’absence de fuite globale ; les tests démontrent la libération des abonnements et timers dans les scénarios couverts, pas une preuve exhaustive d’absence de fuite.

## Coûts, limites et préparation de publication

Aucun service, SDK de monitoring, instance permanente ni index Firebase ajouté. Après autorisation explicite du 16 novembre 2026, seule la fonction `resolveConversationAvatars` a été déployée sur `foundi-7c837`, en `europe-west1`, avec la commande `firebase deploy --only functions:auth:resolveConversationAvatars --project foundi-7c837 --non-interactive`. Firebase confirme la mise à jour réussie. Les 240 tests Node et la commande `check` du dépôt passent lors du pré-déploiement. Le contrôle effectué à 01:43 UTC renvoie HTTP 401 / `UNAUTHENTICATED` pour un appel anonyme sans données utilisateur : la fonction répond et conserve son contrôle d’authentification. Les mesures synthétiques ci-dessus ne sont pas des mesures de production après déploiement. Les optimisations client restent locales et aucun APK n’a été distribué. Aucune règle Firestore/Storage ne change pour ce sprint.

Les appels catalogue et le travail de rafraîchissement peuvent diminuer, mais le montant économisé reste non mesuré. Le renouvellement des images expirées visibles peut au contraire déclencher un manifeste et jusqu’à quatre miniatures par carte : leur mémorisation ne doit pas prolonger un ancien accès après l’échéance. Le bilan net des lectures et octets reste à mesurer. Le nombre de lectures du test d’avatars est identique ; son gain vient du chevauchement des attentes. Jusqu’à quatre résolutions augmentent temporairement la concurrence des lectures dans une invocation, sans relever le nombre d’instances. Il faut confirmer la durée et la charge sur un environnement de recette avant publication.

Les cold starts, le téléchargement des profils avec photos intégrées, les photos de demandes complètes, les retours sur certains écrans privés et les lectures de suppression nécessaires à la messagerie restent à observer avec de vraies données représentatives. Le catalogue peut être ancien d’au plus 30 s dans son cache ; les écritures métier continuent à être revalidées par le serveur. Une revalidation d’accès peut toujours retirer temporairement les médias : ce comportement de sécurité est conservé.

Les lectures et reconnexions des listeners sont facturées selon les règles Firebase, et non selon le seul nombre de méthodes Dart appelées : [documentation Firestore](https://firebase.google.com/docs/firestore/pricing). Les instances minimales et la concurrence de service n’ont pas été modifiées : [documentation Cloud Functions](https://firebase.google.com/docs/functions/manage-functions). Le choix d’un téléphone réel et du mode profile suit les [recommandations Flutter](https://docs.flutter.dev/perf/ui-performance).

Le fichier `public-privacy/assets/deletion.js`, déjà modifié avant le sprint, est préservé et ne fait pas partie de ces optimisations.

Le package de diagnostic a été retiré du téléphone ; seule l’application Foundi normale y reste. Les processus de tests orphelins ont été arrêtés après vérification de l’absence de leurs lanceurs. Aucun émulateur Firestore de test Foundi ne reste actif, les configurations temporaires ont été nettoyées et le daemon Gradle de compilation a été arrêté. L’APK initial portant le mauvais identifiant a également été supprimé des fichiers temporaires.

### Incident de préparation locale

La première compilation du diagnostic n’a pas pris en compte le paramètre Gradle d’isolation par variable d’environnement. Elle a été installée avec l’identifiant normal avant vérification. Le dernier APK normal local a été immédiatement réinstallé avec `adb install -r`, sans désinstallation ni effacement des données. Cette première installation n’a fourni aucune mesure. L’isolation est désormais déterminée directement par le `dart-define` de compilation ; le package contenu dans l’APK est vérifié avec `aapt` avant installation. Les mesures publiées proviennent exclusivement du package distinct vérifié.
