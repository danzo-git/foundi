# Foundi V4 — Navigation mobile et organisation des espaces

Cette livraison concerne uniquement les présentations Flutter mobiles. Aucun déploiement, aucune modification d'Authentication, de Firestore, des fonctions, des règles, de Storage ou de Foundi Admin.

## État initial des destinations

| Destination | État avant V4 | Intégration V4 |
| --- | --- | --- |
| Accueil Client / Professionnel | Pas d'accueil dédié ; affichage du Compte ou du suivi professionnel | Deux présentations dans une coque de navigation commune |
| Compte | Fonctionnel, avec actions de profil et boutons volumineux | Identité, badge réel, espace sélectionné et activité |
| Informations personnelles | Fonctionnelles dans `ProfileScreen` | Même écran, accessible depuis Paramètres |
| Inscription et suivi professionnel | Fonctionnels dans `ProfessionalGate` / `ProfessionalOnboarding` | Formulaire et suivi réutilisés depuis le Compte et Paramètres |
| Confidentialité et CGU | Fonctionnelles dans `LegalAcceptanceScreen` | Même écran déplacé dans un fichier de présentation dédié |
| Déconnexion | Fonctionnelle via `AuthRepository.signOut` | Action déplacée dans Paramètres |
| Explorer | Non développé ; aucune route de consultation des demandes | Icône et message « Bientôt disponible » |
| Publier | Non développé ; aucun formulaire métier | Bouton central commun et message « Bientôt disponible » |
| Messages | Non développé ; aucune route de conversation | Icône et message « Bientôt disponible » |
| Notifications / préférences | Non développées | Entrée visuelle dans Paramètres, sans réglage fictif |

Aucune route métier incomplète n'a été complétée. Les destinations inexistantes n'ouvrent ni faux formulaire ni fausses données.

## Références Figma et choix de présentation

Fichier : https://www.figma.com/design/LckChmodNooeblti7ogQQM

