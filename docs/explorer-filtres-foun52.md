# Avenant FOUN-52 — Explorer commun et Pour moi

Cette correction remplace l'ancienne présentation FOUN-52 décrite dans `demandes-v6.md`. Elle suit le document `Foundi_FOUN52_Avenant_Codex (1).md` et la planche SVG joints. Aucun changement Jira. Le déploiement des index, autorisé après la livraison initiale, est décrit en fin de document. Les données des maquettes restent des exemples, absents du code de production.

## Audit préalable

Explorer V5 utilisait `RequestListView` et `watchPublic()` : un flux public temps réel des 30 demandes `published` les plus récentes, sans filtres. Le visiteur et le shell connecté avaient leurs propres points d'entrée vers cette liste. V6 avait ajouté un écran indépendant `OpportunityView`, un endpoint `listOpportunities` réservé aux professionnels approuvés et un index composite ciblé.

Les modèles V5 contiennent déjà `categoryId`, `specialtyId`, `zoneId`. `ProfessionalCatalog` fournit les références actives de `referenceData/professionalOnboarding`, les spécialités liées à chaque catégorie et les zones avec les libellés hiérarchiques. `ProfessionalProfile.activity` contient les catégories, spécialités et zones approuvées. La propriété d'une demande reste privée, dans son chemin auteur.

FOUN-40 n'a pas été redéveloppé : aucun changement des transitions, confirmations, formulaire d'édition, logique serveur, droits auteur ou suppression. La correction de navigation conserve l'état de son formulaire et des brouillons de publication.

## Comportement livré

- Un seul composant `ExplorerView` pour visiteurs, clients et professionnels. L'ancien écran autonome `OpportunityView` est supprimé. L'entrée professionnelle d'accueil ouvre ce même Explorer en mode Pour moi ; l'onglet Explorer et le retour d'un détail conservent la sélection courante.
- Tout Explorer : filtres manuels par catégorie, spécialité et zone, alimentés par le catalogue actif. Une sélection par dimension, combinée par ET. Changer de catégorie efface la spécialité ; la spécialité est indisponible sans catégorie. Un choix vide n'ajoute pas de contrainte.
- Le segment Pour moi apparaît seulement si le dossier est `approved` et l'espace professionnel actif. Les critères du dossier restent appliqués par `listOpportunities` côté serveur. Les sélections manuelles ne font que réduire ces critères ; Effacer retire les filtres manuels, sans désactiver Pour moi. Les critères vides sont transmis comme absents pour reprendre le domaine du dossier, jamais comme de nouvelles catégories.
- Plusieurs catégories, spécialités ou zones du dossier restent une union, sans doublons, même si les filtres manuels ne proposent qu'un choix par dimension. Les demandes de l'auteur sont exclues par le serveur seulement dans Pour moi ; elles restent dans Tout Explorer.
- Les deux modes conservent leurs filtres manuels séparément. Le passage au détail conserve les filtres et le mode. Le changement de compte dispose le shell ; une suspension ramène au public et invalide les réponses personnalisées en cours.
- Un profil approuvé sans activité/spécialité ou zone exploitable affiche une explication et un lien vers les informations professionnelles existantes. Il ne charge pas arbitrairement le fil général comme opportunités.
- Les cartes et le détail public V5 sont réutilisés. Chargement, erreurs/réessai, compteur de résultats affichés, filtres visibles/effaçables et états vides. Aucun bouton de recherche décoratif ni moteur de recherche ajouté.

Les zones sont comparées par identifiant exact. Leur hiérarchie est conservée dans les libellés Admin ; il n'y a pas d'expansion automatique d'une zone parent ni de correspondance implicite de quartiers. Ce comportement conserve la logique géographique V6 existante.

## Requêtes, limites et sécurité

