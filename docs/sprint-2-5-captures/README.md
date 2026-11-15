# Captures Flutter du Sprint 2.5

Ces PNG proviennent du rendu Flutter réel des widgets de production, avec thème Foundi, icônes et polices chargées, données fictives et sans connexion à un compte réel. Les écrans mobiles sont rendus à 430 px de largeur ; la recette d’accessibilité est à 320 px avec texte ×1,7. La photo synthétique choisie dans le test vérifie le chargement de l’image sans utiliser le portrait d’une personne.

- [explorer-avatar-autorise.png](explorer-avatar-autorise.png) : carte Explorer avec publication de la photo autorisée.
- [explorer-avatar-absent-ou-revoque.png](explorer-avatar-absent-ou-revoque.png) : même carte après révocation, icône de repli.
- [selection-zones.png](selection-zones.png) : choix de deux zones dans le sélecteur.
- [zones-320px-grandes-polices.png](zones-320px-grandes-polices.png) : sélection de trois zones à 320 px et grandes polices.
- [besoin-non-classe.png](besoin-non-classe.png) : catégorie Autre et précision du service.
- [apercu-multi-zone.png](apercu-multi-zone.png) : aperçu avant publication, zones et précision visibles.
- [compte-dossier-avatar-cliquable.png](compte-dossier-avatar-cliquable.png) : avatar LD cliquable pour un dossier incomplet.
- [compte-client-photo-identite.png](compte-client-photo-identite.png) : photo de compte sans profil professionnel.
- [compte-photo-selection-directe.png](compte-photo-selection-directe.png) : sélection depuis l’avatar et confirmation de son utilisation.
- [compte-photo-existante-reutilisee.png](compte-photo-existante-reutilisee.png) : aperçu de la photo existante sans nouvel envoi.
- [compte-pro-photo-commune.png](compte-pro-photo-commune.png) : même portrait dans le profil professionnel.
- [admin-reference-autre.png](admin-reference-autre.png) : opération Admin pour activer la référence contrôlée.

Génération locale : `flutter test --no-pub --concurrency=1 --dart-define=SPRINT25_CAPTURE=true test/sprint25_test.dart`, puis le même drapeau pour `admin/test/sprint25_catalog_test.dart` depuis `admin`. Les captures des sélecteurs incluent les fenêtres du Navigator.

## Parcours auteur et localisation

- [explorer-auteur-cliquable.png](explorer-auteur-cliquable.png) : identité de l’auteur ouvrant son profil, séparément du clic sur la demande.
- [profil-auteur-client.png](profil-auteur-client.png) : identité publique d’un client sans activité professionnelle publiée.
- [profil-auteur-activite-professionnelle.png](profil-auteur-activite-professionnelle.png) : profil approuvé existant et onglet activité.
- [position-zone-a-confirmer.png](position-zone-a-confirmer.png) : confirmation d’une suggestion, avant tout ajout aux zones existantes.
- [position-refusee-selection-conservee.png](position-refusee-selection-conservee.png) : choix manuel conservé après refus, écran de 320 px et grandes polices.

Ces captures utilisent les widgets de production avec données fictives. Les suggestions GPS sont injectées dans les tests ; ces images ne constituent pas un relevé GPS sur un téléphone réel. Génération : `flutter test --no-pub --concurrency=1 --dart-define=SPRINT25_CAPTURE=true test/request_author_navigation_test.dart`.

## Extension Rennes uniquement

- [rennes-position-zone-a-confirmer.png](rennes-position-zone-a-confirmer.png) : suggestion de la commune de Rennes, avant confirmation explicite.
- [admin-rennes-pays-france.png](admin-rennes-pays-france.png) : zone Rennes, identifiant stable et pays France conservés dans l’éditeur Admin avec le thème Foundi.

Données fictives : ces rendus n’activent aucune zone distante et ne constituent pas une réception GPS sur un téléphone réel.
