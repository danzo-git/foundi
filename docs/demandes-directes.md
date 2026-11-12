Une personne peut désormais créer une nouvelle demande privée depuis le profil public d’un professionnel. Ce choix a été confirmé le 12 novembre 2026 : il s’agit d’une nouvelle demande réservée au professionnel choisi, et non du transfert d’une demande déjà publiée.

Le bouton « Faire une demande directe » ouvre le formulaire existant. Le destinataire est affiché et fixé ; le contenu et les photos ne sont jamais publiés dans Explorer. Le formulaire conserve la description, le titre suggéré ou personnalisé, les catégories, spécialités, zones, le budget facultatif, les photos facultatives, la prévisualisation et les erreurs avec réessai. Le visiteur est invité à se connecter et retrouve le professionnel choisi après son inscription ou sa vérification. Le bouton est absent sur son propre profil ; l’interdiction est aussi appliquée par le serveur.

L’auteur retrouve la demande dans « Mes demandes », marquée « Privée ». Le professionnel approuvé la retrouve dans « Compte → Demandes directes reçues ». Les quatre onglets de chaque espace sont conservés. Il peut répondre par la proposition privée existante, puis l’auteur peut ouvrir une discussion et retenir ou refuser la proposition selon le fonctionnement actuel. Les coordonnées ne sont pas exposées et leur partage dans la messagerie garde le consentement existant.

Les demandes publiques restent dans `requests/{id}`. Les demandes directes sont conservées dans `directRequests/{id}`, avec un miroir privé chez l’auteur dans `userRequests/{uid}/items/{id}` et le mapping serveur de propriété existant. Une demande directe n’a jamais de projection dans `requests`, y compris après modification, clôture ou suppression. Le destinataire et la visibilité ne peuvent pas être modifiés par le client. Les lectures de propositions et l’ouverture des conversations vérifient le professionnel destinataire.

Les quotas V9.2 sont partagés entre les deux parcours : délai de 60 secondes, cinq nouvelles demandes par fenêtre de 24 heures et vingt sur sept jours. Le même identifiant est conservé lors d’un réessai, notamment après perte de la réponse serveur. Un réessai ne crée ni seconde demande, ni seconde consommation du quota. Les collisions d’identifiants entre demandes publiques et privées sont refusées.

Les photos utilisent les services de demandes existants et restent séparées des pièces jointes de messagerie. Les mêmes limites, traitements d’images, identifiants, nettoyage et protections de stockage sont réutilisés. Une photo directe est lisible seulement par son auteur ou son destinataire encore approuvé. L’endpoint de photos publiques ne lit jamais la collection privée. Les règles Firestore refusent toute écriture directe du client, toute consultation par un tiers ou un visiteur, et les requêtes de liste insuffisamment contraintes. La suspension et la suppression révoquent l’accès du destinataire.

Le professionnel reçoit l’événement `request.direct_received`, dans sa catégorie de notifications de propositions existante. Le déclencheur utilise un identifiant déterministe : sa répétition ne crée pas de doublon. Le titre et le corps de notification restent génériques ; le texte de la demande, les photos et les coordonnées n’y figurent pas. La résolution du lien vérifie le destinataire, l’état de la demande et l’approbation actuelle. La réception d’une proposition continue à notifier l’auteur avec le mécanisme existant.

| Fichier ou groupe | Intervention |
| --- | --- |
| `lib/app.dart` | Contexte de demande directe, connexion préalable et conservation du destinataire. |
| `lib/features/auth/presentation/account_view.dart` | Accès à la réception des demandes directes pour les professionnels approuvés. |
| `lib/features/navigation/presentation/foundi_shell.dart` | Navigation privée, accès aux propositions et résolution des notifications. |
| `lib/features/professional/presentation/professional_showcase_screen.dart` | Bouton de demande directe sur les profils dont le destinataire est identifié. |
| `lib/features/professional/domain/professional_showcase.dart` | Identifiant public de routage, facultatif et exclu des sauvegardes de vitrine. |
| `lib/features/requests/presentation/request_respondents.dart` | Transmission de l’identifiant du répondant au profil public. |
| `lib/features/requests/domain/request_repository.dart` | Données privées et contrat de réception/publication directe. |
| `lib/features/requests/data/firebase_request_repository.dart` | Appel de publication privée et lectures réservées. |
| `lib/features/requests/presentation/direct_requests.dart` | Contexte partagé, page de formulaire et boîte de réception privée. |
| `lib/features/requests/presentation/request_composer.dart` | Réutilisation du formulaire avec destinataire fixé et libellés privés. |
| `lib/features/requests/presentation/request_views.dart` | Marqueur Privée et détail avec lecture autorisée. |
| `functions/src/request-access.js` | Lecture serveur d’une demande publique ou privée. |
| `functions/src/request-service.js` | Création, quotas, idempotence et gestion sans projection publique. |
| `functions/src/proposal-service.js`, `conversation-service.js` | Réponse et discussion autorisées au destinataire. |
| `functions/src/request-interaction-service.js` | Identifiant du professionnel dans la lecture d’une recommandation, pour le même bouton depuis ce profil. |
| `functions/src/request-photo-service.js` | Photos privées limitées aux deux participants. |
| `functions/src/notification-policy.js`, `notification-service.js`, `index.js` | Événement ciblé, callable et déclencheur de notification. |
| `firestore.rules`, `firestore.indexes.json` | Isolation des lectures et index de réception bornée à 50 demandes récentes. |
| `test/direct_requests_test.dart` | Parcours Flutter, connexion, réessai, réception, auto-envoi et photos. |
| `functions/test/direct-requests.test.js` | Contrats métier et sécurité des photos, propositions et conversations. |
| `functions/rules-test/direct-requests.test.cjs` | Permissions réelles en émulateur Firestore. |
| `functions/integration-test/direct-request-flow.test.cjs` | Transactions, notification unique et résolution du lien en émulateur. |
| `firebase.direct.emulators.json` | Configuration de test Firestore local, sans Functions ni services de production. |