Les sept vues utilisées sont `2:2` (Accueil client), `2:35` (Accueil professionnel), `2:77` (Compte professionnel), `2:121` (Paramètres), `2:174` (Sélecteur d'espaces), `2:215` (Client après bascule) et `2:322` (Compte en attente). Les anciennes vues 07/08 ne sont pas implémentées.

Les couleurs, panneaux, marges, hiérarchie typographique et navigation reprennent les maquettes avec des composants Flutter. Les icônes sont natives Material ; aucun bitmap ou SVG n'était fourni dans ces vues et aucune capture Figma n'est embarquée dans l'application. Les libellés techniques des emplacements (« prochain sprint », etc.) deviennent « Bientôt disponible ». Les noms, e-mails et statuts sont issus des données existantes. Les tirets des modules à venir ne représentent pas des statistiques.

La barre inférieure commune affiche Accueil, Explorer, Publier, Messages, Compte. Publier est centré ; les zones tactiles sont conservées au format mobile et la barre respecte la zone système. Paramètres reste dans la coque, ce qui conserve la barre et permet un retour vers Compte. Le formulaire d'inscription, l'édition du profil et les conditions existants conservent leur navigation dédiée.

## Fichiers de présentation

- `lib/features/navigation/presentation/foundi_shell.dart` : coque, état local de navigation, deux accueils, sélecteur et lecture des informations professionnelles.
- `lib/features/navigation/presentation/settings_view.dart` : regroupement des actions existantes dans Paramètres.
- `lib/features/navigation/presentation/space_widgets.dart` : composants et couleurs V4 partagés.
- `lib/features/auth/presentation/account_screen.dart` : Compte épuré ; les autres écrans d'authentification présents dans ce fichier sont conservés.
- `lib/features/auth/presentation/legal_acceptance_screen.dart` : écran de conditions existant déplacé sans modification de son action métier.
- `lib/features/professional/presentation/professional_gate.dart` : réutilisation de la lecture du statut et des vues de dossier, tout en conservant l'état de navigation sous le formulaire.
- `lib/features/professional/presentation/professional_status_label.dart` : libellés UI des statuts déjà existants.
- `lib/features/professional/presentation/professional_onboarding.dart` : seul l'import de l'écran des conditions change.
- `lib/app.dart` : branchement de la coque après le parcours d'authentification existant.

Les dépôts Firebase, les modèles de domaine, `lib/main.dart`, la configuration Firebase, les règles, les sources des fonctions, Foundi Admin et les dépendances n'ont pas été modifiés. Un contrôle SHA-256 des 27 fichiers protégés a confirmé leur identité avec l'état de début de cette intervention.

## Changement d'espace et limites

Le sélecteur est proposé uniquement si `ProfessionalProfile.approved` est vrai. Le mode choisi est un état local d'interface : aucun appel à `setPreferredMode`, `checkAccess` ou à une écriture Firebase lors de la bascule. L'ancienne préférence peut être utilisée comme indication au démarrage, toujours conditionnée par l'approbation ; le choix V4 reste en mémoire pour la session et n'est pas enregistré comme une nouvelle préférence distante.

Les statuts `draft`, `pending`, `needs_changes`, `rejected` et `suspended` conservent l'espace Client et l'accès au dossier. Une préférence historique « professional » n'accorde aucun accès si le dossier n'est pas approuvé. Si l'approbation est retirée, la présentation revient au mode Client ; un sélecteur déjà ouvert se ferme et ne permet pas d'entrer en mode professionnel. Les autorisations serveur restent celles déjà en place.

Les actions explicites déjà fonctionnelles (modifier ses informations, accepter les conditions, constituer son dossier, se déconnecter) réutilisent leurs services actuels. Aucune publication de demande, messagerie, notification, proposition, consultation de demandes, statistique, recherche, regroupement ou matching n'est ajouté.

## Vérification locale

```powershell
flutter analyze
flutter test --concurrency=1
```

Les tests de régression V3 sont adaptés à l'emplacement V4 des commandes, tout en conservant les vérifications d'inscription, d'e-mail, de consentement, de brouillon et de soumission. Les tests V4 vérifient la navigation, le placement central de Publier, les messages d'indisponibilité, la conservation du même compte, l'absence d'écriture lors de la bascule, les cinq statuts non approuvés, la révocation pendant le sélecteur, les liens de Paramètres et l'absence de débordement à 320 × 568 avec texte agrandi à 180 %.

Pour produire les sept captures de comparaison avec des utilisateurs fictifs uniquement dans les tests :

```powershell
flutter test --concurrency=1 --dart-define=V4_CAPTURE=true
```

Les PNG sont générés dans `.dart_tool/v4-preview/`. Les polices Windows disponibles sont chargées uniquement pour les captures de test ; aucun fichier de police système ni utilisateur fictif n'est ajouté au produit. Les captures simulent une zone système de 24 pixels, sans dessiner de fausse barre de statut.

Pour voir les changements sur un téléphone, relancer l'application via `flutter run -d ID_DU_TELEPHONE` depuis la racine, ou installer une nouvelle compilation locale. Un simple déploiement de fonctions Firebase n'actualise pas cette UI Flutter. Aucun déploiement ni installation sur téléphone n'est effectué par cette livraison.

## Résultats de la livraison

`flutter analyze` : aucune anomalie. `flutter test --concurrency=1 --dart-define=V4_CAPTURE=true` : 30 tests réussis, dont les 10 tests de navigation V4 et les régressions des parcours existants. Les sept captures ont été produites et comparées aux maquettes ; la vérification inclut les zones sûres, les grandes tailles de texte et l'accès à la déconnexion dans les Paramètres.

Aucun paquet supplémentaire, aucune modification des 27 fichiers protégés contrôlés par empreinte, aucun déploiement et aucune installation sur un téléphone.
