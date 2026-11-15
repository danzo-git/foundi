# Photos des demandes — déploiement ciblé du 15 novembre 2026

Autorisation explicite de l’éditeur dans la conversation : déployer les fonctions nécessaires à la photo personnelle des demandes publiées. Projet `foundi-7c837`, région `europe-west1`, branche locale `codex/foundi-sprint-2-5-finitions`.

Vérification distante terminée le 15 novembre 2026 à 02 h 23 (Paris).

## Déploiement effectué

- Création de `savePersonalAvatar`, `readPersonalAvatarState`, `removePersonalAvatar`, `resolveRequestAvatars`, `readPublicPersonalAvatar` et `cleanupPersonalAvatars`.
- Mise à jour de `runAccountDeletion` pour inclure les photos personnelles, leurs projections, leurs mappings et leur file de nettoyage dans la suppression du compte.
- Publication des règles Firestore dédiées aux projections de photo : lecture unitaire publique de la version, aucune lecture cliente des données privées et aucune écriture cliente.
- Planificateur de nettoyage `ENABLED`, toutes les 60 minutes.

Les 83 autres fonctions déjà présentes conservent leur révision et leur compte de service. Les index distants, les règles Storage et la politique de suppression de compte sont identiques à l’état précédent. `ACCOUNT_DELETION_ENABLED` reste actif. Les autres évolutions du Sprint 2.5 ne sont pas déployées par cette intervention. Aucun Hosting, texte juridique ou APK n’a été publié ou distribué.

## Contrôles

- Les 189 tests backend et les contrôles syntaxiques ont réussi au pré-déploiement.
- Sept fonctions ciblées `ACTIVE`, six nouvelles et une mise à jour ; vérification du périmètre exact par comparaison des métadonnées avant/après.
- API de modification/lecture du compte sans authentification : refus 401 attendu.
- Résolution publique d’un lot vide : 200 et aucune donnée personnelle.
- Photo à référence aléatoire inexistante : 404, réponse non mise en cache.
- Projection publique inexistante accessible à la lecture unitaire (404 attendu), données privées refusées à un client anonyme (403 attendu).
- Planificateur de nettoyage vérifié en lecture seule.

Aucun compte ou demande réelle n’a été modifié par ces contrôles. Les essais authentifiés d’envoi, lecture, révocation et suppression d’une photo ont été effectués sur les émulateurs au Sprint 2.5 ; aucune photo n’a été téléversée par l’assistant sur le projet réel.

La première tentative du CLI a échoué sur son serveur local de découverte avant publication. La reprise avec le mode de découverte par fichier pris en charge par le CLI a abouti. Cette option locale n’active aucune nouvelle fonctionnalité métier.

Traces ignorées par Git : `.dart_tool/sprint25-avatar-before.json`, `.dart_tool/sprint25-avatar-after.json`, `.dart_tool/sprint25-avatar-deploy.log`, `.dart_tool/sprint25-avatar-verification.json`. Outil reproductible : `functions/scripts/verify-avatar-deployment.cjs`.

## Révision : identité photo commune

Une seconde mise à jour ciblée applique la demande de l’éditeur : la photo est maintenant l’identité commune du compte et de son éventuel profil professionnel. Le serveur reprend le portrait Foundi existant sans nouvel envoi, y compris pour les anciennes demandes, et prépare la réutilisation du choix d’un client lors de sa future création de dossier professionnel. Ni Google, ni couverture, ni galerie ne servent de source.

Fonctions mises à jour : `savePersonalAvatar`, `readPersonalAvatarState`, `removePersonalAvatar`, `resolveRequestAvatars`, `readProfessionalShowcase`, `saveProfessionalShowcase`, `startProfessionalProfile`. Les sept mises à jour ont réussi. La comparaison distante avant/après confirme que les autres fonctions gardent leur révision et leur compte de service ; index, règles Storage et politique de suppression restent inchangés. Aucune règle Firestore n’a été redéployée lors de cette seconde intervention. Le nettoyage horaire reste activé.

Contrôles distants terminés : **2026-11-15T11:47:05.103Z**. Les six opérations authentifiées refusent les appels anonymes (401), la résolution d’un lot vide reste publique (200), une image inexistante retourne 404 avec interdiction de cache, les mappings privés restent refusés (403). Les tests n’ont modifié aucun compte ni demande réelle. Le comportement authentifié est vérifié sur les émulateurs : reprise du portrait existant, ancienne demande, remplacement, suppression durable, profil pro futur et purge du compte.

Traces ignorées par Git : `.dart_tool/identity-before.json`, `.dart_tool/identity-after.json`, `.dart_tool/identity-deploy.log`, `.dart_tool/identity-verification.json`. Vérification reproductible avec `functions/scripts/verify-avatar-deployment.cjs --identity` et les paramètres explicites de projet/snapshots. Pré-déploiement : 190 tests backend et contrôles serveur réussis. Recette application : 197 tests Flutter et analyse sans anomalie.

## Utilisation dans l’application actualisée

Toucher les initiales ou la photo dans **Mon compte**, choisir une image et confirmer **Utiliser cette photo**. L’accès est disponible même sans dossier professionnel. Une photo déjà présente est immédiatement réutilisée : aucune nouvelle sélection n’est imposée. Le même portrait sert aux demandes et au profil professionnel. Le remplacement et la suppression passent par cet accès commun ; les autres photos du profil restent indépendantes.

Les anciennes demandes n’ont pas à être republiées. Les demandes dont la propriété historique est ambiguë gardent l’icône de repli. La reprise des portraits existants est progressive à la consultation. Le nouveau bouton d’avatar nécessite une application actualisée ; aucun APK n’a été distribué ici. Aucun Hosting ni texte juridique n’a été publié.

[Recette complète et captures réelles](photo-identite-compte-2026-11-15.md).
