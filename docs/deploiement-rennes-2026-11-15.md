# Rennes — déploiement et activation du 15 novembre 2026

L’éditeur a explicitement autorisé la mise à jour de la fonction du catalogue et l’activation de la seule commune de Rennes. Projet `foundi-7c837`, région `europe-west1`, branche `codex/foundi-sprint-2-5-finitions`.

Vérification finale terminée le 15 novembre 2026 à **16 h 13, heure de Paris**.

## Résultat

- `updateProfessionalCatalog` mise à jour et vérifiée **ACTIVE**, révision `updateprofessionalcatalog-00004-lom`.
- **Rennes actif** : `fr_commune_35238`, pays `FR`, type `commune`, sans parent.
- Catalogue passé de **9 à 10 zones**. Les neuf zones ivoiriennes restent strictement identiques. Aucun département, région, métropole ou autre ville française n’a été ajouté.
- Les catégories, spécialités, justificatifs, état d’activation et autres champs métier du catalogue sont conservés.
- Les 90 autres fonctions gardent leur révision et leur compte de service. Règles Firestore/Storage, index, politiques de champs/TTL, Authentication, stockage et politique de suppression inchangés.

## Activation contrôlée

Le catalogue a d’abord été lu et validé sans écriture distante. L’ajout a ensuite utilisé une transaction vérifiant à la fois sa version et sa date de dernière modification, pour refuser un plan devenu obsolète. Seuls le tableau des zones et les métadonnées de modification du catalogue ont été écrits. Une trace `professionalAudit` de type catalogue, opération `enableRennes`, a été créée atomiquement.

L’opération a utilisé les permissions IAM de l’opérateur de projet autorisé, via ADC. Aucun compte administrateur Firebase n’a été créé, modifié ou usurpé. Le champ de modification porte le libellé technique `operator_rennes_cli`, sans publier l’adresse e-mail de l’opérateur.

## Contrôles

Les **209 tests backend** et les contrôles serveur/scripts ont réussi au pré-déploiement. Deux tests complémentaires du plan d’activation vérifient la conservation des données existantes, l’absence de doublon lors d’une reprise et le refus des identifiants conflictuels.

Les contrôles distants confirment : mutation anonyme refusée avec 401, champ administrateur forgé dans le contenu sans effet (401), catalogue public accessible (200) contenant exactement un Rennes actif. Les versions avant/après, l’absence de changement des anciennes zones et autres données du catalogue, et la trace d’audit ont été comparées. Aucun compte ou demande réelle n’a été modifié par ces contrôles.

Les tests authentifiés d’activation, de publication et de diffusion sans mélange entre Rennes et Cocody ont été effectués sur les émulateurs dans la [recette Rennes](rennes-localisation-2026-11-15.md). Aucune demande fictive n’a été publiée en production.

## Application

Rennes est désormais disponible dans le catalogue distant. La suggestion GPS pour Rennes nécessite l’application contenant la dernière modification du parcours de localisation. Une réception GPS réelle à Rennes reste à recetter sur téléphone. Aucun APK n’a été distribué par cette intervention, ni Hosting ou texte juridique publié.

Scripts : `functions/scripts/activate-rennes.cjs` (plan par défaut, `--apply` explicite) et `functions/scripts/verify-rennes-deployment.cjs`. Traces ignorées par Git : `.dart_tool/rennes-deploy-before.json`, `.dart_tool/rennes-deploy-after.json`, `.dart_tool/rennes-activation-plan.json`, `.dart_tool/rennes-activation.json`, `.dart_tool/rennes-deploy.log` et `.dart_tool/rennes-deploy-verification.json`.
