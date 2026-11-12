La page « Mon compte » rassemble désormais la présentation professionnelle, les réalisations et la gestion privée du compte. Le sprint des 11 et 12 novembre 2026 part de la version locale existante, sur la branche `codex/foundi-photos-publiques-explorer`, et réutilise les repositories d’authentification, de dossier professionnel et de vitrine. Les modifications déjà présentes dans le dépôt ont été conservées ; les écarts Git du backend et des sprints de demandes précédents ne font pas partie de ce sprint.

L’audit a couvert `account_screen.dart`, `foundi_shell.dart`, `settings_view.dart`, `professional_gate.dart`, `professional_onboarding.dart`, les repositories et les composants de vitrine. La vitrine existante contient le portrait, la couverture et six réalisations au maximum. Les images restent dans leur stockage existant, avec leurs identifiants et leur validation serveur. Les catégories, spécialités, zones validées et justificatifs suivent les autorisations du dossier professionnel.

Les professionnels approuvés accèdent à la même présentation dans les espaces Client et Professionnel. Les sections « À propos », « Mon activité » et « Réalisations » utilisent les données déjà enregistrées. Le changement d’espace depuis Compte conserve cette page et sa section. Les profils Client, en attente, à compléter, refusés et suspendus présentent leurs informations et leur statut effectifs.

Les boutons de couverture, de portrait et de galerie ouvrent l’éditeur existant sur la section concernée. La sauvegarde actualise la page avec la réponse du repository. Un échec de chargement de la vitrine désactive l’édition jusqu’à une lecture réussie. Une perte d’approbation retire la présentation et les actions réservées aux professionnels approuvés.

Les anciennes étapes « Mon compte → Mon profil professionnel → Modifier » et « Paramètres → Informations professionnelles » pour les professionnels approuvés rejoignent la page unifiée. Les informations personnelles, le suivi du dossier et les profils consultés par des tiers conservent leurs écrans utiles. Les cartes « Vue d’ensemble » ont été retirées. Les destinations absentes de la barre courante restent disponibles dans Compte, dont les demandes en espace Professionnel et les propositions envoyées en espace Client.

Le nom et le téléphone restent modifiables dans le formulaire personnel existant. L’e-mail y est désormais affiché en lecture seule. L’entrée « Sécurité » des paramètres rejoint cet écran privé, qui propose le parcours existant de réinitialisation pour les comptes avec mot de passe. Aucun changement d’e-mail, nouveau mode d’authentification ou droit professionnel n’a été introduit.

| Fichier | Intervention |
| --- | --- |
| `lib/features/auth/presentation/account_view.dart` | Page unifiée, sections, statuts, chargement et gestion du compte. |
| `lib/features/auth/presentation/account_screen.dart` | Réexport de la page unifiée, e-mail privé en lecture seule et accès à la réinitialisation existante. |
| `lib/features/navigation/presentation/foundi_shell.dart` | Accès directs à la page et à ses sections, changement d’espace et informations personnelles. |
| `lib/features/navigation/presentation/settings_view.dart` | Réutilisation du formulaire personnel et accès Sécurité. |
| `lib/features/professional/presentation/professional_profile_widgets.dart` | En-tête, portrait, couverture et galerie partagés avec le profil consulté par des tiers. |
| `lib/features/professional/presentation/professional_showcase_screen.dart` | Réutilisation des composants et de l’éditeur, ouverture ciblée et agrandissement des photos. |
| `test/unified_account_test.dart` | Scénarios du compte unifié et captures Flutter locales. |
| `test/professional_showcase_test.dart` | Édition depuis Compte et maintien de la consultation privée des propositions. |
| `test/navigation_v4_test.dart` | Retour aux paramètres et maintien du compte lors d’un changement d’espace. |
| `test/widget_test.dart` | Adaptation des assertions de suivi et de changement d’espace au nouveau parcours. |
| `test/request_respondents_test.dart` | Défilement avant la lecture de la description du profil public sur petit écran. |
| `admin/lib/applications_page.dart`, `admin/test/login_test.dart` | Formatage uniquement, réalisé par la commande globale demandée `dart format .`. |
| `docs/compte-unifie-v1.md`, `docs/compte-unifie-captures/*.png` | Compte rendu et quatre captures Flutter vérifiées. |

Les composants réutilisés comprennent `FoundiBrand`, `FoundiPanel`, `FoundiUi`, `RequestTag`, `ProfileScreen`, `PasswordResetScreen`, `ProfessionalGate`, `ProfessionalActivityView`, le repository de vitrine et son éditeur. La galerie, l’en-tête et la visionneuse ont été mutualisés avec le profil professionnel existant.

La fusion n’introduit aucun champ ni stockage Firebase. Les coordonnées personnelles et justificatifs ne sont pas transmis aux vues publiques. Les formulaires de demandes, les quotas, les identifiants, les propositions et la messagerie gardent leurs services existants. Les champs protégés du dossier approuvé restent soumis aux règles existantes : les raccourcis de photos ouvrent uniquement l’éditeur de vitrine et n’écrivent pas les catégories, les spécialités ou les zones validées du dossier.

