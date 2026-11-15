# Photo de compte commune — 15 novembre 2026

Branche : `codex/foundi-sprint-2-5-finitions`. Cette révision applique la demande de l’éditeur : une seule identité photo pour le compte, les demandes publiées et le portrait professionnel. Elle remplace la séparation des photos prévue initialement dans le Sprint 2.5.

## Parcours

Toucher les initiales ou la photo dans **Mon compte** ouvre directement la sélection, le remplacement et la suppression. L’accès existe sans compte pro, pour un dossier incomplet et pour un professionnel approuvé. L’aperçu explique l’utilisation de la photo ; une nouvelle sélection se confirme avec **Utiliser cette photo**. La fenêtre se ferme aussi avec son bouton Fermer. Le formulaire d’informations personnelles ne demande plus un second envoi. La couverture et les réalisations gardent leurs propres contrôles.

Une photo de compte déjà enregistrée reste prioritaire. Sinon, le serveur reprend le portrait Foundi existant lors de la lecture du compte ou de la résolution d’une ancienne demande. L’utilisateur n’a pas à le téléverser à nouveau ni à republier ses demandes. Google, couverture et galerie ne servent jamais de source. Une ancienne photo dont l’affichage avait été révoqué reste révoquée jusqu’à confirmation positive.

Le choix fait sans dossier pro ne crée pas de dossier professionnel. Lors de sa création, la photo est réutilisée sans changement de statut ou d’approbation. Les modifications ultérieures de l’identité remplacent aussi le portrait professionnel, en conservant les textes, couverture et réalisations. L’éditeur d’activité conserve cette photo par référence et ne permet plus d’envoyer un portrait indépendant.

## Garanties techniques

- Import progressif borné, validation de l’image et de son empreinte, copie normalisée en WebP 256 × 256 sans métadonnées ; aucun parcours de masse sur les comptes réels.
- L’import concurrent ne remplace jamais une photo choisie entre-temps. La suppression conserve un marqueur privé empêchant de ressusciter un ancien portrait. Ce marqueur est effacé par la purge complète du compte.
- Copie du portrait pro dans une transaction contrôlant la version courante. Une copie déjà identique n’incrémente pas la révision du profil ; les reprises des modifications du texte restent idempotentes.
- Aperçu de la photo uniquement dans la réponse authentifiée du propriétaire. Projection publique limitée à la version, identifiant opaque sur les cartes, compte et propriété toujours privés.
- Retrait public immédiat et nettoyage Storage reprenable inchangés. Les fils de demandes se rafraîchissent après les changements locaux ; les cartes observent toujours les versions publiques.

## Vérifications

| Vérification | Résultat | Trace locale ignorée par Git |
| --- | --- | --- |
| Flutter complet, captures incluses | 197 tests réussis | `.dart_tool/identity-all-widgets-final.log` |
| Analyse Flutter | Aucune anomalie | `.dart_tool/identity-analyze-final.log` |
| Backend | 190 tests réussis | `.dart_tool/identity-node.log` |
| Vérification serveur/scripts | Réussie | `.dart_tool/identity-check.log` |
| Émulateurs Firebase ciblés | 4 scénarios réussis | `.dart_tool/identity-emulators.log` |

Les scénarios vérifient notamment le portrait existant sur une ancienne demande, la priorité de la photo personnelle, la reprise pour un futur dossier pro, les textes/couverture/galerie conservés, les reprises idempotentes, la non-résurrection après suppression, le refus des anciens médias et la purge réelle Firestore/Storage/Auth sur des comptes fictifs locaux. La suite Flutter contrôle l’accès sans compte pro, le dossier incomplet, le clic sur le portrait approuvé, l’envoi, la reprise sans fichier, la suppression et la navigation entre espaces.

Les captures proviennent des widgets Flutter de production, rendus avec le thème Foundi et des données fictives. La photo est un bitmap synthétique : [avatar LD](sprint-2-5-captures/compte-dossier-avatar-cliquable.png), [client avec photo](sprint-2-5-captures/compte-client-photo-identite.png), [photo existante](sprint-2-5-captures/compte-photo-existante-reutilisee.png), [profil pro](sprint-2-5-captures/compte-pro-photo-commune.png).

## Livraison

La mise à jour ciblée des fonctions photo/profil est couverte par l’autorisation de déploiement donnée pour la photo des demandes. Son résultat distant est consigné dans [le rapport de déploiement](deploiement-photos-demandes-2026-11-15.md). Le changement d’interface nécessite une application actualisée. Aucun APK n’a été distribué ; aucun Hosting ni texte juridique n’a été publié. Les textes générés localement restent des projets non publiés.
