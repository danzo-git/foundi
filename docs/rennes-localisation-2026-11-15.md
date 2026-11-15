# Localisation : Rennes uniquement — 15 novembre 2026

> Déploiement et activation effectués après autorisation de l’éditeur : **Rennes est actif dans le catalogue de production**, avec les neuf zones ivoiriennes conservées. Voir [le rapport du déploiement](deploiement-rennes-2026-11-15.md).

La demande finale de l’éditeur limite l’extension française à **Rennes**. La sélection de toutes les régions/départements ou des autres communes françaises a donc été écartée.

## Périmètre

Le seul ajout au catalogue est `fr_commune_35238`, libellé `Rennes`, type `commune`, pays `FR`, sans parent. Cette entrée représente la commune de Rennes, code officiel 35238, et non son arrondissement, le département ou Rennes Métropole. Référence : [INSEE, commune de Rennes, COG 2026](https://www.insee.fr/fr/metadonnees/geographie/commune/35238-rennes).

L’absence de parent évite de rendre la France entière, la Bretagne ou l’Ille-et-Vilaine sélectionnables comme nouvelles zones. Les références ivoiriennes existantes gardent leurs identifiants, libellés et métadonnées.

Le GPS accepte un pays natif `FR` et recherche Rennes dans la commune retournée par le téléphone. Un nom d’arrondissement Rennes associé à une autre commune ne suffit pas. Les zones sans code de pays restent interprétées comme ivoiriennes pour assurer la compatibilité. Les homonymes entre pays ne sont jamais fusionnés. Les coordonnées restent transitoires, sans transmission à Firebase, et une suggestion doit toujours être confirmée.

Une position dans une autre ville française n’est pas rabattue sur Rennes. Le choix manuel reste possible pour demander un service à Rennes depuis une autre ville ou depuis la Côte d’Ivoire.

## Catalogue et activation

L’Admin propose **Activer Rennes (France)**. Cette action appelle `updateProfessionalCatalog` avec `operation:'enableRennes'` et `expectedVersion` ; aucune liste de zones fabriquée par le client n’est acceptée pour ce preset. Le serveur ajoute ou réactive une seule référence stable, conserve le catalogue et journalise la mutation. Un identifiant réservé déjà utilisé pour une autre localisation provoque un refus, sans écrasement.

L’éditeur conserve désormais le pays d’une zone française au lieu de le réécrire systématiquement en CI. Une zone et ses parents doivent appartenir au même pays. La désactivation et les ancêtres désactivés restent respectés dans les choix disponibles. La validation du script de configuration reprend la même validation complète du catalogue.

La lecture distante effectuée pour préparer cette extension a trouvé un catalogue actif de neuf zones, toutes marquées CI, et aucune référence Rennes. Cette lecture n’a modifié aucune donnée distante. Le déploiement du profil auteur déjà autorisé reste indépendant de cette extension.

## Livraison autorisée et effectuée

Pour rendre cette extension disponible : mettre à jour uniquement `updateProfessionalCatalog`, activer le preset Rennes dans le catalogue avec sa version courante, puis utiliser l’application actualisée. Aucun nouvel index, règle publique, clé Maps ou déploiement des fonctions de photo/profil auteur n’est nécessaire pour la reconnaissance de Rennes. Les fonctionnalités plus larges du Sprint 2.5 gardent leur propre périmètre de déploiement et de recette.

La fonction du catalogue a été mise à jour et Rennes activé en production après accord explicite de l’éditeur. Aucun APK n’a été distribué. Les textes générés restent des projets non publiés. Une recette GPS réelle à Rennes reste à faire sur téléphone ; les tests automatisés injectent les résultats du géocodeur natif.

Les montants gardent le fonctionnement monétaire existant de Foundi : cette modification porte sur les zones et la localisation, pas sur une conversion de devise.

## Vérifications

| Contrôle | Résultat | Trace locale |
| --- | --- | --- |
| Backend complet | 207 tests réussis | `.dart_tool/rennes-node-final.log` |
| Vérification serveur/scripts | Réussie | `.dart_tool/rennes-check.log` |
| Flutter ciblé GPS, catalogue, navigation et régressions Sprint 2.5 | 24 tests réussis | `.dart_tool/rennes-flutter-final.log` |
| Admin complet | 18 tests réussis | `.dart_tool/rennes-admin-final.log` |
| Capture Admin avec le thème réel, recette ciblée | 3 tests réussis | `.dart_tool/rennes-admin-captures-final.log` |
| Analyse Flutter | Aucune anomalie | `.dart_tool/rennes-analyze-final.log` |
| Analyse Admin | Aucune anomalie | `.dart_tool/rennes-admin-analyze-final.log` |
| Firebase local : activation, publication et notifications | 1 scénario réussi, code 0 | `.dart_tool/rennes-emulators-final.log` |
| Contrôle des espaces Git | Réussi | `git diff --check` |

Le scénario Firebase utilise de vrais documents et transactions sur un projet de démonstration local. Il ajoute uniquement Rennes, vérifie que la zone ivoirienne reste identique, publie une demande à Rennes et une demande à Cocody, puis contrôle l’exclusion des professionnels de l’autre zone. Un professionnel couvrant les deux zones reçoit une seule alerte pour une demande multi-zones, même après reprise du traitement. Le budget facultatif et le délai entre publications sont respectés dans les données de recette, sans relâcher les protections de production.

Le GPS est testé avec des réponses natives injectées : Rennes en FR, homonyme en CI, autre commune française dans l’arrondissement de Rennes, ville absente du catalogue, pays non pris en charge, refus, faible précision et réponse expirée. Les choix manuels et les zones précédentes restent conservés. Une réception GPS réelle à Rennes n’est pas certifiée par ces tests.

Les traces sont ignorées par Git. Les totaux généraux et ciblés ne s’additionnent pas. Le message Java à l’arrêt de l’émulateur est distinct du résultat TAP et du code de sortie 0. L’environnement local des fonctions a été restauré. [Captures Flutter](sprint-2-5-captures/README.md#extension-rennes-uniquement).
