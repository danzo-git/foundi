# Demandes privées : identité automatique et formulaire simplifié

Suivi : la suppression du nom personnalisable a ensuite été étendue aux demandes publiques, en création comme en modification. Voir [Identité des demandes : nom du compte imposé](demandes-identite-compte.md). Cette extension a été déployée séparément ; le déploiement décrit dans le présent rapport concerne le lot privé V2.

Implémentation locale du 12 novembre 2026, après validation de la maquette et de l’ajustement demandé : reprendre la catégorie et la spécialité du professionnel en grisé, sans laisser le client les modifier.

## Résultat

- Le profil public affiche « Faire une demande » dans un bouton à contour vert, avec fond clair, intégré à son en-tête. Sa hauteur visuelle minimale est de 38 pixels logiques ; la zone tactile conserve au moins 48 pixels.
- Le champ « Nom affiché au professionnel » disparaît des créations et modifications privées. Le nom complet du compte apparaît à la vérification puis dans la demande reçue.
- La catégorie et la spécialité proviennent du dossier professionnel approuvé, pas de son texte de présentation libre. Les champs sont grisés et verrouillés. La zone, la description, le budget facultatif et les photos restent utilisables.
- La carte reçue affiche le nom du demandeur avec un aperçu du besoin. Le détail affiche « Demande de … ».
- Les coordonnées, les propositions et les photos privées gardent leurs restrictions d’accès.

## Décisions métier et compatibilité

Un professionnel peut déclarer plusieurs catégories et spécialités, alors qu’une demande possède une seule paire. Le choix automatique respecte l’ordre enregistré dans son dossier : première catégorie active possédant une spécialité active déclarée par ce professionnel ; une catégorie sans spécialités reste utilisable avec une spécialité vide. Les catégories ou spécialités désactivées sont ignorées. Si aucune combinaison valide n’existe, l’envoi est bloqué avec une invitation à rouvrir le profil. Aucun choix libre de catégorie n’est réintroduit.

À la création, le serveur recalcule cette paire et refuse une sélection différente, notamment si le dossier a changé depuis l’ouverture du profil. En modification, la paire d’origine reste verrouillée, même si le professionnel a changé son activité entre-temps. Les validations des références actives continuent à s’appliquer.

Pour les nouvelles demandes privées, le champ serveur `requesterName` est dérivé de `users/{uid}.fullName`, avec repli sur `Auth.displayName`. Le serveur ignore le nom public fourni par le client. Il ne prend jamais une adresse e-mail ou un numéro comme nom. Si le compte ne possède aucun nom exploitable, il demande de compléter les informations personnelles avant la création. Le nom privé est distinct de `authorPublicName`, dont le fonctionnement reste inchangé pour les demandes publiques.

Les anciennes demandes sont résolues à la lecture par `readDirectRequestAuthors`, par lots de 50 identifiants maximum. Chaque document privé est vérifié : seul l’auteur ou le destinataire encore approuvé peut obtenir le nom correspondant. La réponse contient uniquement une correspondance identifiant de demande / nom. Aucun document utilisateur, aucune coordonnée et aucune proposition ne sont retournés. Cette résolution ne migre ni ne modifie les données de production. Si le nom est réellement absent du profil et d’Auth, le repli « Membre Foundi » reste utilisé.

Le modèle public de vitrine expose une projection `requestActivity` composée uniquement des identifiants et libellés d’activité. Cette projection, comme l’identifiant de navigation du professionnel, est exclue de `toSaveMap()` : l’éditeur de vitrine ne peut pas la modifier.

Les identifiants des demandes, les réessais idempotents, les limites V9.2, les statuts, le destinataire immuable et le circuit proposition / discussion sont conservés. Les tests existants des photos privées et des propositions restent exécutés.

## Fichiers de cette correction

| Groupe | Fichiers |
| --- | --- |
| Profil public et modèle | `lib/features/professional/domain/professional_showcase.dart`, `lib/features/professional/presentation/professional_showcase_screen.dart`, `lib/features/professional/presentation/professional_profile_widgets.dart` |
| Demandes Flutter | `lib/features/requests/domain/request_repository.dart`, `lib/features/requests/data/firebase_request_repository.dart`, `lib/features/requests/presentation/request_composer.dart`, `lib/features/requests/presentation/request_views.dart`, `lib/features/requests/presentation/direct_requests.dart` |
| Serveur | Nouveau `functions/src/direct-request-context.js`, `functions/src/request-service.js`, `functions/src/index.js`, `functions/src/professional-showcase-service.js`, `functions/src/request-interaction-service.js`, `functions/src/request-respondents-service.js` |
| Tests Flutter | `test/direct_requests_test.dart`, `test/public_professional_profile_test.dart` |
| Tests Node | Nouveau `functions/test/direct-request-context.test.js`, `functions/test/direct-requests.test.js`, `functions/test/professional-showcase.test.js` |
| Intégration | `functions/integration-test/direct-request-flow.test.cjs`, `functions/integration-test/request-interaction-flow.test.cjs`, `functions/integration-test/professional-showcase-flow.test.cjs` |

