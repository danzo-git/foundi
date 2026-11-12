# Identité des demandes : nom du compte imposé

Correction locale du 12 novembre 2026. Le choix d’un nom par demande est supprimé pour toutes les demandes, publiques et privées, en création et en modification.

## Comportement

Le formulaire ne propose plus « Nom d’affichage public », « Nom affiché au professionnel », ni une action permettant de choisir, effacer ou abréger un nom. Il indique simplement que le nom du compte sera utilisé automatiquement. La vérification affiche ce nom en lecture seule.

`RequestDraft` ne contient plus de propriété de nom : aucun nom d’auteur n’est envoyé par le formulaire. Les champs de nom de `FoundiRequest` restent présents uniquement pour lire et afficher les réponses du serveur.

Le serveur utilise `users/{uid}.fullName`, puis un `Auth.displayName` exploitable si le profil ne fournit pas de nom. Le nom est normalisé et les valeurs ressemblant à des coordonnées sont écartées. Il n’utilise jamais l’adresse e-mail ou le numéro de téléphone comme nom de remplacement. Pour une demande publique, l’absence réelle de nom exploitable conserve le repli neutre « Membre Foundi » ; pour une demande privée, la validation existante demande de compléter les informations personnelles.

Une ancienne application peut encore transmettre `authorPublicName` : cette valeur est ignorée, quel que soit son contenu. Elle ne permet ni de choisir un autre nom ni de supprimer celui du compte. Les autres champs protégés restent refusés lors d’une modification.

En modification, un ancien nom propre à la demande est remplacé par celui du compte. Les réessais ignorent également l’ancien champ pour leur empreinte d’idempotence : changer seulement ce champ ne crée ni nouvelle version ni nouvelle demande. Les règles des catégories privées, les photos, le quota V9.2, les statuts et l’identifiant de demande sont conservés.

Le premier déploiement ne complétait pas les anciennes demandes publiques. Après le diagnostic du fil « Toutes », les 15 demandes publiques ouvertes sans nom et leurs copies propriétaires ont été réparées à partir du compte : [compte rendu de la réparation](reparation-noms-explorer-2026-11-12.md). Aucun autre champ n’a changé. La résolution sécurisée existante des noms pour les anciennes demandes privées reste en place.

## Fichiers concernés

- `lib/features/requests/presentation/request_composer.dart` : suppression du champ, du contrôleur et de la suggestion modifiable ; aperçu du nom du compte.
- `lib/features/requests/domain/request_repository.dart` : identité retirée des données éditables de `RequestDraft`.
- `functions/src/request-service.js` : nom dérivé du compte pour les demandes publiques aussi, correction à la modification et compatibilité avec les anciens clients.
- `functions/src/direct-request-context.js` : résolution commune du nom de compte, désormais nommée `accountRequesterName`.
- Tests Flutter : `requests_v5_test.dart`, `requests_v6_test.dart`, `request_photos_test.dart`, `direct_requests_test.dart`, `request_respondents_test.dart`.
- Tests Node : `request-service.test.js`, `direct-request-context.test.js`, `direct-requests.test.js`.
- Nouveau test d’intégration : `functions/integration-test/request-account-name-flow.test.cjs`.
- `firebase.account-name.emulators.json` : configuration locale dédiée, ports 1551 à 1556. Elle ne modifie pas la configuration de production.

## Vérifications

| Contrôle | Résultat |
| --- | --- |
| Tests serveur | 131 réussis |
| Vérifications syntaxiques Node | Réussies |
| Tests Flutter ciblés publication, modification, photos et demandes directes | 33 réussis |
| Suite Flutter complète finale | 150 tests réussis, aucun échec |
| Analyse Flutter | Aucune anomalie |
| Firestore en émulateur | 5 tests exécutés et réussis, aucun test ignoré |

Les tests serveur essaient notamment un nom arbitraire, un nom vide, un e-mail, un numéro et un objet dans l’ancien champ client. La valeur enregistrée reste le nom du compte. Ils vérifient également le repli Auth, l’absence de coordonnées dans la projection publique, le remplacement d’un ancien alias lors d’une modification et le maintien du quota et de l’identifiant.

Le nouveau test d’intégration exécute de vraies transactions Firestore en émulateur, y compris la création, la correction d’un ancien alias, le réessai et le refus de modification par un autre compte. Les trois scénarios de règles des demandes privées et le parcours serveur privé existant sont aussi exécutés. Les refus `PERMISSION_DENIED` attendus sont vérifiés par les tests. Les ports de l’émulateur précédent étaient occupés ; une configuration isolée a été utilisée sans arrêter le processus existant.

## Captures Flutter

Les captures proviennent du moteur Flutter en test local, avec un backend simulé disposant des photos facultatives et des données de test. Elles ne représentent pas une publication réelle ni une capture sur téléphone Android. L’export utilise le scénario `zero photos uses the original publication payload` de `test/request_photos_test.dart`, avec `V5_CAPTURE=true` et `REQUEST_PHOTOS_CAPTURE=true`.

- [Formulaire sans champ de nom](demandes-nom-compte-captures/01-formulaire.png).
- [Formulaire rempli](demandes-nom-compte-captures/02-formulaire-rempli.png).
- [Vérification avec le nom du compte en lecture seule](demandes-nom-compte-captures/03-verification.png).

## Activation

Le déploiement ciblé de `publishRequest` et `manageRequest` a été autorisé puis réalisé le 12 novembre 2026. Les deux fonctions sont actives : [compte rendu du déploiement](deploiement-nom-compte-demandes-2026-11-12.md). Les règles et les index sont inchangés. Les fonctions privées déjà déployées conservent leur comportement sécurisé ; aucune nouvelle fonction n’a été créée.

Aucun APK n’a été généré ou distribué. Aucune autre fonctionnalité du backlog n’a été ajoutée ; les modifications locales antérieures sont conservées.