| Référence visuelle | Résultat |
| --- | --- |
| Logo, fond clair et vert Foundi | Composants et palette existants. |
| Couverture horizontale et portrait superposé | Images déjà enregistrées, recadrage proportionnel et actions de modification. |
| Trois sections | À propos, Mon activité et Réalisations dans la page. |
| Aperçu de galerie et gestion privée | Galerie commune et accès personnels sous le profil. |
| Champs d’exemple | Seules les données disponibles sont affichées. La date d’inscription est absente du modèle actuel. |
| Barre inférieure | Quatre destinations conservées pour chaque espace. |

L’examen visuel confirme le portrait superposé, les trois sections, la galerie avec son ajout et les cartes privées sous la présentation. Le bouton d’édition prend sa propre ligne sur téléphone pour préserver la lisibilité. La page n’impose pas la densité exacte de l’image de référence : le défilement garde les actions accessibles, y compris sur 320 px et avec une police agrandie. La couverture enregistrée d’autolinkci est une illustration automobile ; elle remplace donc la photo de parc automobile de la maquette. Une seule réalisation est enregistrée. Aucune date d’adhésion, note, statistique, localisation ou photo supplémentaire n’a été inventée.

La capture du professionnel approuvé utilise une lecture du profil professionnel public autolinkci, avec sa couverture, son portrait et sa réalisation déjà enregistrés. Les captures Client et en attente utilisent les fixtures locales pour représenter ces états. Les captures sont des rendus réels des widgets Flutter dans les tests locaux, sans compte ni demande créés en production. Le viewport est de 430 × 932 pixels logiques, exporté à 2× (860 × 1864). Il s’agit de captures de l’application rendue par Flutter, sans cadre ni barre système Android. Les polices disponibles sur Windows sont chargées pour l’export de test ; le rendu natif Android reste à vérifier.

| Capture locale | État représenté |
| --- | --- |
| [Professionnel approuvé](compte-unifie-captures/01-professionnel-approuve.png) | Présentation, photos existantes, sections et galerie ; espace Client pour montrer que l’édition ne dépend pas du changement d’espace. |
| [Compte Client](compte-unifie-captures/02-compte-client.png) | Initiales, informations privées, accès Devenir professionnel, espace Client. |
| [Professionnel en attente](compte-unifie-captures/03-professionnel-en-attente.png) | Statut réel de l’état testé, suivi du dossier, absence de badge vérifié et de vitrine réservée aux approuvés. |
| [Gestion du compte professionnel](compte-unifie-captures/04-professionnel-gestion.png) | Vue après défilement : informations personnelles, activité, vérification, propositions et changement d’espace. |

Les huit nouveaux scénarios du compte unifié vérifient la conservation du profil et de la section pendant le changement d’espace, les raccourcis de portrait et de réalisations, le parcours des paramètres vers l’activité unifiée, l’échec de lecture avec réessai, l’e-mail privé et le lien de réinitialisation, la révocation d’une approbation, le rendu à 320 px avec une police agrandie à 1,8 et des images indisponibles, ainsi que les états approuvé, Client et en attente. Le test de vitrine couvre aussi le retrait d’une réalisation, une erreur de sauvegarde, le réessai et l’actualisation immédiate du profil. Les tests de navigation existants couvrent les dossiers à compléter, en attente, à corriger, refusés et suspendus, les quatre onglets, les paramètres et la déconnexion.

La commande `dart format .` a traité 90 fichiers. Les sept fichiers reformattés lors de la première passe incluent deux fichiers d’administration dont seuls les espaces et retours à la ligne ont changé. La dernière passe confirme **90 fichiers, aucun changement**. La commande complète `flutter test --no-pub --concurrency=2 --reporter expanded` réussit : **139 tests, aucun échec**. Le contrôle ciblé `test/unified_account_test.dart` réussit également : **8 tests**. L’export final des trois états réussit : **3 tests**. Les journaux sont conservés localement dans `.dart_tool/unified-account-all-tests-final.log`, `.dart_tool/unified-account-targeted-final.log` et `.dart_tool/unified-account-captures.log`.

Les exports sont générés par `flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=UNIFIED_ACCOUNT_CAPTURE=true --name 'unified account state' test/unified_account_test.dart`. Cette commande optionnelle utilise le JSON de lecture publique déjà enregistré localement dans `.dart_tool/unified-account-capture-public-profile.json` et les polices Windows ; ce JSON n’est pas versionné. Les tests habituels ne dépendent pas de ce fichier et n’appellent pas Firebase.

La commande `flutter analyze --no-pub` réussit : **aucune anomalie**. Le journal est conservé dans `.dart_tool/unified-account-analyze-final.log`. Après la suite complète, seul le rafraîchissement des couches de rendu de l’outil de capture a été ajusté ; les trois tests d’export ont été réexécutés avec succès. Ce code de capture est désactivé dans l’exécution habituelle des tests et n’est pas inclus dans l’application.

La validation manuelle sur un téléphone Android doit couvrir le sélecteur natif des photos depuis les trois raccourcis d’édition, l’annulation de la sélection, une sauvegarde authentifiée de vitrine et le rendu avec les réglages d’accessibilité du téléphone. Le sprint ne génère aucun APK et ne déploie aucune ressource Firebase.