Les quatre nouveaux tests métier serveur passent. Les quatre scénarios en émulateur passent aussi : un test d’intégration et trois tests de règles. Les refus d’accès apparaissant dans le journal de règles sont attendus et sont vérifiés par `assertFails`. Le test d’intégration utilise Firestore réel en émulateur et les fabriques de services du projet ; il n’envoie aucun push réel et ne déploie pas de fonction.

Les vérifications finales réussissent :

| Vérification | Résultat |
| --- | --- |
| `dart format .` | 93 fichiers, aucun changement restant. |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 148 tests réussis, aucun échec. |
| `flutter analyze --no-pub` | Aucune anomalie. |
| `npm test` dans `functions` | 122 tests réussis, aucun échec. |
| `npm run check` dans `functions` | Vérifications syntaxiques réussies. |
| Émulateur Firestore : intégration et règles des demandes directes | 4 tests exécutés et réussis, aucun test ignoré. |
| Export des captures Flutter | Scénario d’envoi privé réussi avec quatre captures. |

Les six nouveaux scénarios Flutter couvrent l’identité d’un professionnel recommandé, l’envoi depuis les répondants avec un réessai après perte de réponse, la connexion d’un visiteur avec conservation du destinataire, la réception et l’envoi complet d’une proposition, l’auto-envoi interdit et les photos privées. Le retour de navigation de la proposition reste associé à la demande directe. La suite complète couvre également les demandes publiques, le compte unifié, les notifications et la messagerie existante.

Les journaux de référence sont `.dart_tool/direct-requests-all-tests-final.log`, `.dart_tool/direct-requests-analyze-final.log`, `.dart_tool/direct-requests-node-final.log`, `.dart_tool/direct-requests-node-check.log`, `.dart_tool/direct-requests-emulated.log` et `.dart_tool/direct-requests-captures.log`. Les écarts locaux des sprints précédents sont conservés.

Les tests d’émulateur se reproduisent avec `firebase emulators:exec --only firestore --config firebase.direct.emulators.json --project demo-foundi "node --test --test-concurrency=1 functions/integration-test/direct-request-flow.test.cjs functions/rules-test/direct-requests.test.cjs"`. La configuration ne démarre que Firestore, sur les ports locaux 1541 à 1546 ; elle ne charge ni Functions ni secrets de production. L’export Flutter utilise `flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=DIRECT_REQUEST_CAPTURE=true --dart-define=PUBLIC_PROFILE_CAPTURE=true --name 'direct demand from the public profile' test/direct_requests_test.dart` et le JSON public local non versionné `.dart_tool/unified-account-capture-public-profile.json`.

Les captures sont des rendus réels Flutter en test local, à 430 × 932 pixels logiques, exportés à 2×. Le profil et ses photos proviennent de la projection publique d’autolinkci déjà lue pour les sprints précédents. Le client, le catalogue et la demande sont des fixtures locales explicitement visibles comme données de test. La confirmation « C’est envoyé ! » illustre le scénario local : aucune demande réelle n’a été envoyée à autolinkci. Les polices disponibles sur Windows sont utilisées pour l’export ; le rendu Android natif reste à contrôler.

| Capture | Écran |
| --- | --- |
| [Profil avec le bouton](demandes-directes-captures/direct-01-profil.png) | Point d’entrée depuis le profil public. |
| [Formulaire privé](demandes-directes-captures/direct-02-formulaire.png) | Destinataire fixé et confidentialité explicite. |
| [Vérification](demandes-directes-captures/direct-03-verification.png) | Prévisualisation avant l’envoi. |
| [Confirmation](demandes-directes-captures/direct-04-confirmation.png) | Envoi privé et accès aux demandes de l’auteur. |

L’activation Firebase a été autorisée puis réalisée le 12 novembre 2026 : [compte rendu du déploiement](deploiement-demandes-directes-2026-11-12.md). Les règles sont publiées, l’index `directRequests` est prêt et les 13 fonctions concernées sont actives : `publishDirectRequest`, `publishRequest`, `manageRequest`, `proposalAccess`, `sendProposal`, `selectProposal`, `uploadRequestPhoto`, `readRequestPhoto`, `notifyDirectRequestCreated`, `resolveNotification`, `deliverNotificationPush`, `drainNotifications` et `readRequestRecommendation`. Les fonctions de livraison embarquent la résolution du nouveau type de notification. La dernière fournit l’identifiant du professionnel pour démarrer aussi une demande depuis un profil recommandé ; cet identifiant n’est jamais enregistré par l’éditeur de vitrine. Le comportement de `readPublicRequestPhoto` reste strictement public. L’activation des push est conservée et aucun secret n’est modifié.

Aucun APK n’a été généré ou distribué. Le déploiement Firebase a été effectué après l’accord explicite de l’utilisateur, sans créer de demande réelle. Le contrôle manuel peut maintenant couvrir deux comptes de test autorisés sur téléphone : création avec photos, réception et push, ouverture du lien privé, réponse, discussion, modification et retrait d’images, puis suppression. Il doit aussi vérifier un troisième compte sans accès et un destinataire suspendu.