Les modifications des sprints précédents présentes dans le dépôt ont été conservées. Aucune autre fonctionnalité du backlog n’a été ajoutée.

## Validation

| Vérification | Résultat |
| --- | --- |
| Tests Flutter ciblés des demandes directes | 8 réussis |
| Suite Flutter complète | 150 réussis, aucun échec |
| `flutter analyze --no-pub` | Aucune anomalie |
| `npm test` | 129 réussis, aucun échec ni test ignoré |
| `npm run check` | Réussi |
| Firestore en émulateur | 4 réussis : intégration serveur et trois scénarios de règles, aucun test ignoré |
| Export Flutter des captures | 2 scénarios réussis, 6 captures |

Les nouveaux tests couvrent le verrouillage à la création et à la modification, l’absence de champ de nom, l’activité manquante, l’affichage du nom à la réception et dans le détail, le nom imposé côté serveur, la sélection d’activité selon le dossier, le repli Auth et le refus d’accès aux noms d’anciennes demandes par un autre compte ou un destinataire suspendu. Les assertions vérifient aussi l’absence d’écriture lors de la résolution des anciennes identités et l’absence de projection publique de leur nom privé.

L’intégration utilise Firestore réel en émulateur avec les fabriques Node des services. Les refus d’accès dans son journal sont attendus et vérifiés par les tests. Aucun push réel et aucune demande réelle n’ont été envoyés.

Journaux locaux : `.dart_tool/direct-v2-flutter-targeted-final.log`, `.dart_tool/direct-v2-flutter-all.log`, `.dart_tool/direct-v2-analyze.log`, `.dart_tool/direct-v2-node-final.log`, `.dart_tool/direct-v2-node-check.log`, `.dart_tool/direct-v2-emulated.log`, `.dart_tool/direct-v2-captures-final.log`. Après la suite complète, le contrôle ciblé a été répété pour le dernier ajustement du repli du nom de compte ; les huit scénarios réussissent.

## Captures réelles Flutter

Ces captures sont des rendus du moteur Flutter en test local, à 430 × 932 pixels logiques, exportés à 2×. Elles ne sont pas des captures sur téléphone Android. Le profil et les photos d’autolinkci proviennent de sa projection publique déjà utilisée pour le sprint précédent ; le catalogue, les clients et les demandes sont des données de test. Aucune demande n’a été réellement envoyée à autolinkci.

| Écran après correction | Capture |
| --- | --- |
| Profil, bouton compact | [01-profil.png](demandes-directes-v2-captures/01-profil.png) |
| Formulaire, activité grisée et nom automatique | [02-formulaire.png](demandes-directes-v2-captures/02-formulaire.png) |
| Vérification privée | [03-verification.png](demandes-directes-v2-captures/03-verification.png) |
| Confirmation locale | [04-confirmation.png](demandes-directes-v2-captures/04-confirmation.png) |
| Réception, nom du demandeur | [05-reception.png](demandes-directes-v2-captures/05-reception.png) |
| Détail, nom et confidentialité | [06-detail.png](demandes-directes-v2-captures/06-detail.png) |

Les captures d’avant restent dans `docs/demandes-directes-captures/`. Le bouton plein occupant toute la largeur a été remplacé par une action secondaire dans le profil ; le champ de nom a été retiré ; les deux références d’activité sont désormais visibles et verrouillées, conformément à l’ajustement validé. L’interface et les composants Foundi existants sont réutilisés.

## Activation côté serveur

Le déploiement des six fonctions a été autorisé puis réalisé le 12 novembre 2026 : [compte rendu de déploiement](deploiement-demandes-directes-v2-2026-11-12.md). Les règles Firestore, Storage et les index sont inchangés pour ce lot. Aucun APK n’a été généré ou distribué.

Les cinq fonctions `publishDirectRequest`, `manageRequest`, `readProfessionalShowcase`, `readRequestRecommendation`, `readRequestRespondentProfile` ont été mises à jour et `readDirectRequestAuthors` a été créée. Elles sont toutes actives. Les fonctions de profil fournissent le contexte d’activité nécessaire au formulaire. Le client mis à jour doit être utilisé avec ces fonctions : sans contexte d’activité disponible, le formulaire bloque l’envoi au lieu de proposer une catégorie modifiable.

Le déploiement des demandes directes réalisé précédemment reste distinct de ce lot de corrections. Le contrôle manuel à deux comptes pourra ensuite vérifier une nouvelle demande avec photos, sa réception au bon nom et la lecture d’une ancienne demande ; un troisième compte devra conserver un accès refusé.
