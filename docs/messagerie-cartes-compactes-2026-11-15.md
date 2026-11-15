# Cartes de messagerie compactes — 15 novembre 2026

## Résultat

La variante « Cartes compactes » validée est implémentée dans la liste Messages. Chaque carte présente la photo de profil Foundi du correspondant lorsqu’elle est disponible, avec les initiales en remplacement. La photo de compte déjà choisie est réutilisée : aucun nouvel envoi n’est demandé dans Messages. La photo Google, la couverture et les réalisations ne servent pas de remplacement.

Le nom et la date se trouvent en haut. La demande apparaît ensuite comme contexte, suivie de l’aperçu du dernier message. Le statut « Proposition retenue » est vert ; « Lecture seule » est gris et accompagné d’un cadenas. Les cartes sont plus compactes, avec 16 px de padding et 12 px entre elles. Sur petit écran ou en grand texte, la date passe sous le nom pour éviter les débordements. La date complète reste accessible via l’infobulle.

Les onglets « Mes recherches » et « Mes clients », l’ouverture de la bonne discussion, les états vides/erreur, les statuts et les autorisations existantes sont conservés. Aucun indicateur de présence, accusé de lecture ou filtre supplémentaire n’a été ajouté.

## Photos existantes et accès

Le nouveau callable `resolveConversationAvatars` accepte jusqu’à 30 identifiants de conversation. Il exige un compte actif et vérifié et résout uniquement la photo de l’autre participant aux conversations du demandeur. Il retourne un identifiant public opaque, sans UID supplémentaire, URL de stockage, photo privée ni document de compte. Une photo retirée de la projection publique, un blocage dans l’un des deux sens, un compte indisponible ou une suppression en cours empêchent sa résolution. La lecture d’une conversation inconnue ou étrangère ne révèle aucun identifiant de photo. Les conversations en lecture seule peuvent conserver une photo toujours publique et autorisée.

Le service réutilise l’identité partagée existante et le mécanisme de reprise d’un ancien portrait Foundi. Aucune photo ni nouvelle référence n’est enregistrée dans les conversations. Le composant `PersonalAvatar` existant suit la version publique et rétablit les initiales si l’image est absente, en chargement, invalide, indisponible ou révoquée.

La liste charge immédiatement les conversations ; la résolution facultative des photos ne bloque pas leur affichage. Les changements d’onglet ou de compte isolent leurs résultats, y compris si une ancienne requête photo se termine tardivement. Les photos sont réévaluées lors d’un nouvel événement de conversation, du retour dans l’application ou d’un changement de photo effectué dans l’application. La projection publique actualise une photo déjà résolue au changement de version.

## Vérifications et captures

Les journaux sont conservés dans `.dart_tool/conversation-cards-*.log`. Les tests couvrent les deux rôles, les changements de compte, les réponses tardives, le repli sur initiales, la révocation et l’échec de chargement, le clic sur une carte et le rendu en 320 px avec texte agrandi à 180 %.

Résultats finaux :

- `flutter analyze --no-pub` : aucun problème signalé.
- Suite Flutter complète : 230 tests réussis (`conversation-cards-flutter-all.log`).
- Suite backend complète : 230 tests réussis, dont neuf tests du résolveur de photos (`conversation-cards-node-all.log`).
- Contrôles de syntaxe et des pages locales : réussis (`conversation-cards-functions-check.log`).
- Un scénario d’intégration avec les vrais callables, Auth, Firestore et Storage sur le projet d’émulation `demo-foundi` : réussi (`conversation-cards-emulators.log`). Il vérifie notamment la réutilisation sans nouvel envoi, les deux participants, le refus des appels anonymes et des champs forgés, la révocation, le blocage et le début d’effacement du compte. Le lanceur a terminé avec le code 0 et restauré l’environnement local ; l’avertissement Java lors de l’arrêt du moteur de règles survient après la réussite du scénario.

Les captures suivantes proviennent des vrais widgets Flutter, avec le thème Foundi et des données de recette. Le portrait est une image de test synthétique ; aucun compte réel n’a été utilisé :

- [Cartes compactes avec photo existante et initiales en remplacement](sprint-2-5-captures/messagerie-cartes-compactes.png)
- [Petit écran et texte agrandi](sprint-2-5-captures/messagerie-compacte-petit-ecran.png)

## Livraison

Le code est prêt sur `codex/foundi-sprint-2-5-finitions`. Le backend a été déployé après autorisation explicite et vérifié le 16 novembre 2026 à 00 h 25, heure de Paris : [compte rendu](deploiement-messagerie-2026-11-16.md). Aucun APK n’a été distribué.

Le nouveau callable `resolveConversationAvatars` est actif pour les photos de la liste. Les points d’entrée publics de photo et les photos déjà enregistrées restent réutilisés. Aucune règle Storage, aucun index ni catalogue n’a été modifié. Les règles Firestore de suppression personnelle ont été publiées lors de la même intervention. La nouvelle présentation nécessite également l’application mise à jour.