Tout Explorer utilise `FirebaseRequestRepository.watchExplore` : requête Firestore `status == published`, égalités des dimensions sélectionnées, tri `createdAt DESC, __name__ DESC`, limite 30. Les filtres sont appliqués **avant** la limite, côté Firestore. Le flux reste temps réel : une clôture ou suppression retire une demande de la liste publique. La limite est annoncée et le nombre indique uniquement les résultats affichés, sans lecture de comptage globale.

Pour moi réutilise la callable déployée, sans modification du backend : contrôle du compte actif/vérifié et du profil approuvé, intersection serveur, requêtes exactes, exclusion des demandes personnelles. Pagination existante de 30 résultats au plus, 60 documents examinés et 10 requêtes par appel au plus, avec curseur date/identifiant et combinaison. Les combinaisons sont disjointes, et l'interface déduplique aussi par ID. Une page intermédiaire vide peut encore proposer Charger la suite. Cette vue se recharge avec Actualiser ; elle n'est pas un abonnement serveur temps réel. Le détail public refuse une demande devenue non publique entretemps.

Les règles Firestore et Storage ne sont pas modifiées. Aucune nouvelle fonction, collection, permission, donnée privée, proposition, messagerie ou notification. Les implémentations de repository V5 injectées dans les anciens tests restent compatibles ; le repository Firebase de production applique toujours les filtres dans la requête ciblée.

Quatre index composites supplémentaires sont définis dans `firestore.indexes.json`, tous dans `requests`, avec `status ASC`, les égalités indiquées puis `createdAt DESC, __name__ DESC` : catégorie ; zone ; catégorie + zone ; catégorie + spécialité. L'index V6 existant couvre catégorie + spécialité + zone ; l'index V5 couvre le fil sans filtre. Une spécialité n'est jamais sélectionnée sans catégorie. Leur déploiement a été autorisé ultérieurement et est suivi en fin de document.

## Fichiers de la correction

