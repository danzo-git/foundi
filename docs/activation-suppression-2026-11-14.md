# Activation de la suppression dans l’application — 14 novembre 2026

La suppression de compte est activée sur `foundi-7c837`, en `europe-west1`, à la demande de l’éditeur dans cette conversation. La vérification finale du 14 novembre 2026 à 12 h 14 (Paris) confirme la configuration distante. Cette activation remplace le statut « livraison locale, sans déploiement » des rapports initiaux du Sprint 2 pour le backend de suppression uniquement.

## Périmètre déployé

- Sept nouvelles Functions : demande, suivi, reprise, liste/détail/reprise Admin et worker planifié.
- Les 77 Functions existantes ont reçu les protections communes des comptes en fermeture.
- Règles Firestore et Storage identiques aux sources locales ; les index existants sont préservés et le nouvel index de traitement est prêt.
- Les cinq TTL de suppression sont `ACTIVE`.
- `ACCOUNT_DELETION_ENABLED=true` et `privacyConfiguration/current.enabled=true`.
- Le planificateur est `ENABLED`, toutes les minutes ; ses dernières exécutions vérifiées n’indiquent aucune erreur.

Les parcours de réauthentification Google et mot de passe de l’application utilisent désormais ce backend. Aucun APK ni nouvelle version Admin n’a été produit ou publié dans cette intervention. Le parcours Web public reste désactivé et non publié.

## Configuration appliquée

Source : `config/privacy-policy.json`, version `foundi-deletion-2026-11-14-v1`.

| Élément | Réglage technique |
| --- | --- |
| Suivi après achèvement | 30 jours |
| Journal administratif de consultation/reprise | 90 jours après l’événement |
| Barrière contre les anciennes sessions | 7 jours après achèvement |
| Archives supplémentaires de preuves et métadonnées de modération | 0 jour |
| Messages des autres membres et mesures les concernant | Préservés ; identité du compte supprimé neutralisée |
| Copies de récupération Storage du fournisseur | Paramètre distant vérifié : 7 jours ; aucun effacement instantané de ces copies n’est promis |

Ces durées ont été choisies pour l’activation technique demandée et annoncées pendant l’intervention. Le champ `approved` autorise ce fonctionnement technique ; il ne représente pas une validation juridique par un conseil. Les TTL sont asynchrones et ne garantissent pas l’effacement physique à la seconde de leur échéance.

L’éditeur a précisé que Foundi n’est pas encore immatriculée et que l’adresse complète et le domaine ne sont pas établis. Les nouveaux textes juridiques restent en brouillon. Le contrôle `scripts/validate-privacy-release.cjs` continue donc de refuser la publication des pages publiques ; il n’est pas le commutateur du backend applicatif désormais actif.

## Vérification

- 185 tests backend réussis et contrôle de code réussi, y compris au pré-déploiement.
- Recette combinée sur les émulateurs `demo-foundi` : 39 tests de règles et 3 scénarios d’intégration réussis. L’avertissement Java à l’arrêt de l’émulateur ne modifie pas le résultat des tests ni le code de sortie 0.
- Contrôles HTTP distants : demande/liste sans session refusées ; suivi/reprise avec référence fictive introuvables ; planificateur actif.
- Relecture distante de tous les champs de la politique : valeurs identiques au fichier local.
- Aucun compte réel n’a été supprimé par l’assistant. La suppression complète et la réauthentification Google sur appareil réel restent à recetter avec un compte fictif expressément dédié. Les tests distants effectués ici n’envoient aucune demande de suppression authentifiée.

Traces locales ignorées par Git : `.dart_tool/privacy-deployment-before.json`, `.dart_tool/privacy-deployment-after.json`, `.dart_tool/privacy-endpoints-after-activation.json`, `.dart_tool/privacy-activation-unit-tests.log`, `.dart_tool/privacy-activation-emulator-tests.log`, `.dart_tool/privacy-deploy-indexes.log`, `.dart_tool/privacy-deploy-backend.log`.

## Outils reproductibles

- `functions/scripts/inspect-privacy-deployment.cjs` : inventaire distant en lecture seule, sans lire les comptes ou contenus métier.
- `functions/scripts/verify-privacy-endpoints.cjs` : contrôles non destructifs des accès refusés et du planificateur. Utiliser `--enabled` quand le commutateur Functions est actif.
- `functions/scripts/configure-privacy.cjs` : simulation par défaut ; `--apply` exige les instantanés vérifiés du déploiement, les règles correspondantes, les index et TTL prêts et les Functions à jour avant d’écrire la configuration. Refuse d’écraser une autre version de politique.

En cas d’incident, désactiver `privacyConfiguration/current.enabled` suspend le worker et les nouvelles demandes. Garder les protections et marqueurs de fermeture ; une suspension du service n’annule pas les suppressions déjà effectuées.
