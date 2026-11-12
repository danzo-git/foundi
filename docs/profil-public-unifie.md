Le profil professionnel ouvert depuis la liste des répondants reprend la présentation de « Mon compte » : couverture et portrait existants, nom, activité, badge de professionnel vérifié, présentation, trois sections et galerie. Cette évolution du 12 novembre 2026 conserve le bouton de retour vers les répondants.

La mise en page utilise les mêmes composants que le compte : `ProfessionalShowcaseHeader`, `ProfessionalProfileTabs`, `ProfessionalProfileSection`, `ProfessionalProfileDetail`, `ShowcaseGallery` et la visionneuse existante. Les cartes, couleurs, espacements et onglets sont communs. Le compte conserve ses actions d’édition et de gestion ; la consultation publique n’en reçoit aucune.

Le chargement reste assuré par `readRequestRespondentProfile`, avec la projection publique existante `ProfessionalShowcase`. Aucun document privé ni nouvelle collection ne sont lus. Seuls le nom professionnel, l’activité, la zone, la présentation, la couverture, le portrait et les réalisations déjà projetés sont utilisés. La nouvelle présentation ne nécessite aucune modification du backend, des règles Firestore ou de Storage. Les contrôles serveur sur le statut approuvé, le compte actif et la présence d’une réponse à la demande restent ceux du service existant.

Les coordonnées, justificatifs, paramètres, dossiers et contenus de propositions ne font pas partie du modèle public. Aucun bouton d’ajout, de retrait, de modification ou de consultation de propositions n’est rendu dans ce profil. L’accès de l’auteur aux propositions reçues reste dans le parcours privé existant. La vue publique partagée par les autres accès existants au profil professionnel bénéficie également de cette présentation.

| Fichier | Modification de ce complément |
| --- | --- |
| `lib/features/professional/presentation/professional_profile_widgets.dart` | Sections, onglets et lignes de détails partagés avec le compte. |
| `lib/features/auth/presentation/account_view.dart` | Réutilisation des composants communs, avec les sources métier et actions privées existantes. |
| `lib/features/professional/presentation/professional_showcase_screen.dart` | Présentation publique unifiée, trois sections et aperçu de galerie. |
| `test/public_professional_profile_test.dart` | Navigation depuis les répondants, données publiques, confidentialité, galerie, images indisponibles, petit écran et captures. |
| `docs/profil-public-unifie.md` | Compte rendu de ce complément au sprint du compte unifié. |
| `docs/profil-public-captures/*.png` | Captures réelles des trois sections du profil public. |

Les trois nouveaux tests passent. Ils couvrent l’ouverture depuis Explorer en visiteur, la réutilisation des images déjà chargées, les trois sections sans nouvelle lecture, Voir tout, l’agrandissement d’une photo, le retour à la liste des répondants, une galerie vide, les images indisponibles et le rendu à 320 px avec un texte agrandi à 1,8. Des champs privés supplémentaires dans la réponse simulée sont ignorés par le modèle public ; les tests vérifient leur absence à l’écran et l’absence de lecture de propositions.

Les trois tests serveur existants de `functions/test/professional-showcase.test.js` passent : projection autorisée, gestion des images et refus des coordonnées dans les textes publics. Aucun fichier du backend n’a été modifié pour cette évolution.

Les captures suivantes sont des rendus réels du moteur Flutter en test local, à 430 × 932 pixels logiques, exportés à 2×. Elles utilisent la projection publique d’autolinkci déjà enregistrée localement pour le sprint précédent : couverture, portrait, activité, présentation et réalisation existants. Le parcours de test passe par Explorer, les répondants, puis le profil. Aucun compte ni demande n’est créé en production. Les polices disponibles sur Windows sont chargées pour l’export ; il ne s’agit pas de captures d’un APK installé sur téléphone.

| Section | Capture |
| --- | --- |
| À propos et aperçu de galerie | [Profil public — À propos](profil-public-captures/01-profil-public-a-propos.png) |
| Activité publique | [Profil public — Mon activité](profil-public-captures/02-profil-public-activite.png) |
| Galerie complète | [Profil public — Réalisations](profil-public-captures/03-profil-public-realisations.png) |

La comparaison avec le compte unifié confirme les mêmes proportions de couverture et de portrait, le même badge, la même présentation courte, les mêmes onglets et les mêmes cartes. L’en-tête de navigation conserve le titre « Profil professionnel », le logo Foundi et le retour vers les répondants. Les boutons de modification, la tuile d’ajout de photo et les cartes privées du compte sont absents. La réalisation affichée est celle déjà enregistrée ; aucune image ni information supplémentaire n’est inventée.

L’export réussit avec la commande `flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=PUBLIC_PROFILE_CAPTURE=true --name 'public respondent profile shares' test/public_professional_profile_test.dart`. Cette commande optionnelle utilise le JSON public local `.dart_tool/unified-account-capture-public-profile.json`, non versionné. Les tests habituels utilisent leurs fixtures et ne dépendent pas de ce fichier. Le journal de l’export est conservé dans `.dart_tool/public-profile-captures.log`.

La vérification finale réussit :

| Commande | Résultat |
| --- | --- |
| `dart format .` | 91 fichiers, aucun changement restant. |
| `flutter test --no-pub --concurrency=1 --reporter expanded` | 142 tests réussis, aucun échec. |
| `flutter analyze --no-pub` | Aucune anomalie. |
| Tests unitaires existants de la vitrine serveur | 3 tests réussis, aucun échec. |
| Export Flutter des trois sections publiques | 1 scénario complet réussi, 3 captures générées. |

Les journaux sont conservés dans `.dart_tool/public-profile-all-tests.log`, `.dart_tool/public-profile-analyze.log`, `.dart_tool/public-profile-server-contract.log` et `.dart_tool/public-profile-captures.log`. La suite complète inclut les tests du compte unifié, du profil consulté depuis les propositions reçues, de la liste des répondants, des recommandations, de la publication et de la messagerie. Les modifications locales des autres sprints sont conservées.

Aucun déploiement Firebase, aucune écriture en production ni génération d’APK ne sont réalisés. La validation sur téléphone reste à faire avec la version Flutter mise à jour, notamment le retour à la liste des répondants et l’ouverture des réalisations.