- `lib/features/requests/presentation/explorer_view.dart` : page et panneau partagés ; suppression de `opportunity_view.dart`.
- `lib/features/requests/domain/request_repository.dart` : valeur de filtres et interface de lecture publique filtrée.
- `lib/features/requests/data/firebase_request_repository.dart` : requêtes publiques ciblées temps réel. Les méthodes FOUN-40 et la callable d'opportunités restent inchangées.
- `lib/app.dart`, `request_views.dart` (uniquement l'hôte visiteur et ses imports), `foundi_shell.dart` : catalogue accessible aux visiteurs, route commune et conservation des états de navigation.
- `firestore.indexes.json` : quatre index locaux complémentaires.
- `test/opportunities_v6_test.dart` : tests du composant commun pour les trois profils, restrictions de mode, dépendance catégorie/spécialité, filtrage, effacement, vide, erreurs, détail et retrait temps réel d'une demande clôturée.
- `functions/rules-test/requests.test.cjs` : filtres publics anonymes/authentifiés, cinq combinaisons de dimensions, aucun résultat, refus implicite des demandes clôturées/supprimées dans ces résultats.

## Vérifications

Commandes exécutées avec le SDK local : `dart.exe <SDK>/bin/cache/flutter_tools.snapshot analyze --no-pub`, `test --no-pub`, tests ciblés V5 ; formatage `dart format` et correction des avertissements de blocs via `dart fix --apply --code=curly_braces_in_flow_control_structures lib/features/requests`.

Serveur : `node.exe --test functions/test/*.test.js` — **53 réussis**, dont les tests FOUN-40 et les règles métier des opportunités. Aucun service serveur n'a changé.

Règles : préparation des ports locaux avec `node.exe functions/test-support/prepare-emulators.cjs`, puis Firebase CLI `emulators:exec --config .firebase-integration.json --project demo-foundi --only firestore,storage "npm.cmd --prefix functions run test:rules"` — **13 réussis, aucun ignoré**. Le runtime Storage affiche l'exception Java connue à l'arrêt, après les assertions réussies et le code de sortie 0.

Le premier passage Flutter a détecté deux régressions V5 (déplacement du formulaire lors de la première ouverture d'Explorer, puis réessai asynchrone du flux). Elles ont été corrigées dans les hôtes de navigation et l'abonnement Explorer ; les **8 tests V5 ciblés repassent**.

Validation finale exécutée après les derniers changements de navigation : **56 tests Flutter réussis**, **analyse Flutter sans problème**, `git diff --check` et `node --check functions/rules-test/requests.test.cjs` réussis. Les trois profils sont testés dans l'application, ainsi que le retour au détail en mode Pour moi, un professionnel approuvé en espace client, les six statuts non éligibles, la dépendance des spécialités, les résultats vides, erreurs/réessai, filtres effaçables sans perte de mode et le retrait public d'une demande clôturée. Les tests FOUN-40, FOUN-38/39/42, authentification V3 et navigation V4 restent dans la suite complète.

À la livraison initiale de cet avenant, aucun appel de production ni déploiement n'avait été effectué. Les deux intégrations serveur complètes déjà réussies pour V6 ne sont pas présentées comme relancées ici : le backend est inchangé. Pas de test sur appareil physique.

## Déploiement des quatre index — autorisé le 30 octobre 2026

Commande exécutée :

```powershell
node.exe C:\Users\kouam\AppData\Roaming\npm\node_modules\firebase-tools\lib\bin\firebase.js deploy --project foundi-7c837 --only firestore:indexes --non-interactive
```

Le CLI a terminé avec succès (code 0). Aucun déploiement de fonctions, de règles ou de l'application mobile. Les index existants sont conservés. Les quatre index créés :

| Égalités supplémentaires à `status` | ID Firestore |
| --- | --- |
| `categoryId` | `CICAgJjF9oIK` |
| `zoneId` | `CICAgJj7z4EK` |
| `categoryId, zoneId` | `CICAgNi47oMK` |
| `categoryId, specialtyId` | `CICAgNiav4AK` |

La soumission a été suivie d'un état `CREATING`. Le contrôle local en lecture seule `.dart_tool/explorer-production-check.cjs --wait` a ensuite confirmé **les quatre nouveaux index `READY`**, ainsi que les deux index de demandes V5/V6 préexistants.

Les six formes de requêtes anonymes réellement utilisées par Explorer ont été exécutées contre `foundi-7c837`, avec `status == published`, limite 30 et tri `createdAt DESC, __name__ DESC` :

| Filtres manuels | HTTP | Résultats correspondant aux critères |
| --- | --- | --- |
| Aucun | 200 | 1 |
| Catégorie | 200 | 1 |
| Zone | 200 | 1 |
| Catégorie + zone | 200 | 1 |
| Catégorie + spécialité | 200 | 1 |
| Catégorie + spécialité + zone | 200 | 1 |

Les critères de ces contrôles proviennent d'une demande publique existante ; son contenu et son identifiant ne sont pas enregistrés dans ce rapport. Le script vérifie pour chaque résultat le statut, toutes les égalités de filtres, la liste blanche de champs publics, l'absence de doublons et l'ordre des résultats. Une catégorie de sonde sans correspondance renvoie correctement zéro résultat. Les requêtes anonymes `closed`, `deleted` ou sans filtre de statut sont refusées avec HTTP 403.

Le contrôle final s'est terminé avec code de sortie 0. Aucune écriture, création de compte ou demande de démonstration. Le jeu public disponible ne comportait qu'une demande retournée : ce passage ne constitue pas un test de charge, de tri avec plusieurs documents ou de parcours sur téléphone. Les tests Flutter et de règles de la correction restent ceux rapportés plus haut. L'application mobile et les fonctions n'ont pas été redéployées lors de cette opération limitée aux index.

Un premier appel de contrôle administratif utilisait un `pageSize` refusé par l'API des index (HTTP 400) ; ce paramètre a été retiré avant les contrôles de disponibilité et de requêtes réussis.
