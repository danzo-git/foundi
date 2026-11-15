# Profils des auteurs et localisation — 15 novembre 2026

> Extension ultérieure demandée : [Rennes uniquement, en plus des zones ivoiriennes](rennes-localisation-2026-11-15.md). La restriction initiale à CI décrite ci-dessous est remplacée dans cette révision locale.

Branche : `codex/foundi-sprint-2-5-finitions`. La nouvelle fonction de profil auteur a été déployée le 15 novembre 2026 après autorisation explicite de l’éditeur ; voir [le rapport du déploiement ciblé](deploiement-profil-auteur-2026-11-15.md). Aucun compte réel n’a été modifié par la recette.

## Profil depuis les demandes

Dans Explorer, le nom et la photo de l’auteur forment un lien vers son profil. Le titre et le reste de la carte conservent l’ouverture de la demande. Le retour conserve le fil et ses critères.

- Un auteur professionnel approuvé ouvre le même profil public que l’annuaire, avec ses onglets À propos, Mon activité et Réalisations. La normalisation des textes/photos, les contacts protégés et les vérifications de disponibilité existantes sont réutilisés.
- Un auteur client ou sans activité approuvée ouvre une identité publique : nom déjà publié sur la demande et photo de compte. Le dossier en cours, les coordonnées et les justificatifs ne sont pas révélés.
- Les profils bloqués, suspendus, en suppression, désactivés ou masqués ne sont pas divulgués. L’accès dépend toujours d’une demande publique encore disponible. Les demandes privées n’utilisent pas ce parcours public.

`readRequestAuthorProfile({requestId})` résout le propriétaire exclusivement côté serveur. Le mapping canonique est prioritaire ; les anciennes demandes utilisent une recherche historique bornée à 51 résultats pour détecter le dépassement de 50. Une identité ambiguë est refusée. Aucun accès public aux documents users ou aux mappings n’a été ajouté. Seul un identifiant de professionnel déjà public peut figurer dans une projection professionnelle ; un profil client n’expose pas son UID.

Le serveur contrôle à nouveau la demande, le compte et le blocage après la préparation de la projection. Le client revérifie la disponibilité toutes les 30 secondes et à la reprise de l’application. Un refus confirmé masque l’ancien profil. Les budgets existants de lecture de profil s’appliquent aussi à ce parcours. Si le runtime ne fournit pas d’adresse IP, les visiteurs non authentifiés partagent un budget strict ; un en-tête IP fourni par le client ne permet pas de contourner la limitation.

## Position actuelle

Avant cette révision, le bouton ouvrait uniquement un message d’indisponibilité. Aucun SDK GPS ni permission de localisation n’était branché.

Le nouveau parcours mobile effectue une lecture ponctuelle après appui sur le bouton et autorisation du système. Il utilise Geolocator pour la position et le géocodage natif du téléphone pour reconnaître les noms géographiques. Aucun service Maps payant, clé API de géocodage ou SDK de suivi en arrière-plan n’a été ajouté.

Le résultat est comparé aux zones actives du catalogue, avec conservation des libellés hiérarchiques et exclusion des zones d’intervention arbitraires. Les correspondances sont exactes après normalisation des accents et de la ponctuation. Une commune est préférée à sa ville lorsqu’elle est reconnue plus précisément. Les zones homonymes restent des choix explicites. Il ne s’agit pas d’un calcul de frontières administratives : l’utilisateur vérifie et confirme la suggestion.

La confirmation ajoute une zone sans remplacer les précédentes, sans doublon et dans la limite de trois. Annuler ne modifie rien. Une position vieille de plus de deux minutes ou dont la précision dépasse un kilomètre est refusée. Un refus de permission, une localisation désactivée, un délai dépassé, un pays autre que CI, une absence de géocodeur ou de correspondance laisse le choix manuel disponible et la demande intacte. Un refus permanent propose l’accès aux réglages de l’application.

Les coordonnées ne quittent pas le parcours de localisation natif vers Firebase : elles ne sont ni enregistrées dans une demande, ni envoyées à une fonction Foundi, ni publiées ou journalisées par ce code. Le fournisseur de localisation/géocodage du téléphone peut traiter la position selon ses propres conditions. Le bouton reste un choix manuel sur les plateformes sans géocodeur natif pris en charge.

Android déclare seulement les autorisations de localisation en cours d’utilisation nécessaires. iOS dispose de la description de cette utilisation. Aucun accès en arrière-plan n’est demandé par le parcours. La compilation et la recette iOS sur Mac restent à faire ; avec Swift Package Manager, construire avec `BYPASS_PERMISSION_LOCATION_ALWAYS=1` selon les instructions du plugin. La réception GPS réelle et la couverture du géocodeur doivent aussi être validées sur téléphone en Côte d’Ivoire : les tests automatisés injectent des positions et résultats déterministes.

## Vérifications et livraison

Vérifications terminées :

| Contrôle | Résultat | Trace locale |
| --- | --- | --- |
| Suite Flutter complète | 207 tests réussis, 0 échec | `.dart_tool/author-location-all-flutter.log` |
| Analyse Flutter | Aucune anomalie | `.dart_tool/author-location-analyze-final.log` |
| Suite backend | 204 tests réussis, 0 échec | `.dart_tool/author-node-final.log` |
| Firebase local : auteur et annuaire | 2 scénarios réussis, code 0 | `.dart_tool/author-emulators-final.log` |
| Compilation Android debug | Réussie, composants GPS compilés | `.dart_tool/author-location-android.log` |
| `git diff --check` | Aucun défaut d’espace | Contrôle local |

Les appels effectifs au nouveau callable sont vérifiés sur le projet de démonstration : requête invalide refusée, identité d’un auteur vérifié retournée à un visiteur public, compte en suppression refusé. Les lectures d’anciens propriétaires, les blocages et l’activité approuvée utilisent le véritable adaptateur Firestore. L’annuaire existant conserve sa pagination, ses projections privées, ses révocations et son budget de lecture.

La première recette a révélé que le runtime local pouvait omettre les métadonnées IP : le nouvel endpoint utilise désormais un budget anonyme commun dans ce cas, sans faire confiance aux en-têtes IP fournis par le client. Une tentative de vérification simultanée Android/Firebase a dépassé la mémoire de la machine. La compilation a ensuite terminé et le dernier scénario Firebase a été relancé séparément après arrêt du daemon Gradle utilisé pour ce build. L’environnement local des fonctions a été restauré à la sortie des tests. L’avertissement Java lors de l’arrêt des émulateurs est distinct du code de sortie 0 et des deux résultats TAP réussis.

Les PNG sont des rendus Flutter réels avec données fictives : [liens et descriptions](sprint-2-5-captures/README.md#parcours-auteur-et-localisation).

Le parcours nécessite une application actualisée et la nouvelle fonction `readRequestAuthorProfile`. La commande de déploiement ciblé exécutée après autorisation est `firebase deploy --project foundi-7c837 --only functions:auth:readRequestAuthorProfile --non-interactive`, avec le mode de découverte par fichier déjà utilisé sur Windows. Aucun nouvel index ni règle publique ne sont nécessaires. Aucune autre fonction n’a besoin d’être redéployée pour ce parcours.

La fonction `readRequestAuthorProfile` est déployée en production et vérifiée active ; les 90 fonctions existantes n’ont pas été modifiées. Aucun Hosting, texte juridique, installation ou distribution d’APK n’a été publié par cette intervention. Une compilation locale sert uniquement à vérifier les composants natifs. Les textes de confidentialité générés restent des projets non publiés.

Sources techniques : [Geolocator](https://pub.dev/packages/geolocator), [Geocoding](https://pub.dev/packages/geocoding). Versions résolues : `geolocator 14.1.2`, `geocoding 5.0.1`.
